# P0-1: Починить healthcheck backend (обнулить failing streak)

**Источник:** `docs/pods/cottage-platform/infrastructure/quick-wins-plan.md` §3, P0-1
**Автор брифа:** infra-director
**Дата:** 2026-04-18
**Адресат:** `devops-head` → `devops`
**Статус:** approved, готов к исполнению
**Приоритет:** P0
**Оценка:** 1 рабочий час + 0.5 ч на ревью

---

## 1. Цель

`coordinata56_backend` должен стабильно показывать `Up (healthy)` в `docker ps` в течение 5 минут
после `docker compose up`. Сейчас контейнер в статусе `unhealthy` с failing streak 85,
хотя `/api/v1/health` отвечает 200 OK.

## 2. Контекст (важно прочитать перед началом)

В ходе bootstrap-аудита infra-director установил:
- HEALTHCHECK в `backend/Dockerfile` **уже корректный**: `curl -f http://localhost:8000/api/v1/health`
  (строки 49-50 и 88-89 — два stage'а, dev и prod).
- Эндпоинт живой: `docker exec coordinata56_backend curl -fsS http://localhost:8000/api/v1/health`
  возвращает 200 OK.
- **Корневая причина** unhealthy-статуса — исторический застрявший failing streak от прошлых
  конфигураций (до фикса пути). Docker не пересчитывает streak при смене healthcheck'а без
  `--force-recreate`.
- Вторичный фактор — `start_period=30s` маловат на холодный старт с миграциями Alembic.

## 3. Пошаговый план

### Шаг 1. Верифицировать текущий Dockerfile (защита от дрейфа)

```bash
grep -n HEALTHCHECK /root/coordinata56/backend/Dockerfile
```

Ожидается: две строки с `/api/v1/health`. Если путь другой (`/health` без префикса,
`/healthz`, и т.п.) — **остановиться и вернуть infra-director через devops-head**.
Не исправлять молча — это меняет контракт эндпоинта.

### Шаг 2. Поднять `start_period` с 30s до 60s

Правка в `backend/Dockerfile`, обе строки (dev stage и production stage):

```dockerfile
HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=5 \
    CMD curl -f http://localhost:8000/api/v1/health || exit 1
```

Изменения:
- `start-period=30s` → `60s` (время на миграции + загрузку uvicorn)
- `retries=3` → `5` (допускаем кратковременные лаги на старте)
- `interval=10s` и `timeout=5s` — оставляем как есть.

Альтернатива: вынести healthcheck в `docker-compose.yml` на уровень сервиса `backend` —
**не делаем**, чтобы healthcheck жил вместе с образом и работал в любом окружении (Swarm,
K8s, standalone docker run). Dockerfile — единая точка правды.

### Шаг 3. Пересоздать контейнер с обнулением состояния

```bash
cd /root/coordinata56
docker compose build backend
docker compose up -d --force-recreate backend
```

`--force-recreate` обязателен — без него Docker переиспользует существующий контейнер
со старым failing streak.

### Шаг 4. Проверка через 90 секунд

```bash
sleep 90
docker ps --filter name=coordinata56_backend --format 'table {{.Names}}\t{{.Status}}'
docker inspect coordinata56_backend --format '{{.State.Health.Status}} streak={{.State.Health.FailingStreak}}'
```

**Ожидаемый результат:**
- `Status`: `Up 1 minute (healthy)` (или похожий tail)
- `Health.Status`: `healthy`
- `FailingStreak`: `0`

### Шаг 5. Если нет — диагностика (не гадать, читать логи)

```bash
# Последние 5 healthcheck-попыток с выводом
docker inspect coordinata56_backend --format '{{range .State.Health.Log}}{{.Start}} exit={{.ExitCode}} out={{.Output}}{{"\n"}}{{end}}' | tail -n 20

# Что говорит само приложение
docker logs --tail 100 coordinata56_backend

# Жив ли эндпоинт изнутри
docker exec coordinata56_backend curl -v http://localhost:8000/api/v1/health
```

Типичные находки и действия:
| Симптом в логах healthcheck | Корневая причина | Действие |
|-----------------------------|------------------|----------|
| `curl: (7) Failed to connect to localhost port 8000` | uvicorn ещё не поднялся | поднять `start_period` до 90s |
| `curl: (22) The requested URL returned error: 404` | роутер не смонтирован по `/api/v1/health` | эскалировать к backend через `devops-head → infra-director → Координатор → backend-director` |
| `curl: (22) ... 500` | health-эндпоинт падает на проверке БД | эскалировать к db-engineer через `devops-head` |
| пусто, streak всё ещё растёт | контейнер не был пересоздан | повторить шаг 3 с `--force-recreate` |

**Нельзя:** менять сам health-эндпоинт в backend — это не зона devops, это контракт с
backend-вертикалью. Если эндпоинт сломан — эскалация строго через Heads.

## 4. Definition of Done

- [ ] `docker ps` показывает `healthy` для `coordinata56_backend` 5 минут подряд.
- [ ] `FailingStreak = 0` в `docker inspect`.
- [ ] Dockerfile обновлён: `start_period=60s`, `retries=5` в обеих секциях HEALTHCHECK.
- [ ] Git-коммит включает только `backend/Dockerfile` (никаких чужих файлов — см. CLAUDE.md «Git»).
- [ ] Краткий отчёт (3-5 строк) в ответе `devops-head`: что сделал, что увидел, какой итоговый статус.

## 5. Что явно НЕ делать

- **Не** трогать `/api/v1/health`-хендлер в `backend/app/api/` — это чужая зона (backend).
- **Не** добавлять `/api/v1/readiness` в этой задаче — это отдельный квик-вин P1-4.
- **Не** лезть в healthcheck frontend — это тоже P1-4.
- **Не** коммитить самому — коммит делает Координатор после вердикта infra-director.
- **Не** делать `docker system prune` / `docker volume rm` — необратимо, эскалация к Владельцу.

## 6. Цепочка round-trip

`devops` выполняет → отчёт в `devops-head` → Head ревьюит → `infra-director` утверждает →
Координатор коммитит.

## 7. Риски

| Риск | Вероятность | Митигация |
|------|-------------|-----------|
| `start_period=60s` всё ещё мало при первой миграции с нуля | низкая | шаг 5 в диагностике: поднять до 90s |
| Правка Dockerfile задевает сборку prod-stage (другой базовый образ) | низкая | правим обе секции одинаково, CI прогонит build-тест |
| `--force-recreate` сбросит in-memory state backend (если вдруг есть) | низкая | backend stateless по ADR 0002, данные в Postgres |
