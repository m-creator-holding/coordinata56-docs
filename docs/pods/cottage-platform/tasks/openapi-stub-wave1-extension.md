# Бриф backend-head: Zero-version OpenAPI stub — расширение (Wave 1 Extension)

- **От:** backend-director
- **Кому:** backend-head
- **Дата:** 2026-04-18
- **Тип задачи:** S-уровень (один backend-dev, 0.5–1 день)
- **Паттерн:** Координатор-транспорт v1.6 — Координатор передаёт этот бриф Head'у; Head декомпозирует на backend-dev.
- **Статус брифа:** одобрен Координатором 2026-04-18.
- **Срок сдачи Директору:** 2026-04-19, до обеда (12:00 UTC+3).
- **Параллельность:** фронт уже стартовал Волну 1 (7 admin-экранов) на базовом stub. Волна 2 (Permissions Matrix + Company Settings) заблокирована без этого PR.

---

## 1. Цель задачи

Расширить zero-version OpenAPI stub **ещё 6 группами эндпоинтов** (~17 новых) для разблокировки Волны 2 фронта — Permissions Matrix, Company Settings, Bank Accounts, Integrations Registry, System Config. Все новые эндпоинты возвращают **HTTP 501** в **том же формате**, что и текущий stub (commit `74a066e`).

**Зачем это нужно сейчас:**

1. **Разблокировать Волну 2 admin-экранов M-OS-1.1.** frontend-head стартует 7 экранов сегодня; через 2–3 дня ему нужны Permissions Matrix и Company Settings endpoints.
2. **Зафиксировать именование схем** для `BankAccount`, `Integration`, `SystemConfig`, `FeatureFlag` до того, как PR #2 (RBAC v2) и PR #3 (Audit chain) начнут наполнять реальной логикой.
3. **Подчистить техдолг ревьюера PR #1** — F-3 (dead code `_NARROWING_PAIRS`) и F-4 (дублирование `_STUB_BODY`). Уместно сделать в том же PR, пока мы всё равно трогаем файлы stub'а.

## 2. Что это НЕ

- **Не бизнес-логика.** Никаких SQLAlchemy-запросов, `audit_service.log()`, `require_role(...)` — только 501.
- **Не миграции.** `backend/alembic/versions/` не трогается.
- **Не переопределение существующих ручек.** `/auth/login`, `/auth/register`, `/auth/me` и текущие 20 stub-endpoint'ов остаются как есть.
- **Не новые модели SQLAlchemy.** Pydantic-схемы — да; модели — нет. Поля схем описаны в §4 ниже, соответствовать реальным моделям они будут после PR #2/#3.
- **Не часть RBAC v2 / Audit chain.** Это контрактная фиксация; реальная реализация — в будущих PR.

## 3. Источники (обязательно прочесть исполнителю)

1. `/root/coordinata56/CLAUDE.md` — проектные правила.
2. `/root/coordinata56/docs/agents/departments/backend.md` — регламент отдела.
3. `/root/coordinata56/docs/adr/0005-api-error-format.md` — формат ошибок (тело 501).
4. `/root/coordinata56/docs/adr/0006-pagination-filtering.md` — envelope пагинации.
5. `/root/coordinata56/docs/adr/0011-foundation-multi-company-rbac-audit.md` — модели, enum'ы `UserRole`, `CompanyType`.
6. **Эталон текущего stub:**
   - `backend/app/api/auth_sessions.py` — паттерн роутера (JSONResponse, workaround handler bug, operationId).
   - `backend/tests/test_zero_version_stubs.py` — паттерн параметризованных тестов.
   - `backend/app/schemas/auth_session.py` — паттерн Pydantic-схем.
7. **Бриф-образец:** `docs/pods/cottage-platform/tasks/zero-version-openapi-stub.md` — полный предшественник.
8. **Решения Владельца по M-OS-1** (для per-company settings 7 полей): memory `project_m_os_1_decisions.md` + `docs/pods/cottage-platform/m-os-1-plan.md`.

