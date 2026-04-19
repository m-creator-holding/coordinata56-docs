# Бриф backend-head: Zero-version OpenAPI stub — admin-эндпоинты для 4 доменов

- **От:** backend-director
- **Кому:** backend-head
- **Дата:** 2026-04-18
- **Тип задачи:** S-уровень (один backend-dev, 0.5–1 день)
- **Паттерн:** Координатор-транспорт v1.6 — Координатор передаёт этот бриф Head'у; Head декомпозирует на backend-dev.
- **Статус брифа:** одобрен Координатором 2026-04-18.
- **Параллельность:** работа **параллельна PR #1 Волны 1**. Не трогает `backend/alembic/versions/`, не трогает тесты линтера миграций — конфликтов нет.

---

## 1. Цель задачи

Зафиксировать **контракт (форму URL, HTTP-метод, имена полей схем)** admin-эндпоинтов для 4 доменов `auth / companies / users / roles`, **не реализуя бизнес-логику**. Все 20 эндпоинтов (4 домена × 5 CRUD) возвращают HTTP 501 Not Implemented с единым форматом ответа по ADR 0005.

**Зачем это нужно сейчас:**

1. **Разблокировать frontend-director** на проектирование Admin UI поверх стабильного OpenAPI (ADR-0018 «Admin UI contract поверх OpenAPI», пишется backend-director параллельно). Фронт может начать wireframes и API-клиент сразу, не дожидаясь реализации.
2. **Зафиксировать именование схем** до того, как PR #2 (RBAC v2) начнёт их наполнять реальными моделями. Переименование потом — дороже, чем договориться сейчас.
3. **OpenAPI-снимок** попадёт в Swagger UI, его можно показывать внешним интеграторам и тестировщикам без риска «прилетит настоящий ответ и сломает тесты».

## 2. Что это НЕ

