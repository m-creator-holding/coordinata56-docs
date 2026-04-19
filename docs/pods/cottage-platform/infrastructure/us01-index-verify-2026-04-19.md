# US-01 multi-tenant index verify report

**Дата:** 2026-04-19
**Волна:** 11 (infra-director track A)
**Автор:** `db-head` / `db-engineer` (primary review `infra-director`)
**Статус:** GREEN — все проверенные индексы на месте, план использует index scan на типовых multi-tenant запросах.

---

## 1. Контекст

Миграция `us01_add_company_id` (revision `us01_add_company_id`, commit Sprint 1) добавила колонку `company_id` на 10 доменных таблиц cottage-platform:

```
budget_categories, budget_plan, stages, material_purchases,
house_types, option_catalog, house_type_option_compat,
houses, house_configurations, house_stage_history
```

Дополнительно таблицы `contractors`, `contracts`, `payments` получили `company_id` ранее миграцией `f7e8d9c0b1a2 multi_company_foundation`. `projects` — оттуда же.

Требование US-01 P1: каждая multi-tenant-фильтрация в SQL должна уметь использовать индекс на `company_id`, либо составной `(company_id, <business_key>)` там где business-ключ уникален внутри компании (справочники: `code`).

## 2. Метод верификации

1. `alembic upgrade head` в dev-БД (pod `coordinata56_postgres`).
2. Запрос `pg_indexes` по всем 13 таблицам с фильтром `indexdef ILIKE '%company_id%'`.
3. Seed ~1000 строк в `houses` по двум компаниям + `projects`, `house_types`, `companies`. `ANALYZE` для корректной статистики планировщика.
4. `EXPLAIN (ANALYZE, BUFFERS)` для трёх типовых паттернов multi-tenant запросов.
5. Force-проверка составного UNIQUE через `SET enable_seqscan = off`.

## 3. Результат — таблица индексов

| Таблица | ix_*_company_id | Составной UNIQUE | Статус |
|---|---|---|---|
| budget_categories | да | `uq_budget_categories_company_id_code` | OK |
| budget_plan | да | — (не нужен) | OK |
| stages | да | `uq_stages_company_id_code` | OK |
| material_purchases | да | — (не нужен) | OK |
| house_types | да | `uq_house_types_company_id_code` | OK |
| option_catalog | да | `uq_option_catalog_company_id_code` | OK |
| house_type_option_compat | да | — (не нужен, это junction) | OK |
| houses | да | — (business-key `(project_id, plot_number)` не привязан к company) | OK |
| house_configurations | да | — | OK |
| house_stage_history | да | — | OK |
| contractors | да | — (есть `ix_contractors_inn_unique_active` partial) | OK |
| contracts | да | — (есть `ix_contracts_contractor_number_unique_partial`); также `ix_contracts_counterparty_company_id` | OK |
| payments | да | — | OK |

Итого: 13/13 таблиц имеют `ix_*_company_id`. Все 4 справочника (`stages`, `budget_categories`, `house_types`, `option_catalog`) имеют составной UNIQUE `(company_id, code)` — соответствует US-01 P1 «code уникален в рамках компании».

## 4. EXPLAIN ANALYZE — типовые запросы

### 4.1 `WHERE company_id = $1` (простой multi-tenant фильтр)

```sql
SELECT id, plot_number FROM houses WHERE company_id = 1;
```

План: `Index Scan using ix_houses_company_id on houses (cost=0.15..21.90 rows=500)`. Execution Time 0.22 ms. **Index scan, не seq scan.**

### 4.2 `WHERE company_id = $1 AND project_id = $2 LIMIT N` (список с пагинацией)

План: `Index Scan using ix_houses_company_id` + filter по `project_id`. Execution 0.15 ms. При росте кардинальности project планировщик может переключиться на `ix_houses_project_id` — это ожидаемо и корректно (оба indexed).

### 4.3 `WHERE company_id = $1 AND code = $2` (справочник per-company)

На малой таблице (2 строки) — `Seq Scan` с предикатом (это правильное решение планировщика для 2-строчного справочника). При `SET enable_seqscan = off` — `Index Scan using uq_house_types_company_id_code`. Составной UNIQUE работает на обеих колонках одновременно.

### 4.4 `SELECT count(*) WHERE company_id = $1`

План: `Index Only Scan using ix_houses_company_id`. Heap Fetches: 500 (не блокер, уменьшится после `VACUUM` с обновлением visibility map). Execution 0.27 ms.

## 5. Рекомендация

Дополнительные миграции не требуются.

Опционально — в M-OS-1.2 (или по мере роста таблиц) рассмотреть:

1. **Partial indexes `WHERE deleted_at IS NULL`** для таблиц с soft-delete (`houses`, `projects`, `budget_categories`, `contracts`). Даст 10-30% экономии при высокой доле архивных записей. Сейчас dev-данных слишком мало, преждевременно.
2. **Композитный `(company_id, deleted_at, created_at DESC)`** для типового list-запроса `WHERE company_id=? AND deleted_at IS NULL ORDER BY created_at DESC LIMIT N`. Тоже только после роста БД.

Оба — не блокируют US-01, оформляются отдельным тикетом `db-head` при появлении первых показателей latency.

## 6. Артефакты

- Draft миграции **не создавался** (не требуется).
- Seed-данные для EXPLAIN — остались в dev-БД `coordinata56`, в production не попадут.

## 7. Acceptance check (по брифу Координатора)

- [x] Таблица `table → indexes_present → query_plan_status` — §3.
- [x] EXPLAIN ANALYZE на 4 типовых запросах — §4.
- [x] Вывод: index scan используется, seq scan только на справочниках с <5 строк (ожидаемо).
- [x] Рекомендация + (если нужно) draft миграция — §5, draft не нужен.

**Верхнеуровневый вердикт Трека A: GREEN.**
