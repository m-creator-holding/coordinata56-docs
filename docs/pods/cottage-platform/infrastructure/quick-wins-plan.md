# Инфраструктура: план quick-wins

**Автор:** infra-director
**Дата:** 2026-04-18
**Статус:** draft на утверждение Координатором
**Скоуп:** только планирование. Реализация — отдельными задачами через Heads (`devops-head`, `db-head`, `integrator-head`).
**Ограничение:** каждая задача ≤ 1 рабочего дня одного Worker'а (см. принцип verify-before-scale и engineering principles).

---

## 1. Контекст и допущения

Bootstrap-аудит на момент 2026-04-18 выявил следующие факты:

- `docker ps` показывает `coordinata56_backend` в статусе `unhealthy` (failing streak 85).
  Диагностика: HEALTHCHECK в `backend/Dockerfile` уже корректный (`/api/v1/health`),
  curl из контейнера сейчас возвращает 200 OK. Значит причина — исторический застрявший failing streak
  после прошлой правки, либо race на старте. Фикс: проверить интервал/start_period, при необходимости
  пересобрать образ и удостовериться, что streak обнуляется.
- `coordinata56_frontend` в рестарт-петле: Vite падает с `EACCES: permission denied` на
  `/app/vite.config.ts.timestamp-*.mjs`. Корневая причина — bind-mount хостовой директории под UID 1001
  внутри контейнера, хост-файлы созданы под root. Это отдельный тикет, параллельно quick-wins.
- Бэкапы PostgreSQL не настроены (том `coordinata56_postgres_data` 123 MB, без cron / без pg_dump).
- Мониторинга приложений нет. Есть только zabbix-agent на уровне хоста (вне скоупа M-OS).
- Dashboard на порту 8765 открыт без аутентификации (хост-порт слушает Python-сервер).
- CI (`.github/workflows/ci.yml`) зелёный: `lint` + `lint-migrations` + `test` + `round-trip` — все на месте.
  Текущее состояние CI хорошее, улучшения quick-win касаются **надстройки** (healthcheck-smoke, dependency pinning).
- Интеграций в коде ещё нет (`backend/app/integrations/` отсутствует). В фазе M-OS-1 закладываем
  только скелет под ADR 0009 (pod-архитектура) + anti-corruption layer.
- Правило Владельца: живые внешние вызовы банков/ОФД/Росреестра запрещены до production-gate.
  Quick-wins по `integrator` касаются только кода-на-полке, тестовых стабов и структуры клиентов.

---

## 2. Top-10 quick-wins

| #  | Название                                               | Приоритет | Исполнитель     | Оценка |
|----|--------------------------------------------------------|-----------|-----------------|--------|
| 1  | Починить healthcheck backend (обнулить failing streak) | P0        | devops          | 2 ч    |
| 2  | Ежедневный `pg_dump` на хост-диск + retention 14 дней  | P0        | devops + db     | 4 ч    |
| 3  | Прикрыть dashboard 8765 Basic-Auth (или bind на loopback) | P0     | devops          | 2 ч    |
| 4  | `/readiness` эндпоинт с проверкой БД + docker healthcheck frontend | P1 | devops     | 3 ч    |
| 5  | Makefile target `make backup` + `make restore` (документация) | P1   | db-engineer     | 3 ч    |
| 6  | Индексы по FK и часто-фильтруемым полям (аудит + миграция) | P1    | db-engineer     | 6 ч    |
| 7  | `.env.dev.example` → sync проверка в CI (lint-env-sync) | P1       | devops          | 3 ч    |
| 8  | Скелет `backend/app/integrations/` + base HTTP client (httpx) с таймаутами и retry | P1 | integrator | 6 ч    |
| 9  | Docker image size audit + multi-stage clean-up (prod target) | P2  | devops          | 4 ч    |
| 10 | Скелет `feature flags` для интеграций (сейчас всё OFF по умолчанию) | P2 | integrator | 4 ч    |

Итого: 3 P0 (8 ч), 5 P1 (21 ч), 2 P2 (8 ч). ~37 человеко-часов — 5-6 рабочих дней параллельной работы
трёх Worker'ов (devops, db-engineer, integrator). Реальный календарный срок — 1 неделя с запасом
на ревью Heads и round-trip через Директоров.

---

## 3. Детализация каждого quick-win

### P0-1. Починить healthcheck backend
- **Исполнитель:** devops (через `devops-head`)
- **Проблема:** failing streak 85 в `docker inspect`. Текущий `/api/v1/health` отвечает 200 OK,
  но Docker не обновил статус. Возможные причины: (а) `start_period=30s` маловат на холодный старт
  с миграциями; (б) healthcheck пинговал старый путь до перезапуска контейнера.
