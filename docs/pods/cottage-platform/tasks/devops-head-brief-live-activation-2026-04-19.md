# Дев-бриф devops-head: LIVE-активация инфра-пакета M-OS-1.1A

**Дата:** 2026-04-19
**От:** infra-director
**Кому:** devops-head (координирует devops)
**Основание:** Владелец передал живые ключи (msg 1480/1509); Pattern 5 fan-out; infrastructure.md v1.2 §7
**Статус:** Pattern 5 — Координатор спавнит Вас после получения этого брифа
**Pattern 5 волна:** `dept_queue: infrastructure / wave: live-activation-2026-04-19`

## ultrathink

---

## 0. Контекст от Координатора

Два предыдущих дев-брифа (`devops-head-brief-infra-m-os-1-1a-2026-04-19.md`, `devops-brief-q1-sast-ci-v2-2026-04-18.md`) оставили скелеты без живых вызовов: `wal_archive.sh` в режиме `local`, Sentry SDK с пустым DSN, `.env.dev` без реальных ключей. Владелец 2026-04-19 закрыл это: выдал AccessKey Яндекс Cloud и два DSN Sentry, все три записаны Координатором в `/root/coordinata56/.env.dev` (gitignored). Бакет `coordinata56-wal`, endpoint `https://storage.yandexcloud.net`, регион `ru-central1`.

Эти вызовы **не входят в запрет «банки/Росреестр/1С/ОФД»** из feedback_no_live_external_integrations — Владелец разрешил явно (msg 1480/1509). Можно делать живые HTTP.

## 1. Цель волны

К закрытию волны иметь **три зелёных livecheck'а**:

- **П1:** один WAL-файл физически лежит в `s3://coordinata56-wal/wal/` и виден через `aws s3 ls`.
- **П2:** одно тестовое исключение backend (`ZeroDivisionError` или аналог) появилось в Sentry-проекте backend, с release/environment `dev`.
- **П3:** одно тестовое исключение frontend (клик по dev-кнопке) появилось в Sentry-проекте frontend.

Не настраиваем PITR-runbook, не гоняем pg_basebackup, не трогаем production. Цель — доказать что каналы открыты end-to-end, не более.

## 2. Ваша роль (devops-head)

