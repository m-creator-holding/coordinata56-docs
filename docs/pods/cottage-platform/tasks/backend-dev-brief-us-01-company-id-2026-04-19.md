# Дев-бриф US-01 — company_id на всех сущностях cottage-platform

- **Дата:** 2026-04-19
- **Автор:** backend-director (через backend-head при распределении)
- **Получатель:** backend-dev-1 (код) + db-engineer (миграция) — через `db-head` и `backend-head` соответственно
- **Фаза:** M-OS-1.1A, Sprint 1 (нед. 1–2), первая US в критическом пути
- **Приоритет:** P0 — блокер US-02 и US-03 (обе ждут company_id FK и сервисных условий)
- **Оценка:** L — 5 рабочих дней (db-engineer 1.5 дня миграция + 1 день бэкфилл-скрипт и round-trip; backend-dev-1 2.5 дня сервисный рефакторинг и тесты)
- **Scope-vs-ADR:** verified (ADR 0004 слоёв, ADR 0011 §1.3 multi-company, ADR 0013 safe-migration); gaps: none
- **Источник формулировки:** `docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md` §Sprint 1 / US-01

---

## Контекст

ADR 0011 §1.3 требует: «каждый объект холдингового слоя несёт `company_id`, фильтрация выполняется через `CompanyScopedService._scoped_query_conditions`». На момент 2026-04-19 в коде есть `company_id` только на `Project`, `Contract` и `UserCompanyRole`. Остальные доменные таблицы (`budgets`, `stages`, `materials`, `houses`, `house_configurations`, `house_stage_histories`, `contractors`, `payments`, `house_types`, `option_catalog`, `house_type_option_compat`, `budget_categories`, `budget_plans`) — flat. Это означает, что при добавлении второго юрлица (ООО «АЗС») бухгалтер АЗС физически увидит платежи «Координаты 56».

Задача — закрыть гап: добавить колонку `company_id NOT NULL FK companies.id` на все доменные таблицы, реализовать safe-migration (ADR 0013), отрефакторить сервисы на `CompanyScopedService`, сохранить 351 существующий тест зелёным.

Существующие фундаменты, на которые опираемся:
- `backend/app/services/company_scoped.py` — `UserContext` и `_scoped_query_conditions` уже есть.
- `backend/app/services/base.py` — `BaseService` уже есть.
- `backend/app/repositories/base.py` — `BaseRepository.list_with_total` поддерживает `extra_conditions=`.
- Seed-миграция `2026_04_17_0900_multi_company_foundation.py` уже создала компанию с id=1 (holding default).

---

## Что конкретно сделать

### 1. Список таблиц под миграцию (инвентаризация)

Обязательные к добавлению `company_id` — доменные таблицы cottage-platform:

| Файл модели | Таблица | Текущий statename | Примечание |
|---|---|---|---|
| `backend/app/models/budget.py` | `budget_categories` | flat | ORM-класс `BudgetCategory` |
| `backend/app/models/budget.py` | `budget_plans` | flat | ORM-класс `BudgetPlan` |
| `backend/app/models/stage.py` | `stages` | flat | справочник этапов стройки |
| `backend/app/models/material.py` | `material_purchases` | flat | `MaterialPurchase` |
| `backend/app/models/house.py` | `house_types` | flat | справочник типов |
| `backend/app/models/house.py` | `option_catalog` | flat | справочник опций |
| `backend/app/models/house.py` | `house_type_option_compat` | flat | связка типов и опций (наследует company_id от house_type через бэкфилл, но колонка нужна своя) |
| `backend/app/models/house.py` | `houses` | flat | основной объект |
| `backend/app/models/house.py` | `house_configurations` | flat | |
| `backend/app/models/house.py` | `house_stage_histories` | flat | история этапов дома |
| `backend/app/models/contract.py` | `contractors` | flat | |
| `backend/app/models/contract.py` | `payments` | flat | |

Итого — **12 доменных таблиц** (в декомпозиции указано «16» — это оценка с запасом; реальное число установили инвентаризацией). Если по ходу работы обнаружатся ещё доменные таблицы, не попавшие в список — **стоп, эскалация backend-head**.

