# Дев-бриф devops-head: инфра-пакет M-OS-1.1A (WAL→S3, Sentry cloud, PITR на dev)

**Дата:** 2026-04-19
**От:** infra-director
**Кому:** devops-head (распределяет на devops)
**Основание:** решения Владельца 2026-04-19 (Telegram msg 1480); amendment infrastructure.md v1.1
**Статус:** готов к распределению после ратификации v1.1

## ultrathink

## Соответствие регламенту

Инфра-регламент `departments/infrastructure.md v1.1` §3 (Backup & Recovery — PITR в M-OS-1.1A, WAL→Яндекс Object Storage) и §5 (Sentry облачный как default до production-gate). Все три подзадачи — прямое исполнение текста регламента v1.1. Расхождений нет.

Правило v1.1 §6.5 «первый живой внешний API-вызов — только через Координатора к Владельцу»: подзадача 1 и 2 включают обращения к Яндекс Object Storage API и Sentry API. Регистрации (создание аккаунта Яндекс Cloud, регистрация организации Sentry, выпуск ключей) — **делает Владелец**, не devops. devops подключается с уже готовыми credentials из `.env`.

## Цель пакета

К концу M-OS-1.1A иметь:
1. WAL-архивацию Postgres 16 в Яндекс Object Storage с еженедельным `pg_basebackup`.
2. Sentry (облачный) подключён на backend (Python/FastAPI) и frontend (React/Vite), новая ошибка видна в UI Sentry.
3. Задокументированный runbook PITR + один успешный drill восстановления на dev-данных в точку T-1h.

## Обязательно прочесть

1. `/root/coordinata56/CLAUDE.md`
2. `/root/coordinata56/docs/agents/departments/infrastructure.md` v1.1 §3, §5
3. `/root/coordinata56/infra/backups/pg_dump_daily.sh` и `/etc/cron.d/coordinata56-backup` — текущая backup-механика (не ломать!)
4. `/root/coordinata56/docs/pods/cottage-platform/infrastructure/backup-policy.md`
5. `/root/coordinata56/backend/app/main.py` — точка инициализации FastAPI (Sentry SDK подключается тут)
6. `/root/coordinata56/frontend/src/main.tsx` (или `main.jsx`) — точка инициализации React (Sentry frontend)
7. Docs Яндекс Object Storage: API совместим с AWS S3 v4 (для оценки, не для живых вызовов): `https://yandex.cloud/docs/storage/s3/` (offline-reading)
8. Docs `wal-g` как альтернатива нативному `archive_command`: `https://github.com/wal-g/wal-g` (для оценки, выбор между wal-g и нативным — за devops с обоснованием)

---

## Подзадача 1: WAL-archiving → Яндекс Object Storage + pg_basebackup

### Скоуп работ

1. **Создать бакет и сервис-аккаунт** (действие Владельца, см. §«Действия Владельца» ниже). devops получает готовые: `S3_BUCKET=coordinata56-wal`, `S3_ENDPOINT=https://storage.yandexcloud.net`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`.
2. **Добавить переменные в `.env.dev.example`** (без реальных значений) и в `.env.dev` (реальные, gitignored): `S3_BUCKET`, `S3_ENDPOINT`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `WAL_ARCHIVE_MODE=s3` (для тумблера on/off при локальной разработке без сети).
3. **Добавить `awscli` в образ Postgres** или в side-container. Варианты (выбрать с обоснованием):
   - (а) кастомный `Dockerfile.postgres` на базе `postgres:16` + `apt install awscli`;
   - (б) side-container `coordinata56_wal_archiver` с shared-volume на `pg_wal/archive/` и loop push в S3;
   - (в) `wal-g` бинарник вместо `awscli` (однопроходная утилита, оптимизирована под WAL).
   Рекомендация infra-director: **(в) wal-g** — меньше кастомного кода, сжатие из коробки, нативный `wal-push`/`wal-fetch`.
4. **Конфиг Postgres** в `docker-compose.yml` (или через `postgresql.conf` override-файл): `wal_level = replica`, `archive_mode = on`, `archive_command = 'wal-g wal-push %p'` (если (в)) или `aws s3 cp %p s3://${S3_BUCKET}/wal/%f --endpoint-url=${S3_ENDPOINT}` (если (а)/(б)). `archive_timeout = 60` (чтобы в dev WAL не застревали часами).
5. **Скрипт `infra/backups/pg_basebackup_weekly.sh`** — еженедельный базовый бэкап, упаковка tar.gz, загрузка в `s3://coordinata56-wal/basebackup/YYYY-WW/`. Cron: `0 2 * * 0 root /root/coordinata56/infra/backups/pg_basebackup_weekly.sh` (воскресенье 02:00 UTC). Не ломать существующий `/etc/cron.d/coordinata56-backup` — добавить второй cron-файл `coordinata56-basebackup`.
6. **Sanity-gate**: `pg_basebackup` падает, если размер архива < 10 MiB (защита от пустого бэкапа).
7. **State-файлы** `/var/backups/coordinata56/.last_basebackup_success`, `.last_wal_push_success` — обновляются после успешной загрузки; читаются кастомным Prometheus-экспортёром (задача M-OS-1.2).

