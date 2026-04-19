# Дев-бриф: широкая починка consent-failures

**Кому:** backend-dev-2  
**От:** backend-head  
**Дата:** 2026-04-19  
**Приоритет:** P0 (тест-сьют не запускается)  
**Оценка:** ~2 часа  
**Коммит:** НЕ коммитить — сдать на ревью backend-head

---

## Контекст

В `app/api/contracts.py` обнаружен дефект, блокирующий загрузку `app.main`: используются `UserRole` и `_READ_ROLES`, которые не определены в файле. Это роняет всю коллекцию тестов (23 файла, `NameError` при импорте). После устранения этого блокера — ~294 теста упадут на 403 из-за consent-gate: фикстуры создают `User()` без `pd_consent_version`.

Ты уже знаком с consent-системой (чинил `create_user_with_role`). Задача — починить оба блокера.

---

## Шаг 1 (P0): Починить contracts.py

**Файл:** `backend/app/api/contracts.py`

**Дефект 1 — отсутствует импорт.**  
В блоке импортов (строка ~22) есть:
```python
from app.models.enums import ContractStatus
```
Добавь `UserRole` в тот же импорт:
```python
from app.models.enums import ContractStatus, UserRole
```

**Дефект 2 — не определена `_READ_ROLES`.**  
После блока импортов, перед `_make_service`, добавь:
```python
# Роли, допущенные к просмотру договоров.
# read_only исключён: договоры содержат коммерческую тайну.
_READ_ROLES: frozenset[UserRole] = frozenset({
    UserRole.OWNER,
    UserRole.ACCOUNTANT,
    UserRole.CONSTRUCTION_MANAGER,
})
```

Проверь, что `python -c "from app.api.contracts import router"` не выдаёт ошибок.  
Затем: `cd /root/coordinata56/backend && pytest tests/test_health.py --tb=short -q` — должен коллектиться без `NameError`.

---

## Шаг 2 (P1): Добавить helper в корневой conftest.py

**Файл:** `backend/conftest.py`

После функции `ensure_default_company` добавь публичную хелпер-функцию:

```python
async def get_current_policy_version(db_session: AsyncSession) -> str | None:
    """Возвращает версию актуальной политики ПД (is_current=True) или None.

    Используется в тестовых фикстурах для простановки pd_consent_version
    при создании User, чтобы ConsentEnforcementMiddleware не блокировала
    тестовые запросы с HTTP 403 (Root Cause B, диагностика 2026-04-19).

    Args:
        db_session: тестовая сессия БД.

    Returns:
        Строка версии (например, "v1.0") или None если политики нет.
    """
    result = await db_session.execute(
        select(PdPolicy).where(PdPolicy.is_current.is_(True)).limit(1)
    )
    policy = result.scalar_one_or_none()
    return policy.version if policy else None
```

`select` и `PdPolicy` уже импортированы в conftest.py.

---

## Шаг 3 (P1): Обновить фикстуры в 17 тестовых файлах

**Паттерн замены** — одинаковый для всех файлов.

### Что менять

В каждом файле найди фикстуры, создающие `User(...)` напрямую (без `pd_consent_version`). Заменить по следующему шаблону:

**БЫЛО:**
```python
@pytest_asyncio.fixture()
async def owner_user(db_session: AsyncSession) -> tuple[User, str]:
    password = secrets.token_urlsafe(16)
    user = User(
        email="owner@example.com",
        password_hash=hash_password(password),
        full_name="Owner",
        role=UserRole.OWNER,
        is_active=True,
    )
    db_session.add(user)
    await db_session.flush()
    return user, password
```

**СТАЛО:**
```python
@pytest_asyncio.fixture()
async def owner_user(db_session: AsyncSession) -> tuple[User, str]:
    password = secrets.token_urlsafe(16)
    consent_version = await get_current_policy_version(db_session)
    user = User(
        email="owner@example.com",
        password_hash=hash_password(password),
        full_name="Owner",
        role=UserRole.OWNER,
        is_active=True,
        pd_consent_version=consent_version,
        pd_consent_at=datetime.now(UTC) if consent_version else None,
    )
    db_session.add(user)
    await db_session.flush()
    return user, password
```

### Добавить импорты в каждый изменяемый файл