Не добавлять `company_id` в:
- `audit_log`, `permissions`, `roles`, `role_permissions`, `users`, `pd_policy`, `companies`, `user_company_roles` — это кросс-холдинговые справочники, у них либо `actor_user_id`, либо связь идёт через `UserCompanyRole`.

### 2. Миграция Alembic — safe-pattern

Одна миграция `2026_04_19_XXXX_us01_add_company_id.py` (или, если объём большой — разбить на 2-3 файла по логическим группам: houses/budgets/materials), три шага по ADR 0013 «safe-migration pattern»:

**Шаг 1. Expand — добавить nullable колонку + FK:**
```python
# migration-exception: op_execute — backfill существующих записей company_id=1
for tbl in ("budget_categories", "budget_plans", "stages", "material_purchases",
            "house_types", "option_catalog", "house_type_option_compat",
            "houses", "house_configurations", "house_stage_histories",
            "contractors", "payments"):
    op.add_column(tbl, sa.Column("company_id", sa.Integer(), nullable=True))
    op.create_foreign_key(
        f"fk_{tbl}_company_id", tbl, "companies",
        ["company_id"], ["id"], ondelete="RESTRICT",
    )
    op.create_index(f"ix_{tbl}_company_id", tbl, ["company_id"])
```

**Шаг 2. Backfill — проставить company_id=1 на всех существующих записях:**
```python
# migration-exception: op_execute — бэкфилл ADR 0011 §1.3 miss pattern
for tbl in (...):
    op.execute(f"UPDATE {tbl} SET company_id = 1 WHERE company_id IS NULL")
```

**Шаг 3. Contract — NOT NULL:**
```python
for tbl in (...):
    op.alter_column(tbl, "company_id", nullable=False)
```

Все три шага — в одной транзакции одной миграции (backfill маленький, в одну транзакцию уместится). Если ревью db-head скажет, что таблица `houses` на проде будет >10k записей и transaction-locks опасны — разбить на 2 миграции и batch-update, но для dev-baseline (≤100 записей) одна миграция приемлема.

**Downgrade:** симметрично — убрать FK → убрать индекс → убрать колонку.

**Обязательно перед сдачей:**
- `cd backend && python -m tools.lint_migrations alembic/versions/2026_04_19_*` — зелёный
- `cd backend && alembic upgrade head && alembic downgrade -1 && alembic upgrade head` — зелёный

### 3. Рефакторинг моделей

Для каждой из 12 моделей добавить:

```python
from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

class House(Base, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "houses"
    ...
    company_id: Mapped[int] = mapped_column(
        ForeignKey("companies.id", ondelete="RESTRICT"), nullable=False, index=True
    )
```

### 4. Рефакторинг сервисов на `CompanyScopedService`

**Эталон:** `ContractService` или `ProjectService` (уже рефакторнуты в ADR 0011). Следовать их паттерну.

Сервисы к рефакторингу (12 шт.):
- `BudgetCategoryService`, `BudgetPlanService`
- `StageService`
- `MaterialPurchaseService`
- `HouseTypeService`, `OptionCatalogService`, `HouseService`
- `ContractorService`, `PaymentService`

Каждый сервис:
1. Наследует `CompanyScopedService[Model, Repo]` вместо `BaseService`.
2. В методах `list`, `get`, `update`, `delete` пробрасывает `extra_conditions=await self._scoped_query_conditions(user_context)` в репозиторий.
3. В методе `create` явно проставляет `company_id=user_context.company_id` в создаваемый объект.
4. **Holding-owner bypass:** `_scoped_query_conditions` уже возвращает `[]` при `is_holding_owner=True` — ничего дополнительно не делаем.

### 5. Рефакторинг API-роутеров

Все роутеры, вызывающие эти 12 сервисов, должны:
1. В `Depends(...)` использовать `require_permission(action, resource_type)` или как минимум `get_current_user` — получить `UserContext`.
2. Передавать `user_context=ctx` в метод сервиса.

**Пример:**
```python
@router.get("/houses")
async def list_houses(
    pair: tuple[User, UserContext] = Depends(require_permission("read", "house")),
    service: HouseService = Depends(get_house_service),
) -> PaginatedResponse[HouseRead]:
    _, ctx = pair
    return await service.list(user_context=ctx, offset=0, limit=50)
```

