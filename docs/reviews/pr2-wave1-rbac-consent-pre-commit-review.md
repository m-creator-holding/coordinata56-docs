# Pre-commit Review — PR #2 Wave 1: RBAC v2 + PD Consent (ФЗ-152)

- **Ревьюер**: reviewer (independent code review agent)
- **Дата**: 2026-04-18
- **Ревью методика**: OWASP Top 10 (2021) + ADR Compliance Checker
- **Scope**: 42 staged файла, +4739 / -145 строк
- **Контекст**: финальный production gate блокер по ФЗ-152, штраф до 700 тыс ₽

---

## ВЕРДИКТ: REQUEST-CHANGES

**Основание**: обнаружено 2 блокирующих замечания (P0) и 3 критических (P1), которые должны быть устранены до коммита. Часть из них влияет на корректность legal-compliance ФЗ-152 и нарушает ADR-контракты.

---

## Сводка по приоритетам

| Приоритет | Количество | Статус |
|---|---|---|
| P0 (blocker) | 2 | Блокируют merge |
| P1 (major) | 3 | Блокируют merge |
| P2 (minor) | 6 | Желательно до merge |
| nit | 3 | Опционально |

---

## P0 — BLOCKER (блокируют merge)

### P0-1. `deps.py:41` — SQLAlchemy `select` импортируется в api-слой, нарушение ADR 0004 MUST #1a

**Файл**: `backend/app/api/deps.py`, строка 41

```python
from sqlalchemy import select
```

`select` импортирован напрямую в `deps.py`, который является частью api-слоя (аналог роутера). Далее он используется в строках 111–112 и 123–126 функции `get_current_user`:

```python
result = await db.execute(select(User).where(User.email == sub))
...
roles_result = await db.execute(
    select(UserCompanyRole).where(UserCompanyRole.user_id == user.id)
)
```

Это прямое нарушение ADR 0004 MUST #1a: «SQLAlchemy-запросы пишутся **только** в `repositories/`». `deps.py` — это api-слой, он не имеет права строить или выполнять SQLAlchemy-запросы. Аналогичный паттерн присутствует и в `auth.py` (строки 75, 123) — но там это было унаследовано от PR #1. В PR #2 в `deps.py` добавлен новый код с тем же паттерном.

Нарушение не новое — `auth.py` был таким и до PR #2 — однако PR #2 вводит новые зависимости (`get_current_user`) без рефакторинга, тем самым закрепляя и расширяя паттерн-нарушение. По ADR-checker: незаявленное отклонение, при этом MUST #1a явно запрещён.

**Требование**: Перенести `select(User)` и `select(UserCompanyRole)` в репозиторий (например, `UserRepository.get_by_email(email)` и `UserCompanyRoleRepository.list_by_user(user_id)`). Это изменение `deps.py` — часть FILES_ALLOWED.

**OWASP**: A04 — отсутствие изоляции слоёв делает код трудно аудируемым. Само по себе не уязвимость, но системная проблема.

---

### P0-2. `backend/app/api/permissions.py` — файл отсутствует, роутер не зарегистрирован в `main.py`

**Файл**: отсутствует. Проверено через glob `backend/app/api/permissions*.py` — файл не существует. В `main.py` нет импорта `permissions_router`.

Бриф §3 Пункт 7.4 требует: «Новый файл `backend/app/api/permissions.py`» с эндпоинтами `GET /api/v1/permissions` и `GET /api/v1/permissions/{permission_id}`.

Сервис `PermissionService` (`backend/app/services/permission.py`) реализован, репозиторий `PermissionRepository` реализован, но роутер отсутствует. По DoD PR #2 пункт «Все 9 пунктов скоупа реализованы» — это нарушение.

Это также означает, что `GET /api/v1/permissions` — недоступен, и администратор не может видеть список прав для назначения в матрицу (UI-блокер).

**Требование**: создать `backend/app/api/permissions.py` и зарегистрировать роутер в `main.py`.

---

## P1 — MAJOR (блокируют merge)

### P1-1. `consent.py:86` — `# type: ignore[arg-type]` без адекватного обоснования

**Файл**: `backend/app/services/consent.py`, строка 86

```python
required_action=required_action,  # type: ignore[arg-type]  # Literal проверяется логикой выше
```

