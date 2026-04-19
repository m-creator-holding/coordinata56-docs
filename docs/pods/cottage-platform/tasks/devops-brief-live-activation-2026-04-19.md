# Дев-бриф devops: LIVE-активация 3 каналов (WAL→S3, Sentry backend, Sentry frontend)

**Дата:** 2026-04-19
**От:** infra-director (через devops-head)
**Кому:** devops
**Основание:** Владелец выдал живые ключи (msg 1480/1509); infrastructure.md v1.2 §7 Pattern 5
**Статус:** исполнение, один round-trip с devops-head
**Pattern 5 волна:** `dept_queue: infrastructure / wave: live-activation-2026-04-19`

## ultrathink

---

## 0. Что сделано до тебя

1. **Скелет `infra/backups/wal_archive.sh`** (5936 B) — работает в трёх режимах (`s3`/`local`/`off`). Режим `s3` требует 4 переменные из `.env.dev` + установленного `aws`. Сейчас в `.env.dev` стоит `WAL_ARCHIVE_MODE=s3`, ключи Владельца записаны.
2. **Sentry backend SDK** уже вызывается в `backend/app/main.py` строка ~73 (`sentry_sdk.init(dsn=os.environ.get("SENTRY_DSN_BACKEND", ""))`). DSN записан Координатором в `.env.dev`. Docker перезапущен не был — возможно ему нужен restart, проверь.
3. **Sentry frontend SDK** уже вызывается в `frontend/src/main.tsx` строки 1-17 под guard'ом `if (import.meta.env.VITE_SENTRY_DSN_FRONTEND)`. Переменная записана Координатором в `.env.dev`. Vite читает `.env.dev` автоматически при `npm run dev`.
4. **Ключи в `.env.dev`** (gitignored, строки 52-63) — прочитай файл напрямую:
   `cat /root/coordinata56/.env.dev | grep -E '^(AWS_|S3_|SENTRY_|VITE_SENTRY_)'`
   Ключи: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `S3_ENDPOINT`, `S3_REGION`,
   `S3_BUCKET`, `SENTRY_DSN_BACKEND`, `VITE_SENTRY_DSN_FRONTEND` — все присутствуют.

Фактические значения — **только в `/root/coordinata56/.env.dev`** (gitignored).
Здесь они не приводятся намеренно: файл брифа находится в `docs/pods/` и не исключён из git.

**Не меняй** эти значения. Не логируй их в репо. Не вставляй в commit-сообщения.

## 1. Обязательно прочесть (15 минут)

1. `/root/coordinata56/CLAUDE.md` — общие правила (ПД, секреты, git)
2. `/root/coordinata56/docs/agents/departments/infrastructure.md` §3 (backup), §5 (Sentry), §6 (правила), §7 (Pattern 5)
3. `/root/coordinata56/infra/backups/wal_archive.sh` — скелет, который будешь запускать
4. `/root/coordinata56/backend/app/main.py` строки 55-90 — sentry init
5. `/root/coordinata56/frontend/src/main.tsx` — sentry init frontend
6. `~/.claude/agents/devops.md` — границы твоей роли

---

## 2. Подзадача 1: WAL livecheck → S3 (Яндекс Object Storage)

### Что делаем

Один ручной push любого файла (например, `/tmp/wal-live-test-20260419.txt` с содержимым "hello wal") в `s3://coordinata56-wal/wal/` через `aws s3 cp` с endpoint Яндекс. Подтверждение — `aws s3 ls`. Это не full pg_archive_command setup — это smoke test канала.

### Шаги

**Шаг 1. Установить awscli если нет.**

```bash
which aws || pip3 install --break-system-packages awscli
# или:  apt-get install -y awscli
```

Проверка: `aws --version` должна показать ≥ 1.22.

**Шаг 2. Экспортировать переменные из `.env.dev` в текущую shell.**

Делай через чтение конкретных строк, не `source` всего файла (чтобы не экспортить лишнего):

```bash
export AWS_ACCESS_KEY_ID="$(grep -E '^AWS_ACCESS_KEY_ID=' /root/coordinata56/.env.dev | cut -d= -f2-)"
export AWS_SECRET_ACCESS_KEY="$(grep -E '^AWS_SECRET_ACCESS_KEY=' /root/coordinata56/.env.dev | cut -d= -f2-)"
export S3_ENDPOINT="$(grep -E '^S3_ENDPOINT=' /root/coordinata56/.env.dev | cut -d= -f2-)"
export S3_BUCKET="$(grep -E '^S3_BUCKET=' /root/coordinata56/.env.dev | cut -d= -f2-)"
export AWS_DEFAULT_REGION="$(grep -E '^S3_REGION=' /root/coordinata56/.env.dev | cut -d= -f2-)"
```

