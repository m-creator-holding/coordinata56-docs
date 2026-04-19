# Дев-бриф US-03 — RBAC completeness: матрица object × action + 4 role defaults + require_permission на всех write

- **Дата:** 2026-04-19
- **Автор:** backend-director (через backend-head при распределении)
- **Получатель:** backend-dev-3
- **Фаза:** M-OS-1.1A, Sprint 1 (нед. 1–2), параллельно US-01/US-02
- **Приоритет:** P0 — закрывает RBAC fine-grained completeness (критерий закрытия Sprint 1)
- **Оценка:** L — 4-5 рабочих дней (1 день матрица + seed, 1.5 дня замена `require_role` → `require_permission` на ≈30 write-эндпоинтах, 1.5 дня параметризованный тест, 0.5 дня self-check)
- **Scope-vs-ADR:** verified (ADR 0011 §2 fine-grained RBAC; ответ Владельца Q6 — 7 действий; ADR 0005 ошибки); gaps: none
- **Источник формулировки:** `docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md` §Sprint 1 / US-03 + решение Владельца 2026-04-19 msg 1480 Q6 (7 действий в матрице)
- **Блокируется:** US-01 (`require_permission` использует `user_context.company_id` для проверки prava в конкретной компании).

---

## Контекст

ADR 0011 §2 требует fine-grained RBAC: «доступ = роль + объект + действие», не «роль → все действия». На 2026-04-19:

- Таблицы `permissions`, `roles`, `role_permissions` уже есть (миграция `2026_04_18_1200_ac27c3e125c8_rbac_v2_pd_consent.py`).
- `RbacService.user_has_permission()` уже реализован в `backend/app/services/rbac.py` — `can(resource_type, action, pod_id)`.
- `require_permission(action, resource_type)` уже реализован в `backend/app/api/deps.py` — работает через `RbacService`.
- **Проблема:** матрица `role_permissions` **не seed-ится полностью**. По ADR 0011 предполагалось минимум 20 записей (4 роли × 5 действий). По решению Владельца 2026-04-19 Q6 — **7 действий** (не 5), так что матрица расширяется до 4 × 7 × N_ресурсов.
- **Вторая проблема:** существующие write-эндпоинты частично используют `require_role` (deprecated alias), частично — `require_permission`. Нужно закрыть гап: все POST/PATCH/DELETE используют `require_permission`.

---

## Что конкретно сделать

### 1. Действия (actions) — 7 значений

По решению Владельца 2026-04-19 msg 1480 Q6, полный список действий:

| # | action | Описание | Примеры ресурсов |
|---|---|---|---|
| 1 | `read` | Чтение (GET) | все |
| 2 | `write` | Создание/обновление (POST/PATCH) | все |
| 3 | `delete` | Удаление (DELETE) | все |
| 4 | `approve` | Согласование (кнопка «Одобрить») | payment, contract |
| 5 | `reject` | Отклонение (кнопка «Отклонить») | payment, contract |
| 6 | `export` | Выгрузка списка/отчёта | report, audit_log |
| 7 | `admin` | Администрирование — изменение настроек сущности за рамки CRUD (например, изменение матрицы прав, настроек компании) | role, company_settings, integration_catalog |

Константы — в `backend/app/models/enums.py::PermissionAction` (если такой enum ещё нет — создать StrEnum; если есть — дополнить до 7 значений).

### 2. Ресурсы (resource_types)

Минимум покрыть:
- `project`, `contract`, `payment`, `house`, `house_configuration`, `stage`, `contractor`, `material_purchase`, `budget_category`, `budget_plan`, `house_type`, `option_catalog`
- Административные: `role`, `permission`, `role_permission`, `user`, `user_company_role`, `company`, `company_settings`, `audit_log`, `integration_catalog`
- Служебные (для полноты): `report` (будущий)

Итого ≈22 ресурса (уточнить при инвентаризации).

Константы — в `backend/app/models/enums.py::ResourceType` (если отсутствует, создать).

### 3. 4 Role defaults — матрица разрешений

4 дефолтных роли с предустановленными permissions (ADR 0011 §2.2). Матрица для каждой:

**3.1. `admin` (системный администратор холдинга)**
- Все 7 действий на все ресурсы, bypass на уровне `is_holding_owner=True` в JWT.
- Для таблицы `role_permissions` — явно прописываем все строки (не полагаемся на bypass в коде), кроме тех случаев, когда admin — пользователь конкретной компании без `is_holding_owner`.

**3.2. `director` (директор юрлица / проекта)**
- `read` / `write` / `delete` / `approve` / `reject` / `export`: `project`, `contract`, `payment`, `house*`, `stage`, `contractor`, `material_purchase`, `budget*`
- `read` / `export`: `role`, `audit_log`, `company_settings`
- `admin`: не выдаётся

**3.3. `accountant` (бухгалтер)**
- `read` / `write` / `export`: `contract`, `payment`, `contractor`, `budget*`
- `approve` / `reject`: `payment` (в рамках лимита — **лимит пока не реализуем**, в US-03 только проставление права)
- `read`: `project`, `house*`, `material_purchase`, `stage`
- Остальное — нет

**3.4. `foreman` (прораб)**
- `read`: `project`, `contract` (своих договоров), `contractor`, `budget*`
- `read` / `write`: `house*`, `house_configuration`, `stage`, `material_purchase` (принятие материалов)
- Остальное — нет

**Важно:** матрица в seed — это **стартовые defaults**. Администратор юрлица (через Admin UI в 1.1B) может править её под свои нужды — поэтому матрица лежит в таблице БД, не в коде.

**Число строк в seed:** (admin ≈ 22×7=154) + (director ≈ 70) + (accountant ≈ 30) + (foreman ≈ 20) = ≈ 274 строки. Порядок верный; точное число зависит от инвентаризации ресурсов.

### 4. Seed-миграция

**Файл:** `backend/alembic/versions/2026_04_19_XXXX_us03_rbac_defaults_seed.py`

Миграция:
1. **Not schema change** — только data (INSERT в `permissions`, `roles`, `role_permissions`).
2. Использует `bulk_insert` SQLAlchemy, не raw SQL, чтобы соблюсти линт (ADR 0013).
3. Идемпотентность: `ON CONFLICT DO NOTHING` на `(role_id, permission_id, pod_id)` — чтобы повторный запуск не ломал.
4. Downgrade: удаляет ТОЛЬКО те строки, которые создала эта миграция (по `granted_by` = null или по специальному маркеру `seed_version='us03'` — уточнить со структурой `role_permissions`).

Если `seed_version` поля нет — заводить **не нужно**: можно удалить по JOIN `(role.name, permission.action, permission.resource_type)` — это однозначный ключ.

### 5. Замена `require_role` → `require_permission` на всех write-эндпоинтах

**Файлы:** все `backend/app/api/*.py` кроме `auth.py`, `health.py`, `system.py`, `_stub_utils.py`, `deps.py`.

Для каждой POST/PATCH/DELETE-ручки:
1. Убрать `Depends(require_role(...))`.
2. Поставить `Depends(require_permission(action="<action>", resource_type="<resource>"))`.
3. Action определяется по HTTP-методу: POST/PATCH → `write`, DELETE → `delete`, спец-эндпоинты `/approve` → `approve`, `/reject` → `reject`, `/export` → `export`.
4. **Не убирать** `require_role` из `deps.py` (это deprecated alias, сохраняется до M-OS-1.3 — см. ADR 0011 §2.4).

**Inventory:** ≈30 write-эндпоинтов в 22 файлах `api/`. Пройтись по всем, составить таблицу «было → стало» в отчёте.

### 6. Параметризованный тест матрицы

**Файл (новый):** `backend/tests/test_rbac_matrix_completeness.py`

Параметризованный тест, проверяющий что:
1. Каждая из 4 ролей имеет корректный набор permissions в БД (seed применён).
2. Каждый write-эндпоинт при вызове с каждой из 4 ролей даёт ожидаемый (success / 403) результат.