### 6. Тесты

Добавить:

1. **`backend/tests/test_multi_company_isolation.py`** — параметризованный тест на 12 таблиц:
   - Фикстура: два `Company` (id=1 «Координата 56», id=2 «АЗС»), по одному user с `accountant` в каждой, один holding-owner.
   - Параметризация по `resource_type` → эндпоинт.
   - Сценарии (на каждую сущность):
     - user компании A делает GET list → получает только записи компании A.
     - user компании A делает GET `/{resource}/{id_компании_B}` → 404 (не 403, anti-enumeration — см. CLAUDE.md раздел «API»).
     - user компании A делает POST create без X-Company-ID header (единственная компания) → company_id автоматически = 1 (из UserContext).
     - holding-owner (is_holding_owner=True) с X-Company-ID=2 → видит записи компании 2.
     - holding-owner без X-Company-ID → видит записи всех компаний (bypass).

2. **Существующие 351 тест должны остаться зелёными.** Если какой-то тест упал — разобрать почему, не «подшивать» обходом. Скорее всего, причина — фикстуры, не создающие `company_id`, — починить фикстуры, не ломать логику.

### 7. Самопроверка (перед сдачей backend-head)

- [ ] Прочитан `/root/coordinata56/CLAUDE.md` (секции «Данные и БД», «API», «Код») и `departments/backend.md` (включая ADR-gate A.1–A.5)
- [ ] Прочитан ADR 0011 §1.3 и ADR 0013 §«safe-migration pattern»
- [ ] Выполнен ADR-gate из `departments/backend.md`:
  - A.1 литералы — в фикстурах паролей нет (random secrets), в коде ничего не добавлено
  - A.2 SQL только через репозиторий; `_scoped_query_conditions` возвращает `ColumnElement[bool]` (паттерн из `CompanyScopedService`)
  - A.3 write-эндпоинты имеют `require_permission` с `user_context`
  - A.4 ошибки — ADR 0005, пагинация — ADR 0006 (не трогать, уже работает)
  - A.5 write-операции пишут audit (уже работает, проверить что не сломали)
- [ ] `cd backend && pytest` — зелёный (ориентир: 351 + 12*5 новых = ≈410 тестов)
- [ ] `cd backend && ruff check app tests` — 0 ошибок
- [ ] `cd backend && mypy app` — нет новых ошибок относительно baseline
- [ ] `cd backend && python -m tools.lint_migrations alembic/versions/` — зелёный
- [ ] `cd backend && alembic upgrade head && alembic downgrade -1 && alembic upgrade head` — зелёный
- [ ] `git status` — только файлы из FILES_ALLOWED
- [ ] Не коммитить — коммитит Координатор

---

## DoD

1. 12 доменных таблиц имеют `company_id NOT NULL FK companies.id` с индексом.
2. Alembic миграция проходит round-trip (upgrade → downgrade → upgrade).
3. 12 сервисов переведены на `CompanyScopedService`, используют `_scoped_query_conditions`.
4. Все API-роутеры этих 12 сущностей получают `UserContext` через `Depends(get_current_user)` или `Depends(require_permission(...))` и пробрасывают его в сервис.
5. Существующие 351 тест зелёные.
6. Новый параметризованный тест `test_multi_company_isolation.py` покрывает ≥60 сценариев (12 сущностей × 5 сценариев), все зелёные.
7. `ruff`, `mypy`, `lint-migrations`, `round-trip` — все зелёные.
8. Отчёт backend-head с ключевыми цифрами и артефактами.

---

## FILES_ALLOWED

- `backend/alembic/versions/2026_04_19_*_us01_add_company_id*.py` — **создать** (1-3 файла)
- `backend/app/models/budget.py`, `material.py`, `stage.py`, `house.py`, `contract.py` — добавить `company_id`
- `backend/app/services/budget_categories.py`, `budget_plans.py`, `stages.py`, `material_purchases.py`, `house_types.py`, `option_catalog.py`, `houses.py`, `contractors.py`, `payments.py` — рефакторинг на `CompanyScopedService`
- `backend/app/api/budget_categories.py`, `budget_plans.py`, `stages.py`, `material_purchases.py`, `house_types.py`, `option_catalog.py`, `houses.py`, `contractors.py`, `payments.py` — пробрасывание `UserContext`
- `backend/tests/test_multi_company_isolation.py` — **создать**
- `backend/tests/conftest.py` или отдельные conftest-ы tests/ — минимальная правка фикстур для `company_id` (если требуется)
- `backend/tests/test_*.py` (существующие) — правки фикстур, **но не логики**, при падении из-за отсутствующего `company_id`

