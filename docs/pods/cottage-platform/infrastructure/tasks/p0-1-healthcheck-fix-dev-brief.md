# P0-1: Dev-бриф для devops — Healthcheck fix

**Источник:** `p0-1-healthcheck-fix.md` (бриф infra-director)
**Автор:** devops-head (infra-head)
**Дата:** 2026-04-18
**Адресат:** devops
**Статус:** ready-to-execute
**Приоритет:** P0
**Оценка времени:** 15 мин активной работы + 90 с ожидания

---

## Контекст одной строкой

`coordinata56_backend` застрял в статусе `unhealthy` (failing streak 85) из-за старого состояния
контейнера, несмотря на то что `/api/v1/health` отвечает 200 OK. Нужно: поправить Dockerfile
и пересоздать контейнер с нуля.

---

## Шаг 1. Верификация текущего состояния (защитный)

Перед любыми правками убедиться, что Dockerfile именно тот, который ожидается:

```bash
grep -n HEALTHCHECK /root/coordinata56/backend/Dockerfile
```

**Ожидаемый вывод:**

```
49:HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
88:HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
```

Два HEALTHCHECK — это норма: строки 49 (стадия `development`) и 88 (стадия `production`).

**Стоп-условие:** если путь в CMD другой (`/health`, `/healthz`, что угодно кроме
`/api/v1/health`) — НЕ продолжать. Вернуть devops-head для эскалации к infra-director.

---

## Шаг 2. Правка Dockerfile

**Файл:** `/root/coordinata56/backend/Dockerfile`

**Что менять:** в обоих HEALTHCHECK (строки 49 и 88) заменить параметры:
- `--start-period=30s` → `--start-period=60s`
- `--retries=3` → `--retries=5`

Остальные параметры (`--interval=10s`, `--timeout=5s`) — не трогать.

**Результат после правки в обоих местах:**

```dockerfile
HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=5 \
    CMD curl -f http://localhost:8000/api/v1/health || exit 1
```

**Контрольная точка:** после правки проверить, что обе строки изменились:

```bash
grep -n HEALTHCHECK /root/coordinata56/backend/Dockerfile
```

Должно быть `start-period=60s --retries=5` в обоих вхождениях (строки 49 и 88).

---

## Шаг 3. Пересборка и пересоздание контейнера

Выполнять строго в указанном порядке. Обе команды из рабочей директории проекта:

```bash
cd /root/coordinata56
docker compose build backend
docker compose up -d --force-recreate backend
```

**Почему `--force-recreate` обязателен:** без этого флага Docker переиспользует уже
существующий контейнер с его состоянием, включая старый failing streak. Флаг принудительно
создаёт новый контейнер из свежего образа с чистым healthcheck-состоянием.

**`docker compose down` НЕ выполнять** — требует разрешения infra-director.

---

## Шаг 4. Ожидание и проверка статуса

После `up -d --force-recreate` подождать 90 секунд, затем проверить:

```bash
sleep 90
docker ps --filter name=coordinata56_backend --format 'table {{.Names}}\t{{.Status}}'
docker inspect coordinata56_backend --format '{{.State.Health.Status}} streak={{.State.Health.FailingStreak}}'
```

**Ожидаемый результат (критерий успеха):**

| Команда | Ожидаемый вывод |
|---------|-----------------|
| `docker ps` | `coordinata56_backend ... Up 1 minute (healthy)` |
| `docker inspect` | `healthy streak=0` |

Если оба условия выполнены — задача закрыта, переходить к шагу 6 (отчёт).

---

## Шаг 5. Диагностика при неуспехе (не гадать, читать логи)

Если после 90 секунд контейнер всё ещё `unhealthy`:

```bash
# 1. Последние healthcheck-попытки с выводами curl
docker inspect coordinata56_backend \
  --format '{{range .State.Health.Log}}{{.Start}} exit={{.ExitCode}} out={{.Output}}{{"\n"}}{{end}}' \
  | tail -n 20

# 2. Логи самого приложения
docker logs --tail 100 coordinata56_backend

# 3. Прямая проверка эндпоинта изнутри контейнера
docker exec coordinata56_backend curl -v http://localhost:8000/api/v1/health
```

**Таблица решений по симптомам:**

| Вывод curl в healthcheck-логе | Причина | Действие |
|-------------------------------|---------|----------|
| `curl: (7) Failed to connect to localhost port 8000` | uvicorn не успел подняться | сообщить devops-head: нужно `start_period=90s` |
| `curl: (22) ... 404` | роутер не смонтирован на `/api/v1/health` | сообщить devops-head, НЕ трогать backend-код |
| `curl: (22) ... 500` | health-эндпоинт падает (скорее всего БД) | сообщить devops-head |
| пустой вывод, streak растёт | `--force-recreate` не применился | повторить шаг 3 |

**Нельзя:** менять что-либо в `backend/app/api/` — это зона backend-команды, не devops.

---

## Шаг 6. Отчёт devops-head

После успешного выполнения (или при блокере) написать devops-head 3-5 строк:

1. Какие строки в Dockerfile изменены и как.
2. Вывод `docker ps` после пересоздания.
3. Вывод `docker inspect` (статус + streak).
4. Если была диагностика — что нашёл.

**НЕ коммитить самому.** Коммит делает Координатор после вердикта infra-director.

---

## Rollback план

**Условие применения:** после `--force-recreate` контейнер не поднялся вообще (статус `Exited`
или `Restarting`) — не просто `unhealthy`, а реальный crash.

**Последовательность:**

```bash
# 1. Вернуть Dockerfile к исходным значениям:
#    start-period=30s, retries=3 в обоих HEALTHCHECK (строки 49 и 88)

# 2. Пересобрать и поднять снова:
cd /root/coordinata56
docker compose build backend
docker compose up -d --force-recreate backend

# 3. Убедиться, что контейнер запустился (пусть даже unhealthy):
docker ps --filter name=coordinata56_backend
```

**Если после rollback контейнер тоже не поднимается** — остановиться, не трогать больше ничего,
сообщить devops-head для эскалации к infra-director.

`docker compose down` и любые операции с volumes — только с явного разрешения infra-director.

---

## Контрольные точки devops-head

После получения отчёта от devops devops-head самостоятельно верифицирует:

```bash
docker ps --filter name=coordinata56_backend --format 'table {{.Names}}\t{{.Status}}'
docker inspect coordinata56_backend --format '{{.State.Health.Status}} streak={{.State.Health.FailingStreak}}'
```

Убеждается, что `healthy` держится 5 минут подряд (запустить команду повторно через 5 мин).
Только после этого передаёт результат infra-director.

---

## Definition of Done (checklist для devops-head)

- [ ] `docker ps` показывает `(healthy)` для `coordinata56_backend`
- [ ] `FailingStreak = 0` в `docker inspect`
- [ ] Dockerfile обновлён: `start_period=60s`, `retries=5` в обеих секциях (строки 49 и 88)
- [ ] `git diff backend/Dockerfile` показывает ровно 4 изменённые строки (только параметры HEALTHCHECK)
- [ ] Отчёт devops получен и проверен devops-head
