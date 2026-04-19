# Бриф backend-head: PR #2 Волны 1 Foundation — RBAC v2 + PD consent (C-1 ФЗ-152)

- **От:** backend-director
- **Кому:** backend-head
- **Дата:** 2026-04-18
- **Тип задачи:** L-уровень (декомпозиция + распределение на ≥1 backend-dev, вероятен db-engineer на seed/backfill)
- **Паттерн:** Координатор-транспорт v1.6 (CLAUDE.md проекта §«Pod-архитектура»)
- **Код Директор не пишет.** Head разбивает 9 пунктов скоупа на задачи backend-dev, собирает PR, проводит ревью уровня файлов, возвращает Директору на приёмку.
- **Статус брифа:** подготовлен для одобрения Координатором 2026-04-18. Активация — после одобрения.
- **Критичность:** **PR #2 — финальный блокер production gate по legal (C-1 ФЗ-152).** Без pd_consent_at/pd_consent_version + middleware require-consent юрист не подписывает запуск. Штраф до 700 тыс ₽ за отсутствие согласия (КоАП 13.11, ред. 01.09.2025).

---

## 1. Цель PR

Одним PR закрыть **два взаимосвязанных блока**, делающих систему production-ready с точки зрения безопасности доступа и соответствия ФЗ-152:

1. **RBAC v2 — реализация ADR 0011 Часть 2 (dynamic permissions).** Таблицы `roles` и `permissions` становятся конфигурируемыми данными (configuration-as-data, принцип 10 ADR 0008), связаны через `role_permissions`. Функция `can(user_context, action, resource)` и декоратор `require_permission` заменяют/оборачивают `require_role`. Админ-эндпоинты `/api/v1/roles` и `/api/v1/permissions` переводятся из zero-version stub в рабочее состояние.
2. **PD consent (ФЗ-152 ст. 22 ред. 24.06.2025).** Поля `pd_consent_at`, `pd_consent_version` в `users`; первая политика версии `v1.0` на основе `docs/legal/drafts/privacy-policy-draft.md`; эндпоинты `GET/POST /api/v1/auth/consent-status` и `/api/v1/auth/accept-consent`; middleware/guard, блокирующий все защищённые эндпоинты при устаревшем или отсутствующем согласии с HTTP 403 `PD_CONSENT_REQUIRED`; `POST /api/v1/auth/login` при выдаче токена проверяет согласие и при его отсутствии возвращает 403 с той же ошибкой (не 401 — чтобы клиент знал, что credentials валидны, но нужен accept-consent flow).

Два блока идут одним PR, а не двумя:
- обе истории меняют `users` и `auth`-поверхность (одна миграция, одна серия тестов);
- PD consent без RBAC v2 не имеет смысла (admin-endpoint работы с политиками требует проверки прав `admin` через новую матрицу);
- разделение удвоило бы цикл ревью и миграций без выигрыша.

**За PR #2 пойдут:**
- PR #3 (Crypto Audit + AuditLog маскирование ПД, C-4): строго после PR #2, потому что запись `pd_consent_accepted` в `audit_log` сама должна идти через новую цепочку.
- PR #4 (ADR 0014 каркас ACL): после PR #3.

## 2. Источники (обязательно прочесть исполнителю)

**Проектные правила:**
1. `/root/coordinata56/CLAUDE.md` — особенно разделы «Данные и БД», «Секреты и тесты», «API», «Код», «Git».
2. `/root/coordinata56/docs/agents/departments/backend.md` — правила отдела, чек-лист самопроверки, правило 1 «Слои строго по ADR 0004» (включая Amendment 2026-04-18 о типизированных предикатах), правила миграций (ADR 0013).

