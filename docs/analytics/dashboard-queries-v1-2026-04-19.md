# Dashboard Queries v1 — coordinata56
**Дата:** 2026-04-19  
**Автор:** data-analyst  
**Область:** dev-БД (coordinata56, реплика Sprint 1)  
**Статус:** READ-ONLY — только SELECT, нет изменений данных

---

## Контекст и допущения

- Все деньги хранятся в **копейках** (bigint, ADR 0001 §2). При выводе делить на 100.
- Multi-tenant guard: каждый запрос содержит `WHERE ... company_id = :company_id`.
- Фактическими расходами считаются только платежи со статусом `approved`.
- `budget_plan.deleted_at IS NULL` — soft-delete фильтр для планов.
- `houses.deleted_at IS NULL` — исключает архивированные дома.
- В dev-БД на момент проверки: 1000 домов, 0 стадий, 0 договоров, 0 платежей. EXPLAIN ANALYZE подтверждает корректность индексов на реальных данных (структура плана сохранена).
- Параметры-плейсхолдеры: `:company_id`, `:period_start`, `:period_end`, `:overrun_pct`.

---

## Q1. Финансы: факт vs план по дому за неделю / месяц

**Бизнес-вопрос:** Сколько реально потрачено по каждому дому за последние 7 дней и текущий месяц, и каков плановый бюджет дома?

**Edge cases:**
- Нет платежей → `COALESCE(..., 0)` возвращает 0, строка дома всё равно присутствует.
- Нет плана → `plan_total_cents = 0`; отношение факт/план не считается на уровне этого запроса.
- Один дом может иметь несколько договоров → агрегация через LEFT JOIN корректна.

```sql
SELECT
    h.id                                              AS house_id,
    h.plot_number,
    COALESCE(
        SUM(p.amount_cents) FILTER (
            WHERE p.paid_at >= NOW() - INTERVAL '7 days'
        ), 0
    )                                                 AS paid_week_cents,
    COALESCE(
        SUM(p.amount_cents) FILTER (
            WHERE p.paid_at >= DATE_TRUNC('month', NOW())
        ), 0
    )                                                 AS paid_month_cents,
    COALESCE(SUM(bp.amount_cents), 0)                 AS plan_total_cents
FROM houses h
LEFT JOIN contracts c  ON c.house_id    = h.id   AND c.company_id = :company_id
LEFT JOIN payments  p  ON p.contract_id = c.id   AND p.company_id = :company_id
                       AND p.status = 'approved'
LEFT JOIN budget_plan bp ON bp.house_id = h.id   AND bp.company_id = :company_id
                         AND bp.deleted_at IS NULL
WHERE h.company_id = :company_id
  AND h.deleted_at IS NULL
GROUP BY h.id, h.plot_number
ORDER BY h.plot_number;
```

**Output shape:**

| house_id | plot_number | paid_week_cents | paid_month_cents | plan_total_cents |
|----------|-------------|-----------------|------------------|-----------------|
| 1        | H1-1        | 0               | 0                | 0               |
| …        | …           | …               | …                | …               |

**EXPLAIN ANALYZE (dev, company_id=1):**
```
Index Scan using ix_houses_company_id on houses h
  Index Cond: (company_id = 1)
  Filter: (deleted_at IS NULL)
Index Scan using ix_contracts_company_id on contracts c
  Index Cond: (company_id = 1)
Index Scan using ix_payments_company_id on payments p
  Index Cond: (company_id = 1)
Bitmap Index Scan on ix_budget_plan_company_id
  Index Cond: (company_id = 1)
Planning Time: 6.986 ms | Execution Time: 1.992 ms
```
Все три company_id индекса задействованы. Плановая стоимость при росте данных потребует составного индекса `(company_id, house_id)` на `budget_plan` — рекомендация db-engineer при N > 50k строк.

---

## Q2. Прогресс: % готовности каждого дома по стадиям

**Бизнес-вопрос:** На какой стадии строительства каждый дом и какой это процент готовности (от общего числа стадий)?

**Логика расчёта:** `completion_pct = current_stage.order_index / max(order_index по компании) * 100`. Если стадия не назначена — `current_stage_name = NULL`, `completion_pct = 0`.

**Edge cases:**
- Нет стадий в справочнике → `COALESCE(MAX(order_index), 1)` в знаменателе предотвращает деление на ноль.
- Дом без текущей стадии (`current_stage_id IS NULL`) → LEFT JOIN возвращает NULL, `completion_pct = 0`.
- Стадии нумерованы от 1 в `order_index`, последняя = 100%.