Структура:
```python
import pytest

RBAC_MATRIX = [
    # (role, action, resource, endpoint, expected_status)
    ("admin", "write", "contract", "POST /api/v1/contracts", 201),
    ("director", "write", "contract", "POST /api/v1/contracts", 201),
    ("accountant", "write", "contract", "POST /api/v1/contracts", 201),
    ("foreman", "write", "contract", "POST /api/v1/contracts", 403),
    ("foreman", "approve", "payment", "POST /api/v1/payments/{id}/approve", 403),
    ("accountant", "approve", "payment", "POST /api/v1/payments/{id}/approve", 200),
    ("director", "delete", "contract", "DELETE /api/v1/contracts/{id}", 200),
    ("foreman", "delete", "contract", "DELETE /api/v1/contracts/{id}", 403),
    ...
]

@pytest.mark.parametrize("role,action,resource,endpoint,expected_status", RBAC_MATRIX)
async def test_rbac_matrix(test_client, seeded_users, role, action, resource, endpoint, expected_status):
    ...
```

**Минимум 32 записи в матрице:** 4 роли × 8 ключевых (action, resource) пар. Полное покрытие (4 × 22 × 7 = 616 комбинаций) не требуется — фокус на ключевых бизнес-сценариях:

| role × (action, resource) | expected |
|---|---|
| admin × (write, contract) | 201 |
| director × (write, contract) | 201 |
| accountant × (write, contract) | 201 |
| foreman × (write, contract) | 403 |
| accountant × (approve, payment) | 200 |
| director × (approve, payment) | 200 |
| foreman × (approve, payment) | 403 |
| foreman × (write, house) | 201 |
| accountant × (delete, contract) | 403 |
| director × (delete, contract) | 200 |
| accountant × (export, payment) | 200 |
| foreman × (export, payment) | 403 |
| director × (admin, role) | 403 (директор не админ матрицы) |
| admin × (admin, role) | 200 |
| … и ещё 20+ на другие ресурсы (houses, materials, budgets) |

### 7. Документация

В `backend.md` правила 3-11 не меняются; но в отчёте указать — если по ходу возникли повторяющиеся ошибки (например, забыт `approve` action на payment) — это триггер для backend-director обновить `departments/backend.md` (после Sprint 1 закрытия).

### 8. Самопроверка

- [ ] Прочитан `CLAUDE.md` (секции «API», «Код»), `departments/backend.md` (ADR-gate A.1–A.5)
- [ ] Прочитан ADR 0011 §2 полностью
- [ ] Выполнен ADR-gate:
  - A.1 — никаких литералов секретов в тестовых фикстурах
  - A.2 — SQL только через репозитории (seed-миграция — через `bulk_insert`, не raw SQL)
  - A.3 — все write-эндпоинты имеют `require_permission` с `user_context`; таблица «было → стало» в отчёте
  - A.4 — 403 в формате ADR 0005 (не `{"detail": ...}`)
  - A.5 — аудит-записи `require_permission` events уже логируются через `RbacService` (проверить, что не сломали)
- [ ] `cd backend && python -m tools.lint_migrations alembic/versions/2026_04_19_*` — зелёный
- [ ] `cd backend && alembic upgrade head && alembic downgrade -1 && alembic upgrade head` — зелёный
- [ ] `cd backend && pytest backend/tests/test_rbac_matrix_completeness.py -v` — все зелёные
- [ ] `cd backend && pytest` — все 351+ существующих тестов зелёные
- [ ] `cd backend && ruff check app tests` — 0 ошибок
- [ ] `cd backend && mypy app` — нет новых ошибок
- [ ] `git status` — только файлы из FILES_ALLOWED
- [ ] Не коммитить

---

## DoD

1. Enum `PermissionAction` содержит 7 значений (read, write, delete, approve, reject, export, admin).
2. Enum `ResourceType` охватывает ≥22 ресурса.
3. Seed-миграция `2026_04_19_*_us03_rbac_defaults_seed.py` создаёт defaults для 4 ролей, линт + round-trip зелёные.
4. Все ≈30 write-эндпоинтов используют `require_permission` вместо `require_role`.
5. `require_role` в `deps.py` сохранён как deprecated alias (не удаляется).
6. Тест `test_rbac_matrix_completeness.py` покрывает ≥32 параметризованные комбинации, все зелёные.
7. Все 351 существующих тестов зелёные.
8. `ruff`, `mypy`, `lint-migrations`, `round-trip` — все зелёные.

---

## FILES_ALLOWED