Если в файле ещё нет этих импортов — добавить:
```python
from datetime import UTC, datetime
from conftest import get_current_policy_version
```

Если `datetime` уже импортирован из другого места — не дублировать, только добавить `UTC` если его нет.

### Список файлов для правки (17 штук)

Правь только блоки `User(...)` в фикстурах без `pd_consent_version`. Не трогай тесты, которые намеренно тестируют сценарий с отсутствующим consent (например, `test_pr2_rbac_integration.py` строки 230-231, 278 — там `pd_consent_version = None` проставляется явно для негативных тестов).

| Файл | Фикстуры для правки |
|---|---|
| `tests/test_contractors.py` | `owner_user`, `accountant_user`, `cm_user`, `ro_user` |
| `tests/test_contracts.py` | `owner_user`, `accountant_user`, `cm_user`, `ro_user` |
| `tests/test_budget_categories.py` | `owner_user`, `accountant_user`, `cm_user`, `ro_user` |
| `tests/test_budget_plans.py` | `owner_user`, `accountant_user`, `cm_user`, `ro_user` |
| `tests/test_houses.py` | `owner_user`, `accountant_user`, `cm_user`, `ro_user` |
| `tests/test_projects.py` | `owner_user`, `accountant_user`, `cm_user`, `ro_user` |
| `tests/test_payments.py` | `owner_user` (и другие пользовательские фикстуры) |
| `tests/test_stages.py` | `owner_user`, `cm_user` |
| `tests/test_house_types.py` | `owner_user`, `cm_user` |
| `tests/test_material_purchases.py` | `owner_user`, `accountant_user`, `cm_user`, `ro_user` |
| `tests/test_option_catalog.py` | `owner_user`, `cm_user` |
| `tests/test_company_scope.py` | `owner_user` и другие inline User() создания |
| `tests/test_batch_a_coverage.py` | `_make_user` helper внутри файла |
| `tests/api/test_permissions_api.py` | `user` фикстура |
| `tests/api/test_roles_api.py` | `user` фикстура |
| `tests/api/test_user_roles_api.py` | `_create_user` helper, `user` фикстура |
| `tests/repositories/test_user_company_role_repository.py` | user фикстуры |
| `tests/repositories/test_user_repository.py` | user фикстуры |

**Внимание по `test_company_scope.py`:** строки 307, 362 — inline `User(...)` вне фикстур, внутри тестовых функций. Тоже нужно добавить `pd_consent_version`.

**Внимание по `test_pr2_rbac_integration.py`:** этот файл НЕ в списке правки для consent. Строки 399, 484, 576 и другие — там уже есть правильные `pd_consent_version` проставки или намеренные негативные тесты. Не трогать.

---

## Шаг 4: Верификация

```bash
cd /root/coordinata56/backend && pytest --tb=short -q 2>&1 | tail -30
```

Ожидаемый результат: 0 коллекционных ошибок, значительно меньше FAIL (должны остаться только реальные бизнес-логические падения, если они есть).

Если всё зелёно — запусти `ruff check app/api/contracts.py` и убедись что 0 ошибок.

---

## Ограничения

- Не коммитить — сдать backend-head на ревью
- Править ТОЛЬКО файлы из списка выше
- `FILES_ALLOWED`:
  - `backend/app/api/contracts.py`
  - `backend/conftest.py`
  - все 17+ тестовых файлов из таблицы выше
- `FILES_FORBIDDEN`: всё остальное (production-код кроме contracts.py, middleware, миграции)

---

## Самопроверка перед сдачей

- [ ] `python -c "from app.api.contracts import router"` — нет ошибок
- [ ] `pytest tests/test_health.py --tb=short -q` — нет `NameError`
- [ ] `pytest --tb=no -q 2>&1 | tail -5` — нет `errors during collection`
- [ ] `ruff check app/api/contracts.py` — 0 ошибок
- [ ] В тестах с намеренным `pd_consent_version = None` (test_pr2_rbac_integration.py) — ничего не сломалось
- [ ] Отчёт ≤200 слов: что изменил, сколько файлов, результат прогона

---

## Эталонный пример (уже правильно реализован)

Смотри `tests/test_auth.py` строки 100–136 — там `_get_current_policy_version` и правильная простановка `pd_consent_version` в фикстуре `owner_user`. Это точный образец для копирования паттерна.