1. Прочесть регламенты: `/root/coordinata56/CLAUDE.md`, `docs/agents/departments/infrastructure.md` v1.2 §7 (Pattern 5), `~/.claude/agents/devops-head.md`, предыдущий бриф `devops-head-brief-infra-m-os-1-1a-2026-04-19.md` §0-§2 для контекста скелетов.
2. Проверить что `.env.dev` содержит 7 ключей (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET`, `SENTRY_DSN_BACKEND`, `VITE_SENTRY_DSN_FRONTEND`) — они уже записаны Координатором, верификация чтением файла.
3. Декомпозировать на три конкретные проверки для devops, сформулировать ему дев-бриф (отдельный файл `devops-brief-live-activation-2026-04-19.md` уже готов Директором — Ваша задача передать его дословно).
4. Принять результат devops (round-trip review): прочесть его отчёт + проверить, что в Sentry UI реально видны события (либо попросить devops приложить скриншоты / event-id).
5. Сдать сводным отчётом infra-director (мне) одним сообщением: три вердикта (Ready / Blocked / Partial) + найденные артефакты (event-id, имя WAL-файла в бакете, точный S3 URI) + список изменённых файлов.

**Что НЕ делаете:**
- Не пишете код. Код пишет devops.
- Не создаёте бакет в Яндекс Cloud UI — бакет уже создан Владельцем (по §«Действия Владельца» предыдущего брифа).
- Не гоняете `pg_basebackup_weekly.sh` — он вне скоупа волны.
- Не включаете `archive_mode = on` в postgresql.conf на этой волне — это М-OS-1.1A отдельная задача. Здесь только ручной single-push через `aws s3 cp` любого файла (любой dummy-WAL или тестовый файл).

## 3. Передача брифа сотруднику

Файл `/root/coordinata56/docs/pods/cottage-platform/tasks/devops-brief-live-activation-2026-04-19.md` — готов, подписан infra-director. В нём три конкретных шага с командами и acceptance. Вы передаёте его devops как есть; если нужна локальная правка (уточнение формулировки) — делайте и сообщите Координатору в сводном отчёте.

## 4. FILES_ALLOWED (ваш скоуп review)

Overlap-zones проверены против active-zones.md на 2026-04-19: backend-dev-1 работает с `backend/app/models/*.py`, `backend/alembic/versions/`, `backend/app/services/*scoped*.py`; frontend-dev-1 работает с MSW-handlers и `shared/api/permissions.ts`. **Overlap нулевой** — devops трогает отдельные файлы.

devops может менять / создавать **только**:

- `/root/coordinata56/.env.dev` — читает, не пишет (уже заполнен Координатором)
- `/root/coordinata56/infra/backups/wal_archive.sh` — **не менять** (скелет корректен); вызывать в режиме `s3` через прямой bash-тест
- `/root/coordinata56/backend/app/api/dev_trigger.py` — **создать** (новый файл, dev-only endpoint)
- `/root/coordinata56/backend/app/main.py` — подключить роутер `dev_trigger_router` (одна строка импорт + одна строка `include_router`, под условием `if settings.app_env == "development"`)
- `/root/coordinata56/frontend/src/pages/admin/SentryTestPage.tsx` — **создать** (новая dev-страница с кнопкой)
- `/root/coordinata56/frontend/src/routes.tsx` — добавить роут `/admin/sentry-test` под условием `import.meta.env.DEV`
- `/tmp/wal-live-test-*` — временные файлы для S3 push (удалить после теста)

**Запрещено трогать** (overlap с другими волнами): `backend/app/models/`, `backend/alembic/`, `docker-compose.yml`, `postgresql.conf`, `.github/workflows/`, любые файлы в `frontend/src/mocks/`, `frontend/src/shared/api/permissions.ts`.

## 5. Acceptance criteria (ваш чек-лист как Head'а)

При приёме работы от devops Вы обязаны убедиться:

### П1 — WAL→S3 livecheck

- [ ] devops приложил лог `aws s3 cp` без ошибок (exit 0, без stderr)
- [ ] `aws s3 ls s3://coordinata56-wal/wal/ --endpoint-url=https://storage.yandexcloud.net` возвращает минимум один объект с именем тест-файла
- [ ] Имя тестового файла и размер фигурируют в отчёте devops
- [ ] Ключи не попали в git (`git status` чист по `.env.dev`, `.gitignore` содержит `.env.dev`)
- [ ] Тестовый файл из `/tmp/` удалён после проверки

### П2 — Sentry backend livecheck

- [ ] devops приложил event-id (формат: 32-символьный hex) из ответа Sentry
- [ ] В UI `https://sentry.io/organizations/.../projects/coordinata56-backend/` виден issue с типом `ZeroDivisionError` (или другим намеренным), timestamp ≤ 10 мин от момента теста
- [ ] Dev-endpoint действительно отключается в production (`if settings.app_env == "development"` — grep показывает условие)
- [ ] `main.py` include_router тоже под условием env == development (не всегда-on)

### П3 — Sentry frontend livecheck

- [ ] В Sentry UI frontend-проекта виден issue после клика
- [ ] Dev-страница `/admin/sentry-test` **не рендерится** в production build (проверка: `import.meta.env.DEV` guard, в routes.tsx условный импорт)
- [ ] Sentry.init() вызывается — подтверждение из DevTools Network tab (запрос на `o4511247356788736.ingest.de.sentry.io`)

**При любом "Blocked" — НЕ принимать, возвращать devops на доработку с явной причиной.**

## 6. Формат вашего сводного отчёта мне

Один markdown-файл-отчёт (в ответе Координатору, не в `docs/`), структура:

```
## П1 WAL→S3: Ready | Blocked | Partial
- Event/артефакт: <S3 URI тест-файла>
- Файлы изменены: <список>
- Замечания: ...

## П2 Sentry backend: Ready | Blocked | Partial
- Event/артефакт: <event-id>, <ссылка на issue в Sentry UI>
- Файлы изменены: backend/app/api/dev_trigger.py, backend/app/main.py
- Замечания: ...

## П3 Sentry frontend: Ready | Blocked | Partial
- Event/артефакт: <event-id>, <ссылка на issue в Sentry UI>
- Файлы изменены: frontend/src/pages/admin/SentryTestPage.tsx, frontend/src/routes.tsx
- Замечания: ...

## Метрики волны
- Worker: devops (1)
- Round-count review: 1 / 2 / ... (сколько раз возвращал на доработку)
- Cost: Sentry free-tier, Yandex S3 < 1 руб за сам тест
- Open questions для Координатора: ...
```

**Не "три отдельных отчёта на подзадачу"** (§7.5 infrastructure.md запрещает). Один сводный, с тремя секциями.

## 7. Эскалация

Блокер (нет awscli в системе, ключи не работают, Sentry отдаёт 401, DNS не резолвит ingest.de.sentry.io) → немедленно в сводный отчёт Координатору, не крутите 30 минут. Если `aws s3 cp` отдаёт `InvalidAccessKeyId` — ключи не активировались на стороне Яндекс (может быть до 1 минуты после выпуска): дайте 5 минут и повторите один раз. Если `403 SignatureDoesNotMatch` — ключи скопированы с обрезанием, верните Координатору с citation из `.env.dev`.

---

**Подпись:** infra-director, 2026-04-19
**Pattern 5 волна:** открыта сразу после спавна Координатором