**Нормативные:**
3. `/root/coordinata56/docs/adr/0011-foundation-multi-company-rbac-audit.md` — **Часть 2 §2.1–2.4** (принцип проверки прав, матрица, декоратор, JWT); ссылки на ADR 0004/0005/0006/0007 внутри.
4. `/root/coordinata56/docs/adr/0013-migrations-evolution-contract.md` — expand-pattern для миграций, запреты линтера (в PR #2 важно: все добавления — nullable/additive, никаких DROP/RENAME).
5. `/root/coordinata56/docs/legal/m-os-1-1-foundation-legal-check.md` — **§1.2 (требование 1.2-1, 1.2-4, 1.2-6); §1.4 (требования 1.4-5, 1.4-6); сводный реестр C-1, C-2** и штрафы (стр. «Штрафы (актуально с 30.05.2025)»).
6. `/root/coordinata56/docs/legal/drafts/privacy-policy-draft.md` — источник текста версии `v1.0` (разделы 1–5 принять как v1.0 — метаданные, цели, категории ПД, права субъекта, сроки). Разделы с плейсхолдерами `{ПЛЕЙСХОЛДЕР}` оставить как есть до заполнения юристом.

**Кодовой контекст (существует после PR #1 Волны 1):**
7. `backend/app/models/user.py` — `User` с уже добавленным `is_holding_owner`.
8. `backend/app/models/user_company_role.py` — `UserCompanyRole` с `role_template: UserRole` (enum), **остаётся read-only для backward-compat**. Новая связь: `role_template` enum маппится на `roles.code` при seed.
9. `backend/app/api/deps.py` — `get_current_user`, `require_role` (deprecated alias), `UserContext`.
10. `backend/app/api/auth.py` — `POST /login`, `POST /register`, `GET /me`.
11. `backend/app/api/roles.py`, `role_permissions.py`, `user_roles.py` — **текущие zero-version stubs** (возвращают 501). Эти файлы ЗАМЕНЯЮТСЯ рабочей имплементацией.
12. `backend/app/schemas/user_company_role.py`, `backend/app/schemas/role_permission.py` — существующие stub-схемы. Расширяются/дополняются, существующие поля сохраняются.
13. `backend/app/services/company_scoped.py` — `UserContext`, `CompanyScopedService`. `UserContext` расширяется (см. §5.2).
14. `backend/alembic/versions/2026_04_17_0900_f7e8d9c0b1a2_multi_company_foundation.py` — прецедент seed и safe-migration expand-pattern. **Не трогать.**
15. `backend/tools/lint_migrations.py` — после PR #1 в CI (линтер миграций блокирующий). Все новые миграции должны пройти зелёными.

## 3. Скоуп PR #2 — 9 пунктов с acceptance criteria

Head обязан декомпозировать в задачи для backend-dev в указанном порядке §4. Каждый пункт — самостоятельный acceptance-критерий для ревью.

### Пункт 1. Миграция Alembic (expand-pattern, ADR 0013)

**Что:** один файл в `backend/alembic/versions/` с именем вида `2026_04_18_XXXX_<rev>_rbac_v2_pd_consent.py`. Down-revision — `c34c3b715bcb` (последняя миграция после PR #1, `users_is_holding_owner`).

**Добавляемые объекты:**

1. Таблица `roles`:
   - `id: int PK autoincrement`
   - `code: str(64), NOT NULL, UNIQUE` — `owner`, `accountant`, `construction_manager`, `read_only`, `foreman`, `worker` (последние две — под расширенный набор Волны 1; foreman/worker появляются в seed как новые роли, их нет в enum `UserRole` — это сознательно, чтобы `UserRole` остался узким legacy-контрактом, а новая матрица — расширяемой)
   - `name: str(255), NOT NULL`
   - `description: str(1024), nullable`
   - `is_system: bool, NOT NULL, server_default=true` — системные роли нельзя удалить через API
   - `created_at / updated_at: timestamptz, NOT NULL, server_default now()`

2. Таблица `permissions`:
   - `id: int PK autoincrement`
   - `code: str(128), NOT NULL, UNIQUE` — формат `<resource_type>.<action>`, например `contract.write`, `payment.approve`, `user.admin`, `role.admin`, `*.admin`
   - `resource_type: str(64), NOT NULL` — `contract`, `payment`, `project`, `user`, `role`, `company`, `*`
   - `action: str(32), NOT NULL` — `read`, `write`, `approve`, `delete`, `admin`
   - `name: str(255), NOT NULL`
   - `description: str(1024), nullable`
   - `created_at: timestamptz, NOT NULL, server_default now()`
   - CHECK: `action IN ('read','write','approve','delete','admin')`

3. Таблица `role_permissions`:
   - `id: int PK autoincrement`
   - `role_id: int, FK → roles.id ON DELETE CASCADE, NOT NULL`
   - `permission_id: int, FK → permissions.id ON DELETE CASCADE, NOT NULL`
   - `pod_id: str(64), nullable` — ограничение права конкретным подом (ADR 0011 §2.2)
   - `created_at: timestamptz, NOT NULL, server_default now()`
   - UNIQUE (`role_id`, `permission_id`, `pod_id`) через два партиальных индекса (по образцу `user_company_roles` — один для `pod_id IS NOT NULL`, второй для `pod_id IS NULL`)
   - Индексы: `ix_role_permissions_role_id`, `ix_role_permissions_permission_id`

4. Колонки в `users` (expand, nullable):
   - `pd_consent_at: timestamptz, nullable` — дата принятия актуальной политики
   - `pd_consent_version: str(16), nullable` — версия принятой политики (например, `v1.0`)
   - Оба поля обязательно nullable — иначе миграция сломает существующих пользователей и нарушит ADR 0013.

5. Таблица `pd_policies` (история версий политик обработки ПД):
   - `id: int PK autoincrement`
   - `version: str(16), NOT NULL, UNIQUE` — `v1.0`, `v1.1`, ...
   - `title: str(255), NOT NULL`
   - `body_markdown: text, NOT NULL` — полный текст политики в Markdown (копия из `privacy-policy-draft.md` разделы 1–5)
   - `effective_from: timestamptz, NOT NULL, server_default now()`
   - `is_current: bool, NOT NULL, server_default=true` — ровно одна запись с `is_current=true` (enforced частичным UNIQUE-индексом: `WHERE is_current = TRUE`, колонка `is_current` — ширина 1 строка)
   - `created_at: timestamptz, NOT NULL, server_default now()`
   - Партиальный UNIQUE-индекс: `CREATE UNIQUE INDEX uq_pd_policies_current ON pd_policies(is_current) WHERE is_current = TRUE` — не даёт одновременно иметь две «текущие» версии.

6. **Seed-данные (внутри той же миграции, `op.execute` с маркером `# migration-exception: op_execute — seed RBAC v2 + PD v1.0 (ADR 0011 §2.2 + ФЗ-152 ст. 22)`):**
   - 6 ролей в `roles`: `owner`, `accountant`, `construction_manager`, `read_only`, `foreman`, `worker`.
   - Набор базовых permissions (≈25–30 штук): по комбинациям `resource_type × action` из таблицы ниже.
   - `role_permissions` по матрице ADR 0011 §2.2 + дополнения для новых ролей (см. §5.4 ниже — матрица повторена).
   - Одна запись в `pd_policies`: `version='v1.0'`, `title='Политика обработки персональных данных v1.0'`, `body_markdown` — текст, извлечённый из `privacy-policy-draft.md` разделы 1–5 (плейсхолдеры `{...}` оставить как есть, это заполнит юрист при подготовке продакшна; для MVP важен сам факт наличия версии), `is_current=TRUE`, `effective_from=now()`.

**Downgrade:** в обратном порядке: `DROP TABLE pd_policies`, `DROP COLUMN users.pd_consent_version`, `DROP COLUMN users.pd_consent_at`, `DROP TABLE role_permissions`, `DROP TABLE permissions`, `DROP TABLE roles`. Все через явные вызовы (CASCADE-опираться только на FK ролей/прав, не на users). Round-trip обязан быть чистым.

**Acceptance:**
- Файл миграции проходит `python -m tools.lint_migrations backend/alembic/versions/` — 0 ошибок. Допускается warning `op_execute` **только с маркером `# migration-exception: op_execute — ...`**.
- `alembic upgrade head && alembic downgrade -1 && alembic upgrade head` — чисто.
- Seed роли + базовых permissions + role_permissions успешно отрабатывает на пустой БД.
- `pd_policies` содержит ровно одну запись с `is_current=TRUE` после upgrade.

### Пункт 2. ORM-модели

**Что:** новые модели в `backend/app/models/`:

1. `backend/app/models/role.py` — класс `Role(Base, TimestampMixin)` с полями таблицы `roles`.
2. `backend/app/models/permission.py` — класс `Permission(Base)` с полями таблицы `permissions`.
3. `backend/app/models/role_permission.py` — класс `RolePermission(Base)` с полями таблицы `role_permissions` и unique constraint аналогично `user_company_role`.
4. `backend/app/models/pd_policy.py` — класс `PdPolicy(Base)` с полями таблицы `pd_policies`.
5. Обновление `backend/app/models/user.py`: добавить поля `pd_consent_at: Mapped[datetime | None]`, `pd_consent_version: Mapped[str | None] = mapped_column(String(16), nullable=True)`. Не трогать `role`, `is_holding_owner`.
6. Обновление `backend/app/models/__init__.py`: экспорт новых моделей.

**Правила:**
- `Role.code` и `Permission.code` — `StrEnum`-совместимая строка, но на уровне ORM — обычный `String(64)/(128)`. Это осознанное отступление от паттерна `UserRole: Enum`, потому что матрица прав должна быть расширяемой без миграции (configuration-as-data, ADR 0008 принцип 10).
- Никаких relationship-атрибутов (`relationship(...)`) в моделях на этом PR — используем raw FK + явные join-запросы в репозиториях. Причина: в сервисах правило 1 отдела (нельзя `.execute`) проще соблюдать без implicit lazy-load'ов, а раздувать модели relationship-ами под будущее — over-engineering.

**Acceptance:**
- `ruff check backend/app/models/` чисто.
- Импорт всех новых моделей через `backend/app/models/__init__.py` работает.
- Alembic `autogenerate` не обнаруживает расхождений после миграции из Пункта 1.

### Пункт 3. Pydantic-схемы

**Что:** обновить существующие и создать новые схемы.

**Новые (`backend/app/schemas/`):**

1. `role.py` — `RoleRead`, `RoleCreate`, `RoleUpdate`, `PaginatedRoleListResponse` (не путать с существующим `PaginatedRoleResponse` из `user_company_role.py` — это про `UserCompanyRole`, оставить как есть).
2. `permission.py` — `PermissionRead`, `PermissionCreate` (только для admin, для расширения матрицы), `PaginatedPermissionResponse`.
3. `consent.py` — `ConsentStatusResponse` (`current_version: str`, `user_version: str | None`, `required_action: Literal["accept", "refresh", "none"]`, `policy_effective_from: datetime`), `AcceptConsentRequest` (`version: str` — клиент эхом отправляет принимаемую версию для защиты от race-condition при смене политики между GET и POST).

**Обновляемые:**

4. `role_permission.py` — расширить: добавить `RolePermissionAssignment` (запись в таблице `role_permissions`, поля `role_id`, `permission_id`, `pod_id`), `RolePermissionBulkUpdate` (для PATCH `/api/v1/roles/{id}/permissions` — bulk replace). Сохранить существующие `PermissionCell`, `PermissionsMatrixRead`, `PermissionsMatrixUpdate` — их семантика остаётся (UI-уровень, для вкладок по `resource_type`).
5. `user_company_role.py` — не менять. Read-only связь `role_template: UserRole` сохраняется. Маппинг на `roles.code` — в сервисном слое (при load прав).

**Acceptance:**
- 100% публичных схем имеют docstring и `Field(description=...)` на каждом поле (регламент отдела, стандарт Swagger).
- `ConsentStatusResponse.required_action` — `Literal["accept", "refresh", "none"]`, не `str`. Это форсит клиент на исчерпывающий switch.

### Пункт 4. Репозитории

**Что:** в `backend/app/repositories/`:

1. `role.py` — `RoleRepository(BaseRepository[Role])`.
2. `permission.py` — `PermissionRepository(BaseRepository[Permission])`.
3. `role_permission.py` — `RolePermissionRepository(BaseRepository[RolePermission])` + метод `list_by_role(role_id: int, pod_id: str | None) -> list[RolePermission]`.
4. `pd_policy.py` — `PdPolicyRepository(BaseRepository[PdPolicy])` + метод `get_current() -> PdPolicy | None` (`WHERE is_current = TRUE LIMIT 1`).

**Правила:**
- Все запросы (select, execute, scalar_one, offset/limit) — только здесь. Никаких session.execute в сервисах.
- `list_paginated(extra_conditions: list[ColumnElement[bool]] | None = None)` на каждом репозитории (паттерн `BaseRepository`).

**Acceptance:**
- `ruff check backend/app/repositories/` чисто.
- Каждый метод репозитория покрыт unit-тестом (mock db или реальная session — на усмотрение Head по образцу `test_contract_repository.py`).

### Пункт 5. Сервисный слой

**Что:** `backend/app/services/`:

1. **`rbac.py`** — центральный модуль:

   - Функция `can(user_context: UserContext, action: str, resource) -> bool` — реализация ADR 0011 §2.1. `resource` — объект с `company_id` и опционально `pod_id` (документировать контракт в docstring: допустимо передавать Pydantic-модель, ORM-объект или `SimpleNamespace`).
   - Класс `RbacService` с методами `load_user_permissions(user_id: int, db) -> frozenset[PermissionKey]` (где `PermissionKey = tuple[str, str, str | None]` — `(resource_type, action, pod_id)`), `user_has_permission(user_id, action, resource_type, pod_id=None, company_id=None) -> bool`. Внутри — join `user_company_roles → roles (по role_template=roles.code) → role_permissions → permissions`.
   - Кеш: на PR #2 — in-memory `dict[int, tuple[datetime, frozenset]]` с TTL 5 минут по user_id. Инвалидация по user_id — при любом изменении `user_company_roles` или `role_permissions`, затрагивающем пользователя (вызывается из сервисов `UserCompanyRoleService` и `RolePermissionService`). **Redis — отложить на M-OS-2**, упомянуть в коде TODO с ссылкой на ADR 0011 §«Отрицательные последствия».
   - **Важно про backward-compat:** `UserCompanyRole.role_template` (enum `UserRole`) остаётся источником роли. `load_user_permissions` маппит `role_template.value` → `roles.code` (строки совпадают — `owner`, `accountant`, и т.д.). Это значит: для `foreman`/`worker` на PR #2 никаких пользователей в `user_company_roles` ещё нет — они появятся, когда будет добавлен API назначения новых ролей (отдельная задача после PR #2). Важно, что `roles` уже содержит эти записи — это готовность к расширению, не сам функционал.

2. **`role.py`** — `RoleService` с CRUD: `list`, `get`, `create`, `update`, `delete` (с блокировкой удаления `is_system=TRUE`).

3. **`permission.py`** — `PermissionService` с `list` (фильтрация по `resource_type`, `action`), `get`. Без `create`/`delete` — на PR #2 набор permissions фиксированный из seed; admin получает полный список через `GET`, может только назначать/снимать в `role_permissions`.

4. **`role_permission.py`** — `RolePermissionService` с: `list_by_role(role_id, pod_id)`, `bulk_replace(role_id, pod_id, permission_ids: list[int])` — atomic bulk-replace матрицы для пары (role, pod_id). При вызове — инвалидация кеша RBAC для **всех пользователей с этой ролью** (запрос `SELECT DISTINCT user_id FROM user_company_roles WHERE role_template = :code AND (pod_id = :pod_id OR :pod_id IS NULL)` в репозитории + цикл инвалидации в сервисе).

5. **`user_company_role_service.py`** (новый файл или дополнение существующего — решает Head, предпочтительно новый):
   - `list`, `get_by_user`, `assign(user_id, company_id, role_template, pod_id, granted_by)`, `revoke(assignment_id)`.
   - `assign` валидирует: (a) существует `users.id`, (b) существует `companies.id`, (c) `role_template` валиден (есть в enum `UserRole` ИЛИ существует `roles.code` с таким значением — позволяет назначать новые роли), (d) уникальность (user, company, role_template, pod_id).
   - Каждая write-операция — `audit_service.log()` в той же транзакции (ADR 0007, правило отдела 5).
   - Инвалидация кеша RBAC для user_id при assign/revoke.

6. **`consent.py`** — `ConsentService`:
   - `get_status(user: User) -> ConsentStatusResponse` — сравнение `users.pd_consent_version` с `pd_policies` `is_current=TRUE`. Логика:
     - `current_version`: из `pd_policies.version`.
     - `user_version`: `users.pd_consent_version`.
     - `required_action`: `"accept"` если `user_version is None`; `"refresh"` если `user_version != current_version`; `"none"` если совпадают.
   - `accept(user: User, version: str) -> None` — валидирует, что `version == current_version` (защита от принятия старой), проставляет `pd_consent_at=now()`, `pd_consent_version=version`. Аудит-запись `AuditAction.UPDATE` с `entity_type='user'`, `entity_id=user.id`, `changes_json={"pd_consent_version": {"from": <old>, "to": <new>}}`.

**Правила (жёстко):**
- Сервисы не делают `.execute()`, `.select()`, `session.get()`, `COUNT`, `offset/limit` — только репозитории. Типизированные предикаты (`ColumnElement[bool]`) разрешены (Amendment 2026-04-18, departments/backend.md v1.2).
- Все write-операции — через `audit_service.log()`.
- Никаких `# type: ignore` без комментария-обоснования.

### Пункт 6. Декоратор `require_permission`

**Что:** в `backend/app/api/deps.py`:

1. Новая функция-фабрика:
   ```
   require_permission(action: str, resource_type: str, *, pod_id: str | None = None) -> Depends
   ```
   Логика:
   - Получает `(user, ctx)` из `get_current_user`.
   - Строит placeholder-`resource` на основе `ctx` (для company-scoped ресурсов — `SimpleNamespace(company_id=ctx.company_id, pod_id=pod_id)`).
   - Вызывает `rbac_service.user_has_permission(user.id, action, resource_type, pod_id, ctx.company_id)`.
   - При `False` — `HTTPException(403, PERMISSION_DENIED)` с кодом `PERMISSION_DENIED` (существующий маппинг в `main.py`).
   - При `True` — возвращает пару `(user, ctx)`, чтобы эндпоинт мог использовать `ctx` дальше.

2. Существующий `require_role` остаётся deprecated-alias (не трогать, пока хотя бы один эндпоинт на нём висит). В docstring `require_role` добавить строку: «Deprecated. Новый код использует require_permission. См. PR #2 RBAC v2.»

3. **Не переводить все существующие эндпоинты на `require_permission` в этом PR.** Переведённые в этом PR: только новые эндпоинты (`/roles`, `/permissions`, `/users/{id}/roles`, `/auth/accept-consent`). Остальные мигрируют в отдельном «sweep-PR» — зона ответственности backend-director на планирование после PR #3.

**Acceptance:**
- `require_permission` — чистый, без побочных эффектов при логике `True`.
- Есть тест на `holding_owner bypass` (owner без `UserCompanyRole` всё равно получает доступ).
- Есть тест на cross-company blocking (owner компании A → 403 на ресурс компании B).

### Пункт 7. Admin-эндпоинты (переводят stub'ы в рабочие)

**Что:** заменить заглушки в `backend/app/api/`:

1. **`roles.py`** (был 501):
   - `GET /api/v1/roles` — list, пагинация (ADR 0006), фильтры `is_system`, `code`.
   - `GET /api/v1/roles/{role_id}` — get.
   - `POST /api/v1/roles` — create (required: code, name; is_system=false по умолчанию).
   - `PATCH /api/v1/roles/{role_id}` — update (запрет редактирования `code` если `is_system=true`).
   - `DELETE /api/v1/roles/{role_id}` — 409 если `is_system=true`, 204 иначе.
   - Все эндпоинты требуют `require_permission("admin", "role")`.
   - **Сохранить существующие `operation_id`** (`list_roles`, `get_role`, `create_role`, `update_role`, `delete_role`) — это часть OpenAPI-контракта.

2. **`role_permissions.py`** (был 501):
   - Сохранить существующие `GET /api/v1/roles/permissions?resource_type=...` и `PATCH /api/v1/roles/permissions` с теми же схемами `PermissionsMatrixRead`/`PermissionsMatrixUpdate`. Семантика: матрица как UI-view.
   - **Добавить новые эндпоинты уровня «одна роль»:**
     - `GET /api/v1/roles/{role_id}/permissions?pod_id=...` → `list[RolePermissionAssignment]`.
     - `PATCH /api/v1/roles/{role_id}/permissions` → body `RolePermissionBulkUpdate` (`pod_id: str | None`, `permission_ids: list[int]`). Bulk-replace для данной пары. Atomic по правилу 10 departments/backend.md.
   - **Важно:** `GET /api/v1/roles/permissions` (без `{role_id}`) регистрируется в `main.py` ДО `GET /api/v1/roles/{role_id}` — как сейчас (см. существующий комментарий в `main.py` у регистрации `role_permissions_router`). Проверить, что после замены stub'ов порядок сохраняется.

3. **`user_roles.py`** (был 501):
   - `GET /api/v1/users/{user_id}/roles` — list (пагинация, фильтр `company_id`).
   - `POST /api/v1/users/{user_id}/roles` — assign (body `UserCompanyRoleCreateBody`). **user_id из path должен совпадать с целью**; если попытка назначить чужому — 404 (не 403, чтобы не раскрывать существование другого пользователя). Проверка вложенного ресурса — правило 3 отдела (аналог IDOR-проверки).
   - `DELETE /api/v1/users/{user_id}/roles/{assignment_id}` — revoke. **Проверка:** `UserCompanyRole.id == assignment_id AND user_id == path.user_id` — иначе 404.
   - Все: `require_permission("admin", "user")`.

4. **Новый файл `backend/app/api/permissions.py`:**
   - `GET /api/v1/permissions` — list permissions с пагинацией и фильтрами (`resource_type`, `action`).
   - `GET /api/v1/permissions/{permission_id}` — get.
   - Регистрация в `main.py` с префиксом `/api/v1`. Зарегистрировать ПОСЛЕ `role_permissions_router` и ДО `roles_router` (или в любом порядке, т.к. `/permissions` не конфликтует с `/roles/permissions`).
   - Только `require_permission("read", "permission")` — назначать permissions нельзя (они определены seed'ом).

5. **Новые эндпоинты в `backend/app/api/auth.py`:**
   - `GET /api/v1/auth/consent-status` — возвращает `ConsentStatusResponse`. Требует только аутентификации (`get_current_user_only`), не требует согласия (иначе deadlock).
   - `POST /api/v1/auth/accept-consent` — body `AcceptConsentRequest{version: str}`. Валидация: `version == current`. При успехе — обновление `users.pd_consent_at/version`, аудит-лог. Требует только аутентификации.

**Acceptance:**
- Все новые эндпоинты имеют `summary`, `description`, `response_model`, корректные `responses={...}` с ADR 0005 error-схемой.
- Swagger `/docs` рендерится без warning.
- Все новые эндпоинты вызывают `require_permission` (кроме двух consent-эндпоинтов — они на `get_current_user_only`).
- Все write-эндпоинты вызывают `audit_service.log()`.

### Пункт 8. Guard-зависимость `require_consent` + интеграция в login

**Что:**

1. В `backend/app/api/deps.py` добавить зависимость:
   ```
   async def require_consent(
       pair: tuple[User, UserContext] = Depends(get_current_user),
       consent_service: ConsentService = Depends(get_consent_service),
   ) -> tuple[User, UserContext]
   ```
   Логика: если `get_status(user).required_action != "none"` → `HTTPException(403, code="PD_CONSENT_REQUIRED", message="Требуется принять актуальную версию политики обработки персональных данных", details=[{"field": "current_version", "message": <version>}])`.

2. **Эндпоинты, НЕ требующие consent:** `POST /api/v1/auth/login`, `GET /api/v1/auth/consent-status`, `POST /api/v1/auth/accept-consent`, `GET /api/v1/auth/me`, `GET /api/v1/health`. Всё остальное — через `require_consent` **вместо** или **в дополнение** к `get_current_user`.

3. **Техника подключения:** не переводить все эндпоинты в этом PR. Достаточно:
   - Добавить `require_consent` в `deps.py`.
   - **Применить к login-flow напрямую:** в `POST /api/v1/auth/login` после успешной аутентификации, ДО выдачи токена, проверить consent. Если `required_action != "none"` — вернуть 403 с кодом `PD_CONSENT_REQUIRED` и телом, где `details.current_version` и `details.user_version` заполнены. Токен всё равно **выдаётся** (иначе клиент не сможет вызвать `accept-consent`), но со специальным claim `consent_required: true`. Клиент обязан принять согласие и перелогиниться.
   - Альтернативный вариант (решение Head): не выдавать токен при missing consent, клиент использует temporary token из тела 403. Выбор — за Head с обоснованием в отчёте Директору. Предпочтителен первый вариант (проще, JWT ограничен consent-флоу).

4. В `backend/app/core/security.py` расширить `create_access_token(... , consent_required: bool = False)` и добавить claim.

**Acceptance:**
- Test: `login` пользователя без consent возвращает 403 `PD_CONSENT_REQUIRED` ИЛИ 200 с `consent_required=true` (в зависимости от выбранного варианта). В документации эндпоинта чётко указано.
- Test: после `accept-consent` повторный login возвращает чистый токен без `consent_required`.
- Test: пользователь с `is_holding_owner=true` **также обязан принять политику** (ФЗ-152 не делает исключений для владельца). Поймать в тесте — типичная ошибка.

### Пункт 9. Тесты

**Что:** в `backend/tests/`:

1. `test_rbac.py` — unit-тесты `can()` / `RbacService`:
   - happy-path: owner может write contract своей компании → True.
   - cross-company block: owner компании A → read contract компании B → False.
   - `is_holding_owner` bypass: True для любого resource.
   - pod_id: роль с `pod_id='cottage_platform'` → False на resource с `pod_id='gas_stations'`; True на `pod_id='cottage_platform'`; True на `pod_id=None` у ресурса только если `pod_id=None` у роли.
   - Кеш: два вызова подряд → один SQL-запрос (mock db.execute, assert call_count).
   - Инвалидация: после `RolePermissionService.bulk_replace(...)` кеш сбрасывается.

2. `test_consent.py` — consent-флоу:
   - `GET /auth/consent-status` для пользователя без consent → `required_action='accept'`.
   - `POST /auth/accept-consent` с неверной версией → 422 `VALIDATION_ERROR`.
   - `POST /auth/accept-consent` с верной версией → 200, `users.pd_consent_at` заполнен.
   - После accept: `GET /auth/consent-status` → `required_action='none'`.
   - Смена current_version (seed новой записи `pd_policies v1.1 is_current=true`, v1.0 → `is_current=false`) → `required_action='refresh'`.

3. `test_login_consent.py` — login-gate:
   - Login без consent → 403 `PD_CONSENT_REQUIRED` (или 200+`consent_required=true`, в зависимости от выбора в Пункте 8).
   - Accept → login → 200 чистый токен.
   - Holding-owner без consent: login блокирован так же.

4. `test_roles_api.py` — admin-эндпоинты:
   - non-admin → 403 на GET `/roles`.
   - admin (user с role_permission `role.admin`) → 200 список.
   - delete system role → 409.
   - create/update/delete custom role → 200/204 + аудит.

5. `test_user_roles_api.py` — IDOR и вложенный ресурс:
   - DELETE `/users/42/roles/99`, где `UserCompanyRole(id=99).user_id != 42` → **404, не 403** (правило 3 отдела).
   - POST `/users/42/roles` не-admin → 403.
   - assign duplicate (user, company, role, pod_id) → 409.

6. `test_role_permissions_api.py`:
   - PATCH `/roles/{id}/permissions` bulk_replace работает атомарно (тест на rollback при невалидном `permission_id`).
   - После PATCH — `load_user_permissions` для пользователя с этой ролью отражает новые права (проверка инвалидации кеша).

7. `test_migration_rbac.py` — проверка seed:
   - После миграции: `roles` содержит 6 ролей, `permissions` содержит ≥20 записей, `role_permissions` повторяет матрицу §5.4 для `owner/accountant/construction_manager/read_only`.
   - `pd_policies` содержит ровно одну запись с `is_current=TRUE`, `version='v1.0'`.

**Стандарты:**
- Покрытие: ≥85% строк новых модулей (`rbac.py`, `consent.py`, `role.py`, `role_permission.py`, `permission.py`, `role`).
- Никаких литералов паролей/секретов (правило 7 отдела, CLAUDE.md §Секреты).
- Фикстуры в `conftest.py` для консент-статуса и RBAC: `create_user_with_role_and_consent(db, role_code, pod_id=None)`.

**Acceptance:** `pytest backend/tests -q` зелёный, `ruff check backend/` 0 ошибок.

## 4. Порядок выполнения (рекомендация Head'у)

1. **День 1.** Пункт 1 (миграция + seed) + Пункт 2 (ORM-модели) — это основа. Прогон round-trip, линтер миграций. Головная боль: обязательно тест на `pd_policies is_current` UNIQUE (PostgreSQL-специфика).
2. **День 2.** Пункт 3 (схемы) + Пункт 4 (репозитории) + Пункт 5.1 (`rbac.py` — `can`, `RbacService`). Параллельно unit-тесты `test_rbac.py` (TDD).
3. **День 3.** Пункт 5.2–5.6 (остальные сервисы, включая `consent.py`, `role_permission_service`). Параллельно начинается `test_consent.py`, `test_roles_api.py`.
4. **День 4.** Пункт 6 (`require_permission` в `deps.py`) + Пункт 7 (admin-эндпоинты, заменяют stubs). Все новые эндпоинты — через `require_permission`.
5. **День 5.** Пункт 8 (consent guard + login-integration) + Пункт 9 (добор тестов до 85% покрытия). Ручной smoke в Swagger UI.
6. **День 6.** Финальная чистка, ревью backend-head (уровень файлов), подготовка отчёта Директору. Раунды ревью при необходимости.

## 5. Матрица прав (seed для `role_permissions`)

Расширение ADR 0011 §2.2. Матрица хранится в seed-скрипте миграции.

### 5.1. Список permissions (seed)

| code | resource_type | action |
|---|---|---|
| `contract.read` | contract | read |
| `contract.write` | contract | write |
| `contract.delete` | contract | delete |
| `payment.read` | payment | read |
| `payment.write` | payment | write |
| `payment.approve` | payment | approve |
| `payment.delete` | payment | delete |
| `project.read` | project | read |
| `project.write` | project | write |
| `project.delete` | project | delete |
| `contractor.read` | contractor | read |
| `contractor.write` | contractor | write |
| `user.read` | user | read |
| `user.write` | user | write |
| `user.admin` | user | admin |
| `role.read` | role | read |
| `role.admin` | role | admin |
| `permission.read` | permission | read |
| `company.read` | company | read |
| `company.write` | company | write |
| `company.admin` | company | admin |
| `audit.read` | audit | read |
| `audit.admin` | audit | admin |

### 5.2. Расширение `UserContext`

`UserContext` дополняется (не сломать существующий интерфейс):
- `permissions: frozenset[tuple[str, str, str | None]] | None = None` — закеш-нутый набор прав для быстрого повторного use в том же запросе. Заполняется при первом вызове `can()` через `RbacService`. Если `None` — ещё не загружали.
- Поля `user_id`, `company_id`, `company_ids`, `is_holding_owner` — остаются без изменений.

### 5.3. JWT claims (остаются как в PR #1)

Ничего не меняется: `sub`, `role`, `company_ids`, `is_holding_owner`. Новое: опциональный `consent_required: bool = false`. Клиенту важно знать, что предложить пользователю после logit.

### 5.4. Матрица seed role_permissions

Базовые 4 роли (по ADR 0011 §2.2), `pod_id = NULL` (applicable to all pods):

| Роль / Permission | read | write | approve | delete | admin |
|---|---|---|---|---|---|
| **owner** | contract, payment, project, contractor, user, role, permission, company, audit | contract, payment, project, contractor, user, company | payment | contract, payment, project | user, role, company, audit |
| **accountant** | contract, payment, project, contractor, user, company | contract, payment, contractor | — | — | — |
| **construction_manager** | contract, payment, project, contractor, user, company | project, contractor | — | — | — |
| **read_only** | contract, payment, project, contractor, company | — | — | — | — |
| **foreman** *(новая)* | project, contract, contractor | contractor | — | — | — |
| **worker** *(новая)* | project | — | — | — | — |

**Важно:** `is_holding_owner` на уровне `can()` bypass'ит всё (ADR 0011 §2.1 шаг 1). Матрица выше не применяется к нему.

**Отличие от ADR 0011 §2.2:** расширен список permissions (добавлены `user.*`, `role.*`, `permission.read`, `company.*`, `audit.*`). ADR 0011 описывал минимальную матрицу для 4 доменных resource_type. Для production-gate нужны admin-пути для управления ролями и правами — отсюда расширение. Это **не отклонение от ADR**, а его реализация с дополнениями, санкционированными legal-checkом и production-сценариями.

## 6. Связь с PR #1 и совместимость

- **`users.is_holding_owner` остаётся** — читается `can()` для bypass (ADR 0011 §2.1).
- **`users.role` (enum `UserRole`) остаётся** — в PR #2 **не удаляется и не переводится в deprecated технически**. Причина: ADR 0011 §1.5 явно фиксирует, что удаление `users.role` — отдельной миграцией после стабилизации M-OS-1. На PR #2 колонка живёт, но бизнес-логика её не читает (кроме `require_role` deprecated-alias). План удаления — после PR #3+PR #4, когда все эндпоинты переведены на `require_permission`.
- **`user_company_roles.role_template`** — остаётся `Enum(UserRole)`. Это осознанно: enum даёт typo-safety и FK на Python-enum. `roles.code` — строка; при load в `RbacService` матчится по `role_template.value == roles.code`. Новые роли (`foreman`, `worker`) НЕ появляются в `UserRole`; назначить их пользователю на PR #2 нельзя (ограничено enum). Расширение enum `UserRole` → отдельная задача после PR #2.
- **`require_role` deprecated** остаётся как wrapper; эндпоинты остаются на нём. «Sweep-PR» по миграции endpoint'ов на `require_permission` — после PR #3.
- **`CompanyScopedService`** — не трогаем. `can()` читает `resource.company_id` — тот же контракт.

## 7. Риски и зависимости

- **Frontend.** Новые эндпоинты (`/auth/consent-status`, `/auth/accept-consent`, расширенные `/roles`, `/roles/{id}/permissions`, `/permissions`, `/users/{id}/roles`) добавляются в OpenAPI. После мержа PR #2 — backend-director уведомит frontend-director через Координатора о новом контракте. На фронте нужен consent-скрин (вёрстка-блокер для login-flow); это отдельная задача FE-отдела.
- **Legal.** Текст `pd_policies.v1.0.body_markdown` — **черновик от tech-writer**. Юрист при открытии production gate заменит на финальный текст через обновление политики (v1.1). Миграция политик (v1.0 → v1.1) идёт штатно: новая запись в `pd_policies`, старая `is_current=false`, новая `is_current=true` — все пользователи получают `required_action='refresh'`. **Тест этого сценария — в `test_consent.py` обязательно.**
- **Performance.** RBAC без Redis-кеша: при каждом первом запросе в сессии — join из 4 таблиц. Для MVP-нагрузки (десятки rps) приемлемо. Для M-OS-2 — Redis (ADR 0011 §«Отрицательные последствия»). TODO в коде.
- **Конфликт имён с существующим `role_permissions_router`.** Существующий роутер уже регистрирует `/roles/permissions`. Новый эндпоинт `/roles/{role_id}/permissions` — другой префикс, конфликта нет, но FastAPI должен правильно разрулить порядок. Проверить руками в Swagger после мержа.
- **Конфликт с PR #3 (Crypto Audit).** PR #3 добавит поля `prev_hash/hash` в `audit_log`. Семантически несовместимых изменений нет, но `consent.py` будет писать в `audit_log` через `audit_service.log()` — к моменту PR #3 интерфейс не должен меняться. Митигация: `audit_service.log()` сохраняет существующую сигнатуру; крипто-цепочка — деталь реализации внутри сервиса.

## 8. DoD PR #2

- [ ] Все 9 пунктов скоупа реализованы.
- [ ] Миграция RBAC v2 + PD consent проходит линтер (`lint_migrations`) без ошибок, с 1 warning `op_execute` и маркером.
- [ ] Round-trip миграции чист (CI job `round-trip` зелёный на PR).
- [ ] `pytest backend/tests -q` зелёный; покрытие новых модулей ≥85%.
- [ ] `ruff check backend/app backend/tests` — 0 ошибок.
- [ ] Swagger `/docs` рендерится, все новые эндпоинты с `summary`/`description`/`response_model`.
- [ ] Никаких секретов-литералов в коде и тестах (`secrets.token_urlsafe(16)` или `os.environ.get(...)`).
- [ ] **Legal-acceptance (критично):**
  - consent blocks login: login без consent → 403 (или 200+`consent_required=true`) — задокументировано в Swagger.
  - consent refresh works: новая версия политики → `required_action='refresh'` → accept → `'none'`.
  - holding_owner тоже обязан accept.
- [ ] **RBAC-acceptance:**
  - IDOR по ролям: DELETE `/users/A/roles/{id_пользователя_B}` → 404.
  - cross-company block: owner компании A → 403 на ресурс компании B.
  - holding_owner bypass работает.
- [ ] Ревью backend-head — approve.
- [ ] Ревью reviewer (review-head → reviewer) — approve.
- [ ] Ручной smoke-test флоу accept-consent через Swagger UI (скриншот или лог команды в отчёте Head).
- [ ] Существующий stub `user_roles.py`, `roles.py`, `role_permissions.py` полностью заменён рабочей имплементацией; 501 больше не возвращается.
- [ ] Существующие 351+ тестов PR #1 — зелёные (никаких регрессий).

## 9. Ревью-маршрут

1. **backend-dev → backend-head.** Head делает ревью уровня файлов: каждая модель, каждая схема, каждый сервис. Особое внимание: соблюдение правила 1 (сервис не делает SQL-запросы), правила 5 (аудит-лог в write-операциях), правила 3 (IDOR-проверка во вложенных ресурсах).
2. **backend-head → review-head → reviewer.** Reviewer проверяет на соответствие CLAUDE.md, ADR 0011, ADR 0013, legal-check C-1. Отдельное внимание: отсутствие литералов секретов, корректность `require_permission`, маскировка ПД в возвращаемых схемах.
3. **Reviewer approve → backend-head → backend-director.** Я принимаю работу на уровне DoD: состав PR, логи CI, покрытие, smoke-тест консент-флоу.
4. **Backend-director approve → Координатору.** Координатор делает git commit + push (правило auto-push, memory feedback_auto_push_github).

## 10. Что Head возвращает Директору на приёмку

Head оформляет отчёт одним сообщением со следующими разделами:

1. **Состав PR.** Список всех изменённых/созданных файлов с путями.
2. **Результаты тестов.** Вывод `pytest backend/tests -q --tb=short` (последние 30–50 строк).
3. **Покрытие.** Вывод `pytest --cov=backend/app --cov-report=term` по новым модулям.
4. **Результаты линтеров.** `ruff check backend/` и `python -m tools.lint_migrations backend/alembic/versions/`.
5. **Результаты round-trip.** Вывод трёх команд `alembic upgrade head && alembic downgrade -1 && alembic upgrade head`.
6. **Swagger smoke.** Подтверждение что `/docs` рендерится без ошибок + список новых операций.
7. **Legal-чек:**
   - скриншот/лог `curl -X POST /auth/login` для пользователя без consent (демонстрация 403).
   - лог `curl -X POST /auth/accept-consent` + последующий login (демонстрация 200).
8. **Замечания ревьюеров и их закрытие.** Краткая сводка (P0/P1/P2, ссылки на коммиты).
9. **Отклонения от брифа.** Любое решение Head'а, не описанное в брифе — фиксируется с обоснованием. Особенно: выбор между двумя вариантами consent-login-integration в Пункте 8.
10. **Метрики.** Время на задачу (план 5–6 дней чистой работы vs факт), раунды ревью.

## 11. Оценка времени

- **Backend-dev работа:** 5–6 дней чистой работы (Sonnet). Из них:
  - 1 день — миграция + модели (Пункты 1–2);
  - 1 день — схемы + репозитории + core RBAC (Пункты 3–5.1);
  - 1 день — остальные сервисы (Пункты 5.2–5.6);
  - 1 день — `require_permission` + admin-эндпоинты (Пункты 6–7);
  - 1 день — consent guard + login integration + тесты (Пункты 8–9);
  - 0.5–1 день — финальная чистка, раунды ревью, smoke-тесты.
- **Backend-head ревью:** 0.5–1 день (≥3 раунда: первый подход, после исправлений, после reviewer).
- **Reviewer (review-head → reviewer):** 0.5 дня.
- **Итого календарно с учётом циклов:** ~7–8 рабочих дней. С учётом выходных и того, что это финальный блокер production — не форсировать, качество важнее.

**Оценка Директора (в «днях живой работы»):** **5–6 дней backend-dev + 0.5–1 день Head + 0.5 день reviewer = 6–7.5 дней чистой человеко-работы.** Wall-clock (от старта до мержа Координатором) — 7–10 рабочих дней без форсажа.

## 12. Ограничения (жёсткие)

- **ADR 0002, 0004, 0005, 0006, 0007 не трогаем.** Отклонение от любого — request-changes.
- **ADR 0011 Часть 3 (Crypto Audit) — НЕ в скоупе.** Поля `prev_hash`/`hash` в `audit_log` не добавляются. Это PR #3.
- **Audit log P0 маскирование ПД (C-4) — НЕ в скоупе.** Тоже PR #3 (`changes_json` маскировка `full_name`/`email`).
- **`users.role` НЕ удаляется.** Никакого `DROP COLUMN` в миграции. Deprecation будет позже.
- **`require_role` НЕ удаляется.** Остаётся как deprecated alias.
- **Sweep-перевод существующих эндпоинтов на `require_permission` НЕ делается.** Только новые эндпоинты (admin + consent).
- **Никаких секретов-литералов.** Только `os.environ.get(...)` и `secrets.token_urlsafe(16)`.
- **`# type: ignore` / `# noqa` запрещены без комментария-обоснования.**
- **`git add -A` запрещён.** Только перечисление конкретных файлов.
- **Коммит — после reviewer approve.** Правило CLAUDE.md §«Reviewer — до git commit».

**FILES_ALLOWED (для backend-dev):**
- `backend/alembic/versions/2026_04_18_*_rbac_v2_pd_consent.py` (1 новая миграция)
- `backend/app/models/role.py`, `permission.py`, `role_permission.py`, `pd_policy.py`
- `backend/app/models/__init__.py` (экспорт)
- `backend/app/models/user.py` (только добавление 2 полей pd_consent_*)
- `backend/app/schemas/role.py`, `permission.py`, `consent.py`
- `backend/app/schemas/role_permission.py` (расширение)
- `backend/app/repositories/role.py`, `permission.py`, `role_permission.py`, `pd_policy.py`
- `backend/app/services/rbac.py`, `role.py`, `permission.py`, `role_permission.py`, `user_company_role_service.py`, `consent.py`
- `backend/app/services/company_scoped.py` (расширение `UserContext` полем `permissions`)
- `backend/app/api/roles.py`, `role_permissions.py`, `user_roles.py` (заменяются с 501 на рабочие)
- `backend/app/api/permissions.py` (новый)
- `backend/app/api/auth.py` (два новых эндпоинта + login-consent-check)
- `backend/app/api/deps.py` (добавить `require_permission`, `require_consent`, `get_consent_service`, `get_rbac_service`)
- `backend/app/core/security.py` (расширение `create_access_token`)
- `backend/app/main.py` (регистрация `permissions_router` + возможные комментарии об изменении порядка)
- `backend/tests/test_rbac.py`, `test_consent.py`, `test_login_consent.py`, `test_roles_api.py`, `test_user_roles_api.py`, `test_role_permissions_api.py`, `test_permissions_api.py`, `test_migration_rbac.py`
- `backend/tests/conftest.py` (только добавление новых фикстур для consent/RBAC)

**FILES_FORBIDDEN:** всё остальное, в частности:
- `backend/app/models/audit.py` (Part 3, PR #3)
- Любые другие миграции в `backend/alembic/versions/` (только свою новую)
- Любые ADR-файлы (amendment не нужен; если нужен — эскалация Директору)
- `CLAUDE.md` проектный (если нужны правила из новой работы — через backend-director после мержа)
- Pod-specific модели (`backend/app/models/project.py`, `contract.py` и т.п.) — не трогаем.
- `frontend/*` — всё фронтовое

**COMMUNICATION_RULES:**
- backend-dev не общается с другими отделами напрямую.
- Все вопросы по скоупу — только к backend-head.
- Head эскалирует Директору, если вопрос не решается через бриф или §2.
- К legal / design / frontend / db — только через Директора (backend-director).
- К Координатору / Владельцу — только через Директора.

## 13. Вопросы на обсуждение с Координатором (не блокируют старт)

1. **Выбор варианта consent-login (Пункт 8):** «403 без токена» vs «200 + токен с `consent_required=true`». Моя рекомендация — **вариант 2** (токен с флагом), проще интегрируется с фронтом. Но это вопрос UX, хочу получить явное «добро» Координатора перед стартом.
2. **Текст политики v1.0.** Брать из `privacy-policy-draft.md` разделы 1–5 (плейсхолдеры остаются) — достаточно для MVP и legal-gate? Или нужно **дождаться юриста** на заполнение плейсхолдеров? Моя позиция: для MVP плейсхолдеры приемлемы — сам факт наличия механизма и версии важнее конкретного текста. Юрист при production-gate обновит через v1.1 и все пользователи пройдут refresh.
3. **foreman/worker в enum `UserRole`.** На PR #2 они добавляются только в `roles.code` (строка), но НЕ в Python-enum `UserRole`. Это значит, что назначить их через API `POST /users/{id}/roles` пока нельзя (валидация упадёт на `UserCompanyRole.role_template: UserRole`). Моё предложение: на PR #2 в сервисе `UserCompanyRoleService.assign()` **разрешить любой `role_template`, если он существует в `roles.code`** — не ограничиваться enum. Это потребует маленького архитектурного решения: `UserCompanyRole.role_template` на уровне DB уже строка (`String(30)` в миграции f7e8d9c0b1a2, `CHECK role_template IN (...)`) — в миграции PR #2 расширить CHECK до 6 значений (`foreman`, `worker` добавить). Python-enum `UserRole` остаётся узким legacy-контрактом. **Риск:** рассинхрон enum ↔ CHECK. **Митигация:** тест на миграцию, что CHECK расширен; код в сервисе использует `roles.code` как источник истины, не enum.
4. **Длительность пункта 9 (тесты).** Моя оценка — половина общего времени. Если времени жмёт — согласуем какие тесты «обязательные» vs «желательные». Но не советую: legal-тесты из §8 неопциональны.

**Рекомендация Директора:** по пунктам 1, 2 — ответы Координатора ДО старта работы. Пункты 3, 4 — можно решить в процессе раунда ревью.

---

*Бриф составлен backend-director 2026-04-18 для backend-head в рамках M-OS-1 Волна 1 Foundation PR #2. После одобрения Координатором — передача Head через паттерн Координатор-транспорт v1.6. После вычитки Head — запрос на уточнения ко мне. После старта — отчёт по §10 на приёмку.*
