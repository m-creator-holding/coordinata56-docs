# Бриф backend-head: PR #5 Волны 1 Foundation — Legal PD Skeleton (ПД-поля, маскирование, экспорт/удаление)

- **От:** backend-director
- **Кому:** backend-head
- **Дата:** 2026-04-18
- **Тип задачи:** L-уровень (декомпозиция + распределение на 1–2 backend-dev параллельно)
- **Паттерн:** Координатор-транспорт v1.6 (CLAUDE.md проекта §«Pod-архитектура»)
- **Код Директор не пишет.** Head разбивает 8 блоков скоупа на задачи backend-dev, собирает PR, проводит ревью уровня файлов, возвращает Директору на приёмку.
- **Статус брифа:** подготовлен для одобрения Координатором 2026-04-18. Активация — после ответа Координатора на §14 вопросы и после мержа PR #3 в `main`.
- **Критичность:** **PR #5 закрывает права субъекта ПД по 152-ФЗ ст. 14 (доступ к своим ПД) и ст. 21 (удаление).** Без этих эндпоинтов и маскирования паспортных данных в ответах API юрист не подпишет production-gate. Штрафы по ст. 13.11 КоАП — до 700 тыс ₽ за отказ/нарушение прав субъекта.

---

## 0. Блокер-зависимости (важно прочитать первым)

**PR #5 стартует ПОСЛЕ PR #3.** Причины:

1. **Down-revision миграции PR #5** = финальная ревизия PR #3 (`audit_crypto_chain`). Точное значение Head подставит из `alembic/versions/` после мержа PR #3. Промежуточного PR#4 **не существует в `backend/alembic/versions/`** — ADR-0014 про integration adapters (каркас ACL для внешних API, не про RBAC). PR#4 схему БД не трогает, поэтому миграционная цепочка: PR#2 (`ac27c3e125c8`) → PR#3 (`audit_crypto_chain`) → **PR#5 здесь**.
2. **Audit-логирование `pd.unmask_view` и `pd.erase`** пишется через `AuditService.log()` — записи должны **сразу** включаться в крипто-цепочку PR #3. Если PR #5 мержится раньше — часть консент-чувствительных событий уйдёт в pre-hash журнал.
3. **Маскирование ПД-полей в `changes_json`** при записи user-update в audit_log (C-4) — уже настроено в PR #3 расширением `AUDIT_EXCLUDED_FIELDS`. PR #5 добавляет **новые** ПД-поля (`phone`, `passport_series`, `passport_number`, `passport_issued_by`, `passport_issued_at`, `date_of_birth`) — Head обязан расширить `AUDIT_EXCLUDED_FIELDS` в рамках PR #5, **не трогая** крипто-логику.

**Параллельная работа до мержа PR #3 разрешена:** Head читает источники, декомпозирует на backend-dev задачи, готовит тексты политики (Блок 4) и описание эндпоинтов. `Agent`-вызов на имплементацию — только после сигнала Координатора «PR #3 смержен».

**PR #2 уже закрыл:** `users.pd_consent_at`, `users.pd_consent_version`, таблицы `pd_policies/roles/permissions/role_permissions`, сервис `ConsentService` с методами `get_status`/`accept`, эндпоинты `GET /api/v1/auth/consent-status` и `POST /api/v1/auth/accept-consent`, middleware `require_consent`. **Повторно реализовывать их в PR #5 не нужно** — см. §2.1, Решение 1.

---

## 1. Цель PR

Одним PR закрыть **четыре взаимосвязанных блока**, формирующих юридический скелет обработки ПД по 152-ФЗ:

1. **Расширение модели `User` ПД-полями.** Добавить `phone`, `passport_series`, `passport_number`, `passport_issued_by`, `passport_issued_at`, `date_of_birth`. Все — nullable (expand-pattern ADR 0013).
2. **Маскирование ПД в API-ответах.** `UserRead` по умолчанию возвращает `passport_series="**"`, `passport_number="****XX"` (последние 2 цифры), `phone="+7XXXXXXXX88"` (формат — Head уточнит с юристом, см. §14.2). Полный вид — только пользователям с правом `user.read_pd` (формат соответствует CHECK-enum `permissions.action`, см. §2.1, Решение 3). Факт обращения за полным видом (`?unmask=true`) логируется в audit_log как `AuditAction.READ` c `action_detail='pd.unmask_view'`.
3. **Экспорт ПД субъекта (ФЗ-152 ст. 14).** `GET /api/v1/users/{user_id}/pd-export?format=json|csv` — возвращает все ПД пользователя. Доступ: (а) сам пользователь себе, (б) обладатель `user.admin`. Аудит обязателен.
4. **Удаление ПД субъекта (ФЗ-152 ст. 21).** `POST /api/v1/users/{user_id}/pd-erase` — soft-delete пользователя + **маскирование ПД-полей в БД** заменой на константу `"<erased>"` / `NULL` (см. §3 Блок 7). Аудит обязателен. Только `user.admin`.

