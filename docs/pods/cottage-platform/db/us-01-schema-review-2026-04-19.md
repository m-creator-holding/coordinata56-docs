# DB Schema Review — US-01: company_id на 12 таблицах

- **Дата ревью:** 2026-04-19
- **Ревьюер:** db-engineer
- **Файл миграции:** `backend/alembic/versions/2026_04_19_1100_us01_add_company_id.py`
- **Статус:** БЛОКЕР (3 дефекта P1) + рекомендации P2

---

## 1. Дефекты (требуют исправления до слияния)

### P1-1 — Несовпадение имён таблиц: `budget_plan` vs `budget_plans` и `house_stage_history` vs `house_stage_histories`

**Место:** `_TABLES` в `us01_add_company_id.py`, строки 44–55.

Бриф указывает таблицы `budget_plans` и `house_stage_histories` (множественное число). ORM-класс `BudgetPlan` привязан к `__tablename__ = "budget_plan"` (единственное число), `HouseStageHistory` — к `"house_stage_history"` (единственное число). Миграция использует имена `budget_plan` и `house_stage_history`, но в шапке документации написано `budget_plan` и `house_stage_history` — это правильно. **Однако** бриф в разделе «Список таблиц» перечисляет `budget_plans` и `house_stage_histories`. Необходимо сверить с реальным `\d` из `psql` перед запуском round-trip: если initial_schema создавала таблицы с другим именем, миграция упадёт с `relation does not exist`.

**Рекомендация:** перед round-trip выполнить `SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY 1` и сверить точные имена. Исправить `_TABLES` под фактическую схему.

### P1-2 — Таблицы `contractors` и `payments` уже имеют `company_id` — двойное добавление

**Место:** `_TABLES` включает `contractors` и `payments` — нет, миграция их **не** включает. Это правильно: комментарий в шапке файла подтверждает, что `contractors`, `contracts`, `payments` уже получили `company_id` в `f7e8d9c0b1a2`. ORM-модели `Contractor` и `Payment` это подтверждают.

**Статус: P1-2 снимается.** Миграция `_TABLES` корректно не включает эти таблицы. **Но** бриф в разделе «Список таблиц» всё равно указывает `contractors` и `payments` в списке 12 таблиц — это противоречие в брифе. В итоге под миграцию US-01 фактически попадают **10 таблиц**, а не 12. Это нужно отразить в отчёте backend-head.

### P1-3 — Уникальные индексы не обновлены под multi-tenant семантику

**Место:** следующие существующие уникальные индексы не включают `company_id`:

| Индекс | Таблица | Проблема |
|---|---|---|
| `code` UNIQUE на `HouseType` (строка 19 `house.py`) | `house_types` | Разные компании не смогут иметь одинаковый код типа дома |
| `code` UNIQUE на `OptionCatalog` (строка 33 `house.py`) | `option_catalog` | То же — один каталог опций на все компании |
| `code` UNIQUE на `BudgetCategory` (строка 16 `budget.py`) | `budget_categories` | Статьи бюджета не могут повторяться между компаниями |
| `code` UNIQUE на `Stage` (строка 21 `stage.py`) | `stages` | Стадии стройки — глобальный справочник или per-company? |
| `uq_contracts_contractor_id_number_active` на `contracts` | `contracts` | Номер договора уникален у подрядчика, но не учитывает разные компании |
| `uq_houses_project_id_plot_number` на `houses` | `houses` | Нормально — project_id уже несёт company_id через FK |

**Для `code`-индексов справочных таблиц** (`house_types`, `option_catalog`, `budget_categories`, `stages`) принципиальный вопрос: это **холдинговые справочники** (один кодификатор на все юрлица) или **per-company** (каждая компания ведёт свой каталог)?

- Если **холдинговые** — `company_id` на них семантически неверен, и ADR 0011 §1.3 сам по себе под вопросом для этих таблиц. Нужна эскалация к architect.
- Если **per-company** — уникальность `code` нужно переделать на `(company_id, code)` через partial UNIQUE `WHERE deleted_at IS NULL`. Текущий глобальный UNIQUE на `code` станет ошибкой после добавления второй компании.

