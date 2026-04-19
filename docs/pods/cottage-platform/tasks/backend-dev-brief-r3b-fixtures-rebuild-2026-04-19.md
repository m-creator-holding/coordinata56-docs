# backend-dev-B brief — Sprint 1 regression R3B (fixtures rebuild)

**Wave:** Round 3 regression hotfix.
**Origin:** `docs/pods/cottage-platform/quality/sprint1-regression-report-round2-2026-04-19.md` (RED STOP).
**Director:** backend-director → Head: backend-head → Worker: backend-dev (label B).
**Pattern:** Pattern 5 fan-out (параллельно с Worker A, файлы не пересекаются).
**Model:** Opus **обязательно** (крупный fixture-rewiring, высокий риск пропуска).

---

## ПЕРЕД СТАРТОМ — ПРОЧТИ

1. `/root/coordinata56/CLAUDE.md`
2. `/root/coordinata56/docs/agents/departments/backend.md`
3. Этот бриф целиком.
4. `backend/alembic/versions/2026_04_19_1100_us01_add_company_id.py` — знай, какие модели требуют company_id.
5. `backend/alembic/versions/2026_04_19_1200_us03_rbac_owner_seed.py` — знай, почему owner без UCR получает 403.
6. `backend/tests/test_pr2_rbac_integration.py:178-210` — **эталонный паттерн** создания пользователя c UserCompanyRole.

---

## Контекст ошибок

После Round 2 остались 2 категории:

### Категория 1: BUG-001 (57 FAIL) — owner возвращает 403

Миграция `us03_rbac_owner_seed` (1200) добавила RBAC-модель, при которой права резолвятся через JOIN `users → user_company_roles → roles → role_permissions → permissions`. Fixtures в 5+ test-файлах создают объект `User(role=UserRole.OWNER)`, но **не создают** запись в `user_company_roles` — RBAC JOIN возвращает 0 прав → 403 на всех защищённых эндпоинтах.

### Категория 2: NotNullViolation company_id (103 ERROR) — fixtures ломаются на INSERT

Миграция `us01_add_company_id` (1100) добавила `company_id NOT NULL` на 10 таблиц: `budget_categories`, `budget_plan`, `stages`, `material_purchases`, `house_types`, `option_catalog`, `house_type_option_compat`, `houses`, `house_configurations`, `house_stage_history`. Fixtures в 5 файлах создают объекты **без** `company_id=...` — SQLAlchemy INSERT падает NotNullViolation до исполнения самого теста.

---

## Что нужно сделать

### B1 — Добавить UserCompanyRole ко всем user-fixtures (BUG-001)

**В каждом** из 6 файлов ниже для **всех** user-fixtures (owner_user, read_only_user, accountant_user, construction_manager_user — если есть в файле) сразу после `await db_session.flush()` добавить создание `UserCompanyRole`:

**Эталон (из `test_pr2_rbac_integration.py:202-208`):**
```python
from app.models.user_company_role import UserCompanyRole  # импорт сверху

# ... внутри fixture, после db_session.add(user); await db_session.flush():
ucr = UserCompanyRole(
    user_id=user.id,
    company_id=1,  # default dev-компания (seeded by multi_company_foundation migration)
    role_template=UserRole.<OWNER|READ_ONLY|ACCOUNTANT|CONSTRUCTION_MANAGER>,
)
db_session.add(ucr)
await db_session.flush()
```

**Critical:** `role_template` должен **совпадать** с `user.role`. Используй тот же enum-member, который в fixture уже указан.

### B2 — Добавить company_id ко всем object-fixtures (NotNullViolation)

Моделям ниже нужен `company_id=1` в конструкторе:
- `Stage` (`test_stages.py`, `test_houses.py` если есть)
- `HouseType` (`test_house_types.py`, `test_houses.py`, `test_batch_a_coverage.py`)
- `OptionCatalog` (`test_option_catalog.py`, `test_house_types.py`, `test_houses.py`, `test_batch_a_coverage.py`)
- `House` (`test_houses.py`, `test_batch_a_coverage.py`)
- `HouseTypeOptionCompat` (если создаётся в fixture — редко)
- `HouseConfiguration`, `HouseStageHistory` (если создаются в fixtures)
- `BudgetCategory`, `BudgetPlan`, `MaterialPurchase` (**не в этих 6 файлах**, это Worker A territory для BUG-005; если увидишь — НЕ трогай)

**Project уже имеет company_id=1** в `test_houses.py:195` и `test_batch_a_coverage.py:150` — ок, ничего не меняй.