**Шаг 3. Создать тестовый файл и запушить.**

```bash
TS="$(date -u +%Y%m%dT%H%M%SZ)"
TEST_FILE="/tmp/wal-live-test-${TS}.txt"
echo "coordinata56 wal livecheck ${TS}" > "${TEST_FILE}"

aws s3 cp "${TEST_FILE}" "s3://${S3_BUCKET}/wal/wal-live-test-${TS}.txt" \
    --endpoint-url="${S3_ENDPOINT}"
```

Ожидание: `upload: /tmp/wal-live-test-... to s3://coordinata56-wal/wal/wal-live-test-...txt`, exit code 0.

**Шаг 4. Подтверждение.**

```bash
aws s3 ls "s3://${S3_BUCKET}/wal/" --endpoint-url="${S3_ENDPOINT}"
```

Должна быть строка с именем загруженного файла, размером ~42 байта, timestamp сегодня.

**Шаг 5. Альтернативно через скелет (опционально, если хочешь проверить скрипт).**

```bash
bash /root/coordinata56/infra/backups/wal_archive.sh "${TEST_FILE}" "wal-live-test-${TS}.txt"
# Проверь /var/backups/coordinata56/.last_wal_push_success — должен обновиться
cat /var/backups/coordinata56/.last_wal_push_success
```

**Шаг 6. Очистка.**

```bash
rm -f /tmp/wal-live-test-*
# сам объект в бакете оставь — это маркер успеха, infra-director может захотеть удалить позже
```

### Acceptance П1

- [ ] Команда `aws s3 ls` выдала минимум одну строку с тест-файлом
- [ ] Exit code всех команд = 0
- [ ] `/var/backups/coordinata56/.last_wal_push_success` обновлён (если делал шаг 5)
- [ ] `/tmp/wal-live-test-*` удалены
- [ ] В отчёте Head'у указан точный S3 URI и timestamp

### Если провал

- `InvalidAccessKeyId` → проверь что `AWS_ACCESS_KEY_ID` в `.env.dev` имеет длину 25 символов без кавычек и пробелов. Подожди 1 минуту, повтори один раз. Если не помогло — эскалация Head → Координатор → Владелец.
- `SignatureDoesNotMatch` → `AWS_SECRET_ACCESS_KEY` скопирован с обрезанием. Сверь длину: должна быть 40 символов (`wc -c` на значение).
- `NoSuchBucket` → бакет не создан. Эскалация Head → Координатор → Владелец.
- `command not found: aws` → шаг 1 не выполнен.

---

## 3. Подзадача 2: Sentry backend livecheck

### Что делаем

Создаём dev-only endpoint `GET /api/v1/dev/trigger-error`, который делит на ноль. Включаем его только если `settings.app_env == "development"`. Делаем запрос → проверяем что в Sentry UI backend-проекта появился issue.

### Шаг 1. Создать файл `backend/app/api/dev_trigger.py`

```python
"""Dev-only endpoint для livecheck Sentry backend.

Включается ТОЛЬКО при app_env == "development". На staging/production
роутер не регистрируется — см. guard в app/main.py.

Назначение: одноразовая проверка end-to-end канала backend → Sentry
после выпуска DSN. Не для регулярного использования.
"""

from fastapi import APIRouter, HTTPException, status

router = APIRouter(prefix="/dev", tags=["dev"])


@router.get(
    "/trigger-error",
    summary="Dev-only: выбрасывает ZeroDivisionError для livecheck Sentry",
    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
)
def trigger_error() -> dict:
    """Умышленно делит на ноль — исключение попадает в Sentry через FastApiIntegration.

    Endpoint не возвращает 200 при успехе; возврат 500 = ожидаемое поведение.
    """
    _ = 1 / 0  # noqa: E501 — намеренно, livecheck Sentry
    return {"status": "unreachable"}
```

### Шаг 2. Подключить роутер в `backend/app/main.py`

Найди блок `app.include_router(...)` (после создания `app = FastAPI(...)`). Добавь **под условием**:

```python
from app.core.config import get_settings

settings = get_settings()
if settings.app_env == "development":
    from app.api.dev_trigger import router as dev_trigger_router
    app.include_router(dev_trigger_router, prefix="/api/v1")
```

`settings` там уже есть выше — используй существующую ссылку, не создавай вторую.

### Шаг 3. Перезапустить backend-контейнер

```bash
docker compose restart backend
# ждём healthcheck
sleep 5
docker compose logs --tail=30 backend | grep -iE "sentry|started|error"
```