## 4. Скоуп — 6 групп эндпоинтов

Для каждого роутера: создаётся **новый файл** в `backend/app/api/`, регистрируется в `backend/app/main.py`, получает Pydantic-схемы в `backend/app/schemas/`.

Все эндпоинты ниже **возвращают 501** в формате §5. `response_model` указывает "что будет когда реализуем" — это важно для Swagger и фронтового API-клиента.

### Группа 1. `/api/v1/users/{user_id}/roles` — привязки UserCompanyRole

**Файл:** `backend/app/api/user_roles.py`
**Тег:** `user-roles`
**Схемы:** расширение `backend/app/schemas/user_company_role.py` (не создавать новый файл).

| # | Метод | Путь | operationId | response_model |
|---|---|---|---|---|
| 1 | GET | `/users/{user_id}/roles` | `list_user_roles` | `PaginatedUserCompanyRoleResponse` |
| 2 | POST | `/users/{user_id}/roles` | `create_user_role` | `UserCompanyRoleRead` (201) |
| 3 | DELETE | `/users/{user_id}/roles/{assignment_id}` | `delete_user_role` | `204 No Content` |

**Схемы (добавить, если нет):**
- `UserCompanyRoleCreate`: `company_id: int`, `role_template: UserRole`, `pod_id: str | None = None`.
- `UserCompanyRoleRead`: `id: int`, `user_id: int`, `company_id: int`, `role_template: UserRole`, `pod_id: str | None`, `granted_at: datetime`, `granted_by: int | None` (по полям модели `UserCompanyRole`).
- `PaginatedUserCompanyRoleResponse`: envelope ADR 0006.

**Важно по URL:** это **вложенный** ресурс — `user_id` присутствует в пути для всех трёх операций. `assignment_id` — это `UserCompanyRole.id`.

---

### Группа 2. `/api/v1/roles/permissions` — матрица прав

**Файл:** `backend/app/api/role_permissions.py`
**Тег:** `role-permissions`
**Схемы:** новый файл `backend/app/schemas/role_permission.py`.

| # | Метод | Путь | operationId | response_model |
|---|---|---|---|---|
| 1 | GET | `/roles/permissions` (query: `resource_type: str`) | `get_permissions_matrix` | `PermissionsMatrixRead` |
| 2 | PATCH | `/roles/permissions` | `update_permissions_matrix` | `PermissionsMatrixRead` |

**Схемы:**
- `PermissionCell`: `role: UserRole`, `resource_type: str`, `action: str` (`read`/`write`/`delete`/`admin`), `allowed: bool`.
- `PermissionsMatrixRead`: `resource_type: str`, `cells: list[PermissionCell]`, `updated_at: datetime`.
- `PermissionsMatrixUpdate`: `resource_type: str`, `cells: list[PermissionCell]` (bulk replace для указанного `resource_type`).

**Важно:** `GET` принимает `resource_type` как **query-параметр**, а не path. Это соответствует UI (вкладки по типу ресурса).

---

### Группа 3. `/api/v1/companies/{id}/settings` — per-company settings (7 полей)

**Файл:** `backend/app/api/company_settings.py`
**Тег:** `company-settings`
**Схемы:** новый файл `backend/app/schemas/company_settings.py`.

| # | Метод | Путь | operationId | response_model |
|---|---|---|---|---|
| 1 | GET | `/companies/{company_id}/settings` | `get_company_settings` | `CompanySettingsRead` |
| 2 | PATCH | `/companies/{company_id}/settings` | `update_company_settings` | `CompanySettingsRead` |