- `backend/app/models/enums.py` — дополнить `PermissionAction` и `ResourceType`
- `backend/alembic/versions/2026_04_19_*_us03_rbac_defaults_seed.py` — **создать**
- `backend/app/api/projects.py`, `contracts.py`, `payments.py`, `houses.py`, `contractors.py`, `material_purchases.py`, `stages.py`, `house_types.py`, `option_catalog.py`, `budget_categories.py`, `budget_plans.py`, `roles.py`, `role_permissions.py`, `permissions.py`, `user_roles.py`, `users.py`, `companies.py`, `company_settings.py`, `integrations.py`, `audit.py`, `bank_accounts.py` — замена `require_role` → `require_permission` на write-ручках
- `backend/tests/test_rbac_matrix_completeness.py` — **создать**
- `backend/tests/conftest.py` или отдельные tests/conftest — добавить фикстуру `seeded_users` (4 user с 4 ролями), если её нет

## FILES_FORBIDDEN

- `backend/app/api/deps.py` — `require_role` deprecated alias **не удалять**; `require_permission` уже готов
- `backend/app/services/rbac.py`, `company_scoped.py`, `base.py` — не трогать
- `backend/app/models/role.py`, `permission.py`, `role_permission.py` — ORM-модели не менять
- `backend/app/api/auth.py`, `health.py`, `system.py`, `_stub_utils.py` — не трогать
- `frontend/**`, `docs/**` (кроме отчётного сообщения)
- `.github/workflows/**`

---

## Зависимости

- **Блокирует:** ничего напрямую в Sprint 1; Sprint 2 US-05/US-07 пользуются стабильным `require_permission`.
- **Блокируется:** US-01 (`company_id` — частично; `require_permission` уже работает и без US-01, но параметризованный тест в §6 требует compose «user компании A + role admin компании A» → company_id должен быть на ресурсах).

---

## COMMUNICATION_RULES

- Перед стартом — прочитать `CLAUDE.md`, `departments/backend.md`, ADR 0011, `backend/app/services/rbac.py`, `backend/app/api/deps.py::require_permission`.
- Если при инвентаризации (§2) число ресурсов >30 — **стоп, эскалация backend-head**. Скорее всего, взяли таблицу, которая не должна быть resource_type (например, связь-таблица без прав).
- Если при замене `require_role` → `require_permission` на каком-то endpoint не понятно, какой `action` поставить (нестандартный case, например, `POST /import-csv`) — **стоп, эскалация backend-head → backend-director**. Не «угадывать».
- Если seed-миграция при запуске на чистой БД падает (FK violation на `role_id` или `permission_id`) — проверить порядок: сначала `permissions` bulk_insert, потом `roles`, потом `role_permissions`. Не полагаться на лексикографический порядок.
- Матрицу в коде НЕ хардкодить в сервисе — она живёт только в seed-миграции (и через 1.1B будет Admin UI).
- Никаких сторонних зависимостей.

---

## Обязательно прочитать перед началом

1. `/root/coordinata56/CLAUDE.md` — секции «API», «Код», «Git»
2. `/root/coordinata56/docs/agents/departments/backend.md` — ADR-gate A.1–A.5, правила 1–11
3. `/root/coordinata56/docs/adr/0011-foundation-multi-company-rbac-audit.md` — §2 полностью
4. `/root/coordinata56/docs/adr/0005-api-error-format.md` — 403 в ADR 0005 формате
5. `/root/coordinata56/docs/adr/0013-migrations-evolution-contract.md` — правила seed-миграций
6. `/root/coordinata56/backend/app/services/rbac.py` — реализация `can()` и `user_has_permission`
7. `/root/coordinata56/backend/app/api/deps.py` — `require_permission` фабрика
8. `/root/coordinata56/backend/app/models/role_permission.py` — модель связи

---

## Отчёт (≤ 300 слов)

Структура:
1. **Enum-ы** — `PermissionAction` (7 значений), `ResourceType` (число значений).
2. **Seed-миграция** — путь, число вставляемых строк в `permissions`/`roles`/`role_permissions`, результат `lint-migrations` и `round-trip`.
3. **Замена require_role → require_permission** — таблица из ≥30 эндпоинтов «файл:строка: старый → новый» в сокращённом виде (группировка по файлам).
4. **Тест** — путь, число параметризованных кейсов, результат `pytest`.
5. **Существующие тесты** — результат `pytest` на 351+ тестов.
6. **ADR-gate** — A.1/A.2/A.3/A.4/A.5 pass/fail + артефакты.
7. **Отклонения от scope** — если были.