Должно быть видно строку инициализации Sentry без ошибок.

### Шаг 4. Триггер

```bash
curl -sS -w "\nHTTP=%{http_code}\n" http://127.0.0.1:8000/api/v1/dev/trigger-error
```

Ожидание: HTTP=500, body в ADR 0005 формате `{"error":{"code":"internal_error",...}}` или аналог.

### Шаг 5. Проверка в Sentry UI

1. Открой `https://sentry.io/` (Владелец даёт доступ)
2. Projects → `coordinata56-backend` (project DSN id = 4511247381233744)
3. Issues → отсортируй по "Last Seen"
4. Должен быть issue `ZeroDivisionError: division by zero` создан секунды назад
5. Скопируй event-id (длинный hex в URL issue) — вставь в отчёт Head'у

### Acceptance П2

- [ ] Файл `backend/app/api/dev_trigger.py` создан
- [ ] В `backend/app/main.py` добавлено 2-3 строки под `if settings.app_env == "development":`
- [ ] `grep -n "dev_trigger" backend/app/main.py` показывает условный импорт
- [ ] `curl ... /api/v1/dev/trigger-error` возвращает 500
- [ ] В Sentry UI появился issue с `ZeroDivisionError`, env=dev
- [ ] event-id зафиксирован в отчёте
- [ ] Если поменяешь `APP_ENV=production` в `.env.dev` и рестартнёшь backend — endpoint должен отвечать 404 (проверка guard'а); после проверки верни `APP_ENV=development` обратно

### Если провал

- Sentry SDK не инициализируется → логи `docker compose logs backend | grep -i sentry`. Проверь что `SENTRY_DSN_BACKEND` попал в контейнер: `docker compose exec backend printenv SENTRY_DSN_BACKEND`.
- В Sentry UI не видно события → проверь DNS: `docker compose exec backend getent hosts o4511247356788736.ingest.de.sentry.io`. Если DNS не резолвится — egress блокировка (но ADR 0014 egress на dev не применяется, так что быть не должно).

---

## 4. Подзадача 3: Sentry frontend livecheck

### Что делаем

Добавляем dev-only страницу `/admin/sentry-test` с кнопкой "Trigger Sentry Error". Кнопка делает `throw new Error(...)`. Sentry ловит через global error handler (который активирует `Sentry.init()` автоматически). Проверяем в UI.

### Шаг 1. Создать `frontend/src/pages/admin/SentryTestPage.tsx`

```tsx
import * as Sentry from '@sentry/react'

/**
 * Dev-only страница для livecheck Sentry frontend.
 *
 * Доступна по /admin/sentry-test только в dev-сборке (route-guard в routes.tsx
 * через import.meta.env.DEV). В production bundle не попадает благодаря
 * tree-shaking Vite — условный импорт.
 */
export default function SentryTestPage() {
  const triggerError = () => {
    throw new Error('coordinata56 frontend sentry livecheck — умышленная ошибка')
  }

  const triggerCapture = () => {
    Sentry.captureException(
      new Error('coordinata56 frontend sentry livecheck — captureException'),
    )
    alert('captureException отправлен — проверьте Sentry UI')
  }

  return (
    <div style={{ padding: 24 }}>
      <h1>Sentry livecheck (dev-only)</h1>
      <p>Эта страница доступна только в dev-сборке. Две кнопки:</p>
      <ul>
        <li><b>throw</b> — необработанное исключение (через global handler)</li>
        <li><b>captureException</b> — явный вызов SDK (без throw)</li>
      </ul>
      <button onClick={triggerError} style={{ marginRight: 8 }}>
        throw new Error
      </button>
      <button onClick={triggerCapture}>
        Sentry.captureException
      </button>
    </div>
  )
}
```

### Шаг 2. Добавить роут в `frontend/src/routes.tsx`

Найди массив роутов. Добавь условно:

```tsx
// Dev-only: Sentry livecheck page
...(import.meta.env.DEV
  ? [
      {
        path: '/admin/sentry-test',
        element: <SentryTestPage />,
      },
    ]
  : []),
```

И импорт также под guard'ом, если bundler не делает tree-shake (для уверенности используй `lazy`):

```tsx
import { lazy } from 'react'
const SentryTestPage = lazy(() => import('@/pages/admin/SentryTestPage'))
```

(Если проект уже использует `lazy` — следуй тому же паттерну. Если все страницы импортируются eagerly — делай eager import, tree-shaking на production vite build уберёт.)

### Шаг 3. Запустить dev-сервер

```bash
cd /root/coordinata56/frontend
npm run dev -- --host 0.0.0.0
```

Открой `http://127.0.0.1:5173/admin/sentry-test` в браузере. (Или тот порт, который Vite показал.)

### Шаг 4. DevTools Network tab

F12 → Network → фильтр по `sentry.io`. Должен быть запрос `POST ... /api/4511247400894544/envelope/` после инициализации.

### Шаг 5. Клик → проверка

1. Кликни "Sentry.captureException" (проще, не прерывает страницу)
2. В Sentry UI → project `coordinata56-frontend` → Issues → отсортируй по Last Seen
3. Должен появиться issue `Error: coordinata56 frontend sentry livecheck — captureException`
4. Зафиксируй event-id

Дополнительно можно проверить "throw new Error" — но тогда React upsession ломается (unhandled error reload), это ожидаемо.

### Acceptance П3

- [ ] Файл `frontend/src/pages/admin/SentryTestPage.tsx` создан
- [ ] `frontend/src/routes.tsx` содержит условный роут под `import.meta.env.DEV`
- [ ] `npm run dev` поднимает сервер без TS-ошибок
- [ ] `http://127.0.0.1:5173/admin/sentry-test` рендерит две кнопки
- [ ] DevTools Network показывает POST на `ingest.de.sentry.io`
- [ ] В Sentry UI виден issue после клика
- [ ] `npm run build` проходит; в build-output (`frontend/dist/assets/*.js`) **НЕ** встречается строка `"SentryTestPage"` (проверь: `grep -l SentryTestPage frontend/dist/assets/*.js` — должно быть пусто). Это подтверждает tree-shaking.
- [ ] event-id зафиксирован в отчёте

### Если провал

- `npm run dev` падает на TS → убедись что импорт `@sentry/react` уже есть в `package.json` (он должен быть — `main.tsx` его использует).
- В DevTools нет запросов на sentry.io → проверь что `VITE_SENTRY_DSN_FRONTEND` прочитался: `import.meta.env.VITE_SENTRY_DSN_FRONTEND` в консоли браузера (перед инициализацией). Если undefined — Vite не перезапущен после правки `.env.dev`, рестартни `npm run dev`.

---

## 5. Итог и отчёт Head'у

После всех трёх подзадач — **один** markdown-отчёт devops-head, структура:

```
## П1 WAL→S3: Ready
- Команды выполнены: aws s3 cp + aws s3 ls
- S3 URI: s3://coordinata56-wal/wal/wal-live-test-20260419T...Z.txt
- Размер: 42 B
- Timestamp: 2026-04-19T...Z

## П2 Sentry backend: Ready
- Изменённые файлы:
  - backend/app/api/dev_trigger.py (new, 24 LoC)
  - backend/app/main.py (+3 LoC, условный include_router)
- event-id: <32 hex>
- Sentry issue URL: https://sentry.io/organizations/.../issues/<id>/
- Guard проверен: APP_ENV=production → 404

## П3 Sentry frontend: Ready
- Изменённые файлы:
  - frontend/src/pages/admin/SentryTestPage.tsx (new)
  - frontend/src/routes.tsx (+6 LoC, условный роут)
- event-id: <32 hex>
- Sentry issue URL: https://sentry.io/organizations/.../issues/<id>/
- Tree-shake verified: grep SentryTestPage в dist пуст

## Risks / notes
- ...
```

## 6. Границы (что НЕ делаешь)

- **Не коммитишь.** Коммитит Координатор после сводного отчёта Директора.
- **Не трогаешь** `.env.dev` (Координатор заполнил), `.env.dev.example` (не в скоупе этой волны).
- **Не включаешь** `archive_mode = on` в postgresql.conf — это отдельная задача M-OS-1.1A.
- **Не запускаешь** `pg_basebackup_weekly.sh` — вне скоупа.
- **Не создаёшь** Prometheus-экспортёры — вне скоупа.
- **Не пишешь** регулярный cron на push — это M-OS-1.1A, сейчас только разовый livecheck.
- **Не удаляешь** тестовый WAL-объект из бакета — может пригодиться Директору для проверки.

## 7. Связь с другими волнами

На этой волне активны:
- backend-dev-1 (US-01 company_id, 5 дней) — твои файлы не пересекаются
- frontend-dev-1 (FE-W1-4, 1 день) — пересечения нет

Если попадёшь в мерж-конфликт на `backend/app/main.py` с US-01 — уведоми Head, скорее всего твой один `if`-блок конфликтов не вызовет.

---

**Подпись:** infra-director, 2026-04-19
**Передача через:** devops-head → devops

# Head sign-off: APPROVED devops-head-1, 2026-04-19
/approved-for-execution: true