**Метод поиска:** в каждом файле `grep -n "= Stage(\|= HouseType(\|= OptionCatalog(\|= House(\|= HouseConfiguration(\|= HouseStageHistory(\|= HouseTypeOptionCompat("` — найди все конструкторы, добавь `company_id=1` первым аргументом (до code/name).

### B3 — Проверка RBAC действительно резолвится

После B1+B2 прогони подмножество:
```
pytest backend/tests/test_projects.py backend/tests/test_stages.py backend/tests/test_house_types.py backend/tests/test_houses.py backend/tests/test_option_catalog.py backend/tests/test_batch_a_coverage.py -q 2>&1 | tail -10
```

Ожидание: 0 ERROR и 0 FAIL с сообщением «403 Forbidden» и 0 FAIL с «NotNullViolation».

Если owner всё ещё 403 — проверь, что `role_template` enum **value** ("owner"), а не имя атрибута (OWNER). В модели `UserCompanyRole` используется `values_callable`, и семплы в миграции 1200 вставляют именно .value. Эталон из `test_pr2_rbac_integration.py` правильный — просто повторяй.

---

## FILES_ALLOWED

Эксклюзивно (Worker A их не трогает):

- `backend/tests/test_projects.py`
- `backend/tests/test_stages.py`
- `backend/tests/test_house_types.py`
- `backend/tests/test_houses.py`
- `backend/tests/test_option_catalog.py`
- `backend/tests/test_batch_a_coverage.py`

## FILES_FORBIDDEN

Всё остальное, в частности:
- `backend/app/**` (миграции и эндпоинты не трогаем).
- `backend/alembic/**` (миграции корректны).
- 6 тестов Worker A (BUG-005) — даже если соблазнительно.
- `backend/tests/integration/api/test_multi_company_isolation.py` — Worker A.
- `backend/app/schemas/permission.py` — Worker A.

---

## COMMUNICATION_RULES (Pattern 5)

- Отчёт **только** backend-head.
- Если обнаруживаешь, что fixture создаёт модель, которой нет в списке B2, но она тоже в `_TABLES` миграции us01 (см. docstring миграции, 10 таблиц) — добавь `company_id=1` и **пометь** в отчёте. Это ожидаемое расширение scope в рамках NotNullViolation fix, не нарушение.
- Если тесты после твоего fix падают по новой причине (например, RBAC permissions не хватает для `construction_manager` на конкретном эндпоинте) — это **не твой баг**, это дефект матрицы RBAC v2. Отметь в отчёте как «open: RBAC матрица для role X на resource Y» и продолжай дальше, не правь матрицу.
- Коммит **не** делаешь. `git status --short` в конце отчёта.

---

## Чек-лист самопроверки (ADR-gate + локальный)

- [ ] **A.1:** новых литералов секретов не добавлено (пароли через `secrets.token_urlsafe` — уже есть).
- [ ] **A.2:** не применимо.
- [ ] **A.3:** не применимо (тест-уровень, RBAC-декораторы не трогаются).
- [ ] **A.4:** не применимо.
- [ ] **A.5:** не применимо.
- [ ] Во всех 6 файлах все user-fixtures теперь создают UserCompanyRole (owner, read_only, accountant, cm — где есть).
- [ ] Во всех 6 файлах все object-fixtures моделей из B2 имеют company_id=1.
- [ ] `ruff check backend/tests` → чисто на 6 файлах.
- [ ] Pytest subset (6 файлов) зелёный: 0 ERROR, 0 FAIL с 403.
- [ ] `git status --short` — только 6 файлов выше.

---

## Отчёт backend-head (≤200 слов)

- Что сделал: B1 — сколько user-fixtures обогатил UCR; B2 — сколько object-fixtures дополнил company_id.
- Список изменённых файлов с LOC.
- Acceptance-вывод B3 pytest.
- Если были новые баги — список «open».
- ADR-gate self-check.
- `git status --short`.

---

## Красные флаги — сразу эскалировать Head

- Если в файле > 1 UserCompanyRole одного (user_id, company_id, role_template) — сработает uq_user_company_role_pod unique-constraint. Создавай **одну** запись на user, пересекающихся ролей у одного теста не должно быть.
- Если после B1 owner всё ещё 403 на `GET /api/v1/projects` — возможно, RBAC cache в `rbac_service` кеширует старый результат между тестами. Эскалируй, не чини.
- Если NotNullViolation остаётся после B2 на таблице, которой нет в списке B2 — запиши название таблицы в отчёт и эскалируй.
