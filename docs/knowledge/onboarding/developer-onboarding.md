# Онбординг разработчика — M-OS / coordinata56

> **Для кого:** backend- и frontend-разработчики, приходящие в проект как подрядчики.
> **Время чтения:** 45–60 минут.
> **Дата:** 2026-04-18

После прочтения этого документа вы сможете поднять локальную среду, написать первый endpoint, пройти ревью и закоммитить рабочий код без нарушения правил проекта.

---

## Шаг 1. Поймите контекст (15 минут)

Прочитайте в этом порядке:

1. [`docs/ONBOARDING.md`](../../ONBOARDING.md) — общая картина проекта (если ещё не читали)
2. [`docs/m-os-vision.md`](../../m-os-vision.md) — что мы строим и зачем
3. [`CLAUDE.md`](../../../CLAUDE.md) в корне проекта — обязательный антипаттерник. Читайте внимательно: каждый пункт появился из реальной ошибки в этом проекте.

Без понимания `CLAUDE.md` вы будете наступать на уже известные грабли.

---

## Шаг 2. Поднимите локальную среду

### Требования

- Docker и Docker Compose (актуальные версии)
- Python 3.12 (для запуска линтеров локально)
- Node.js 20+ (для frontend)
- Git

### Backend

```bash
# Клонировать репозиторий
git clone <repo-url> coordinata56
cd coordinata56

# Скопировать пример конфига и заполнить
cp backend/.env.example backend/.env
# Откройте backend/.env и заполните DATABASE_URL, SECRET_KEY и остальные переменные

# Поднять контейнеры
docker compose up -d

# Проверить, что backend запустился
curl http://localhost:8000/health
# Ожидаемый ответ: {"status": "ok"}

# Открыть автогенерируемую документацию API
# http://localhost:8000/docs
```

### Frontend

```bash
cd frontend
npm install
npm run dev
# Откроется на http://localhost:5173
```

### Запуск тестов

```bash
cd backend
docker compose exec backend pytest --cov=app tests/
```

Покрытие должно быть ≥ 85% строк. Если оно упало после ваших изменений — добавьте тесты перед ревью.

---

## Шаг 3. Разберитесь с архитектурой backend

### Послойная структура (ADR 0004)

Код backend делится на четыре слоя. Каждый слой знает только о нижележащем:

```
router (api/)
  │  принимает HTTP-запросы, валидирует через Pydantic-схемы, вызывает service
  ↓
service (services/)
  │  бизнес-логика, транзакции, вызов audit_service.log(), вызов repository
  ↓
repository (services/ или отдельная папка)
  │  работа с SQLAlchemy: запросы, фильтры, пагинация — только SQL
  ↓
models (models/)
     SQLAlchemy-классы = таблицы в PostgreSQL
```

**Нарушать послойность нельзя.** Если router делает запрос к БД напрямую — это дефект, который поймает Reviewer.

### Обязательные правила backend (из `docs/agents/departments/backend.md`)

- Фильтры коллекций — только в `WHERE`, никогда в Python после `LIMIT`. Иначе пагинация сломается.
- Вложенные ресурсы (`/parents/{pid}/children/{cid}`) — всегда проверяйте `child.parent_id == pid`. При несовпадении — 404, не 403.
- Аудит-лог — в той же транзакции, что и запись. Вызов `audit_service.log()` обязателен в каждом write-методе сервиса.
- Soft-delete: если у модели есть `SoftDeleteMixin`, DELETE выставляет `deleted_at`. Повторный DELETE на удалённый объект → 404.
- Секреты не в коде. Используйте `secrets.token_urlsafe(N)` в тестах.

### Форматы ответов API (ADR 0005, 0006)

Формат ошибки — всегда такой:

```json
{
  "error": {
    "code": "SOME_ERROR_CODE",
    "message": "Понятное сообщение об ошибке",
    "details": {}
  }
}
```

Формат списка — всегда с пагинацией:

```json
{
  "items": [...],
  "total": 42,
  "offset": 0,
  "limit": 20
}
```

Голый массив `[...]` в ответе — дефект. `limit` клиппируется к 200.

### Миграции (ADR 0013)

Миграции пишутся через Alembic. Ряд операций **запрещён в одном шаге** и блокируется CI-линтером:

| Запрещено | Правильный путь |
|---|---|
| `op.drop_column(...)` | Expand/contract: пометить deprecated, через 2 спринта удалить |
| `op.alter_column(..., new_column_name=...)` | Добавить новую колонку + скопировать данные, потом удалить старую |
| `op.alter_column(..., nullable=False)` без `server_default` | Сначала nullable + backfill, потом NOT NULL |
| `op.drop_table(...)` | Переименовать в `_deprecated_<name>`, через 2 спринта удалить |

Перед push: `cd backend && python -m tools.lint_migrations alembic/versions/`

Round-trip проверяется в CI: upgrade → downgrade → upgrade. Если round-trip не проходит — миграция не принята.

---

## Шаг 4. Frontend — что нужно знать