Правило CLAUDE.md проекта: «Никаких `# type: ignore` / `# noqa` без комментария-обоснования». Комментарий есть, но обоснование технически неверно: `required_action` имеет тип `str` (присваивается через if/elif/else с строковыми литералами), а схема ожидает `Literal["accept", "refresh", "none"]`. Mypy/pyright не может вывести тип автоматически.

Корректное решение — дать `required_action` правильный тип явно:

```python
required_action: Literal["accept", "refresh", "none"]
if user_version is None:
    required_action = "accept"
elif user_version != current_version:
    required_action = "refresh"
else:
    required_action = "none"
```

Или использовать `cast()` из `typing`. Подавление с `# type: ignore` без реального исправления — технический долг с риском регрессии при рефакторинге. Регламент запрещает именно такой паттерн.

**Требование**: убрать `# type: ignore`, использовать явную аннотацию типа.

---

### P1-2. `deps.py:273` — `# type: ignore[assignment]` в `get_consent_service` — архитектурный запах

**Файл**: `backend/app/api/deps.py`, строки 272–273

```python
user_repo: BaseRepository[UserModel] = BaseRepository(db)
user_repo.model = UserModel  # type: ignore[assignment]  # BaseRepository[User] без специализации
```

Паттерн `BaseRepository(db)` без привязки модели и последующее `user_repo.model = UserModel` — это обход типобезопасности. `BaseRepository` требует класса-наследника с заданным атрибутом `model`. Прямое присвоение `model` на экземпляре нарушает контракт класса.

Это нарушение ADR 0004 архитектурного контракта: репозиторий должен специализироваться через наследование, а не через динамическое присвоение атрибута. Правильное решение — создать `UserRepository(BaseRepository[User])` в `backend/app/repositories/` (это FILES_ALLOWED) или добавить `user_repo` как параметр `ConsentService`.

Тот же паттерн повторяется в `auth.py:141–142`. Это незаявленное отклонение от ADR 0004.

**Требование**: создать `UserRepository` или переделать сигнатуру `ConsentService.accept()` так, чтобы не требовать обобщённого репозитория напрямую.

---

### P1-3. `user_roles.py` — аудит-лог записывается до удаления объекта, нарушение транзакционного порядка

**Файл**: `backend/app/api/user_roles.py`, строки 268–278

```python
await audit_svc.log(
    ...
    action=AuditAction.DELETE,
    ...
)

await db.delete(assignment)
await db.flush()
```

По ADR 0007: «Вызов `audit_service.log(...)` — после успешной операции». Здесь аудит записывается **до** физического удаления объекта из БД. Если `db.delete(assignment)` / `db.flush()` завершится с ошибкой (например, при нарушении FK), аудит-запись останется, но удаление не произошло — аудит солжёт.

Правильный порядок: сначала `db.delete(assignment)` + `db.flush()`, затем `await audit_svc.log()`. Оба вызова находятся в одной транзакции, поэтому транзакционность сохранится.

Аналогичная проблема отмечена в `RoleService.delete()` (`backend/app/services/role.py`, строки 206–215) — там аудит тоже пишется до `repo.delete_by_id()`.

**Требование**: переставить порядок: физическое изменение → аудит-лог в обоих файлах.

---

## P2 — MINOR (желательно устранить до merge)

### P2-1. `consent.py` — `get_status()` бросает `ValueError` при отсутствии политики вместо `AppError`

**Файл**: `backend/app/services/consent.py`, строки 68–71

```python
raise ValueError(
    "В системе отсутствует текущая политика обработки персональных данных. "
    "Необходимо применить миграцию с seed-данными."
)
```

`ValueError` — это встроенное исключение Python, а не `AppError`. Обработчик `Exception` в `main.py` поймает его и вернёт `500 INTERNAL_ERROR` без подробностей. В `auth.py:150–157` этот случай обработан через `except ValueError`, что является правильным поведением на уровне роутера — но это антипаттерн.

По ADR 0005 доменные ошибки должны наследоваться от `AppError`. Для данного случая подходит `DomainValidationError` или специальный `ConfigurationError`. Тогда клиент получит понятный код ошибки, а не 500.

**Требование**: заменить `raise ValueError` на `raise DomainValidationError(...)` или аналогичный `AppError`-подкласс.

---

### P2-2. `middleware/consent.py:109` — `current_version="unknown"` в ошибке middleware — неинформативно для клиента

**Файл**: `backend/app/middleware/consent.py`, строка 109