### Файлы

- Создать: `infra/backups/pg_basebackup_weekly.sh`, `infra/docker/postgresql.conf` (override), `/etc/cron.d/coordinata56-basebackup`, возможно `infra/docker/Dockerfile.postgres` или `infra/wal-archiver/` — решение devops.
- Изменить: `docker-compose.yml` (секция postgres — volume для archive, возможно новый service `wal-archiver`), `.env.dev.example` (новые переменные), `README.md` infra-секция (упомянуть WAL-archive).
- Не трогать: `infra/backups/pg_dump_daily.sh` (существующий cron pg_dump остаётся, это второй пояс защиты).

### Acceptance criteria

- [ ] `.env.dev.example` содержит все 5 новых переменных, без реальных значений.
- [ ] `docker compose up -d` на чистой машине поднимает Postgres с `archive_mode=on`.
- [ ] После `docker compose exec postgres psql -c "SELECT pg_switch_wal();"` в бакете появляется новый WAL-сегмент (проверка: `aws s3 ls s3://coordinata56-wal/wal/ --endpoint-url=...`).
- [ ] Ручной прогон `pg_basebackup_weekly.sh` успешно заливает tar.gz в `s3://coordinata56-wal/basebackup/`.
- [ ] `.last_basebackup_success` обновляется (ISO-8601 UTC).
- [ ] Cron-файл валиден (`crontab -T /etc/cron.d/coordinata56-basebackup` без ошибок — только если такой флаг есть; иначе просто `cat` и глазами).
- [ ] Существующий `pg_dump_daily` продолжает работать (dry-run: `.last_success` обновляется после запуска).
- [ ] Secrets не в git (проверить `git status` и `.gitignore`).

### Оценка

**devops-head:** 0.5 дня (декомпозиция, review, принятие).
**devops:** 3 дня (выбор варианта + обоснование — 0.5д; реализация wal-g/awscli + compose + скрипт — 1.5д; тесты + sanity — 1д).
**Итого подзадача 1:** 3.5 дня.

---

## Подзадача 2: Sentry (облачный) — backend + frontend

### Скоуп работ

1. **Регистрация Sentry-организации и проектов** — действие Владельца (см. §«Действия Владельца»). devops получает: `SENTRY_DSN_BACKEND`, `SENTRY_DSN_FRONTEND`, `SENTRY_ENVIRONMENT=dev`.
2. **Backend SDK**: добавить `sentry-sdk[fastapi]>=2.0` в `backend/pyproject.toml`, секция `[project.dependencies]` (не dev — в production тоже нужно). Инициализация в `backend/app/main.py` до создания `FastAPI()`:
   ```python
   import sentry_sdk
   from sentry_sdk.integrations.fastapi import FastApiIntegration
   sentry_sdk.init(
       dsn=os.environ.get("SENTRY_DSN_BACKEND", ""),
       environment=os.environ.get("SENTRY_ENVIRONMENT", "dev"),
       integrations=[FastApiIntegration()],
       traces_sample_rate=0.0,  # M-OS-1.1A: только ошибки, без APM
       send_default_pii=False,  # маскирование ПД по CLAUDE.md «Данные / ПД»
       release=os.environ.get("GIT_COMMIT_SHA", "dev"),
   )
   ```
   Пустой DSN = SDK no-op (не падает локально без интернета).