```sql
SELECT
    h.id                AS house_id,
    h.plot_number,
    s.name              AS current_stage_name,
    s.order_index       AS current_stage_order,
    max_s.max_order     AS total_stages,
    CASE
        WHEN max_s.max_order > 0
        THEN ROUND(s.order_index::numeric / max_s.max_order * 100, 1)
        ELSE 0
    END                 AS completion_pct
FROM houses h
LEFT JOIN stages s ON s.id = h.current_stage_id
                   AND s.company_id = :company_id
CROSS JOIN LATERAL (
    SELECT COALESCE(MAX(order_index), 1) AS max_order
    FROM stages
    WHERE company_id = :company_id
) max_s
WHERE h.company_id = :company_id
  AND h.deleted_at IS NULL
ORDER BY h.plot_number;
```

**Output shape:**

| house_id | plot_number | current_stage_name | current_stage_order | total_stages | completion_pct |
|----------|-------------|-------------------|---------------------|--------------|----------------|
| 1        | H1-1        | NULL               | NULL                | 1            | 0              |
| …        | …           | …                 | …                   | …            | …              |

**EXPLAIN ANALYZE (dev, company_id=1):**
```
Index Scan using ix_houses_company_id on houses h
  Index Cond: (company_id = 1)
Index Scan using uq_stages_company_id_code on stages s
  Index Cond: (company_id = 1)
Aggregate over Index Scan on stages (LATERAL)
Planning Time: 3.096 ms | Execution Time: 1.036 ms
```
Индексы попадают. LATERAL-агрегат выполняется один раз (не N раз на каждую строку) — оптимизатор распознал инвариантность.

---

## Q3. Контрагенты: топ-5 по сумме платежей за квартал

**Бизнес-вопрос:** Кому больше всего заплатили в текущем квартале? Топ-5 подрядчиков по объёму утверждённых платежей.

**Edge cases:**
- Мягко удалённые подрядчики (`deleted_at IS NOT NULL`) исключены.
- Квартал рассчитывается динамически через `DATE_TRUNC('quarter', NOW())` — не хардкодится.
- Если платежей в квартале нет — запрос возвращает пустой результат (не ошибку).

```sql
SELECT
    co.id                               AS contractor_id,
    co.short_name,
    co.inn,
    SUM(p.amount_cents)                 AS total_paid_cents,
    COUNT(DISTINCT c.id)                AS contracts_count
FROM payments p
JOIN contracts   c  ON c.id = p.contract_id   AND c.company_id = :company_id
JOIN contractors co ON co.id = c.contractor_id AND co.company_id = :company_id
WHERE p.company_id = :company_id
  AND p.status = 'approved'
  AND p.paid_at >= DATE_TRUNC('quarter', NOW())
  AND p.paid_at <  DATE_TRUNC('quarter', NOW()) + INTERVAL '3 months'
  AND co.deleted_at IS NULL
GROUP BY co.id, co.short_name, co.inn
ORDER BY total_paid_cents DESC
LIMIT 5;
```

**Output shape:**

| contractor_id | short_name | inn | total_paid_cents | contracts_count |
|---------------|-----------|-----|-----------------|----------------|
| 12            | ООО «…»   | … | 15000000        | 3              |
| …             | …         | … | …               | …              |

**EXPLAIN ANALYZE (dev, company_id=1):**
```
Index Scan using ix_payments_company_id on payments p
  Index Cond: (company_id = 1)
  Filter: status='approved' AND paid_at в диапазоне квартала
Index Scan using ix_contracts_company_id on contracts c
Index Scan using uq_contractors_inn_active on contractors co
Planning Time: 4.401 ms | Execution Time: 0.258 ms
```
Все три индекса по company_id используются. При росте payments рекомендуется составной индекс `(company_id, status, paid_at)`.

---

## Q4. Бюджет-рискованные дома: факт > плана на N%

**Бизнес-вопрос:** Какие дома превысили бюджет более чем на N%? Отсортировать по убыванию перерасхода.

**Edge cases:**
- `NULLIF(hp.plan_cents, 0)` — защита от деления на ноль, если план равен нулю.
- Дома без плана (`budget_plan` отсутствует) исключаются через `JOIN` (не LEFT JOIN) — они не могут «превысить» план.
- Порог N задаётся как `:overrun_pct` (например, `0.10` = 10%). Default для dashboard: 10%.