```python
error = PdConsentRequiredError(current_version="unknown")
```

Middleware при блокировке возвращает `current_version="unknown"` в деталях ошибки. Клиент не может узнать, какую версию нужно принять. Middleware не имеет доступа к БД — это архитектурное ограничение — но можно было прочитать `current_version` из JWT-клейма, если он там есть. Если нет — это допустимо для MVP.

**Рекомендация**: добавить комментарий с обоснованием `"unknown"` (middleware не имеет доступа к БД, actual version получается через `GET /auth/consent-status`). Либо добавить `current_version` в JWT-payload при логине.

---

### P2-3. `user_roles.py:102` — `require_permission("read", "user_roles")` — ресурс `user_roles` отсутствует в матрице

**Файл**: `backend/app/api/user_roles.py`, строка 102

```python
pair: tuple[User, UserContext] = Depends(require_permission("read", "user_roles")),
```

В seed-данных миграции (`2026_04_18_1200_ac27c3e125c8`) действительно добавлены `user_roles.read` и `user_roles.admin` — это соответствует. Но в матрице роли `accountant` и `construction_manager` получают только `user_roles.read`, а `owner` получает их через `SELECT * WHERE r.code='owner'` (все 25 прав). Проблема в том, что `user_roles.admin` не назначен ни одной роли кроме `owner`. Роль `accountant`, у которой есть `user.admin`, не имеет `user_roles.admin` — что выглядит несимметрично. Это не блокер, но стоит проверить бизнес-требование.

**Рекомендация**: уточнить у директора, должны ли `accountant`/`construction_manager` иметь `user_roles.admin` или только read.

---

### P2-4. `auth.py:293` — `accept_consent` принимает `db: AsyncSession` но не использует его напрямую

**Файл**: `backend/app/api/auth.py`, строка 309

```python
db: AsyncSession = Depends(get_db),
```

Параметр `db` объявлен в `accept_consent`, но в теле функции не используется — `consent_service` уже имеет свою сессию через Depends. Это мёртвый параметр. Docstring объясняет это: «нужна только для flush — ConsentService использует свою сессию», — но на самом деле flush происходит внутри `consent_service.accept()`, которому сессия передаётся через `get_consent_service`. Мёртвый `Depends` вызывает лишний запрос к БД (создаёт ещё одну сессию).

**Требование**: удалить неиспользуемый параметр `db`.

---

### P2-5. Отсутствует тест `test_roles_api.py` и `test_user_roles_api.py` из бриф §3 Пункт 9

Бриф требует тесты: `test_roles_api.py`, `test_user_roles_api.py`, `test_role_permissions_api.py`, `test_permissions_api.py`, `test_migration_rbac.py` — ни одного из этих файлов нет в staged-наборе. Существующие тесты покрывают: unit `test_rbac_service.py`, unit `test_consent_service.py`, integration `test_pr2_rbac_integration.py`, unit middleware `test_consent_middleware.py`, integration `test_consent_enforcement.py`.

По DoD PR #2: «`pytest backend/tests -q` зелёный; покрытие новых модулей ≥85%». Без тестов на роутеры admin-эндпоинтов это требование не выполнено для IDOR-сценариев и 409 на системные роли.

**Требование**: минимально добавить тест IDOR `DELETE /users/A/roles/{id_пользователя_B} → 404` и `DELETE system_role → 409`. Это ключевые legal-риски.

---

### P2-6. `P2-6. `role.py:72` — фильтрация через `filters` dict, а не `extra_conditions` list — нарушение Amendment 2026-04-18

**Файл**: `backend/app/services/role.py`, строки 65–76

```python
filters: dict = {}
if is_system is not None:
    filters["is_system"] = is_system
if code is not None:
    filters["code"] = code

return await self.repo.list_paginated(
    offset=offset,
    limit=limit,
    filters=filters if filters else None,
    ...
)
```

Если `BaseRepository.list_paginated` принимает `filters: dict`, это означает что репозиторий сам преобразует словарь в `WHERE` — это приемлемо. Но если внутри репозитория происходит ключевой доступ по строке `filters["is_system"]` — нет типобезопасности. По Amendment ADR 0004 2026-04-18 MUST #1b предпочтительный паттерн — `extra_conditions: list[ColumnElement[bool]]`.