## FILES_FORBIDDEN

- `backend/app/models/company.py`, `user.py`, `user_company_role.py`, `role.py`, `permission.py`, `role_permission.py`, `audit.py`, `pd_policy.py` — эти модели трогать **не надо** (они уже корректны или являются кросс-холдинговыми справочниками)
- `backend/app/services/company_scoped.py`, `base.py`, `rbac.py`, `audit.py` — ядро, менять нельзя (если нужна правка — стоп, эскалация backend-head → backend-director)
- `docs/adr/**` — ADR не трогать
- `frontend/**`, `docs/**` кроме этого брифа (отчёт пишется в отчётном сообщении, не в файле)
- `.github/workflows/**` — CI не менять
- `backend/app/api/deps.py` — уже корректен, не трогать

---

## Зависимости

- **Блокирует:** US-02 (JWT клеймы `company_ids` — нужен FK и модель для выборок), US-03 (`require_permission` по умолчанию требует `company_id` у ресурса для проверки).
- **Блокируется:** ничем — US-01 стартовая.

---

## COMMUNICATION_RULES

- Перед стартом — прочитать `/root/coordinata56/CLAUDE.md`, `/root/coordinata56/docs/agents/departments/backend.md`, ADR 0011 §1.3, ADR 0013 §«safe-migration pattern», `backend/app/services/company_scoped.py`, `backend/app/services/contract.py` как эталон.
- Если миграция падает на каком-то dev-бэкфилле (старые seed-данные не дают proof) — **стоп, эскалация backend-head → db-head**. Не решать «в лоб» через `ON DELETE CASCADE`.
- Если инвентаризация (§1) показывает >12 доменных таблиц — **стоп, эскалация backend-head**. Скорее всего, забыли таблицу из другого пода или не учли мигранты — нужно уточнить scope.
- Если какой-то из 351 существующих тестов падает по **логической** причине (не по фикстуре) — **стоп, эскалация backend-head**. Возможно, существующий тест сам содержит баг, который до ADR 0011 не срабатывал.
- Никаких сторонних зависимостей.

---

## Обязательно прочитать перед началом

1. `/root/coordinata56/CLAUDE.md` — секции «Данные и БД», «API», «Код», «Git»
2. `/root/coordinata56/docs/agents/departments/backend.md` — правила 1-10, ADR-gate A.1–A.5, «Правила для авторов миграций»
3. `/root/coordinata56/docs/adr/0011-foundation-multi-company-rbac-audit.md` — §1 «Multi-company» полностью
4. `/root/coordinata56/docs/adr/0013-migrations-evolution-contract.md` — safe-migration pattern
5. `/root/coordinata56/backend/app/services/company_scoped.py` — `UserContext`, `_scoped_query_conditions`
6. `/root/coordinata56/backend/app/services/contract.py` и `project.py` — эталон рефакторинга
7. Последний отчёт `/root/coordinata56/docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md` §US-01

---

## Отчёт (≤ 300 слов)

Структура:
1. **Миграция** — путь к файлу(ам), результат `round-trip`, результат `lint-migrations`, число новых колонок.
2. **Модели** — список изменённых моделей (12 шт.), diff-summary.
3. **Сервисы** — список переведённых на `CompanyScopedService`, примечания о нюансах.
4. **API** — список роутеров, пробрасывающих `UserContext`.
5. **Тесты** — число новых тестов в `test_multi_company_isolation.py`, результат `pytest`, число прежних упавших и причина починки фикстур.
6. **ADR-gate** — A.1/A.2/A.3/A.4/A.5 pass/fail + артефакты.
7. **Отклонения от scope** — если были (ожидается «нет»).