**Схемы (7 полей — `project_m_os_1_decisions.md`):**
- `CompanySettingsRead`:
  - `company_id: int`
  - `vat_mode: Literal["general", "simplified_6", "simplified_15", "none"]` — НДС-режим
  - `currency: str` (ISO 4217, default `"RUB"`)
  - `timezone: str` (IANA, default `"Europe/Moscow"`)
  - `work_week: Literal["mon_fri", "mon_sat", "mon_sun"]` — рабочая неделя
  - `units_system: Literal["metric", "imperial"]` (default `"metric"`)
  - `logo_url: str | None`
  - `brand_color: str | None` (hex `#RRGGBB`)
  - `updated_at: datetime`
- `CompanySettingsUpdate`: все поля (кроме `company_id`, `updated_at`) — optional. `exclude_unset=True` при partial update.

---

### Группа 4. `/api/v1/companies/{id}/bank-accounts` — CRUD банковских счетов

**Файл:** `backend/app/api/bank_accounts.py`
**Тег:** `bank-accounts`
**Схемы:** новый файл `backend/app/schemas/bank_account.py`.

| # | Метод | Путь | operationId | response_model |
|---|---|---|---|---|
| 1 | GET | `/companies/{company_id}/bank-accounts` | `list_bank_accounts` | `PaginatedBankAccountResponse` |
| 2 | POST | `/companies/{company_id}/bank-accounts` | `create_bank_account` | `BankAccountRead` (201) |
| 3 | GET | `/companies/{company_id}/bank-accounts/{account_id}` | `get_bank_account` | `BankAccountRead` |
| 4 | PATCH | `/companies/{company_id}/bank-accounts/{account_id}` | `update_bank_account` | `BankAccountRead` |
| 5 | DELETE | `/companies/{company_id}/bank-accounts/{account_id}` | `delete_bank_account` | `204 No Content` |

**Схемы:**
- `BankAccountRead`:
  - `id: int`
  - `company_id: int`
  - `account_number: str` (20 цифр)
  - `bik: str` (9 цифр)
  - `bank_name: str`
  - `correspondent_account: str` (20 цифр)
  - `currency: str` (ISO 4217, default `"RUB"`)
  - `purpose: str | None` — назначение/метка
  - `is_active: bool`
  - `created_at: datetime`
  - `updated_at: datetime`
- `BankAccountCreate`: все обязательные, кроме `id/created_at/updated_at/is_active` (`is_active` default `True` на сервере).
- `BankAccountUpdate`: все optional.
- `PaginatedBankAccountResponse`: envelope.