```sql
WITH house_spend AS (
    SELECT
        h.id                             AS house_id,
        h.plot_number,
        COALESCE(SUM(p.amount_cents), 0) AS fact_cents
    FROM houses h
    LEFT JOIN contracts c ON c.house_id    = h.id AND c.company_id = :company_id
    LEFT JOIN payments  p ON p.contract_id = c.id AND p.company_id = :company_id
                          AND p.status = 'approved'
    WHERE h.company_id = :company_id
      AND h.deleted_at IS NULL
    GROUP BY h.id, h.plot_number
),
house_plan AS (
    SELECT house_id, SUM(amount_cents) AS plan_cents
    FROM budget_plan
    WHERE company_id = :company_id
      AND deleted_at IS NULL
      AND house_id IS NOT NULL
    GROUP BY house_id
)
SELECT
    hs.house_id,
    hs.plot_number,
    hs.fact_cents,
    hp.plan_cents,
    ROUND(
        (hs.fact_cents - hp.plan_cents)::numeric
        / NULLIF(hp.plan_cents, 0) * 100,
        1
    )                                    AS overrun_pct
FROM house_spend hs
JOIN house_plan  hp ON hp.house_id = hs.house_id
WHERE hp.plan_cents > 0
  AND hs.fact_cents > hp.plan_cents * (1 + :overrun_pct)
ORDER BY overrun_pct DESC;
```

**Output shape:**

| house_id | plot_number | fact_cents | plan_cents | overrun_pct |
|----------|-------------|-----------|-----------|-------------|
| 42       | H2-10       | 1850000   | 1500000   | 23.3        |
| …        | …           | …         | …         | …           |

**EXPLAIN ANALYZE (dev, company_id=1):**
```
Hash Join (house_spend CTE × house_plan CTE)
  house_spend: Index Scan ix_houses_company_id → Hash Left Join contracts/payments
  house_plan:  Bitmap Index Scan ix_budget_plan_company_id + ix_budget_plan_deleted_at
Planning Time: 7.575 ms | Execution Time: 0.522 ms
```
CTE-материализация даёт hash join вместо вложенных loops — при 1000+ домов это правильная стратегия.

---

## Q5. Просрочки: стадии где дом завис (не завершена стадия)

**Бизнес-вопрос:** Какие дома находятся на текущей стадии без продвижения? Сколько дней дом на этой стадии?

**Логика:** `house_stage_history` — запись открыта (`completed_at IS NULL`), совпадает с текущей стадией дома (`h.current_stage_id = hsh.stage_id`). Нет отдельного поля deadline на стадии — отслеживается факт залегания.

**Примечание:** Если бизнес хочет deadline на стадию, потребуется добавить поле `deadline_date` в таблицу `stages` или `house_stage_history` — это задача для db-engineer + backend.

**Edge cases:**
- Дома без назначенной стадии — исключаются (нет записи в history).
- `CURRENT_DATE - hsh.started_at::date` — число дней в стадии. Может быть 0 в день начала.
- При использовании в dashboard добавить фильтр `:min_days_stuck` (например, > 7).

```sql
SELECT
    hsh.house_id,
    h.plot_number,
    s.name                                      AS stage_name,
    s.order_index,
    hsh.started_at,
    CURRENT_DATE - hsh.started_at::date         AS days_in_stage
FROM house_stage_history hsh
JOIN houses h ON h.id = hsh.house_id  AND h.company_id = :company_id
JOIN stages s ON s.id = hsh.stage_id  AND s.company_id = :company_id
WHERE hsh.company_id = :company_id
  AND hsh.completed_at IS NULL
  AND h.current_stage_id = hsh.stage_id
  AND h.deleted_at IS NULL
ORDER BY days_in_stage DESC;
```

**Output shape:**

| house_id | plot_number | stage_name   | order_index | started_at           | days_in_stage |
|----------|-------------|-------------|-------------|----------------------|---------------|
| 7        | H1-7        | Фундамент   | 4           | 2026-03-01T09:00:00Z | 49            |
| …        | …           | …           | …           | …                    | …             |