- **Задачи:**
  1. Перезапустить backend (`docker compose restart backend`), проверить `docker inspect`.
  2. Если streak снова копится — поднять `start_period` до 60 s, `retries` до 5.
  3. Разделить liveness и readiness (см. P1-4): liveness не ходит в БД.
- **DoD:**
  - `docker ps` показывает `healthy` в течение 5 минут после `docker compose up`.
  - `FailingStreak` = 0 при нормальной работе.
  - Правило добавлено в `docs/agents/departments/infrastructure.md`: «HEALTHCHECK ходит только
    на `/api/v1/health` (liveness), никогда на `/readiness`».

### P0-2. Ежедневный pg_dump
- **Исполнитель:** devops (cron-контейнер/systemd-timer) + db-engineer (формат dump, restore-тест)
- **Проблема:** 123 MB данных в Docker volume без бэкапов. Потеря volume = потеря всего.
- **Задачи:**
  1. devops: выбрать механизм — отдельный сервис `postgres_backup` в docker-compose с `cron` внутри,
     или systemd timer на хосте. Рекомендация: сервис в compose (переносимость).
  2. db-engineer: согласовать `pg_dump -Fc` (custom format, удобен для `pg_restore`) +
     список исключаемых таблиц (если появятся временные / тяжёлые audit-таблицы).
  3. devops: хранить дампы в `/root/coordinata56/backups/postgres/YYYY-MM-DD.dump`, retention 14 дней
     (cron-задача на удаление старше 14 дней).
  4. db-engineer: проверить `restore` на пустую БД из свежего дампа.
- **DoD:**
  - Первый `pg_dump` создался и весит > 0 байт.
  - `pg_restore` из дампа успешно поднимает БД на отдельном контейнере (smoke-тест).
  - `Makefile` target `make backup` запускает pg_dump вручную.
  - Документирован путь хранения и retention в `docs/pods/cottage-platform/infrastructure/backups.md`.
  - **Не готово к production** (нужен off-site storage) — это отдельная задача перед Фазой 9.

### P0-3. Прикрыть dashboard 8765
- **Исполнитель:** devops
- **Проблема:** `dashboard/server.py` слушает 0.0.0.0:8765 и отдаёт live-картину субагентов
  coordinata56. Сейчас доступен без пароля всем, кто знает IP 81.31.244.71.
- **Варианты (devops выбирает с `devops-head`):**
  - Вариант A: bind на 127.0.0.1 + SSH-tunnel для Владельца. Самый простой, ноль новых компонентов.
  - Вариант B: nginx-reverse-proxy с Basic-Auth. Больше движимых частей, но работает из браузера без туннеля.
- **DoD:**
  - Внешний `curl http://81.31.244.71:8765/` возвращает 401 / connection refused.
  - Владелец может открыть dashboard по своему сценарию (описано в README).
  - Регламент обновлён: «любой новый открытый порт на production-IP требует Basic-Auth или loopback».

### P1-4. `/readiness` + docker healthcheck frontend
- **Исполнитель:** devops (+ кратко backend для эндпоинта, через `backend-director`)
- **Проблема:** сейчас healthcheck проверяет только процесс FastAPI. Не отличает «процесс жив,
  но БД отвалилась» от «всё работает». У frontend — healthcheck вообще нет.
- **Задачи:**
  1. Согласовать с `backend-director` добавление `/api/v1/readiness` (SELECT 1 к БД, timeout 2 s).
  2. Использовать `/readiness` для Kubernetes-readiness probe в будущем. Docker-healthcheck оставить
     на `/health` (liveness) — иначе потеря БД убьёт backend-контейнер без надобности.
  3. Для frontend добавить HEALTHCHECK на `curl http://localhost:5173/`.
- **DoD:**
  - `GET /api/v1/readiness` отдаёт 200 при живой БД, 503 при упавшей.
  - `docker inspect coordinata56_frontend` показывает healthcheck-секцию.
  - Контракт описан в `docs/pods/cottage-platform/infrastructure/health-probes.md`.

### P1-5. Makefile `make backup` / `make restore`
- **Исполнитель:** db-engineer
- **Проблема:** даже после P0-2 восстановление вручную — команды из головы. Рискованно.
- **Задачи:**
  1. `make backup` — вызывает pg_dump в контейнере, сохраняет в `backups/postgres/manual-YYYY-MM-DDTHHMMSS.dump`.
  2. `make restore DUMP=...` — восстанавливает из указанного файла в dev-БД с **обязательным**
     интерактивным подтверждением (`read -p "Точно? Это перезапишет dev-БД: "`).
  3. Написать раздел в `docs/pods/cottage-platform/infrastructure/backups.md` с пошаговым runbook.