3. **Frontend SDK**: `npm i @sentry/react` (уточнить у frontend-director — не пересекается ли с их planner). Инициализация в `frontend/src/main.tsx` до `createRoot`:
   ```ts
   import * as Sentry from "@sentry/react";
   if (import.meta.env.VITE_SENTRY_DSN_FRONTEND) {
     Sentry.init({
       dsn: import.meta.env.VITE_SENTRY_DSN_FRONTEND,
       environment: import.meta.env.VITE_SENTRY_ENVIRONMENT ?? "dev",
       tracesSampleRate: 0.0,
       sendDefaultPii: false,
     });
   }
   ```
   **Важно:** frontend-SDK требует согласования с `frontend-director` (его зона). devops даёт только план и DSN, реальную вставку делает frontend-worker через свой бриф. В этом брифе — только backend + DSN-выдача.
4. **Переменные** в `.env.dev.example`: `SENTRY_DSN_BACKEND`, `SENTRY_ENVIRONMENT=dev`. В `frontend/.env.dev.example`: `VITE_SENTRY_DSN_FRONTEND`, `VITE_SENTRY_ENVIRONMENT=dev`.
5. **Тестовая ошибка**: эндпоинт `GET /debug/sentry-test` (только при `SENTRY_ENVIRONMENT=dev`), делает `raise RuntimeError("Sentry smoke-test 2026-04-19")`. После деплоя dev — вручную дёрнуть, проверить в Sentry UI появление события, скриншот → отчёт.
6. **Маскирование ПД**: `send_default_pii=False` обязательно (CLAUDE.md §«Данные / ПД»). Дополнительно `before_send` hook — фильтрует любые поля, содержащие ключи `passport`, `snils`, `inn`, `phone` (регексп на keys). Шаблон в `backend/app/core/sentry_scrub.py`.

### Файлы

- Создать: `backend/app/core/sentry_scrub.py`, `backend/app/api/_debug_sentry.py` (route `/debug/sentry-test`, gated env).
- Изменить: `backend/app/main.py` (init), `backend/pyproject.toml` (+ sentry-sdk), `.env.dev.example`, `frontend/.env.dev.example` (только переменные, не код frontend).
- Координация: передать frontend-director задачу на SDK-вставку через Координатора (отдельный sub-бриф, не в этом файле).

### Acceptance criteria

- [ ] `sentry-sdk[fastapi]` в `pyproject.toml`, `pip install -e "backend/[dev]"` проходит.
- [ ] Backend стартует с пустым `SENTRY_DSN_BACKEND` (no-op, без ошибок в логах).
- [ ] Backend стартует с валидным DSN, в Sentry UI виден `service: coordinata56-backend, environment: dev`.
- [ ] `GET /debug/sentry-test` → 500, событие в Sentry UI в течение 60 с.
- [ ] `send_default_pii=False`, `before_send` scrubber юнит-тестирован (1 тест на удаление ключа `passport_number`).
- [ ] frontend-director уведомлён, DSN передан (через Координатора).
- [ ] `.env.dev` реальные DSN — не в git.

### Оценка

**devops-head:** 0.5 дня.
**devops:** 2 дня (backend-init + scrub + test-endpoint — 1д; тест на реальной DSN + debug-эндпоинт сносится после проверки — 0.5д; sub-бриф для frontend через Координатора — 0.5д).
**Итого подзадача 2:** 2.5 дня (без учёта frontend-работы, она в параллели у `frontend-director`).

---

## Подзадача 3: PITR runbook + drill на dev-данных

### Скоуп работ