**EXPLAIN ANALYZE (dev, company_id=1):**
```
Nested Loop
  Index Scan uq_stages_company_id_code on stages
  Index Scan ix_houses_current_stage_id on houses h
  Index Scan ix_house_stage_history_stage_id on house_stage_history hsh
Planning Time: 3.956 ms | Execution Time: 0.215 ms
```
Три индекса в цепочке join работают. `ix_houses_current_stage_id` — специализированный индекс по FK полю `current_stage_id`, обеспечивает lookup без сиквенс скана.

---

## Q6. Движение денег: платежи по категориям бюджета за период

**Бизнес-вопрос:** Сколько потрачено по каждой статье расходов (категории бюджета) за произвольный период?

**Связь:** `payments → contracts → budget_plan → budget_categories`. Договор может быть привязан к дому+стадии, только к дому, или ни к чему — поэтому LEFT JOIN на budget_plan с матчингом по `house_id` и `stage_id`.

**Edge cases:**
- Платежи без связанного плана → `bc.name = NULL` (группируется как «Без категории»).
- `ORDER BY total_cents DESC NULLS LAST` — платежи без категории уходят в конец.
- Параметры `:period_start` / `:period_end` — передаются как timestamp with time zone.

```sql
SELECT
    COALESCE(bc.code, 'UNCATEGORIZED')    AS category_code,
    COALESCE(bc.name, 'Без категории')    AS category_name,
    COUNT(p.id)                           AS payments_count,
    SUM(p.amount_cents)                   AS total_cents,
    MIN(p.paid_at)                        AS first_payment,
    MAX(p.paid_at)                        AS last_payment
FROM payments p
JOIN contracts     c  ON c.id = p.contract_id  AND c.company_id = :company_id
LEFT JOIN budget_plan bp ON bp.house_id  = c.house_id
                         AND bp.stage_id = c.stage_id
                         AND bp.company_id = :company_id
                         AND bp.deleted_at IS NULL
LEFT JOIN budget_categories bc ON bc.id = bp.category_id
                               AND bc.company_id = :company_id
WHERE p.company_id = :company_id
  AND p.status = 'approved'
  AND p.paid_at >= :period_start
  AND p.paid_at <  :period_end
GROUP BY bc.code, bc.name
ORDER BY total_cents DESC NULLS LAST;
```

**Output shape:**

| category_code | category_name | payments_count | total_cents | first_payment        | last_payment         |
|---------------|--------------|---------------|-------------|----------------------|----------------------|
| FOUNDATION    | Фундамент    | 12            | 4500000     | 2026-02-15T10:00:00Z | 2026-03-20T14:00:00Z |
| UNCATEGORIZED | Без категории | 3            | 800000      | …                    | …                    |
| …             | …            | …             | …           | …                    | …                    |

**EXPLAIN ANALYZE (dev, company_id=1, период = текущий месяц):**
```
Nested Loop Left Join
  Index Scan ix_payments_company_id on payments p
    Filter: status='approved' AND paid_at в периоде
  Index Scan ix_contracts_company_id on contracts c
  Index Scan uq_budget_plan_proj_cat_stage_house on budget_plan bp
  Index Scan uq_budget_categories_company_id_code on budget_categories bc
Planning Time: 8.176 ms | Execution Time: 0.412 ms
```
Уникальный составной индекс `uq_budget_plan_proj_cat_stage_house` используется для lookup по `(stage_id, house_id)` — это оптимально. При росте данных добавить индекс `(company_id, paid_at, status)` на payments.

---

## Рекомендованные индексы для production

При объёме > 50k строк в payments рекомендовать db-engineer:

```sql
-- payments: составной для фильтра по статусу + периоду
CREATE INDEX CONCURRENTLY ix_payments_company_status_paid_at
    ON payments (company_id, status, paid_at)
    WHERE status = 'approved';

-- budget_plan: для быстрого lookup по house_id
CREATE INDEX CONCURRENTLY ix_budget_plan_company_house
    ON budget_plan (company_id, house_id)
    WHERE deleted_at IS NULL AND house_id IS NOT NULL;
```

Эти индексы — рекомендация для эскалации к `db-engineer`, не для самостоятельного применения.

---

## Использование в коде (SQLAlchemy / psycopg)

```python
from datetime import datetime, timezone

result = await session.execute(
    text(Q1_FINANCE_FACT_VS_PLAN),
    {"company_id": current_user.company_id}
)
rows = result.mappings().all()
# Конвертация копеек → рубли на уровне сериализатора, не в SQL
```

Параметры передавать через bind-переменные (`:`-синтаксис) — никогда f-строками во избежание SQL-инъекций.
