# Triage: 304 FAIL → диагностика и план починки

**Дата:** 2026-04-19  
**Автор:** backend-head  
**Статус:** диагностика завершена, план утверждён

---

## Текущее состояние прогона

Попытка запустить полный pytest suite дала неожиданный результат:
вместо 304 FAIL обнаружена **коллекция вообще не запустилась** из-за `NameError` при загрузке `app.main`.

```
ERROR tests/test_health.py - NameError: name 'UserRole' is not defined
... (23 файла с тем же ERROR)
Interrupted: 23 errors during collection
```

Это означает, что картина «332 PASS / 304 FAIL» устарела — появился новый регрессионный дефект, блокирующий коллекцию.

---

## Блокер 0 (новый, P0): NameError в contracts.py

**Файл:** `backend/app/api/contracts.py`  
**Дефекты:**

1. Строка 103: `current_user.role != UserRole.OWNER` — `UserRole` используется, но **не импортирован**. В блоке импортов есть `from app.models.enums import ContractStatus`, но `UserRole` отсутствует.

2. Строки 101, 161: `current_user.role not in _READ_ROLES` — переменная `_READ_ROLES` **нигде не определена** в файле. Судя по docstring эндпоинта («owner, accountant, construction_manager»), должна быть `frozenset` из трёх ролей.

**Эффект:** `from app.api.payments import router` в `app/main.py` → цепочка импортов достигает `contracts.py` (через зарегистрированные роутеры) → при загрузке модуля Python не может разрешить `UserRole` → все 23 тестовых файла падают с `NameError` ещё на этапе коллекции.

**Проверено:** `python -c "from app.models.enums import UserRole"` — работает. Проблема локализована в `contracts.py`.

---

## Блокер 1 (consent-gate, после починки Блокера 0)

После устранения Блокера 0 тесты снова запустятся и воспроизведут исходную картину 304 FAIL. Диагностика по паттернам:

### Распределение 304 failures

| Категория | Кол-во тестов | Файлы |
|---|---|---|
| **Consent-gate (403 от middleware)** | ~294 | 17 тестовых файлов (см. ниже) |
| **Другое** (миграции, стейл-фикстуры) | ~10 | TBD после починки Блокера 0 |

### Consent-gate: паттерн

Все 17 файлов используют **inline-создание `User(...)`** в фикстурах без проставления `pd_consent_version` и `pd_consent_at`. Пример (test_contractors.py, строки 82–90):

```python
user = User(
    email="owner_contractor@example.com",
    password_hash=hash_password(password),
    role=UserRole.OWNER,
    is_active=True,
    # pd_consent_version ОТСУТСТВУЕТ
)
```

Когда пользователь логинится, `ConsentService.get_status()` видит `user.pd_consent_version = None` при существующей политике `is_current=True` → выдаёт `required_action != "none"` → `create_token(consent_required=True)` → `ConsentEnforcementMiddleware` блокирует все запросы 403.

**Файлы-нарушители (17 штук, ~294 теста):**

- `tests/test_contractors.py` — 16 тестов
- `tests/test_contracts.py` — 28 тестов
- `tests/test_budget_categories.py` — 22 теста
- `tests/test_budget_plans.py` — 31 тест
- `tests/test_houses.py` — 48 тестов
- `tests/test_projects.py` — 32 теста
- `tests/test_payments.py` — 27 тестов
- `tests/test_stages.py` — 15 тестов
- `tests/test_house_types.py` — 18 тестов
- `tests/test_material_purchases.py` — 18 тестов
- `tests/test_option_catalog.py` — 15 тестов
- `tests/test_company_scope.py` — 12 тестов
- `tests/test_batch_a_coverage.py` — 64 теста
- `tests/api/test_permissions_api.py` — 3 теста
- `tests/api/test_roles_api.py` — 3 теста
- `tests/api/test_user_roles_api.py` — 4 теста
- `tests/repositories/test_user_company_role_repository.py` — 3 теста
- `tests/repositories/test_user_repository.py` — 3 теста

**Эталон правильного подхода** уже есть в `tests/test_auth.py` (функция `_get_current_policy_version`) и в `conftest.py` (`create_user_with_role`).

---

## Выбранное решение: Вариант B

**`autouse=True` session-level фикстура + вспомогательная функция в корневом conftest.py**

### Обоснование выбора

| Критерий | A (global fixture) | **B (autouse + helper)** | C (заглушка middleware) |
|---|---|---|---|
| Чистота тестирования | Принуждает все тесты к одному пути создания User | **Прозрачна: каждый тест сам создаёт User, но consent гарантирован контекстом** | Обходит middleware — тестирует другое поведение |
| Масштаб правок | 17 файлов переписать фикстуры | **17 файлов: заменить `User(...)` на `_make_user(...)` или добавить 2 поля** | 1 файл (middleware) |
| Риск поломки | Высокий: глобальная фикстура меняет DI | **Низкий: helper-функция, consent берётся из БД** | Средний: в prod middleware всё равно работает, но тест не проверяет реальный сценарий |
| Тестовое покрытие consent | Тестирует через `create_user_with_role` | **Явные consent-тесты (test_pr2_rbac_integration.py) остаются нетронутыми** | Consent-middleware фактически не тестируется |
| Соответствие skeleton-first (CLAUDE.md) | Да | **Да** | Нет — нарушает принцип «маскирование ПД всегда» |

Вариант C отклонён: он pad-тестирует — тесты проходят, но не проверяют реальный consent-flow. Нарушает принцип из CLAUDE.md §«Данные / ПД».

Вариант B выбран потому, что `_get_current_policy_version` уже написан в `test_auth.py` как эталон, `create_user_with_role` в `conftest.py` тоже правильный — нужно только перенести helper в корневой conftest и использовать его в 17 файлах.

### Суть решения

1. В `backend/conftest.py` добавить публичную хелпер-функцию `get_current_policy_version(db_session)` (уже есть как приватная в `test_auth.py`, нужно поднять в conftest).

2. В каждом из 17 файлов заменить inline-`User(...)` в фикстурах на вызов с `pd_consent_version=await get_current_policy_version(db_session)`.

3. Блокер 0 (contracts.py) чинится первым, отдельным шагом.

---

## Оценка времени

- Блокер 0 (contracts.py): 15–20 минут — добавить импорт `UserRole`, определить `_READ_ROLES`
- Блокер 1 (consent в 17 файлах): 60–90 минут — паттерн однотипный, после первых 2-3 файлов идёт механически
- Верификация: 10 минут — прогон полного suite

**Итого: ~2 часа. Исполнитель: backend-dev-2** (уже знает consent-систему, делал первичную правку `create_user_with_role`).