**Рекомендация backend-dev-1:** не приступать к рефакторингу сервисов для `HouseTypeService`, `OptionCatalogService`, `StageService`, `BudgetCategoryService` до решения этого вопроса. Эскалация к architect или backend-director.

---

## 2. Рекомендации по индексам (таблица)

| Таблица | Минимальный индекс (уже в миграции) | Дополнительный (рекомендован) | Обоснование |
|---|---|---|---|
| `houses` | `ix_houses_company_id` | `(company_id, project_id)` составной | JOIN в `HouseService.list` всегда `company_id AND project_id` |
| `budget_plan` | `ix_budget_plan_company_id` | `(company_id, project_id, category_id)` | Типовой запрос выборки плана по проекту + статье |
| `material_purchases` | `ix_material_purchases_company_id` | `(company_id, project_id, purchased_at DESC)` | Сортировка по дате при выборке закупок проекта |
| `payments` | уже есть `ix_payments_company_id` | `(company_id, contract_id)` составной | Список платежей по договору — критичный путь |
| `house_configurations` | `ix_house_configurations_company_id` | нет дополнительных | Доступ всегда через `house_id`, company_id вторичен |
| `house_stage_history` | `ix_house_stage_history_company_id` | нет дополнительных | Узкий запрос по `house_id` |
| `contractors` | уже есть `ix_contractors_company_id` | нет дополнительных | Уже достаточно |
| `stages`, `house_types`, `option_catalog`, `budget_categories` | `ix_<tbl>_company_id` | нет — если справочники глобальные, индекс не нужен вовсе | Решение зависит от ответа на P1-3 |
| `house_type_option_compat` | `ix_house_type_option_compat_company_id` | нет дополнительных | Связующая таблица, доступ через PK-пару |

---

## 3. Уникальные ограничения — что нужно пересмотреть

После добавления `company_id` ряд `unique=True` на одиночных колонках становится неверным для multi-tenant:

1. `stages.code unique=True` — если per-company, заменить на partial UNIQUE `(company_id, code) WHERE deleted_at IS NULL` (stages не имеет SoftDeleteMixin, но паттерн применим).
2. `house_types.code unique=True` — аналогично.
3. `option_catalog.code unique=True` — аналогично.
4. `budget_categories.code unique=True` — аналогично.

Для `contracts`: `uq_contracts_contractor_id_number_active` (`contractor_id, number WHERE deleted_at IS NULL`) — после multi-tenant становится корректным только если `contractor_id` уже несёт `company_id` (несёт, через FK `contractors.company_id`). Таким образом, индекс косвенно защищает multi-tenant. **Не требует изменения.**

---

## 4. Миграционная стратегия: одна vs несколько

**Рекомендация: одна миграция для dev-baseline, разбитая на 2 при переходе к production.**

Аргументы:

- Текущая миграция `us01_add_company_id.py` правильно реализует expand/backfill/contract в одной транзакции.
- При dev-baseline (≤100 строк) одна транзакция атомарна и безопасна. Это соответствует ADR 0013.
- При production (возможные тысячи строк в `houses`, `payments`) `ALTER COLUMN ... SET NOT NULL` удерживает `ACCESS EXCLUSIVE LOCK`. Рекомендуется разбить на:
  - **Миграция A:** ADD COLUMN nullable + FK + индекс + backfill через batch UPDATE.
  - **Миграция B:** ALTER COLUMN SET NOT NULL (выполняется в короткий maintenance window или через `ALTER TABLE ... VALIDATE CONSTRAINT` паттерн для zero-downtime).
- Для текущего skeleton-этапа (M-OS-1) разбивка на 2 — не срочна. Добавить `PRODUCTION-NOTE` в комментарий файла.

---

## 5. Performance check: 3 тяжёлых запроса

Анализ без доступа к живой БД — на основе плана выполнения. После применения миграции добавятся фильтры `WHERE company_id = $N` во все сервисные запросы.

### Запрос 1 — Список платежей с деталями договора

