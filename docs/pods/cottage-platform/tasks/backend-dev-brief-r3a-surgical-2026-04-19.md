# backend-dev-A brief — Sprint 1 regression R3A (surgical fixes)

**Wave:** Round 3 regression hotfix.
**Origin:** `docs/pods/cottage-platform/quality/sprint1-regression-report-round2-2026-04-19.md` (RED STOP).
**Director:** backend-director → Head: backend-head → Worker: backend-dev (label A).
**Pattern:** Pattern 5 fan-out (параллельно с Worker B, файлы не пересекаются).
**Model:** Opus recommended (3 независимых фикса + 6 file-copies).

---

## ПЕРЕД СТАРТОМ — ПРОЧТИ

1. `/root/coordinata56/CLAUDE.md`
2. `/root/coordinata56/docs/agents/departments/backend.md`
3. Этот бриф целиком.
4. Для BUG-008 — `docs/adr/0011-rbac-v2.md` §2.2 (action enum).

---

## Задача A1 — BUG-008 P1 (5 минут)

**Файл:** `backend/app/schemas/permission.py`
**Что:** `PermissionRead.action` и `PermissionCreate.action` имеют `Literal["read","write","approve","delete","admin"]`. Миграция `us03_rbac_defaults_seed` посеяла права с action `export`, `reject`. Pydantic ValidationError на GET /permissions.

**Fix:** расширить Literal до 7 actions (соответствует `PermissionAction` StrEnum из `backend/app/models/enums.py:6-24`):
```python
Literal["read", "write", "approve", "reject", "delete", "export", "admin"]
```

Применить одинаково в обоих местах (PermissionRead и PermissionCreate). Docstring обновить (перечисление 7 действий). Проверь: `backend/app/models/enums.py::PermissionAction` — это source of truth.

**Acceptance A1:** `pytest backend/tests/api/test_permissions_api.py -q` → 0 FAIL.

---

## Задача A2 — BUG-005 P1 scope P0 (15 минут)

**Файлы (6 шт.):**
- `backend/tests/test_budget_categories.py`
- `backend/tests/test_budget_plans.py`
- `backend/tests/test_contracts.py`
- `backend/tests/test_payments.py`
- `backend/tests/test_contractors.py`
- `backend/tests/test_material_purchases.py`

**Что:** все 6 файлов используют `os.environ.get` паттерн, но **fallback URL неверный**:
```python
TEST_DB_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+psycopg://postgres@localhost/test_coordinata56",  # ← неправильно: нет пароля, нет порта 5433, неверное имя БД
)
```

Эталон из passing-файла `backend/tests/test_houses.py:44-47` (и `test_projects.py:44-47`):
```python
TEST_DB_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+psycopg://coordinata:change_me_please_to_strong_password@localhost:5433/coordinata56_test",
)
```

**Fix:** в каждом из 6 файлов заменить только строку с fallback URL (2-я строка в `os.environ.get(...)`) на эталонную.

Ничего другого в этих файлах не трогать.

**Acceptance A2:** `pytest backend/tests/test_budget_categories.py backend/tests/test_budget_plans.py backend/tests/test_contracts.py backend/tests/test_payments.py backend/tests/test_contractors.py backend/tests/test_material_purchases.py -q 2>&1 | tail -3` → 0 ERROR (могут остаться FAIL из-за RBAC — это работа Worker B, не твоё).

---

## Задача A3 — BUG-002 P1 (2 минуты)

**Файл:** `backend/tests/integration/api/test_multi_company_isolation.py`
**Строка:** 220.
**Что:** `category=OptionCategory.FINISH` — такого значения в enum нет. `OptionCategory` имеет: CANOPY, INTERIOR, WELLNESS, LANDSCAPE, UTILITY, OTHER (`backend/app/models/enums.py:75-83`).

**Fix:** заменить `OptionCategory.FINISH` → `OptionCategory.INTERIOR` (семантически ближайшее — финишная отделка дома).

Других использований `FINISH` в репозитории не осталось (я проверил grep'ом).

**Acceptance A3:** `python -c "from backend.tests.integration.api.test_multi_company_isolation import *"` → без ImportError; `pytest backend/tests/integration/api/test_multi_company_isolation.py -q --collect-only 2>&1 | tail -3` → collection успешен.

---

## FILES_ALLOWED

Эксклюзивно (Worker B их не трогает):

- `backend/app/schemas/permission.py`
- `backend/tests/test_budget_categories.py`
- `backend/tests/test_budget_plans.py`
- `backend/tests/test_contracts.py`
- `backend/tests/test_payments.py`
- `backend/tests/test_contractors.py`
- `backend/tests/test_material_purchases.py`
- `backend/tests/integration/api/test_multi_company_isolation.py`

## FILES_FORBIDDEN

Всё остальное, в частности:
- `backend/app/api/**`, `backend/app/services/**`, `backend/app/repositories/**` — миграции и эндпоинты Round 3 НЕ трогаем.
- `backend/alembic/**` — миграции корректны.
- `backend/tests/test_projects.py`, `test_stages.py`, `test_house_types.py`, `test_houses.py`, `test_option_catalog.py`, `test_batch_a_coverage.py` — это Worker B.
- `backend/tests/api/test_permissions_api.py` — трогать ТОЛЬКО если тест падает после A1 из-за fixture, не из-за Literal (маловероятно). Если падает — эскалируй Head, не правь самовольно.

---

## COMMUNICATION_RULES (Pattern 5)

- Отчёт **только** backend-head, не backend-director напрямую.
- В отчёте: изменённые файлы (полный список с LOC), acceptance-команды + вывод, подтверждение ADR-gate (A.1-A.5 из чек-листа).
- Коммит **не** делаешь. `git status --short` в конце отчёта для Head.
- Не расширяй scope. Только 3 задачи выше.

---

## Чек-лист самопроверки (ADR-gate)

- [ ] **A.1:** literals в diff отсутствуют (визуально убедиться, что не добавлены новые).
- [ ] **A.2:** не применимо (SQL-слои не трогаются).
- [ ] **A.3:** не применимо (RBAC-декораторы не трогаются).
- [ ] **A.4:** не применимо (форматы ошибок не трогаются).
- [ ] **A.5:** не применимо (write-эндпоинты не трогаются).
- [ ] `ruff check backend/app/schemas/permission.py` → чисто.
- [ ] 3 acceptance-команды прошли зелёными.
- [ ] `git status --short` — только 8 файлов выше.

---

## Отчёт backend-head (≤200 слов)

- Что сделал (A1, A2, A3 — pass/fail на каждой).
- Список изменённых файлов с LOC.
- Acceptance-вывод (3 команды).
- ADR-gate self-check.
- Пометки «что удивило» (если что-то сломалось не по плану).