- **DoD:**
  - `make backup` создаёт файл.
  - `make restore DUMP=<path>` восстанавливает из него dev-БД.
  - Runbook проверен self-review (db-engineer копипастит команды из документа и они работают).

### P1-6. Индексы по FK и часто-фильтруемым полям
- **Исполнитель:** db-engineer (+ утверждение миграции infra-director)
- **Проблема:** после Фазы 3 моделей уже много (users, houses, house_configurations, payments, etc.),
  PostgreSQL не создаёт индексы на FK автоматически. При росте данных JOIN'ы деградируют.
- **Задачи:**
  1. `db-engineer` запускает `EXPLAIN ANALYZE` на ключевых запросах (список — из `repositories/*.py`).
  2. Аудит: все `ForeignKey` + все поля в `.filter(...)` / `.where(...)` — индексированы?
  3. Одна миграция `add_missing_indexes` с `CREATE INDEX CONCURRENTLY` (или обычный CREATE INDEX
     для dev — уточнить с infra-director, так как `ALTER` в Alembic проходит через ADR 0013 линтер).
  4. Round-trip миграции: обязателен (см. CLAUDE.md).
- **DoD:**
  - Миграция прошла round-trip в CI.
  - Отчёт «до/после» с `EXPLAIN ANALYZE` для топ-5 запросов (в том же PR как комментарий).
  - Утверждена infra-director после рецензии Heads (`db-head`).

### P1-7. Lint `.env.dev.example` vs реальные переменные
- **Исполнитель:** devops
- **Проблема:** `.env.dev.example` легко разъезжается с тем, что на самом деле читает backend.
  Новый разработчик скопировал пример — а половина переменных отсутствует.
- **Задачи:**
  1. Написать короткий скрипт `tools/check_env_example.py` — собирает все `os.environ.get(...)` /
     `os.getenv(...)` / pydantic `Settings` fields в `backend/app/` и сравнивает с ключами в
     `.env.dev.example`.
  2. Добавить в `.github/workflows/ci.yml` новый job `env-sync`, запускающий скрипт.
- **DoD:**
  - Скрипт падает с понятной ошибкой, если переменная есть в коде, но нет в `.env.dev.example`.
  - CI-job добавлен и зелёный на текущем `main`.
  - Правило в `infrastructure.md`: «любое новое `os.environ.get` требует правки `.env.dev.example`».

### P1-8. Скелет `backend/app/integrations/` + base HTTP client
- **Исполнитель:** integrator (через `integrator-head`, согласование с `backend-director`)
- **Проблема:** директории нет, первый интегратор (например, банк-клиент) начнёт писать ad-hoc
  `requests.get(...)` — и получим connection leaks, бесконечные таймауты, отсутствие логирования.
- **Задачи (только код-на-полке, никаких живых вызовов):**
  1. Создать `backend/app/integrations/__init__.py`, `backend/app/integrations/base/http_client.py`.
  2. `BaseHTTPClient` на `httpx`: таймауты (connect=5s, read=15s), retry на 5xx (tenacity или
     httpx-retry), логирование request/response (без секретов), `request_id` propagation.
  3. `BaseClient` абстрактный класс под anti-corruption layer (метод `call` возвращает **наш**
     DTO, не сырой JSON провайдера).
  4. Pytest-фикстуры с `respx` для мокирования HTTP.
- **DoD:**
  - `backend/app/integrations/base/` создана с `BaseHTTPClient` и `BaseClient`.
  - Тесты на таймаут, retry, логирование — зелёные.
  - **Ни одного реального внешнего вызова** — ADR 0009 anti-corruption layer + правило владельца
    о live external integrations (`feedback_no_live_external_integrations.md`).
  - Утверждено infra-director и backend-director (совместный PR review).

### P2-9. Docker image size audit
- **Исполнитель:** devops
- **Проблема:** production-target в backend Dockerfile не оптимизирован: копирует `.` целиком
  (включая tests, docs, __pycache__), `libpq-dev` устанавливается в deps, но не вычищается.