### Структура src/

```
src/
├── admin/        — страницы и компоненты для Admin UI
├── field/        — интерфейс для прорабов (мобильный, оффлайн-first)
├── components/   — переиспользуемые UI-компоненты (shadcn/ui)
├── providers/    — React Context провайдеры (auth, theme, query client)
├── layouts/      — обёртки страниц с навигацией и шапкой
├── lib/          — утилиты: форматирование дат, валюты, api-клиент
└── mocks/        — MSW-хендлеры для работы без бэкенда
```

### Обязательные правила frontend

- Только shadcn/ui компоненты. Не изобретать свои кнопки, инпуты, модалки — они уже есть.
- Tailwind только через классы shadcn/ui или утилиты. Никаких inline-style.
- TanStack Query для всех запросов к API. Прямой `fetch` в компонентах — дефект.
- TypeScript строгий: `noImplicitAny`, `strictNullChecks`. Не обходить через `any`.
- Каждая форма — через `react-hook-form` + `zod` (схема валидации).

### Работа с API

API-клиент централизован в `src/lib/api.ts`. Все запросы идут через него. Базовый URL читается из переменной окружения `VITE_API_URL`.

Состояния загрузки (loading, empty state, error) — обязательны для каждого экрана, где есть запрос к API.

---

## Шаг 5. Архитектурные решения (ADR)

Прочитайте ключевые ADR перед тем, как писать код:

| ADR | Что фиксирует | Ссылка |
|---|---|---|
| 0001 | Модель данных v1: деньги в копейках, soft-delete, TIMESTAMPTZ | [`docs/adr/0001-data-model-v1.md`](../../adr/0001-data-model-v1.md) |
| 0002 | Выбор стека (полное обоснование) | [`docs/adr/0002-tech-stack.md`](../../adr/0002-tech-stack.md) |
| 0003 | Аутентификация: JWT, refresh-token | [`docs/adr/0003-auth-mvp.md`](../../adr/0003-auth-mvp.md) |
| 0004 | Слои кода: router → service → repository | [`docs/adr/0004-crud-layer-structure.md`](../../adr/0004-crud-layer-structure.md) |
| 0005 | Формат ошибок API | [`docs/adr/0005-api-error-format.md`](../../adr/0005-api-error-format.md) |
| 0006 | Пагинация и фильтрация | [`docs/adr/0006-pagination-filtering.md`](../../adr/0006-pagination-filtering.md) |
| 0007 | Аудит-лог: когда и как писать | [`docs/adr/0007-audit-log.md`](../../adr/0007-audit-log.md) |
| 0013 | Правила миграций: что запрещено | [`docs/adr/0013-migrations-evolution-contract.md`](../../adr/0013-migrations-evolution-contract.md) |

Если ваша задача затрагивает multi-company, RBAC или Anti-Corruption Layer — дополнительно прочитайте ADR 0011 и 0014.

---

## Шаг 6. Процесс сдачи задачи

### Чек-лист перед тем как отдать на ревью

Backend:
- [ ] `ruff check backend/` — 0 ошибок
- [ ] `pytest` — все тесты зелёные, покрытие ≥ 85%
- [ ] Каждый write-endpoint вызывает `audit_service.log()`
- [ ] Нет литеральных паролей/токенов в коде и тестах
- [ ] Миграции прошли `lint-migrations` и `round-trip`
- [ ] Формат ошибок — ADR 0005, формат списков — ADR 0006
- [ ] `git status --short` просмотрен перед `git add`

Frontend:
- [ ] TypeScript компилируется без ошибок (`npm run type-check`)
- [ ] Линтер чист (`npm run lint`)
- [ ] Все состояния экрана реализованы: loading, empty, error, success
- [ ] Нет прямых `fetch` вне api-клиента
- [ ] Нет `any` без обоснования в комментарии

### Reviewer

Reviewer получает задачу до `git commit`. Он запускает:

```bash
git diff --staged
```

И проверяет по тому же чек-листу. Если нашёл P0/P1 замечания — коммит не происходит, возвращает на доработку.

P0 — блокирует коммит безусловно (security, дата-потеря, сломанный API).
P1 — блокирует коммит (нарушение ADR, отсутствие аудита, тесты красные).
P2 — замечание без блокировки (стиль, комментарии, именование).

---

## Полезные ссылки

- Swagger (локально): http://localhost:8000/docs
- Регламент отдела backend: [`docs/agents/departments/backend.md`](../../agents/departments/backend.md)
- Регламент отдела frontend: [`docs/agents/departments/frontend.md`](../../agents/departments/frontend.md)
- Антипаттерник: [`CLAUDE.md`](../../../CLAUDE.md) (в корне проекта)
- Все ADR: [`docs/adr/`](../../adr/)
- Журнал известных ошибок: [`docs/knowledge/bug_log.md`](../bug_log.md)

---

*Поддерживается tech-writer (L4 Advisory). Вопросы по онбордингу — через Директора вашего направления.*