1. **Runbook** `docs/pods/cottage-platform/infrastructure/pitr-runbook.md` — пошаговая процедура восстановления на произвольный момент времени T. Разделы:
   - Предусловия (доступ в S3, `wal-g`/`aws-cli` на хосте, свободное место ≥ 2× размер БД).
   - Шаг 1: остановить backend (`docker compose stop backend`).
   - Шаг 2: поднять чистый Postgres-контейнер `coordinata56_postgres_restore` с тем же major-версией (16).
   - Шаг 3: скачать последний `basebackup` из S3 (`wal-g backup-fetch` или `aws s3 cp` + `tar xzf`), развернуть в `PGDATA`.
   - Шаг 4: создать `recovery.signal` + `postgresql.auto.conf` с `restore_command = 'wal-g wal-fetch %f %p'` и `recovery_target_time = 'YYYY-MM-DD HH:MM:SS+00'`.
   - Шаг 5: старт Postgres, дождаться выхода из recovery (`pg_is_in_recovery()` → false после `pg_promote()`).
   - Шаг 6: sanity-check (row-count по 7 ключевым таблицам, сравнение с ожидаемым на момент T).
   - Шаг 7: переключение DSN в backend `.env` либо переименование БД.
   - Шаг 8: запуск backend, health-check `/healthz`.
   - Rollback-план если PITR не удался: fall-back на последний pg_dump.
2. **Drill на dev-данных**:
   - В 10:00 UTC (пример) зафиксировать row-count таблицы `users` — значение N1.
   - В 10:15 UTC добавить тестового пользователя — row-count N1+1, записать точное время T_add.
   - В 10:30 UTC удалить всю таблицу (`DELETE FROM users`) — симуляция инцидента.
   - В 10:35 UTC запустить runbook с `recovery_target_time = T_add + 10s` (момент сразу после добавления, до удаления).
   - Ожидаемый результат: после PITR row-count = N1+1, тестовый пользователь присутствует.
   - Зафиксировать фактическое RTO (от «инцидент в 10:30» до «backend отвечает в 10:XX») и RPO.
3. **Отчёт drill** — `docs/pods/cottage-platform/infrastructure/pitr-drill-2026-04-XX.md`: факт RPO, факт RTO, отклонения от runbook, предложения по правкам runbook.

### Файлы

- Создать: `docs/pods/cottage-platform/infrastructure/pitr-runbook.md`, `docs/pods/cottage-platform/infrastructure/pitr-drill-2026-04-XX.md`.
- Изменить: `docs/pods/cottage-platform/infrastructure/backup-policy.md` — добавить секцию «PITR» со ссылкой на runbook.
- Обновить: `docs/agents/departments/infrastructure.md` §3 «Процедура восстановления» — добавить вариант «через PITR» со ссылкой.

### Acceptance criteria

- [ ] Runbook читается человеком за 10 минут, все команды — copy-paste-ready (абсолютные пути, явные значения переменных через `export`-блок в начале).
- [ ] Drill выполнен успешно: row-count после recovery = ожидаемый, факт RPO ≤ 5 мин, факт RTO ≤ 60 мин.
- [ ] Отчёт drill зафиксирован с датой и скриншотами/логами ключевых шагов.
- [ ] Runbook протестирован повторно другим человеком (рекомендация: `db-head` прогоняет по инструкции — не хардкодить знания в голову автора).
- [ ] Ссылки в backup-policy.md и infrastructure.md обновлены.

### Оценка

**devops-head:** 1 день (принятие runbook, повторный прогон).
**devops:** 3 дня (runbook — 1д; drill + отладка — 1.5д; отчёт + правки runbook после drill — 0.5д).
**db-head:** 0.5 дня (review runbook + повторный прогон).
**Итого подзадача 3:** 4.5 дня.

---

## Общая оценка и таймфрейм

| Подзадача | devops-head | devops | db-head | Итого |
|---|---|---|---|---|
| 1. WAL→S3 + pg_basebackup | 0.5 | 3.0 | — | 3.5 |
| 2. Sentry cloud backend | 0.5 | 2.0 | — | 2.5 |
| 3. PITR runbook + drill | 1.0 | 3.0 | 0.5 | 4.5 |
| **Всего** | **2.0** | **8.0** | **0.5** | **10.5 чел-дней** |