- **Задачи:**
  1. `docker build --target production -t coordinata56-backend:prod .` — замерить размер.
  2. Добавить `.dockerignore` (исключить tests/, docs/, __pycache__, .git, backend/alembic/versions/*.pyc).
  3. В prod-stage: `libpq-dev` заменить на `libpq5` (runtime-only), установка в отдельном слое.
- **DoD:**
  - Prod-образ < 300 MB (текущий — замерить).
  - `.dockerignore` на месте, в CI-сборке образ строится без ошибок.
  - Описано в `backends/Dockerfile` комментарий «почему libpq5, а не libpq-dev».

### P2-10. Feature flags для интеграций
- **Исполнитель:** integrator (через `integrator-head`)
- **Проблема:** когда появятся клиенты банков/ОФД — нужен механизм «код на полке, но в runtime OFF».
  Иначе кто-то случайно выкатит с `SBER_ENABLED=True` на стейджинге.
- **Задачи:**
  1. `backend/app/integrations/feature_flags.py` — pydantic `Settings` с полями
     `SBER_ENABLED: bool = False`, `OFD_ENABLED: bool = False`, `DADATA_ENABLED: bool = False`,
     `ROSREESTR_ENABLED: bool = False`.
  2. В каждом будущем клиенте: первая строка `call(...)` — `if not settings.SBER_ENABLED: raise IntegrationDisabled("Sber")`.
  3. Документировать список флагов в `infrastructure.md` + правило «новый внешний провайдер =
     новый флаг, дефолт False».
- **DoD:**
  - Модуль `feature_flags.py` создан.
  - В тестах проверено: попытка вызова disabled-клиента поднимает `IntegrationDisabled`.
  - Правило в регламенте: **никогда** не выставлять дефолт True без согласования Владельца.

---

## 4. Распределение по Worker'ам

| Worker          | Quick-wins                         | Суммарно |
|-----------------|------------------------------------|----------|
| **devops**      | P0-1, P0-2 (infra), P0-3, P1-4, P1-7, P2-9 | 6 задач / ~18 ч |
| **db-engineer** | P0-2 (формат dump + restore-тест), P1-5, P1-6 | 3 задачи / ~13 ч |
| **integrator**  | P1-8, P2-10                        | 2 задачи / ~10 ч |

Параллелизация: три Worker'а могут идти параллельно — пересечения только в P0-2
(devops пишет cron, db-engineer отвечает за формат и restore-тест). Координация через
`devops-head` + `db-head` на одном созвоне (или async в комментариях к PR).

---

## 5. Критерии готовности плана в целом

- [ ] План утверждён Координатором.
- [ ] `devops-head` принял брифы на свою вертикаль (P0-1, P0-2 infra-часть, P0-3, P1-4, P1-7, P2-9).
- [ ] `db-head` принял брифы на свою вертикаль (P0-2 dump-часть, P1-5, P1-6).
- [ ] `integrator-head` принял брифы на свою вертикаль (P1-8, P2-10).
- [ ] Каждый quick-win при сдаче проходит round-trip через Head → infra-director → Координатор.
- [ ] Правила, рождённые при реализации, мигрируют в `docs/agents/departments/infrastructure.md`
      (обновление с 0.1 до 1.0 через Governance — см. отдельную задачу).

---

## 6. Риски и отложенное

- **Риск 1:** P0-2 без off-site storage — это dev-бэкап, не production-бэкап. Если упадёт
  физический диск сервера — данные потеряны вместе с дампами. Решение: отдельная задача перед
  Фазой 9 — S3-совместимое хранилище (Selectel/Yandex Object Storage), шифрование, ротация ключей.
- **Риск 2:** P1-8 base HTTP client ≠ готовая интеграция. Каждый провайдер (Сбер, Тинькофф, Дадата,
  ОФД) — отдельный крупный тикет с изучением регламента провайдера. Это quick-win только для **базы**.
- **Риск 3:** P1-6 индексы без нагрузочного профиля. Мы оптимизируем «на глазок» по структуре
  repositories. Настоящая оптимизация — после появления production-трафика (Фаза 9 + квартал работы).
- **Отложено (не quick-win):**
  - Полноценный мониторинг (Prometheus + Grafana + alertmanager) — отдельная фаза, ≥ 1 недели.
  - Централизованное логирование (Loki/ELK) — отдельная фаза.
  - CI для docker-compose e2e (поднять всю связку, прогнать smoke) — крупный тикет на 1-2 дня.
  - Миграция с Docker Compose на Kubernetes — не quick-win и не обсуждается до Фазы 9.
  - Staging-окружение — требует отдельного сервера, обсуждение с Владельцем.

---

## 7. Следующий шаг

После утверждения плана Координатором:
1. infra-director пишет три брифа: `devops-head`, `db-head`, `integrator-head`.
2. Каждый Head распределяет на своего Worker'а (в данном случае по 1 Worker'у на Head).
3. Worker реализует — Head ревьюит — infra-director утверждает — Координатор коммитит.
4. Паттерн «Координатор-транспорт» соблюдаем строго (CLAUDE.md, Паттерн v1.6).