```sql
SELECT p.*, c.number, c.subject
FROM payments p
JOIN contracts c ON c.id = p.contract_id
WHERE p.company_id = 1
  AND p.status = 'approved'
ORDER BY p.paid_at DESC
LIMIT 50;
```

**Текущие индексы:** `ix_payments_company_id` (одиночный), `ix_payments_contract_id`.
**Риск:** seq scan на `payments` если `company_id = 1` возвращает большой процент строк (одна компания = все строки). Оптимизатор может предпочесть seq scan.
**Митигация:** составной индекс `(company_id, status, paid_at DESC)` — покрывающий для типовой выборки «одобренные платежи по компании».

### Запрос 2 — Договоры по проекту + компании

```sql
SELECT co.*, cr.short_name as contractor_name
FROM contracts co
JOIN contractors cr ON cr.id = co.contractor_id
WHERE co.company_id = 1
  AND co.project_id = $project_id
  AND co.deleted_at IS NULL
ORDER BY co.signed_at DESC;
```

**Текущие индексы:** `ix_contracts_company_id`, `ix_contracts_project_id` — раздельные.
**Риск:** оптимизатор выберет один индекс, второй условие станет фильтром. При росте контрактов — bitmap index scan по двум индексам (нормально). При большом числе компаний — без регрессии.
**Митигация:** составной `(company_id, project_id) WHERE deleted_at IS NULL` — рекомендован при >1000 контрактов.

### Запрос 3 — Стадии/история дома

```sql
SELECT hsh.*, s.name as stage_name
FROM house_stage_history hsh
JOIN stages s ON s.id = hsh.stage_id
JOIN houses h ON h.id = hsh.house_id
WHERE h.company_id = 1
  AND hsh.house_id = $house_id;
```

**Текущий путь:** фильтр по `hsh.house_id` — узкий, индекс `ix_house_stage_history_house_id` работает эффективно. Добавление `company_id` на `house_stage_history` создаёт новый индекс, который будет использоваться только при запросах без `house_id`. **Регрессии нет.**

---

## 6. Риски P0/P1 сводная таблица

| Риск | Уровень | Статус |
|---|---|---|
| Несовпадение имён таблиц в `_TABLES` (проверить `budget_plan` vs `budget_plans`) | P1 | Требует проверки перед запуском |
| `contractors`/`payments` уже имеют `company_id` — бриф считает их в 12, итого фактически 10 | P1 | Уточнить в отчёте backend-head |
| Глобальный UNIQUE на `code` справочников становится неверным для multi-tenant | P1 | Эскалация architect/backend-director |
| `ALTER TABLE ... SET NOT NULL` без CONCURRENTLY — допустимо для dev, блокирует на prod | P2 | Добавить PRODUCTION-NOTE в миграцию |
| Отсутствие составных индексов `(company_id, *)` — замедление при росте данных | P2 | Добавить после решения P1-3 |

---

## 7. Итоговые рекомендации backend-dev-1

1. **Проверить имена таблиц** через `psql \dt` на dev-БД до запуска round-trip. Исправить `_TABLES` под фактические имена (`budget_plan` или `budget_plans`, `house_stage_history` или `house_stage_histories`).

2. **Уточнить scope у backend-head**: `contractors` и `payments` уже получили `company_id` в `f7e8d9c0b1a2`. Если бриф считает 12 таблиц включая их — либо бриф некорректен, либо нужна проверка, что модели и схема синхронны.

3. **Эскалировать к architect** вопрос о семантике `house_types`, `option_catalog`, `stages`, `budget_categories`: холдинговые справочники (один на весь холдинг) или per-company (каждое юрлицо ведёт свой каталог). От этого зависит, нужен ли `company_id` на этих 4 таблицах, и нужно ли ломать глобальные UNIQUE `code`-индексы.

---

*Ревью подготовлено db-engineer. Партнёрство с backend-dev-1 — код пишет backend-dev-1, это только schema review. Если вопросы P1-3 требуют решения архитектора — эскалация через backend-head к backend-director.*