При последовательной работе (devops один) — 8 рабочих дней devops, подзадачи 1 и 3 идут подряд (3 зависит от 1). Подзадача 2 параллелится с 1.

**Оптимальный план:**
- Неделя 1: П1 старт + П2 параллельно (П2 готов к концу недели).
- Неделя 2: П1 завершение + П3 старт (runbook).
- Неделя 3: П3 drill + отчёт + повторный прогон db-head.

**Укладываемся ли в M-OS-1.1A (5 недель)?** Да, с запасом 2 недели. Риски: задержка на действиях Владельца (регистрации в Яндекс Cloud и Sentry) — если затянется > 3 дней, П1/П2 сдвигаются. Mitigation: П3 runbook пишется без живого S3 (в теории), drill — только когда П1 готов.

---

## Ограничения

- НЕ делать живых вызовов Яндекс Cloud API и Sentry API до того, как Владелец зарегистрирует аккаунты и выдаст credentials. Любые `aws s3 ...`, `curl sentry.io/...` до этого момента — запрещены.
- НЕ ломать существующий `pg_dump_daily` cron и `backup-policy.md` v1 — это второй пояс защиты, остаётся работать параллельно с WAL/PITR.
- НЕ коммитить — diff передать Координатору через отчёт devops-head.
- НЕ писать frontend Sentry-код самостоятельно — это зона `frontend-director`, передать sub-бриф через Координатора.
- verify-before-scale: сначала прогнать WAL-push на 1 тестовом сегменте (`pg_switch_wal`), убедиться что файл реально попал в S3, только после этого включать в продовый cron.
- Маскирование ПД в Sentry — обязательное (CLAUDE.md §«Данные / ПД»). `send_default_pii=False` + `before_send`-scrubber — без вариантов.

---

## Действия Владельца (блокирующие, до старта работ devops)

1. **Яндекс Cloud:**
   - Зарегистрировать платёжный аккаунт (если ещё нет).
   - Создать облако `coordinata56` и каталог `infra`.
   - Создать бакет Object Storage `coordinata56-wal` (класс `Standard`, регион `ru-central1`).
   - Создать сервис-аккаунт `coordinata56-wal-writer` с ролью `storage.editor` на бакет.
   - Выпустить статический ключ доступа (AccessKeyID + SecretAccessKey).
   - Передать Координатору: ключи + endpoint. Координатор — в `.env.dev` devops (либо через защищённый канал).

2. **Sentry:**
   - Зарегистрировать организацию `coordinata56` на sentry.io (Developer plan, free-tier).
   - Создать два проекта: `coordinata56-backend` (platform: Python/FastAPI), `coordinata56-frontend` (platform: React).
   - Скопировать DSN обоих проектов.
   - Передать Координатору: 2 DSN. Координатор — в `.env.dev`.

3. **Подтверждение стоимости:**
   - Яндекс Object Storage: прогноз ≤ 3 руб/мес в dev. Подтверждение не требуется (ниже шумового порога).
   - Sentry: free-tier 5k events/мес × 2 проекта = 0 руб. Подтверждение не требуется.
   - Эскалация к Владельцу — только если фактические расходы превысят 200 руб/мес (триггер — в регламенте v1.1 §3).

**Пока пункты 1-2 не выполнены — devops работает только над теоретической частью (runbook П3, план wal-g vs awscli П1, скелет кода Sentry П2 с пустым DSN).**

---

## Критерии приёмки брифа (DoD infra-director ← devops-head)

- [ ] Все 3 подзадачи закрыты по своим acceptance criteria.
- [ ] Amendment regulation v1.1 ратифицирован (отдельный PR или включён в этот коммит — решает Координатор).
- [ ] Отчёт devops-head ≤ 400 слов: какие файлы, какие гитфлоу, результат drill (факт RPO/RTO), список остаточных рисков, предложения для M-OS-1.2.
- [ ] Тестовый debug-эндпоинт Sentry удалён перед merge (только для ручной проверки, в main не нужен).
- [ ] Все новые secrets — в `.env*.example` с пустыми значениями и в `.gitignore` (фактические `.env` — не коммитятся).