**Два блока НЕ в скоупе PR #5:**
- **Текст политики обработки ПД.** Уже есть `pd_policies` таблица с v1.0 (PR #2). PR #5 ничего не делает с текстом политики, он хранится версионировано.
- **Согласие на обработку ПД.** Уже работает через `/auth/accept-consent` и middleware `require_consent` (PR #2). **Координатор в исходном брифе попросил "реализовать реальный эндпоинт POST /api/v1/auth/accept-consent" — это ошибка формулировки, эндпоинт УЖЕ реализован.** Head выносит это в вопрос §14.1 Координатору для подтверждения, что не нужно.

**За PR #5 пойдут (по решению Директора/Координатора):**
- PR #6 (frontend legal skeleton): формы ПД, модалка unmask-подтверждения, экран «Мои данные», кнопки Export/Erase. Frontend-director планирует после мержа PR #5.
- Regression-sweep: проверка, что все read-эндпоинты, возвращающие `UserRead`, используют маскированную схему — через quality-director.

---

## 2. Решения Директора и вопросы Координатору

### 2.1. Решения, принятые Директором (уточнения к исходному брифу Координатора)

1. **Эндпоинты `/auth/consent-status` и `/auth/accept-consent` — УЖЕ реализованы в PR #2** (`backend/app/api/auth.py`, `backend/app/services/consent.py`, подтверждено grep'ом 2026-04-18). **Не переделываем.** Константа `CONSENT_POLICY_VERSION` в бэкенде не нужна отдельно в `app/core/config.py` — версия хранится в таблице `pd_policies.version` (`is_current=TRUE`). Frontend-MSW-stubs будут заменены реальным вызовом на уже существующий бэкенд автоматически. Если Координатор подтверждает — п. 6–8 исходного запроса **вычёркиваем**.
2. **Паспорт: серия 4 цифры + номер 6 цифр** — стандарт РФ (ст. 2 Постановления Правительства от 08.07.1997 № 828). Это решение финализируется в §14.3; если Владелец ответит «нужны ещё ИНН/СНИЛС» — отдельный PR.
3. **Новое право на полный вид ПД называется `user.read_pd`** (resource_type=`user`, action=`read_pd`). **Конфликт с CHECK-enum:** PR #2 ввёл `CHECK (action IN ('read','write','approve','delete','admin'))`. `read_pd` не укладывается. **Два варианта, решение Head с учётом ответа Координатора §14.4:**
   - **Вариант A (рекомендация Директора):** расширить CHECK enum до `('read','write','approve','delete','admin','read_pd','erase_pd')`. Мигрирует одной операцией `op.execute` с маркером `# migration-exception: op_execute — extend permissions.action enum for ФЗ-152 skeleton`.
   - **Вариант B:** использовать существующее `user.admin` как триггер unmask — избегает миграции enum. Минус: admin'у выдаётся не только чтение ПД, но и write/delete users. Слабее принцип least-privilege.
   - Директор рекомендует **Вариант A**. Без ответа Координатора не стартуем.
4. **Erasure: что именно писать в БД при `pd-erase`.** Решение:
   - `email` → `deleted_{user_id}@erased.local` (чтобы unique constraint не упал; email — идентификатор, нельзя NULL)
   - `full_name` → `"<erased>"`
   - `phone` → `NULL`
   - `passport_*` поля → `NULL`
   - `date_of_birth` → `NULL`
   - `password_hash` → сохраняется как есть (не ПД с точки зрения ст. 21; плюс нужен для исторической целостности audit-цепочки)
   - `is_active` → `False`
   - `deleted_at` → `now()` (soft-delete mixin уже есть)
   - `pd_consent_at` / `pd_consent_version` → сохраняются (доказательство факта согласия в прошлом — требование ст. 9 ФЗ-152 п. 2 «…после прекращения оператор обязан хранить…»)
5. **Срок хранения после erase — открытый вопрос Владельцу** (§14.5). Предложение Директора: 30 дней soft-delete → потом hardcoded DELETE из БД (отдельный тех-долг). На MVP принимается **бессрочное** хранение erased-записей.

### 2.2. Вопросы Координатору (блокируют старт §3 работы, см. §14 ниже)

См. §14 — 5 вопросов, на которые нужен ответ до `Agent`-вызова backend-dev.

---

## 3. Источники (обязательно прочесть исполнителю)

**Проектные правила:**
1. `/root/coordinata56/CLAUDE.md` — особенно разделы «Данные и БД», «Секреты и тесты», «API», «Код», «Git».
2. `/root/coordinata56/docs/agents/departments/backend.md` — правила отдела, чек-лист самопроверки, правило 1 (`ColumnElement[bool]` в `extra_conditions`), правила миграций (ADR 0013).

**Нормативные:**
3. `/root/coordinata56/docs/adr/0004-crud-layer-structure.md` — строгая слойность (особенно Amendment 2026-04-18).
4. `/root/coordinata56/docs/adr/0005-api-error-format.md` — единый формат ошибки.
5. `/root/coordinata56/docs/adr/0006-pagination-filtering.md` — envelope list-ответов.
6. `/root/coordinata56/docs/adr/0007-audit-log.md` — контракт audit-лога (`changes_json`, маскировка).
7. `/root/coordinata56/docs/adr/0011-foundation-multi-company-rbac-audit.md` — Часть 2 (RBAC) и Часть 3 (crypto).
8. `/root/coordinata56/docs/adr/0013-migrations-evolution-contract.md` — expand-pattern + запреты линтера.
9. `/root/coordinata56/docs/legal/m-os-1-1-foundation-legal-check.md` — legal-check требования.
10. `/root/coordinata56/docs/legal/reviews/ui-pd-labels-review-2026-04-18.md` — **раздел 4** (текст согласия как справочник) и §1.1 (категории полей по 152-ФЗ).

**Кодовой контекст (baseline):**
11. `backend/app/models/user.py` — текущая модель `User` (PR #2 добавил `pd_consent_at`, `pd_consent_version`, `is_holding_owner`). **ПД-поля из §1.1 отсутствуют — это и есть скоуп Блока 1.**
12. `backend/app/schemas/auth.py` — `UserCreate`, `UserRead`. Расширяются в Блоке 3.
13. `backend/app/schemas/user_admin.py` — `UserAdminUpdate`, `PaginatedUserResponse`. Расширяются в Блоке 3.
14. `backend/app/api/users.py` — **текущий stub 501** для admin-CRUD. В PR #5 **переводим в рабочее состояние** (Блок 6), включая 2 новых эндпоинта export/erase.
15. `backend/app/services/consent.py` — готовый `ConsentService` (PR #2). **Не трогать.**
16. `backend/app/services/audit.py` — `AUDIT_EXCLUDED_FIELDS` после PR #3 уже содержит `passport_number`, `phone`. Нужно расширить `passport_series`, `passport_issued_by`, `passport_issued_at`, `date_of_birth`.
17. `backend/alembic/versions/2026_04_18_1200_ac27c3e125c8_rbac_v2_pd_consent.py` — прецедент seed permissions через op.execute (строки 249–273).
18. `backend/app/api/deps.py` — `require_permission`, `require_consent`, `get_current_user_only`.

**Бриф-предшественник (паттерн):**
19. `/root/coordinata56/docs/pods/cottage-platform/tasks/pr3-wave1-audit-crypto-chain.md` — структура брифа, §9 ревью-маршрут, §10 отчёт.

---

## 4. Скоуп PR #5 — 8 блоков с acceptance criteria

Head декомпозирует в задачи для backend-dev в порядке §5.

### Блок 1. Миграция Alembic (expand) — ПД-поля + новые права

**Что:** один файл `backend/alembic/versions/2026_04_18_XXXX_<rev>_legal_pd_skeleton.py`.
**Down-revision:** финальная ревизия PR #3 (Head подставит из `alembic/versions/` после мержа).

**Добавляемые объекты:**

1. Колонки в `users` (все **nullable**, без server_default):
   - `phone: str(20), nullable` — E.164 формат (до 15 цифр + префикс `+`).
   - `passport_series: str(4), nullable` — ровно 4 цифры (валидация — Pydantic).
   - `passport_number: str(6), nullable` — ровно 6 цифр.
   - `passport_issued_by: str(255), nullable` — наименование органа.
   - `passport_issued_at: date, nullable` — дата выдачи.
   - `date_of_birth: date, nullable`.
   - CHECK-constraint: `CHECK (passport_series ~ '^[0-9]{4}$' OR passport_series IS NULL)` и аналогичный для `passport_number ~ '^[0-9]{6}$' OR passport_number IS NULL`. Защита от обхода Pydantic через прямой SQL.
   - **Тонкий момент:** пара (`passport_series`, `passport_number`) — логически связаны. В этом PR **не добавляем** CHECK «оба или ни одного» (добавим в отдельной миграции, когда будет требование).

2. **Расширение CHECK `permissions.action` enum** (условно — только если Координатор подтвердит Вариант A в §14.4):
   ```
   op.execute("ALTER TABLE permissions DROP CONSTRAINT ck_permissions_action")
   op.execute("""
       ALTER TABLE permissions
       ADD CONSTRAINT ck_permissions_action
       CHECK (action IN ('read','write','approve','delete','admin','read_pd','erase_pd'))
   """)
   ```
   С маркером `# migration-exception: op_execute — extend permissions.action enum for ФЗ-152 read_pd/erase_pd actions`.

3. **Seed новых прав** (op.execute с маркером `# migration-exception: op_execute — seed PD rights (ФЗ-152 ст. 14, 21)`):
   - `user.read_pd` — `resource_type='user'`, `action='read_pd'`, `name='Просмотр ПД в полном виде'`, `description='Право видеть паспорт/телефон/ДР без маскирования. Использование фиксируется в audit_log.'`
   - `user.erase_pd` — `resource_type='user'`, `action='erase_pd'`, `name='Удаление ПД субъекта (ФЗ-152 ст. 21)'`, `description='Право инициировать erasure операцию: ПД заменяются на placeholder, пользователь деактивируется.'`

4. **Привязка прав к ролям `owner`** (для `holding_owner` bypass всё равно работает, но выдача через матрицу — для явности и для `is_holding_owner=False` owner-ов per-company). Роли `accountant`, `construction_manager`, `read_only`, `foreman`, `worker` — **НЕ получают** `read_pd`/`erase_pd`.

**Downgrade:** снятие констреинта action, удаление прав `user.read_pd`/`user.erase_pd` из `role_permissions` и `permissions` (CASCADE), возврат CHECK к старому списку, `DROP COLUMN` всех 6 новых полей users. Round-trip чистый.

**Acceptance:**
- `python -m tools.lint_migrations backend/alembic/versions/` — 0 ошибок, warning `op_execute` только с маркером.
- `alembic upgrade head && alembic downgrade -1 && alembic upgrade head` — чистый round-trip.
- После upgrade: `SELECT code FROM permissions WHERE code IN ('user.read_pd','user.erase_pd')` возвращает 2 строки; owner-роль имеет их в `role_permissions`.

### Блок 2. ORM-модель `User` — расширение

**Что:** обновить `backend/app/models/user.py`:
- Добавить 6 полей-колонок по шаблону существующих `pd_consent_at/version`.
- Все — `Mapped[... | None]`, `nullable=True`.
- Использовать типы `String(20)/(4)/(6)/(255)`, `Date`.
- **Не трогать** существующие поля.

**Правила:**
- Никаких relationship-атрибутов.
- Type hints обязательно, без `# type: ignore`.

**Acceptance:**
- `ruff check backend/app/models/user.py` чисто.
- `alembic check` (`autogenerate` diff) — никаких расхождений с миграцией Блока 1.

### Блок 3. Pydantic-схемы — маскирование

**Что:** в `backend/app/schemas/`:

1. **Обновить `auth.py`:**
   - `UserRead` — добавить **опциональные** поля `phone: str | None`, `passport_series: str | None`, `passport_number: str | None`, `passport_issued_by: str | None`, `passport_issued_at: date | None`, `date_of_birth: date | None`.
   - **Важно:** ReadSchema сериализуется из ORM в роутере; маскирование делается **не** в Pydantic, а в сервисном слое (Блок 5) — перед заполнением схемы. Pydantic только типизирует payload.
   - `UserCreate` — добавить те же 6 опциональных полей с валидацией:
     - `phone`: `Field(pattern=r"^\+?[0-9]{10,15}$")` — E.164 упрощённый.
     - `passport_series`: `Field(pattern=r"^[0-9]{4}$")`.
     - `passport_number`: `Field(pattern=r"^[0-9]{6}$")`.

2. **Обновить `user_admin.py`:**
   - `UserAdminUpdate` — те же 6 опциональных полей с такой же валидацией (все `None` по умолчанию — PATCH-семантика).

3. **Новый файл `backend/app/schemas/pd_export.py`:**
   - `PdExportResponse` — полный payload экспорта: все поля User + `pd_consent_at`, `pd_consent_version`, `assigned_roles: list[str]` (коды ролей из `user_company_roles`), `audit_history_count: int` (только счётчик, не содержимое — юрист подтверждает, что срез аудита в экспорт не входит, см. §14.5).
   - `PdEraseRequest` — body для POST erase: `confirmation: Literal["ERASE_CONFIRMED"]` (явное подтверждение намерения, защита от случайного вызова), `reason: str = Field(min_length=5, max_length=500)` (обоснование для audit_log).

**Acceptance:**
- Все новые поля с `Field(description=...)`.
- `UserRead` — по-прежнему `from_attributes=True`; маскирование делается в сервисе до передачи.
- Swagger-пример в docstring для каждой схемы.

### Блок 4. Репозиторий `UserRepository` — расширение

**Что:** `backend/app/repositories/user.py` (существует после PR #2; Head подтверждает):
- Метод `async def erase_pd(self, user_id: int) -> User` — атомарный UPDATE с набором полей по §2.1 Решение 4.
  - Использует `session.execute(update(User).where(User.id == user_id).values(...))`.
  - Если пользователь уже `deleted_at IS NOT NULL` — 404 (erase от erased запрещён).
- Метод `async def get_for_export(self, user_id: int) -> dict` — возвращает dict всех ПД-полей + consent + ролей через join; **без raw SQL в сервисе**, всё в репо.

**Правила:**
- Все запросы — только в репо (правило 1 отдела).
- `erase_pd` возвращает обновлённую ORM-запись после flush.

**Acceptance:**
- Unit-тесты в `test_user_repository.py` (расширение существующего, если есть, иначе новый) — happy, 404 на повторный erase, 404 на несуществующий user_id.

### Блок 5. Сервисный слой — `UserService` + маскирование

**Что:**

1. **Новый / расширение `backend/app/services/user.py`:**
   - Метод `async def get_user_read(user_id: int, requester: UserContext, unmask: bool = False) -> UserRead`:
     - Загружает ORM через репозиторий.
     - Если `unmask=True`:
       - Проверяет `rbac_service.user_has_permission(requester.user_id, "read_pd", "user")` ИЛИ `requester.user_id == user_id` (самому себе без маскировки всегда можно).
       - При `False` — `PermissionError` (роутер превратит в 403).
       - При `True` — записывает в audit_log: `AuditAction.READ`, `entity_type='user'`, `entity_id=user_id`, `changes_json={"action_detail": "pd.unmask_view", "by_user_id": requester.user_id}`. **Это в той же транзакции** что SELECT, чтобы не потерять факт.
       - Возвращает полную `UserRead`.
     - Если `unmask=False` — возвращает маскированную версию:
       - `passport_series`: если NULL → None, иначе `"**"`.
       - `passport_number`: если NULL → None, иначе `"****" + value[-2:]` (последние 2 цифры).
       - `phone`: если NULL → None, иначе `value[:2] + "X" * (len(value) - 4) + value[-2:]` (первые 2 и последние 2 симв).
       - `passport_issued_by`: NULL → None, иначе `"***"`.
       - `passport_issued_at`: NULL → None, иначе скрыть (None? — Head уточняет в §14.2, рекомендация Директора — скрывать).
       - `date_of_birth`: NULL → None, иначе скрыть (None).
   - Метод `async def export_pd(user_id: int, requester: UserContext, format_: Literal["json","csv"] = "json") -> PdExportResponse | str`:
     - Проверка доступа: `requester.user_id == user_id` ИЛИ `user.admin` (существующее право из PR #2).
     - Загружает через `user_repo.get_for_export(user_id)`.
     - audit_log: `AuditAction.READ`, `changes_json={"action_detail": "pd.export", "format": format_, "requested_by": requester.user_id}`.
     - Возвращает `PdExportResponse` (для JSON) или CSV-строку (для CSV, одна строка-row).
   - Метод `async def erase_pd(user_id: int, requester: UserContext, reason: str) -> None`:
     - Проверка `rbac_service.user_has_permission(requester.user_id, "erase_pd", "user")` (или `is_holding_owner`).
     - **Запрет erasure самого себя:** если `requester.user_id == user_id` — 409 CONFLICT (опасный сценарий; erasure должна выполняться другим admin'ом для разделения обязанностей). Head фиксирует в отчёте §10 если нужно иначе.
     - Вызов `user_repo.erase_pd(user_id)`.
     - audit_log: `AuditAction.DELETE`, `entity_type='user'`, `entity_id=user_id`, `changes_json={"action_detail": "pd.erase", "reason": reason, "by_user_id": requester.user_id}`.
     - **Маскирование в changes_json не применяется** — сам `reason` может содержать ПД (если admin вводит ФИО в обосновании); но это бизнес-решение: в отчёте §10 Head фиксирует, что `reason` принимается как есть, admin ответственен не писать лишних ПД.
   - Существующие методы CRUD (list/get/create/update/delete) — тоже тут, Head реализует по паттерну эталона Project.

**Правила:**
- Сервис **не делает** SQL-запросов — только через `UserRepository`.
- Все write — через `audit_service.log()`.
- Маскирование — чистая функция без побочных эффектов.

**Acceptance:**
- Метод `_mask_pd(user_orm) -> UserRead` — приватный, покрыт unit-тестом.
- Все 3 новых метода (get_user_read unmask-ветка, export_pd, erase_pd) пишут в audit_log в той же транзакции.

### Блок 6. Admin-эндпоинты — заменить stub'ы + новые export/erase

**Что:** `backend/app/api/users.py` (сейчас 5 stub'ов → рабочая имплементация):

1. **CRUD (заменяет 501):**
   - `GET /api/v1/users` — list с пагинацией (ADR 0006), фильтры `is_active`, `role`. `require_permission("read", "user")`. **Возвращает маскированные `UserRead`** (для списка — всегда masked).
   - `GET /api/v1/users/{user_id}` — get. Query-параметр `?unmask=true` разрешён. `require_permission("read", "user")`. Вызов `user_service.get_user_read(user_id, ctx, unmask=True)`.
   - `POST /api/v1/users` — create. `require_permission("admin", "user")`. Body `UserCreate`.
   - `PATCH /api/v1/users/{user_id}` — update. `require_permission("admin", "user")`. Body `UserAdminUpdate`.
   - `DELETE /api/v1/users/{user_id}` — soft-delete (deactivate). `require_permission("admin", "user")`.

2. **Новый `GET /api/v1/users/{user_id}/pd-export`:**
   - Query: `format: Literal["json","csv"] = "json"`.
   - Доступ: сам себе ИЛИ `user.admin`. Проверка в сервисе (см. Блок 5).
   - Response:
     - `format=json` → `PdExportResponse`.
     - `format=csv` → `Response(content=csv_body, media_type="text/csv; charset=utf-8", headers={"Content-Disposition": f"attachment; filename=pd_export_{user_id}.csv"})`.
   - ADR 0005 error format для 403/404.
   - Swagger: `summary="Экспорт ПД субъекта (ФЗ-152 ст. 14)"`, `description` с ссылкой на норму.

3. **Новый `POST /api/v1/users/{user_id}/pd-erase`:**
   - Body: `PdEraseRequest{confirmation: Literal["ERASE_CONFIRMED"], reason: str}`.
   - `require_permission("erase_pd", "user")`.
   - Ответ: 200 `{"status": "erased", "user_id": user_id, "erased_at": datetime}`.
   - Swagger: `summary="Удаление ПД субъекта (ФЗ-152 ст. 21)"`, предупреждение `description="Операция необратима: ПД-поля заменяются на placeholder, пользователь деактивируется. `confirmation` обязателен для защиты от случайного вызова."`.

**Правила:**
- Все роуты — через `require_consent` (кроме login/consent-flow из PR #2).
- Порядок регистрации в `main.py`: `users_router` уже зарегистрирован (с prefix `/users`, tags `["users"]`) — **не меняем**, только заменяем stub-содержимое.
- Все write-эндпоинты логируют в audit_log через сервис.

**Acceptance:**
- Swagger `/docs` показывает 7 эндпоинтов `/users` (5 CRUD + 2 новых), все с summary/description/response_model, корректные responses (401, 403, 404, 422).
- Ручной smoke: GET `/users/1?unmask=true` не-admin'ом → 403 `PERMISSION_DENIED`; admin'ом → 200 с полным паспортом.

### Блок 7. Маскирование ПД-полей в `AUDIT_EXCLUDED_FIELDS` (C-4 расширение)

**Что:** `backend/app/services/audit.py`:
- Расширить `AUDIT_EXCLUDED_FIELDS` новыми ПД-полями:
  ```
  "passport_series", "passport_issued_by", "passport_issued_at", "date_of_birth",
  # phone и passport_number уже в наборе с PR #3
  ```
- Эти поля добавились к модели User → без расширения `AUDIT_EXCLUDED_FIELDS` любой UPDATE-вызов `user_service.update()` запишет их в `changes_json` в открытом виде (нарушение C-4).

**Правила:**
- Не трогать саму логику рекурсивной `_sanitize` (PR #3 уже её реализовал).
- Не трогать формулу crypto-хеша (PR #3).

**Acceptance:**
- Тест в `test_audit_sanitize.py` (расширение файла из PR #3): UPDATE user с `date_of_birth` / `passport_series` → после `_sanitize` эти ключи отсутствуют в `changes_json`.

### Блок 8. Тесты

**Что:** в `backend/tests/`:

1. **`test_users_pd_masking.py`** (новый):
   - test_get_user_masked_by_default: пользователь-admin GET /users/2 без `?unmask=true` → `passport_series="**"`, `passport_number` заканчивается 2 цифрами.
   - test_get_user_unmasked_with_right: admin с `user.read_pd` GET `/users/2?unmask=true` → полный паспорт.
   - test_get_user_unmask_without_right: admin БЕЗ `user.read_pd` GET `/users/2?unmask=true` → 403.
   - test_get_user_self_unmask_always: пользователь GET `/users/me?unmask=true` (или через ID-самого себя) → 200, полные ПД.
   - test_unmask_writes_audit: после unmask-get — запись в audit_log c `action_detail="pd.unmask_view"`.
   - test_list_users_always_masked: GET /users — все записи маскированы независимо от прав.

2. **`test_users_pd_export.py`** (новый):
   - test_export_self_json: пользователь экспортирует свои ПД → 200 JSON.
   - test_export_by_admin: admin экспортирует чужие → 200.
   - test_export_forbidden_foreign: не-admin → 403 при попытке чужого экспорта.
   - test_export_csv: `format=csv` → response с `Content-Type: text/csv`.
   - test_export_writes_audit: после экспорта — `audit_log` содержит `action_detail="pd.export"`.
   - test_export_nonexistent: user_id не существует → 404.

3. **`test_users_pd_erase.py`** (новый):
   - test_erase_happy: admin с `user.erase_pd` → 200, поля User в БД замаскированы; `is_active=False`.
   - test_erase_without_confirmation: `confirmation != "ERASE_CONFIRMED"` → 422.
   - test_erase_self_forbidden: admin пытается erase себя → 409 CONFLICT.
   - test_erase_without_right: admin без `user.erase_pd` → 403.
   - test_erase_already_erased: повторный erase → 404 (soft-deleted не видим).
   - test_erase_preserves_consent_record: после erase `pd_consent_at` / `pd_consent_version` **остаются** (ст. 9 ФЗ-152 п. 2).
   - test_erase_writes_audit: запись в audit_log с `reason`.

4. **`test_users_crud.py`** (новый или расширение):
   - test_create_user_with_pd_fields: POST /users с phone/passport — 201.
   - test_create_user_invalid_passport_series: `passport_series="123"` (3 цифры) → 422 с ошибкой валидации.
   - test_update_user_pd_fields: PATCH полей → 200; `changes_json` в audit_log НЕ содержит значений ПД.
   - test_delete_soft: DELETE → 204, last_login_at preserved.

5. **`test_audit_sanitize.py`** (расширение файла из PR #3):
   - test_new_pd_fields_masked: все 6 новых ПД-полей из PR #5 маскируются.

6. **`test_migration_legal_pd_skeleton.py`** (новый):
   - test_columns_present_after_upgrade: 6 полей существуют в `users`.
   - test_new_permissions_seeded: `user.read_pd`/`user.erase_pd` в `permissions`.
   - test_owner_has_new_permissions: role=owner через join имеет оба новых права.
   - test_check_constraint_passport_series: INSERT `passport_series='ABC'` → violation.

**Стандарты:**
- Покрытие: ≥85% строк новых модулей (`user.py` сервис, `pd_export.py` схема, новые ветки `users.py` API).
- Никаких литералов паролей/секретов. Фикстуры в `conftest.py`: `create_user_with_pd(db, **pd_fields)`.
- Все тесты на `pytest-asyncio` в стиле существующих.

**Acceptance:** `pytest backend/tests -q` зелёный, `ruff check backend/` 0 ошибок, покрытие отчётом.

---

## 5. Порядок выполнения (рекомендация Head'у)

1. **День 1.** Блок 1 (миграция) + Блок 2 (модель). Round-trip, линтер. + `test_migration_legal_pd_skeleton.py`.
2. **День 2.** Блок 3 (схемы) + Блок 4 (репо) + Блок 7 (audit fields). Unit-тесты репо.
3. **День 3.** Блок 5 (сервис с маскированием, export, erase). TDD `test_users_pd_masking.py`.
4. **День 4.** Блок 6 (API-эндпоинты — заменить stub'ы + 2 новых). Swagger smoke.
5. **День 5.** Блок 8 (полный набор integration-тестов). Покрытие до 85%+.
6. **День 6.** Финальная чистка, ревью backend-head, reviewer. Отчёт Директору.

---

## 6. Правила слоёв (напомнить backend-dev)

**Жёстко по ADR 0004 Amendment 2026-04-18:**
- `UserService._mask_pd` — pure function, OK в сервисе.
- Все `.execute()`, `select()`, `update()`, `delete()` — только в `UserRepository`. Если начнёт писать `session.execute(update(User)...)` в сервисе — Head возвращает с request-changes.
- Типизированные предикаты (`User.is_active == True`) в `extra_conditions` — разрешены.

---

## 7. Связь с PR #2, PR #3 и совместимость

- **PR #2 API**: `require_permission`, `require_consent`, `get_current_user_only`, `ConsentService` — **не трогаем**.
- **PR #2 модели**: `Role`, `Permission`, `RolePermission`, `PdPolicy` — не трогаем; только расширяем CHECK `permissions.action` (Блок 1 п. 2) через op.execute.
- **PR #3 audit**: формула хеша не меняется; `AUDIT_EXCLUDED_FIELDS` расширяется аддитивно (Блок 7); новые audit-записи попадают в крипто-цепочку автоматически.
- **Существующие тесты PR #1, PR #2, PR #3** (~400+ штук) — **должны оставаться зелёными**. Head обязан прогнать весь `pytest backend/tests` перед финальной сдачей.

---

## 8. Риски и зависимости

- **Блокер PR #3.** Без мержа PR #3 нет down-revision для миграции Блока 1.
- **CHECK enum расширение.** Одна миграция меняет enum на лету через `op.execute`. При высокой нагрузке на staging/prod — краткий lock. На MVP-нагрузке (десятки rps) — OK.
- **Erasure и внешние ссылки.** Если ФИО пользователя уже попало в `contracts.contractor_signatory` или другие бизнес-модели — erasure в `users` не затронет эти поля. **Tech-debt фиксируется в отчёте §10:** полная erasure по системе — отдельный проект (M-OS-2 DLP).
- **Frontend.** После мержа PR #5 — frontend-director активирует FE-W1-4 (формы ПД + модалка unmask-подтверждения + экран «Мои данные» + кнопки Export/Erase). Координация через Директора после мержа.
- **Legal-review текста политики.** Политика v1.0 (PR #2) — черновик; юрист при production-gate выпустит v1.1 через обновление `pd_policies` (миграция не нужна — это data). Не блокирует PR #5.

---

## 9. DoD PR #5

- [ ] Все 8 блоков скоупа реализованы.
- [ ] Миграция `<rev>_legal_pd_skeleton.py` проходит линтер — 0 ошибок, warning `op_execute` **только** с маркерами (2 шт.).
- [ ] Round-trip миграции чист (CI job `round-trip` зелёный).
- [ ] `pytest backend/tests -q` зелёный; покрытие новых модулей ≥85%.
- [ ] `ruff check backend/app backend/tests` — 0 ошибок.
- [ ] Swagger `/docs` рендерится, `/users/*` эндпоинты (7 штук) с summary/description/response_model.
- [ ] Никаких секретов-литералов в коде и тестах.
- [ ] **Masking-acceptance:**
  - [ ] Список /users — всегда masked.
  - [ ] GET /users/{id} без `unmask` — masked; с `unmask=true` и правом — full; без права — 403.
  - [ ] Self-view — всегда full (пользователь может видеть свои ПД без дополнительных прав).
  - [ ] Unmask-вызов пишет в audit_log с `action_detail="pd.unmask_view"`.
- [ ] **Export-acceptance (ФЗ-152 ст. 14):**
  - [ ] JSON и CSV форматы работают.
  - [ ] Self-export без admin-прав — 200.
  - [ ] Foreign-export без admin-прав — 403.
  - [ ] Запись в audit_log `action_detail="pd.export"`.
- [ ] **Erase-acceptance (ФЗ-152 ст. 21):**
  - [ ] ПД-поля в БД после erase замаскированы / NULL.
  - [ ] `pd_consent_at/version` **сохраняются** (доказательство истории).
  - [ ] Confirmation string обязателен.
  - [ ] Self-erase запрещён (409).
  - [ ] Запись в audit_log `action_detail="pd.erase"` + `reason`.
- [ ] **C-4 extension:**
  - [ ] `AUDIT_EXCLUDED_FIELDS` содержит все 6 новых ПД-полей.
  - [ ] Тест UPDATE пользователя с паспортом — `changes_json` без значений.
- [ ] Существующие 400+ тестов PR #1/2/3 зелёные (регрессий 0).
- [ ] Ревью backend-head — approve.
- [ ] Ревью reviewer — approve.
- [ ] Ручной smoke всех 3 флоу (masking, export, erase) через Swagger UI.
- [ ] **Tech-debt в отчёте:**
  - (а) Erasure не затрагивает бизнес-модели (contracts/payments) — отложено до M-OS-2.
  - (б) CHECK enum расширение через op.execute — минорный риск lock на больших таблицах.
  - (в) Erased-записи хранятся бессрочно; политика срока хранения — отдельный вопрос Владельцу.
  - (г) Bulk-erasure (например, при увольнении группы) — не реализован, отдельный endpoint в будущем.

---

## 10. Ревью-маршрут

1. **backend-dev → backend-head.** Head делает ревью уровня файлов. Особое внимание: правило 1 (нет `.execute` в сервисе), маскирование не утекает в список, self-access чётко отделён от admin-доступа, audit пишется в той же транзакции.
2. **backend-head → review-head → reviewer.** Reviewer проверяет на соответствие CLAUDE.md, ADR 0004/0005/0006/0007/0011/0013, legal (ФЗ-152 ст. 14, 21). Особое внимание: не ломаем ли PR #2/3; нет ли способа обойти маскирование.
3. **Reviewer approve → backend-head → backend-director.** Приёмка по DoD: состав PR, CI-логи, покрытие, smoke-тесты трёх флоу, tech-debt.
4. **Backend-director approve → Координатору.** Координатор — git commit + push.

---

## 11. Что Head возвращает Директору на приёмку

Head оформляет отчёт одним сообщением:

1. **Состав PR.** Список файлов.
2. **Результаты тестов.** `pytest backend/tests -q --tb=short` (последние 30–50 строк).
3. **Покрытие.** `pytest --cov=backend/app/services/user --cov=backend/app/api/users --cov=backend/app/repositories/user --cov-report=term`.
4. **Линтеры.** `ruff check backend/` + `python -m tools.lint_migrations backend/alembic/versions/`.
5. **Round-trip.** Три команды alembic.
6. **Swagger smoke.** Лог/скрин `/docs` с новыми эндпоинтами.
7. **Masking-smoke.** Логи `curl` на GET /users/{id} с `unmask=true/false` для admin-с-правом и без.
8. **Export-smoke.** JSON и CSV ответы `curl` на GET /users/{id}/pd-export.
9. **Erase-smoke.** Лог POST /users/{id}/pd-erase, затем SELECT из users — пустые / placeholder значения.
10. **Замечания ревьюеров.** Сводка P0/P1/P2 и коммиты-фиксы.
11. **Отклонения от брифа.** Любое решение Head'а — с обоснованием. Особенно: выбор варианта A/B из §14.4, формат masking для `phone`, маскирование `date_of_birth` / `passport_issued_at` (показывать год? скрывать полностью?).
12. **Tech-debt.** См. §9 DoD.
13. **Метрики.** Время vs план (5–6 дней чистой работы), число раундов ревью.

---

## 12. Оценка времени

- **Backend-dev работа:** 5–6 дней чистой работы (Sonnet). Из них:
  - 1 день — миграция + модель + seed;
  - 1 день — схемы + репо + audit-extension;
  - 1 день — сервис с маскированием/export/erase;
  - 1 день — API-эндпоинты (заменить stub'ы + 2 новых);
  - 1 день — тесты (~40 штук);
  - 0.5–1 день — чистка, smoke, раунды ревью.
- **Backend-head ревью:** 0.5–1 день (≥2 раундов).
- **Reviewer:** 0.5 дня.
- **Итого календарно:** ~6–8 рабочих дней.

**Реальные блокеры:**
- Мерж PR #3 (иначе down-revision пустой).
- Ответ Координатора на §14 (иначе Head не выбирает Вариант A/B CHECK enum).
- Если Владелец ответит «добавить ИНН/СНИЛС физлица» — скоуп расширяется, +1 день.

---

## 13. Ограничения (жёсткие)

**FILES_ALLOWED (для backend-dev):**
- `backend/alembic/versions/2026_04_18_*_legal_pd_skeleton.py` (1 новая миграция)
- `backend/app/models/user.py` (расширение 6 полями)
- `backend/app/schemas/auth.py` (расширение UserCreate/UserRead)
- `backend/app/schemas/user_admin.py` (расширение UserAdminUpdate)
- `backend/app/schemas/pd_export.py` (новый файл)
- `backend/app/repositories/user.py` (расширение — 2 метода)
- `backend/app/services/user.py` (новый или расширение существующего — Head уточнит, есть ли файл)
- `backend/app/services/audit.py` (только AUDIT_EXCLUDED_FIELDS, 4 строки)
- `backend/app/api/users.py` (заменяет stub 501 + 2 новых эндпоинта)
- `backend/app/api/deps.py` (если нужен `get_user_service` helper — Head решает)
- `backend/app/main.py` (регистрация роутера уже есть — **не трогать** без причины)
- `backend/tests/test_users_pd_masking.py` (новый)
- `backend/tests/test_users_pd_export.py` (новый)
- `backend/tests/test_users_pd_erase.py` (новый)
- `backend/tests/test_users_crud.py` (новый или расширение)
- `backend/tests/test_audit_sanitize.py` (расширение файла из PR #3)
- `backend/tests/test_migration_legal_pd_skeleton.py` (новый)
- `backend/tests/conftest.py` (добавление фикстуры `create_user_with_pd`)

**FILES_FORBIDDEN:** всё остальное, в частности:
- Любые миграции, кроме своей
- `backend/app/models/role.py`, `permission.py`, `role_permission.py`, `pd_policy.py`, `audit.py` — **не трогаем** (PR #2/#3 ownership)
- `backend/app/services/consent.py`, `rbac.py`, `role.py`, `role_permission.py`, `pd_policy.py` — **не трогаем**
- `backend/app/api/auth.py`, `roles.py`, `role_permissions.py`, `permissions.py`, `user_roles.py` — **не трогаем**
- `backend/app/core/security.py`, `config.py` — **не трогаем** (const `CONSENT_POLICY_VERSION` НЕ создаём, это решение §2.1 Решение 1)
- `backend/app/middleware/consent.py` — **не трогаем**
- `frontend/*` — всё фронтовое
- Любые ADR-файлы
- `CLAUDE.md` проектный

**COMMUNICATION_RULES:**
- backend-dev не общается с другими отделами напрямую.
- Вопросы по скоупу — только к backend-head.
- Head эскалирует Директору, если вопрос не решается через бриф.
- К legal / design / frontend / db — только через Директора.
- К Координатору / Владельцу — только через Директора.

**Жёсткие технические запреты:**
- **ADR 0004, 0005, 0006, 0007, 0011, 0013 не трогаем.** Отклонение — request-changes.
- **Никаких изменений формулы хеша PR #3.** Формула bit-exact.
- **Никакой retroactive mask старых записей** audit_log (запрет из PR #3 §2.2).
- **Никаких секретов-литералов.** `os.environ.get(...)` или `secrets.token_urlsafe(16)`.
- **`# type: ignore` / `# noqa` — только с комментарием-обоснованием.**
- **`git add -A` запрещён.** Только конкретные файлы.
- **Коммит — после reviewer approve.**

---

## 14. Вопросы Координатору (блокируют старт работы backend-dev)

**1. Эндпоинты `/auth/consent-status` и `/auth/accept-consent` — в PR #5 НЕ переделываем?**
   - Директор подтверждает: они уже реализованы в PR #2 (`app/api/auth.py` строки 258, 289; `app/services/consent.py` метод `accept`).
   - Координатор в исходном запросе п. 6–7 просил «реализовать реальный эндпоинт» — это формулировка, видимо, основана на старом состоянии frontend-MSW.
   - **Решение Директора:** из PR #5 вычёркиваем. Константа `CONSENT_POLICY_VERSION` в `app/core/config.py` не создаётся (источник истины — `pd_policies.is_current=TRUE`).
   - **Требуется ответ: подтверждаете?**

**2. Формат маскирования `phone`, `date_of_birth`, `passport_issued_at`:**
   - `phone`: Директор предлагает формат `+7 *** *** XX 88` (первые 2 и последние 2 цифры). Альтернативы: полностью скрыть, или last-4.
   - `date_of_birth`: полностью скрывать (None) vs показывать год (безопаснее).
   - `passport_issued_at`: полностью скрывать vs показывать год.
   - **Директор рекомендует:** `phone` — first-2+last-2 (идентификация при звонке), `date_of_birth` — только год, `passport_issued_at` — полностью скрывать. **Требуется согласие Координатора ИЛИ эскалация Владельцу, если нужен другой баланс приватность/удобство.**

**3. Состав паспорта (базовый вопрос Владельцу):**
   - **РФ-паспорт**: серия 4 цифры + номер 6 цифр + кем выдан + когда выдан — это база.
   - **Опционально:** код подразделения (6 цифр, формат XXX-XXX), место рождения, место регистрации.
   - **Отдельно:** ИНН физлица (12 цифр), СНИЛС (11 цифр в формате XXX-XXX-XXX XX).
   - **В исходном запросе Координатора:** 4 + 6 + «кем» + «когда» + дата рождения.
   - **Вопрос к Владельцу через Координатора:** достаточно ли базы, или нужны ИНН/СНИЛС для MVP? Если да — отдельный PR #5.1 после PR #5.
   - **Директор рекомендует: только база, без ИНН/СНИЛС в M-OS-1.** Причины: (а) для текущих бизнес-сценариев (доступ сотрудников к M-OS) ИНН/СНИЛС не нужны; (б) лишние поля — лишний штраф-риск при утечке. ИНН/СНИЛС — для contractor / contract-payment flows (M-OS-2).

**4. Новое право на unmask: имя и как встроить в CHECK enum:**
   - Вариант A (рекомендация): `user.read_pd` + `user.erase_pd`; расширить CHECK enum `permissions.action` до 7 значений (+ `read_pd`, `erase_pd`).
   - Вариант B: использовать существующее `user.admin` — избегает миграции enum, но снижает least-privilege.
   - **Директор рекомендует Вариант A.** Ответственность: +1 миграционная операция `op.execute` с маркером. **Ответ Координатора обязателен.**

**5. Политика срока хранения erased-записей (вопрос Владельцу):**
   - 0 дней = hard DELETE сразу (потеря доказательной базы для возможных споров)
   - 30 дней = soft-delete → hard DELETE через 30 (сбалансировано)
   - 1 год = требование некоторых ЛНА (бухгалтерия)
   - Бессрочно = простейший MVP-подход
   - **Директор рекомендует для MVP: бессрочно** (hard DELETE не реализуется в PR #5; все erased-записи остаются с `deleted_at IS NOT NULL` и замаскированными полями). Политика и cron-job на hard DELETE — отдельный ADR после legal-review. **Ответ Координатора блокирует только документирование tech-debt, не код.**

---

## 15. Ответы Координатора (+ Владельца Мартина) — 2026-04-18

*Источник: Telegram msg 1411 «делай» + msg 1420 «ок по всем» после сводки 10 рекомендаций Координатора.*

**1. Эндпоинты consent — подтверждено вычёркиваем из PR #5.** `/auth/accept-consent` и `/auth/consent-status` уже в PR #2. Константа `CONSENT_POLICY_VERSION` не создаётся — источник истины `pd_policies.is_current=TRUE`.

**2. Формат маскирования — принимаем рекомендацию Директора:** `phone` — first-2+last-2 (`+7 *** *** XX 88`), `date_of_birth` — только год, `passport_issued_at` — полностью скрыть. Для паспорта серия/номер — «•» символами с auto-hide 60 сек (рекомендация дизайнера, принято).

**3. Состав паспорта — только база** (серия 4 + номер 6 + кем выдан + когда выдан + дата рождения). **ИНН/СНИЛС не добавляем в M-OS-1**, откладываем до M-OS-2 для contractor/payment flows.

**4. CHECK enum permissions — Вариант A** (расширяем до 7 значений: + `read_pd`, `erase_pd`). Принцип least-privilege приоритетнее избегания миграции.

**5. Срок хранения erased-записей — бессрочно для MVP.** Hard DELETE не реализуется в PR #5. Tech-debt: отдельный ADR после live-legal review в production-gate.

### Дополнительные ответы (вопросы из консолидированной сводки):

**6. Кто оператор ПДн** — открыто, решение за живым юристом в production-gate. В тексте согласия — плейсхолдеры.

**7. Пользователи не-сотрудники (подрядчики)** — да, планируются. Consent-flow работает для всех типов пользователей.

**8. Частичное заполнение паспорта** — WARN (не блок). «Паспорт введён не полностью — для некоторых операций потребуются все поля».

**9. Удаление ПД при активных договорах** — BLOCK с overridable-флагом для OWNER. UI добавляет подтверждение с перечислением активных связей.

**10. Unmask — granular** (отдельные кнопки per-field). Больше audit-событий, лучше для compliance.

---

*Бриф составлен backend-director 2026-04-18 для backend-head в рамках M-OS-1 Волна 1 Foundation PR #5. Ответы Координатора зафиксированы в §15. Активация — после мержа PR #3 в `main`. После мержа — передача Head через паттерн Координатор-транспорт v1.6.*