**Важно:** nested resource — обязательная проверка `bank_account.company_id == company_id` (в реальной реализации — PR #2, в stub'е — не нужна, т.к. возвращаем 501 сразу).

---

### Группа 5. `/api/v1/integrations/*` — Integration Registry

**Файл:** `backend/app/api/integrations.py`
**Тег:** `integrations`
**Схемы:** новый файл `backend/app/schemas/integration.py`.

| # | Метод | Путь | operationId | response_model |
|---|---|---|---|---|
| 1 | GET | `/integrations` | `list_integrations` | `PaginatedIntegrationResponse` |
| 2 | GET | `/integrations/{name}` | `get_integration` | `IntegrationRead` |
| 3 | PATCH | `/integrations/telegram` | `update_telegram_integration` | `IntegrationRead` |
| 4 | POST | `/integrations/telegram/test` | `test_telegram_integration` | `IntegrationTestResult` |

**Схемы:**
- `IntegrationStatus = Literal["active", "unavailable", "disabled"]`
- `IntegrationRead`:
  - `name: str` (идентификатор, например `"telegram"`, `"1c"`, `"rosreestr"`)
  - `display_name: str`
  - `status: IntegrationStatus`
  - `is_editable: bool` (для `telegram` — `True`, для прочих — `False` по ст. 45а CODE_OF_LAWS)
  - `config: dict[str, Any] | None` (сейчас only для telegram; значения — строки)
  - `last_tested_at: datetime | None`
- `IntegrationUpdate`: `config: dict[str, Any]` — обновление конфига (реально применимо только к `telegram`).
- `IntegrationTestResult`: `success: bool`, `message: str`, `tested_at: datetime`.
- `PaginatedIntegrationResponse`: envelope.

**Контрактное ограничение:** эндпоинты `PATCH` и `POST` реализованы **только для `telegram`**. Путь `/integrations/telegram` — литеральный. В UI фронт должен показывать для остальных интеграций (`1c`, `rosreestr`, `bank_adapter`, `ofd`) кнопки как disabled, ориентируясь на `is_editable: false` и `status: "unavailable"` из body GET-ответа. Stub возвращает 501, но эту семантику надо зафиксировать в `description` эндпоинта и в ADR-0017 (пишется Директором параллельно).

---

### Группа 6. `/api/v1/system/*` + `/api/v1/audit/verify`

**Файл:** `backend/app/api/system.py` (и `/audit/verify` — **в этом же файле**, чтобы не плодить роутеры; но тег у него отдельный — `audit`).
**Теги:** `system` (для `/system/*`), `audit` (для `/audit/verify`).
**Схемы:** новый файл `backend/app/schemas/system_config.py`.

| # | Метод | Путь | operationId | Тег | response_model |
|---|---|---|---|---|---|
| 1 | GET | `/system/config` | `get_system_config` | `system` | `SystemConfigRead` |
| 2 | PATCH | `/system/config` | `update_system_config` | `system` | `SystemConfigRead` |
| 3 | GET | `/audit/verify` | `verify_audit_chain` | `audit` | `AuditChainVerifyResult` |

**Схемы:**
- `FeatureFlag`: `name: str`, `enabled: bool`, `description: str | None`.
- `SystemConfigRead`:
  - `base_url: str` (внешний URL сервиса)
  - `api_url: str`
  - `rate_limit_per_minute: int`
  - `max_upload_mb: int`
  - `session_ttl_seconds: int`
  - `feature_flags: list[FeatureFlag]` (ровно **5 флагов**, имена — фронт договорит с ADR-0017, в схеме — произвольный список из 5)
  - `updated_at: datetime`
- `SystemConfigUpdate`: все поля optional (кроме `updated_at`).
- `AuditChainVerifyResult`:
  - `status: Literal["valid", "broken", "not_implemented"]`
  - `verified_up_to: datetime | None`
  - `broken_at_id: int | None`
  - `message: str`

**Важно:** `/audit/verify` в stub'е возвращает 501 с тем же телом. Реальная имплементация — PR #3 (crypto-chain). Путь `/audit/verify` **не** идёт под префиксом `/system/` — это отдельный логический тег, но физически живёт в `system.py` для уменьшения количества файлов.

---

## 5. Формат тела 501-ответа (строго — тот же что в текущем stub)

```python
_STUB_BODY = {
    "error": {
        "code": "not_implemented",
        "message": (
            "Endpoint is a zero-version stub; "
            "implementation scheduled in PR #2 (RBAC v2) / PR #3 (audit chain)."
        ),
        "details": {"stub": True, "tracking": "wave-1-pr-2"},
    }
}
```

Возвращается **через `JSONResponse`**, не через `HTTPException` — это workaround на глобальный handler (см. комментарий в `auth_sessions.py` стр. 22–25: handler конвертирует non-str `detail` через `str()`, ломая JSON).

## 6. F-4: вынос `_STUB_BODY` и `_stub_response()` в общий модуль

**Новый файл:** `backend/app/api/_stub_utils.py`. Содержит:

```python
"""Общие утилиты для zero-version stub эндпоинтов.

Вынесено из auth_sessions.py / companies.py / users.py / roles.py по итогам
ревью PR #1 Волны 1 (замечание F-4). До этого _STUB_BODY дублировался в
4 роутерах дословно.

Возвращается напрямую через JSONResponse, минуя глобальный HTTPException-хендлер,
чтобы структурированный dict-ответ не был сериализован в строку (ADR 0005 handler
конвертирует non-str detail через str(), что ломает JSON-структуру ответа).
"""
from __future__ import annotations

from fastapi import status
from fastapi.responses import JSONResponse

STUB_BODY = {
    "error": {
        "code": "not_implemented",
        "message": (
            "Endpoint is a zero-version stub; "
            "implementation scheduled in PR #2 (RBAC v2) / PR #3 (audit chain)."
        ),
        "details": {"stub": True, "tracking": "wave-1-pr-2"},
    }
}


def stub_response() -> JSONResponse:
    """Единый ответ для всех zero-version stub эндпоинтов — 501 Not Implemented."""
    return JSONResponse(status_code=status.HTTP_501_NOT_IMPLEMENTED, content=STUB_BODY)
```

**Во всех 4 существующих stub-роутерах** (`auth_sessions.py`, `companies.py`, `users.py`, `roles.py`):
- удалить локальные `_STUB_BODY` и `_stub_response()`;
- заменить на `from app.api._stub_utils import stub_response`;
- все вызовы `_stub_response()` → `stub_response()`.

**Комментарий о workaround handler'а** (строки 22–25 в `auth_sessions.py`) — **переехать в docstring `_stub_utils.py`** (см. текст выше). В 4 роутерах этот блок удалить.

Имя `stub_response` (без подчёркивания) выбрано потому что это экспортируемый API модуля. `STUB_BODY` — также без подчёркивания, т.к. является частью публичного контракта утилитарного модуля (может пригодиться в тестах).

## 7. F-3: удалить dead code `_NARROWING_PAIRS`

В `backend/tools/lint_migrations.py` (строки ~114–122) удалить блок:

```python
# Явно сужающие переходы, которые точно запрещены.
_NARROWING_PAIRS: set[tuple[str, str]] = {
    ("Integer", "String"),
    ("BigInteger", "String"),
    ("Text", "String"),
    ("Text", "Varchar"),
    ("Numeric", "Integer"),
    ("Float", "Integer"),
}
```

**Проверка перед удалением:** `grep -rn "NARROWING_PAIRS" /root/coordinata56/backend/` должен вернуть 0 использований помимо самой декларации. Это подтверждено Директором (единственное упоминание — в строке 115). **Тесты линтера должны остаться зелёными после удаления.** Если линтер использует `_NARROWING_PAIRS` косвенно (например, рефлексией) — backend-head эскалирует Директору перед удалением; на данный момент такого нет.

## 8. Регистрация роутеров в `backend/app/main.py`

Добавить **6 импортов** + **6 строк** `include_router`:

```python
from app.api.user_roles import router as user_roles_router
from app.api.role_permissions import router as role_permissions_router
from app.api.company_settings import router as company_settings_router
from app.api.bank_accounts import router as bank_accounts_router
from app.api.integrations import router as integrations_router
from app.api.system import router as system_router

# Zero-version stub эндпоинты — Wave 1 Extension
app.include_router(user_roles_router, prefix="/api/v1")
app.include_router(role_permissions_router, prefix="/api/v1")
app.include_router(company_settings_router, prefix="/api/v1")
app.include_router(bank_accounts_router, prefix="/api/v1")
app.include_router(integrations_router, prefix="/api/v1")
app.include_router(system_router, prefix="/api/v1")
```

Существующие импорты и регистрации **не трогать**. Порядок — блок после текущего комментария «Zero-version stub эндпоинты (PR OpenAPI, wave-1-pr-openapi-stub)».

## 9. Swagger / OpenAPI требования

Каждый из ~17 новых эндпоинтов:
- `summary` (1 строка, на русском),
- `description` (≥1 предложение, заканчивается `"Заглушка нулевой версии; полная реализация — PR #2 (RBAC v2)."` или `"— PR #3 (audit chain)."` для `/audit/verify`),
- `response_model` (указанный в §4),
- `responses={501: {"description": "Not implemented yet (stub)"}}`,
- `operation_id` — строго из таблиц §4 (без автогенерации).

Теги: 6 новых — `user-roles`, `role-permissions`, `company-settings`, `bank-accounts`, `integrations`, `system`, `audit`. Декларируются в `APIRouter(prefix="...", tags=[...])`.

**Регенерация `backend/openapi.json`:** после того, как роутеры зарегистрированы и тесты зелёные, — **запустить генерацию snapshot'а** (скрипт или ручка `/openapi.json` с сохранением в файл). Ожидаемый размер — ~14k строк (текущий 10,951). Файл **должен** попасть в PR.

## 10. Тесты (обязательный минимум ≥50 parametrized)

Расширить существующий `backend/tests/test_zero_version_stubs.py` (не создавать новый файл):

1. **Добавить ~17 новых записей в `_STUB_ENDPOINTS`** с корректными operationId и телами в `_REQUEST_BODIES`:
   - `user_roles`: 3 эндпоинта.
   - `role_permissions`: 2.
   - `company_settings`: 2.
   - `bank_accounts`: 5.
   - `integrations`: 4.
   - `system` + `audit`: 3.
   - **Итого 19** новых (не 17 — `bank-accounts` имеет 5, а не 4, по первоначальному описанию Координатора; см. §4.4).
2. Существующие 4 параметризованных теста автоматически покроют 20 + 19 = **39 случаев**. Плюс 4 теста OpenAPI-контракта = **43 теста**.
3. **Добавить ≥7 целевых тестов** на новые аспекты:
   - `test_openapi_contains_all_new_tags()` — 7 новых тегов присутствуют.
   - `test_user_roles_nested_path_structure()` — `{user_id}` в пути трёх операций.
   - `test_bank_accounts_nested_path_structure()` — `{company_id}` в пути пяти операций.
   - `test_integrations_telegram_patch_only()` — PATCH/POST есть только для `/telegram`, но не для других интеграций (проверка OpenAPI paths: остальные интеграции только GET).
   - `test_audit_verify_returns_not_implemented()` — отдельный тест что `/audit/verify` отдаёт 501 с тем же форматом.
   - `test_stub_utils_module_imported_by_all_routers()` — интроспективный тест: `_STUB_BODY` в `_stub_utils` == response body любого stub-ручки (гарантирует что после F-4-рефакторинга ни один роутер не "забыл" перейти на общий модуль).
   - `test_role_permissions_query_param()` — `GET /roles/permissions?resource_type=company` отдаёт 501 (не 422 от Pydantic).
4. **Итого тестов: ≥50** (39 параметризованных + 4 OpenAPI + 7 целевых).

**Запуск:** `pytest backend/tests/test_zero_version_stubs.py -q` — всё зелёное.

## 11. DoD задачи

- [ ] 6 новых роутеров созданы и зарегистрированы в `main.py`.
- [ ] ~19 новых эндпоинтов возвращают 501 в формате §5.
- [ ] Pydantic-схемы для 6 групп присутствуют; `PaginatedXxxResponse` — через envelope ADR 0006.
- [ ] `backend/app/api/_stub_utils.py` создан; 4 существующих роутера мигрированы на него (F-4).
- [ ] `_NARROWING_PAIRS` удалён из `lint_migrations.py` (F-3).
- [ ] `backend/openapi.json` регенерирован и закоммичен (~14k строк).
- [ ] `pytest backend/tests/test_zero_version_stubs.py -q` — зелёный, ≥50 тестов.
- [ ] `pytest backend/tests/` (полный прогон) — зелёный (миграционный линтер F-3 после удаления мёртвого кода).
- [ ] `ruff check backend/app/api/ backend/app/schemas/ backend/tests/test_zero_version_stubs.py backend/tools/lint_migrations.py` — чисто.
- [ ] Swagger UI (`/docs`) показывает все 6 новых групп под 7 тегами (`user-roles`, `role-permissions`, `company-settings`, `bank-accounts`, `integrations`, `system`, `audit`).
- [ ] Типы на публичных функциях; никаких секретов-литералов; `# type: ignore` / `# noqa` — только с комментарием-обоснованием.
- [ ] Ревью backend-head — approve.
- [ ] Ревью reviewer — approve (через review-head).
- [ ] `docs/agents/departments/backend.md` **НЕ трогается**. `CLAUDE.md` **НЕ трогается**.

## 12. FILES_ALLOWED

**Новые файлы (8):**
- `backend/app/api/_stub_utils.py`
- `backend/app/api/user_roles.py`
- `backend/app/api/role_permissions.py`
- `backend/app/api/company_settings.py`
- `backend/app/api/bank_accounts.py`
- `backend/app/api/integrations.py`
- `backend/app/api/system.py`
- `backend/app/schemas/role_permission.py`
- `backend/app/schemas/company_settings.py`
- `backend/app/schemas/bank_account.py`
- `backend/app/schemas/integration.py`
- `backend/app/schemas/system_config.py`

**Модифицируемые (7):**
- `backend/app/api/auth_sessions.py` (F-4 миграция на `_stub_utils`)
- `backend/app/api/companies.py` (F-4)
- `backend/app/api/users.py` (F-4)
- `backend/app/api/roles.py` (F-4)
- `backend/app/schemas/user_company_role.py` (добавить Create/Read/Paginated)
- `backend/app/main.py` (6 импортов + 6 `include_router`)
- `backend/tools/lint_migrations.py` (F-3 удаление dead code)
- `backend/tests/test_zero_version_stubs.py` (+19 записей, +7 целевых тестов)
- `backend/openapi.json` (регенерация)

## 13. FILES_FORBIDDEN

- `backend/alembic/versions/` — **никаких миграций**.
- `backend/app/models/` — модели не меняются, новых не создаём.
- `backend/app/services/` / `backend/app/repositories/` — сервисы и репозитории не создаются.
- `backend/app/api/auth.py` — `/login`, `/register`, `/me` не трогаются.
- `backend/app/main.py` в части exception-handler'ов — **не трогать**. Добавляем только импорты и `include_router` в существующем блоке.
- `backend/app/errors.py` / `backend/app/core/` — не меняются.
- `docs/adr/` — никаких ADR-правок (ADR-0017 и ADR-0018 пишет Директор отдельно, срок 22 апреля).
- `CLAUDE.md` и `docs/agents/departments/backend.md` — не меняются.
- `pyproject.toml` — новых зависимостей не добавлять (всё делается на stdlib + FastAPI + Pydantic).
- `backend/tests/conftest.py` и другие test-модули — **не трогать**. Работаем только в `test_zero_version_stubs.py`.

## 14. COMMUNICATION_RULES

- backend-dev общается **только** с backend-head.
- backend-head эскалирует backend-director при сомнениях по:
  - именованию схем (`BankAccount` vs `BankAccountInfo`, `FeatureFlag` vs `SystemFeatureFlag` и т.п.);
  - составу 7 полей `CompanySettings` (если выплывает противоречие с `project_m_os_1_decisions.md`);
  - влиянию F-3 на линтер-тесты (если что-то ломается при удалении `_NARROWING_PAIRS`).
- **Frontend-head напрямую backend-dev'у вопросы не задаёт.** Если у фронта по мере работы появятся вопросы по контракту — через frontend-head → frontend-director → backend-director → backend-head → backend-dev. Это фиксирует наш контракт для Волны 2 **до** старта фронтом.
- Все сомнения по **именованию схем** — к backend-director, не к frontend-director. Фронт подстраивается под контракт бэка.

## 15. Главные риски и митигации

| # | Риск | Митигация |
|---|---|---|
| 1 | Имя схемы (`FeatureFlag`, `BankAccount`) столкнётся с будущей SQLAlchemy-моделью | Schema Read копирует поля строго из §4; при создании реальной модели в PR #2/#3 — поля модели подгоняются под схему (stub фиксирует контракт, не наоборот) |
| 2 | Удаление `_NARROWING_PAIRS` сломает латентный тест линтера | backend-head запускает полный `pytest backend/tests/` до коммита; если хоть один fail — эскалация Директору, откат F-3 из этого PR, вынос F-3 в отдельный тикет |
| 3 | `/audit/verify` имеет тег `audit`, но физически живёт в `system.py` — проверяющий может не найти | В `system.py` два роутера: `router = APIRouter(prefix="/system", tags=["system"])` и `audit_router = APIRouter(prefix="/audit", tags=["audit"])`. Оба экспортируются. В `main.py` импорт `from app.api.system import router as system_router, audit_router as audit_router` (2 строки), но регистрация одним блоком. **Альтернатива** (на усмотрение Head'а): создать отдельный `backend/app/api/audit.py` — один эндпоинт, меньше когнитивной нагрузки. **Предпочтительно — отдельный файл.** |
| 4 | Регенерация `backend/openapi.json` может дать discrepancy между локальной машиной и CI (порядок ключей JSON) | Использовать `json.dumps(schema, indent=2, ensure_ascii=False, sort_keys=True)` при сохранении — детерминированный вывод. Если в проекте уже есть скрипт генерации — использовать его |
| 5 | `PermissionCell` с union-типом `action` может быть интерпретирован Pydantic как `str` в OpenAPI | Использовать `Literal["read", "write", "delete", "admin"]` — гарантирует `enum` в OpenAPI schema |
| 6 | Глобальный handler `HTTPException` перехватит 501 и вернёт неправильный формат | Решено в PR #1: `JSONResponse` напрямую. Новые роутеры используют `stub_response()` из `_stub_utils.py` — тот же workaround |

## 16. Ревью-маршрут

Тот же что и PR #1 / zero-version-openapi-stub:

1. backend-dev → backend-head (ревью файлов и тестов).
2. backend-head → review-head → reviewer (соответствие CLAUDE.md, ADR 0005/0006, регламенту backend.md).
3. Reviewer approve → backend-head → backend-director → Координатор (git commit).

Если reviewer находит ≥1 P0 или ≥2 P1 — возврат на доработку. backend-director допускает **максимум 1 раунд** правок, иначе эскалация Координатору (срок критичен — Волна 2 ждёт).

## 17. Что Head возвращает Директору на приёмку

Короткий отчёт (≤300 слов):

1. **Список созданных/изменённых файлов** с краткой пометкой что в каждом.
2. **Результат pytest** (количество тестов, время, список параметризованных случаев).
3. **Результат ruff** (ожидается 0 ошибок).
4. **Подтверждение F-3 и F-4** выполнены (diff `lint_migrations.py` + импорт из `_stub_utils` в 4 роутерах).
5. **Размер `backend/openapi.json`** (до/после) и sanity-check что все новые operationId присутствуют.
6. **Скриншот или копипаст** `/docs` с 7 новыми тегами.
7. **Любые отклонения от брифа** (например, вместо `system.py` разделили на `system.py` + `audit.py` — это ок, но отметить).
8. **Raised concerns** — если backend-head считает, что какое-то решение Директора (именование, структура) стоит пересмотреть — отдельным пунктом.

## 18. Оценка и состав

- **1 × backend-dev** (Sonnet, заморозка паттерна auth_sessions.py).
- **Оценка:** 0.5–1 рабочий день чистой работы + 0.5 дня ревью. Параллельно с любой другой задачей в отделе нельзя — затрагиваются общие файлы (`main.py`, 4 существующих stub-роутера через F-4).
- **Срок backend-dev → Head:** до конца 2026-04-18.
- **Срок Head → Директор:** 2026-04-19 утром.
- **Срок Директор → Координатор:** 2026-04-19 до обеда.

---

*Бриф составлен backend-director 2026-04-18 по запросу Координатора. Активация — через Координатора паттерном v1.6 (Координатор передаёт текст брифа Head'у через Agent-вызов с `subagent_type=backend-head`).*