Необходимо убедиться, что `BaseRepository.list_paginated` корректно обрабатывает `filters={"is_system": True}` (без SQL-инъекции через строку). Если реализация безопасная (через ORM `getattr` или `filter_by`) — это P2. Если нет — P0.

**Рекомендация**: проверить реализацию `BaseRepository.list_paginated` в `backend/app/repositories/base.py` на предмет обработки `filters` параметра. Если там `sa.text(f"...")` — поднять до P0.

---

## nit (опционально)

### nit-1. `middleware/consent.py:89` — `except (jwt.InvalidTokenError, Exception)` — второй класс избыточен

```python
except (jwt.InvalidTokenError, Exception):
```

`Exception` является супером `jwt.InvalidTokenError`, поэтому первый элемент кортежа избыточен. Достаточно `except Exception`. Или, если цель — поймать только JWT-ошибки, убрать `Exception` и добавить конкретный список.

### nit-2. `consent.py:44` — параметр `db: AsyncSession | None = None` не используется

В `get_status(self, user: User, db: AsyncSession | None = None)` параметр `db` объявлен в сигнатуре, docstring объясняет «не используется», но сам параметр добавляет путаницу. Его стоит убрать из публичного API метода.

### nit-3. `seeds.py:340` — seed создаёт пользователя без согласия на обработку ПД

Начальный seed-пользователь (owner Мартин) будет создан без `pd_consent_at` и `pd_consent_version`. Это ожидаемое поведение для MVP (consent через UI первого логина), но стоит добавить комментарий о том, что owner обязан принять политику при первом входе.

---

## ADR Compliance Summary

| ADR | Требование | Статус |
|---|---|---|
| ADR 0004 MUST #1a | SQL только в repositories | НАРУШЕНИЕ (P0-1) |
| ADR 0004 MUST #1b | Предикаты допустимы в сервисе | Соблюдено |
| ADR 0005 | Формат ошибок `{error:{code,message,details}}` | Соблюдено — PdConsentRequiredError через AppError |
| ADR 0005 | Конкретно `PD_CONSENT_REQUIRED` в middleware | Соблюдено |
| ADR 0006 | Пагинация `{items,total,offset,limit}` | Соблюдено |
| ADR 0007 | Аудит в той же транзакции | НАРУШЕНИЕ (P1-3) — порядок операций |
| ADR 0011 §2.1 | is_holding_owner bypass | Соблюдено |
| ADR 0011 §2.2 | Configuration-as-data матрица | Соблюдено |
| ADR 0011 §2.3 | require_permission | Соблюдено |
| ADR 0011 §2.4 | JWT claims: company_ids, is_holding_owner, consent_required | Соблюдено |
| ADR 0013 | Expand-pattern миграции | Соблюдено (nullable добавления) |
| ADR 0013 | Drop CHECK на user_company_roles | Заявлено с migration-exception — приемлемо |
| ADR 0013 | Round-trip | Не верифицировано ревьюером (требует live БД) |

---

## OWASP Top 10 Checklist

| OWASP | Проверка | Результат |
|---|---|---|
| A01 Broken Access Control | IDOR в user_roles.py DELETE | Соблюдено — `assignment.user_id != user_id → 404` |
| A01 | require_permission на всех admin-эндпоинтах | Соблюдено |
| A01 | CORS с allow_credentials | Соблюдено — origins не wildcard в prod |
| A02 | Пароли через bcrypt | Соблюдено |
| A02 | JWT_SECRET_KEY без дефолта, ≥32 символов | Соблюдено — `Field(...)` без default |
| A02 | PII в логах | Не обнаружено в reviewed файлах |
| A03 | SQL инъекция в raw-text запросах | Соблюдено — параметризованные `:user_id`, `:role_code` |
| A03 | Pydantic-валидация входных данных | Соблюдено |
| A05 | Стек-трейсы клиенту | Соблюдено — `unhandled_error_handler` фиксированный текст |
| A05 | Дефолтные пароли в коде | `change_me` в DATABASE_URL дефолте — допустимо (не секрет, env) |
| A07 | Timing-атака на login | Соблюдено — `dummy_verify()` |
| A07 | Anti-enumeration (одинаковый ответ на неверный пароль/нет юзера) | Соблюдено |
| A09 | Аудит login / смена прав | Соблюдено (аудит consent.accept) |
| A09 | Логи не содержат пароли | Соблюдено в reviewed коде |

---

