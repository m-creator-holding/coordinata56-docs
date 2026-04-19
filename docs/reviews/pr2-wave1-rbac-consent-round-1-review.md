# Round-1 Review — PR #2 Wave 1: RBAC v2 + PD Consent (ФЗ-152)

- **Ревьюер**: reviewer (Quality Department, Worker L4)
- **Дата**: 2026-04-18
- **Scope**: fix-round-3, 18 файлов, +1108/-51
- **Контекст**: re-review после исправления 2 P0 + 3 P1 + 6 P2 + 3 nit из round-0

---

## ВЕРДИКТ: APPROVE

Все блокирующие замечания (P0, P1) из round-0 устранены. Новых P0 и P1 не выявлено.
Commit разрешён.

---

## Верификация замечаний round-0

### P0-1 — `select` в deps.py → репозитории

ЗАКРЫТО.

`/root/coordinata56/backend/app/api/deps.py` строки 110–111, 122–123: `UserRepository(db).get_by_email(sub)` и `UserCompanyRoleRepository(db).list_by_user(user.id)`. SQL выполняется в репозиториях. `from sqlalchemy import select` в deps.py удалён. ADR 0004 MUST #1a соблюдён.

### P0-2 — отсутствующий `permissions.py` роутер

ЗАКРЫТО.

`/root/coordinata56/backend/app/api/permissions.py` создан (127 строк). В `main.py` строка 33: импорт `permissions_router`; строка 245: `app.include_router(permissions_router, prefix="/api/v1")`. Оба эндпоинта `GET /permissions/` и `GET /permissions/{permission_id}` реализованы с `require_permission("read", "role")`, ADR 0006 envelope и ADR 0005 404.

### P1-1 — `# type: ignore[arg-type]` в consent.py

ЗАКРЫТО.

`/root/coordinata56/backend/app/services/consent.py` строка 73: `required_action: Literal["accept", "refresh", "none"]` — явная аннотация без `# type: ignore`. Typing корректен.

### P1-2 — `BaseRepository(db)` hack в deps.py

ЗАКРЫТО.

`get_consent_service` (deps.py строки 266–273) передаёт `UserRepository(db)` — правильный наследник. `BaseRepository` в сигнатуре `ConsentService.__init__` используется как тип-контракт (`user_repo: BaseRepository[User]`), фактическое значение — `UserRepository`. Динамического присвоения `.model` нет.

### P1-3 — аудит до физического удаления

ЗАКРЫТО.

`user_roles.py` строки 268–280: `db.delete(assignment)` → `db.flush()` → `audit_svc.log()`. Комментарий «Физическое удаление — до записи аудит-лога (ADR 0007)» присутствует.

`role.py` строки 206–217: `self.repo.delete_by_id(role_id)` → `self.audit.log()`. Порядок правильный. ADR 0007 соблюдён в обоих местах.

### P2-1 — ValueError → DomainValidationError

ЗАКРЫТО. `consent.py` строки 64–68: `DomainValidationError(..., code="PD_POLICY_NOT_CONFIGURED")`.

### P2-2 — current_version="unknown" без обоснования

ЗАКРЫТО. `middleware/consent.py` строка 108: комментарий «Middleware не имеет доступа к БД — actual version берётся через GET /auth/consent-status. "unknown" допустимо для MVP».

### P2-3 — матрица user_roles.admin

ЗАКРЫТО решением Координатора: `user_roles.admin` → только `owner`. Остальные роли получают `user_roles.read`. Эскалация Владельцу не требовалась.

### P2-4 — мёртвый `db` параметр в accept_consent

ЗАКРЫТО. `auth.py:accept_consent` (строки 299–332) — параметр `db` отсутствует.

### P2-5 — отсутствие тестов роутеров

ЗАКРЫТО. 5 тестовых файлов созданы:

- `/root/coordinata56/backend/tests/api/test_user_roles_api.py` — 4 теста: IDOR DELETE чужого assignment → 404 (код `NOT_FOUND`); happy path assign → 201; list без токена → 401; delete системной роли → 409 `SYSTEM_ROLE_PROTECTED`.
- `/root/coordinata56/backend/tests/api/test_permissions_api.py` — 3 теста: list happy (ADR 0006 envelope); 401 без токена; 404 на несуществующий id.
- `/root/coordinata56/backend/tests/api/test_roles_api.py` — 3 теста: list happy; delete system role → 409; create без токена → 401.
- `/root/coordinata56/backend/tests/repositories/test_user_repository.py` — 3 теста: get_by_email happy; not found; excludes soft-deleted.
- `/root/coordinata56/backend/tests/repositories/test_user_company_role_repository.py` — 3 теста: list_by_user happy; empty list; изоляция по user_id.

Итого 16 тестов. Ключевые правовые риски (IDOR, 409 на системную роль, soft-delete исключение) покрыты.

### P2-6 — filters dict в BaseRepository

ЗАКРЫТО. `base.py` строки 107–111: `col = getattr(self.model, col_name, None); if col is not None: stmt = stmt.where(col == value)`. ORM-предикат, SQL injection невозможна.

### nit-1, nit-2, nit-3

Все закрыты: `except Exception` в middleware; мёртвый `db` в consent.py убран; комментарий об owner first-login consent в seeds.py добавлен.

---

## Новые наблюдения fix-round-3

### minor — дублирование `_UserCompanyRoleRepository` в user_roles.py

`user_roles.py` строки 37–73 содержит приватный класс `_UserCompanyRoleRepository` с методом `list_by_user(offset, limit) -> tuple[list, int]`. Параллельно создан публичный `UserCompanyRoleRepository` в `repositories/`, у которого `list_by_user` возвращает `list` без total. Функциональное различие есть: API-роутеру нужна пагинированная версия (items + total), `deps.py` — только список. TODO-SERVICE комментарий зафиксирован в коде. Это плановый технический долг, не blocker.

### nit — import внутри метода в user_roles.py

`user_roles.py:65` — `from sqlalchemy import ColumnElement` внутри метода `list_by_user`. Семантически корректно, но нестандартно: импорт не выполняется при каждом вызове (Python кеширует модули), однако затрудняет статический анализ. Рекомендация: перенести на уровень модуля при следующем касании файла.

### nit — company_id=1 в test fixture

`test_user_company_role_repository.py:66` — `_create_ucr(session, user_id, company_id=1)` предполагает, что Company(id=1) существует. В изолированной транзакции без seed-данных это может дать FK violation. Не блокер для CI (тест гоняется против тестовой БД с seed), но хрупкое место.

---

## ADR Compliance — итог round-1

| ADR | Требование | Статус |
|---|---|---|
| ADR 0004 MUST #1a | SQL только в repositories | СОБЛЮДЕНО (P0-1 закрыт) |
| ADR 0005 | Формат ошибок | СОБЛЮДЕНО |
| ADR 0006 | Пагинация envelope | СОБЛЮДЕНО |
| ADR 0007 | Аудит после операции | СОБЛЮДЕНО (P1-3 закрыт) |
| ADR 0011 §2.3 | require_permission | СОБЛЮДЕНО |

---

## OWASP — финальный статус

| OWASP | Проверка | Статус |
|---|---|---|
| A01 IDOR | DELETE чужого assignment → 404 | СОБЛЮДЕНО + тест |
| A01 require_permission | Все write-эндпоинты | СОБЛЮДЕНО |
| A03 SQL injection | filters через ORM getattr | СОБЛЮДЕНО |
| A09 Аудит | Порядок: операция → лог | СОБЛЮДЕНО |

---

*Reviewer (Quality Department, Worker L4) — 2026-04-18. Регламент regulations_addendum_v1.3 §1.*