- **Это не имплементация бизнес-логики.** Никаких SQLAlchemy-запросов в новых роутерах. Никаких `audit_service.log()`. Никаких `require_role(...)` — только заглушка, возвращающая 501 сразу.
- **Это не миграции.** Никаких изменений в `backend/alembic/versions/`.
- **Это не переопределение существующих `/auth/login`, `/auth/register`, `/auth/me`.** Они остаются как есть (реализованы).
- **Это не часть RBAC v2 (PR #2).** PR #2 потом заменит stub-эндпоинты на реальные. До этого — 501.

## 3. Источники (обязательно прочесть исполнителю)

1. `/root/coordinata56/CLAUDE.md` — проектные правила.
2. `/root/coordinata56/docs/agents/departments/backend.md` — регламент отдела.
3. `/root/coordinata56/docs/adr/0005-api-error-format.md` — формат ошибок (для тела 501-ответа).
4. `/root/coordinata56/docs/adr/0011-foundation-multi-company-rbac-audit.md` — модели `Company`, `User`, `UserCompanyRole`, enum'ы `UserRole`, `CompanyType`.
5. Существующий эталон: `backend/app/api/auth.py`, `backend/app/api/projects.py` — стиль роутера, `response_model`, summary/description.
6. `backend/app/models/user.py`, `backend/app/models/company.py`, `backend/app/models/user_company_role.py` — поля моделей, чтобы схемы Read совпадали по именам с будущими реальными ответами.

## 4. Скоуп задачи — 20 эндпоинтов-заглушек (4 домена × 5 CRUD)

Для каждого домена — **стандартный CRUD-5**:

| # | Метод | Путь | Что | response_model (Pydantic-схема) |
|---|---|---|---|---|
| 1 | GET | `/{resource}` | List с пагинацией | `Paginated{Resource}Response` |
| 2 | GET | `/{resource}/{id}` | Retrieve | `{Resource}Read` |
| 3 | POST | `/{resource}` | Create | `{Resource}Read` (201) |
| 4 | PATCH | `/{resource}/{id}` | Update (частичный) | `{Resource}Read` |
| 5 | DELETE | `/{resource}/{id}` | Delete | `204 No Content` |

### Домен 1. `auth` — admin-функции (не `/login`, `/register`, `/me`)

**Префикс:** `/api/v1/auth/sessions` (активные сессии пользователей; `/login` и `/me` — не трогаем).

- `GET /auth/sessions` — список активных сессий (для admin).
- `GET /auth/sessions/{id}` — одна сессия.
- `POST /auth/sessions` — принудительная выдача сессии (сервисный сценарий).
- `PATCH /auth/sessions/{id}` — продление / перевыпуск.
- `DELETE /auth/sessions/{id}` — принудительный logout.

Файл: `backend/app/api/auth_sessions.py`.

**Схемы (в `backend/app/schemas/auth_session.py`):**
- `AuthSessionRead`: `id: int`, `user_id: int`, `created_at: datetime`, `expires_at: datetime`, `ip: str | None`.
- `AuthSessionCreate`: `user_id: int`, `ttl_seconds: int`.
- `AuthSessionUpdate`: `ttl_seconds: int | None = None`.
- `PaginatedAuthSessionResponse`: `{ items: list[AuthSessionRead], total: int, offset: int, limit: int }` (envelope ADR 0006).

### Домен 2. `companies`

**Префикс:** `/api/v1/companies`.

Файл: `backend/app/api/companies.py`.

**Схемы — в уже существующем `backend/app/schemas/company.py`.** Если каких-то Create/Update/Paginated нет — добавить. `CompanyRead` должен совпадать по полям с моделью `Company` (`id, inn, kpp, full_name, short_name, company_type, is_active`).

### Домен 3. `users` — admin-функции

**Префикс:** `/api/v1/users`.

Файл: `backend/app/api/users.py`.

**Схемы — в уже существующем `backend/app/schemas/auth.py` (`UserRead`) + добавить в `backend/app/schemas/user_admin.py`:**
- `UserAdminUpdate`: `full_name: str | None`, `is_active: bool | None`, `role: UserRole | None` (частичный patch).
- `PaginatedUserResponse` — envelope.
- `UserCreate` — уже есть в `auth.py`.

### Домен 4. `roles`

**Префикс:** `/api/v1/roles`. Операции над `UserCompanyRole`.

Файл: `backend/app/api/roles.py`.

**Схемы — в уже существующем `backend/app/schemas/user_company_role.py`.** Если Create/Update/Paginated отсутствуют — добавить. `RoleRead` = `UserCompanyRoleRead` с полями `id, user_id, company_id, role_template, pod_id, granted_at, granted_by`.

## 5. Формат тела 501-ответа (строго)

**Каждый из 20 эндпоинтов** возвращает:

```python
from fastapi import HTTPException, status

raise HTTPException(
    status_code=status.HTTP_501_NOT_IMPLEMENTED,
    detail={
        "error": {
            "code": "not_implemented",
            "message": "Endpoint is a zero-version stub; implementation scheduled in PR #2 (RBAC v2).",
            "details": {"stub": True, "tracking": "wave-1-pr-2"}
        }
    },
)
```

**Замечание:** глобальный exception handler ADR 0005 уже оборачивает `HTTPException` в формат `{"error": {...}}`. Если для 501 существующий handler не срабатывает (например, он фильтрует только 400/403/404/422) — **это не задача stub-PR**. Head фиксирует в отчёте: «501 возвращается прямо, глобальный handler не изменялся». Изменение handler'а — отдельный тикет.

## 6. Регистрация роутеров

В `backend/app/main.py` добавить 4 строки:

```python
from app.api import auth_sessions, companies, users, roles

app.include_router(auth_sessions.router, prefix="/api/v1")
app.include_router(companies.router, prefix="/api/v1")
app.include_router(users.router, prefix="/api/v1")
app.include_router(roles.router, prefix="/api/v1")
```

Проверить, что в `app.api.__init__.py` (если там есть реэкспорт) новые модули не сломают существующий импорт.

## 7. Swagger / OpenAPI требования

- **Каждый из 20 эндпоинтов** имеет:
  - `summary` (1 строка, на русском),
  - `description` (≥1 предложение, заканчивается `"Зaглушка нулевой версии; полная реализация — PR #2."`),
  - `response_model` (указанный в §4),
  - `responses={501: {"description": "Not implemented yet (stub)"}}` явно.
- OpenAPI схема, генерируемая FastAPI, должна содержать все 20 operationId (`list_companies`, `get_company`, `create_company`, ...). Имена — `{verb}_{resource_singular}` для item-эндпоинтов и `{verb}_{resource_plural}` для list.
- На `/docs` и `/redoc` 4 новых тега: `auth-sessions`, `companies`, `users`, `roles`. Каждый роутер декларирует свой tag в `APIRouter(prefix="/resource", tags=["resource"])`.

## 8. Тесты (обязательный минимум)

Файл: `backend/tests/test_zero_version_stubs.py`.

- Параметризованный тест по списку из **20 (метод, путь)** пар — каждый возвращает 501.
- Для каждого — проверка, что response body содержит `error.code == "not_implemented"` и `error.details.stub is True`.
- Для каждого — проверка, что Swagger JSON (`GET /openapi.json`) содержит operationId и правильный response_model ($ref на Pydantic-схему).
- **Тестов: ≥25** (20 основных + 5 на форму ошибки и OpenAPI-контракт).

## 9. DoD задачи

- [ ] 4 новых роутера созданы и зарегистрированы в main.
- [ ] Все 20 эндпоинтов возвращают 501 с форматом §5.
- [ ] Pydantic-схемы для всех 4 доменов присутствуют, `PaginatedXxxResponse` реализованы через envelope ADR 0006.
- [ ] `pytest backend/tests/test_zero_version_stubs.py -q` — зелёный.
- [ ] `ruff check backend/app/api/ backend/app/schemas/ backend/tests/test_zero_version_stubs.py` — чисто.
- [ ] Swagger UI (`/docs`) показывает 20 новых эндпоинтов под 4 тегами.
- [ ] `openapi.json` генерируется без ошибок; в нём 20 новых operationId.
- [ ] Проектные правила соблюдены: типы на публичных функциях, никаких секретов-литералов.
- [ ] Ревью backend-head — approve.
- [ ] Ревью reviewer — approve.
- [ ] `docs/agents/departments/backend.md` **НЕ трогается**. `CLAUDE.md` **НЕ трогается**.

## 10. Ревью-маршрут

Тот же, что у PR #1:

1. backend-dev → backend-head (ревью файлов).
2. backend-head → review-head → reviewer (соответствие CLAUDE.md, ADR 0005/0006).
3. Reviewer approve → backend-head → backend-director → Координатор (git commit).

## 11. Оценка и состав

- **1 × backend-dev** (Sonnet, параллельно с backend-dev на PR #1 — или последовательно, решает Head).
- **Оценка:** 0.5–1 рабочий день чистой работы + 0.5 дня ревью.
- **Срок:** 2026-04-19 (следующий день), если запуск сегодня.

## 12. FILES_ALLOWED

- `backend/app/api/auth_sessions.py` (новый)
- `backend/app/api/companies.py` (новый)
- `backend/app/api/users.py` (новый)
- `backend/app/api/roles.py` (новый)
- `backend/app/schemas/auth_session.py` (новый)
- `backend/app/schemas/user_admin.py` (новый)
- `backend/app/schemas/company.py` (расширить при необходимости — Create/Update/Paginated)
- `backend/app/schemas/user_company_role.py` (расширить при необходимости)
- `backend/app/schemas/auth.py` (только если нужен `PaginatedAuthSessionResponse` или он размещается здесь — на усмотрение Head'а)
- `backend/app/main.py` (4 строки регистрации роутеров)
- `backend/tests/test_zero_version_stubs.py` (новый)

## 13. FILES_FORBIDDEN

- `backend/alembic/versions/` — никаких миграций.
- `backend/app/models/` — модели не меняются.
- `backend/app/services/` — сервисы не создаются, бизнес-логики нет.
- `backend/app/repositories/` — репозитории не создаются.
- `backend/app/api/auth.py` — существующие `/login`, `/register`, `/me` не трогаются.
- `backend/app/core/exceptions.py` / глобальные handler'ы — не меняются (см. §5 замечание).
- `docs/adr/` — никаких ADR-правок (ADR-0018 пишет Директор отдельно).
- `CLAUDE.md` и `docs/agents/departments/backend.md` — не меняются.
- `pyproject.toml` — новых зависимостей не добавлять.

## 14. COMMUNICATION_RULES

- backend-dev общается только с backend-head;
- Head эскалирует backend-director при сомнениях по контракту;
- Все сомнения по **именованию схем и URL** — к backend-director, а не к frontend-director: имена фиксирует Директор бэкенда, frontend подстраивается (он ждёт стабильный контракт).

## 15. Главные риски

1. **Имя схемы не совпадёт с будущей реальной моделью** → frontend переклеит код дважды. Митигация: schema Read копируем строго с полей существующих SQLAlchemy-моделей (`User`, `Company`, `UserCompanyRole`).
2. **OpenAPI generation ломается из-за имени operationId** → Swagger UI не показывает эндпоинт. Митигация: тест §8 на `openapi.json`.
3. **Глобальный handler перехватывает 501 и даёт детализированный stacktrace** → раскрытие инфраструктуры. Митигация: тест проверяет, что response body содержит только `error.code/message/details`, без стектрейса.

## 16. Что Head возвращает Директору на приёмку

Короткий отчёт в формате §9 брифа PR #1, пункты 1–7. Особое внимание — скриншот или копипаст Swagger UI с 4 новыми тегами и раскрытыми операциями.

---

*Бриф составлен backend-director 2026-04-18 по запросу Координатора. Активация — через Координатора паттерном v1.6.*