## Compliance ФЗ-152 (C-1)

| Требование | Реализация | Статус |
|---|---|---|
| pd_consent_at / pd_consent_version в users | Миграция, ORM-модель | Выполнено |
| PdPolicy v1.0 из privacy-policy-draft.md §1–5 | seed в миграции | Выполнено |
| consent_required в JWT | create_access_token + login | Выполнено |
| Middleware блокирует бизнес-эндпоинты | ConsentEnforcementMiddleware | Выполнено |
| Whitelist exact match (не startswith) | `if (method, path) in list` | Выполнено |
| /consent-status без require_consent | get_current_user_only | Выполнено (deadlock-защита) |
| /accept-consent без require_consent | get_current_user_only | Выполнено |
| holding_owner обязан принять политику | login проверяет consent для всех | Выполнено |
| Аудит принятия согласия | ConsentService.accept() → audit.log() | Выполнено |
| Unit-тест `error.code == "PD_CONSENT_REQUIRED"` | test_consent_middleware.py:152 | Выполнено |
| 3 integration сценария | test_consent_enforcement.py | Выполнено |

---

## Безопасность тестовых данных

- `conftest.py:27` — `JWT_SECRET_KEY = secrets.token_urlsafe(48)` — правильно, генерируется при каждом прогоне.
- `conftest.py:67` — пароль пользователей `secrets.token_urlsafe(16)` — правильно.
- `TEST_DB_URL` в integration-тестах содержит `change_me_please_to_strong_password` — это не секрет (dev-only URL), допустимо. Сам факт не закомммиченного `.env` — нормально.
- Литеральных паролей типа `password123` не обнаружено.

---

## Что сделано хорошо (отметить разработчику)

1. `PdConsentRequiredError` через `AppError` — правильный паттерн, даёт корректный ADR 0005 формат без дополнительной обработки в middleware.
2. `ConsentEnforcementMiddleware` с exact-match whitelist через tuple — правильно, без startswith/regexp.
3. `dummy_verify()` для защиты от timing-атаки на login — выровнено время ответа.
4. `RbacCache.invalidate_many()` вызывается при `bulk_replace` — инвалидация кеша реализована.
5. IDOR-защита в `delete_user_role`: `assignment.user_id != user_id → 404` (не 403) — соответствует CLAUDE.md.
6. Параметризованные raw-SQL запросы в `RolePermissionRepository.get_user_permissions()` — безопасно.
7. Партиальный UNIQUE-индекс на `pd_policies.is_current` — единственная текущая политика гарантирована на уровне БД.
8. `is_holding_owner` bypass в `user_has_permission` — первым шагом, без SQL-запроса.

---

## Список файлов с замечаниями

- `/root/coordinata56/backend/app/api/deps.py` — P0-1, P1-2
- `/root/coordinata56/backend/app/api/auth.py` — P1-2 (повтор паттерна), P2-4
- `/root/coordinata56/backend/app/services/consent.py` — P1-1, P2-1, nit-2
- `/root/coordinata56/backend/app/api/user_roles.py` — P1-3, P2-3
- `/root/coordinata56/backend/app/services/role.py` — P1-3 (порядок аудита в delete)
- `/root/coordinata56/backend/app/middleware/consent.py` — P2-2, nit-1
- `/root/coordinata56/backend/app/services/role.py` — P2-6 (filters dict)
- Отсутствующий файл `backend/app/api/permissions.py` — P0-2

---

## Что необходимо для approve

1. **P0-1**: вынести `select(User)` и `select(UserCompanyRole)` из `deps.py` в репозитории.
2. **P0-2**: создать `backend/app/api/permissions.py` и зарегистрировать в `main.py`.
3. **P1-1**: убрать `# type: ignore[arg-type]` в `consent.py:86`, дать `required_action` правильный тип.
4. **P1-2**: убрать `BaseRepository(db)` + динамическое присвоение `.model` — создать `UserRepository` или рефакторить `ConsentService`.
5. **P1-3**: переставить порядок в `user_roles.py:delete_user_role` и `role.py:delete` — физическое изменение перед аудит-логом.

После устранения P0 и P1 — повторное ревью не требуется, достаточно подтверждения разработчика с указанием коммита исправлений.

---

*Отчёт сформирован reviewer (Quality Department, Worker L4) 2026-04-18 по регламенту regulations_addendum_v1.3 §1.*
