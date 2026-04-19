-- =============================================================================
-- Owner Top-10 Reports — coordinata56
-- Схема: ADR 0001 v1.1 | PostgreSQL 16
-- Денежные поля хранятся в копейках (bigint); деление на 100 даёт рубли.
-- Soft-delete: все транзакционные таблицы фильтруются по deleted_at IS NULL.
-- Только SELECT — без изменения данных.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- R-01: CASH BURN — сводка одобренных и оплаченных платежей
-- ---------------------------------------------------------------------------
-- Показывает: сколько денег ушло из кассы (APPROVED/PAID-платежи),
-- разбивку по статусам и динамику по месяцам.
-- Допущение: "paid" трактуется как статус 'approved' (финальный положительный
-- статус в модели). Колонка paid_at содержит дату фактической операции.
-- ---------------------------------------------------------------------------
SELECT
    date_trunc('month', p.paid_at)::date                     AS month,
    p.status,
    COUNT(*)                                                  AS payments_count,
    SUM(p.amount_cents) / 100.0                               AS total_rub,
    AVG(p.amount_cents) / 100.0                               AS avg_payment_rub,
    MAX(p.amount_cents) / 100.0                               AS max_payment_rub
FROM payments p
JOIN contracts c ON c.id = p.contract_id
WHERE p.status IN ('approved', 'pending')
  AND c.deleted_at IS NULL
GROUP BY 1, 2
ORDER BY 1 DESC, 2;


-- ---------------------------------------------------------------------------
-- R-02: ДОМА ПО СТАДИЯМ — распределение 85 домов по текущим стадиям строительства
-- ---------------------------------------------------------------------------
-- Показывает: на каком этапе находится каждый дом, сколько домов на каждой
-- стадии, процент от общего числа активных домов.
-- Допущение: дома без current_stage_id (NULL) показываются отдельной строкой
-- со стадией "Не назначена".
-- ---------------------------------------------------------------------------
SELECT
    COALESCE(s.name, 'Не назначена')                         AS stage_name,
    COALESCE(s.order_index, -1)                               AS stage_order,
    COUNT(h.id)                                               AS houses_count,
    ROUND(
        COUNT(h.id) * 100.0 / NULLIF(SUM(COUNT(h.id)) OVER (), 0),
        1
    )                                                         AS pct_of_total,
    ht.name                                                   AS house_type_name
FROM houses h
LEFT JOIN stages s ON s.id = h.current_stage_id
LEFT JOIN house_types ht ON ht.id = h.house_type_id
WHERE h.deleted_at IS NULL
GROUP BY s.name, s.order_index, ht.name
ORDER BY stage_order, ht.name;


-- ---------------------------------------------------------------------------
-- R-03: ПРОСРОЧЕННЫЕ ПЛАТЕЖИ — платежи по договорам с истёкшим сроком действия
-- ---------------------------------------------------------------------------
-- Показывает: контракты с end_date < сегодня, у которых есть неоплаченные
-- платежи в статусе draft или pending.
-- Логика просрочки: договор просрочен, если end_date < CURRENT_DATE и статус
-- контракта не 'completed' / 'cancelled'.
-- Допущение: "просроченный платёж" = pending-платёж по просроченному договору.
-- ---------------------------------------------------------------------------
SELECT
    c.number                                                  AS contract_number,
    c.subject                                                 AS contract_subject,
    ctr.short_name                                            AS contractor_name,
    c.end_date,
    CURRENT_DATE - c.end_date                                 AS overdue_days,
    COUNT(p.id)                                               AS pending_payments_count,
    SUM(p.amount_cents) / 100.0                               AS pending_amount_rub,
    h.plot_number                                             AS house_plot
FROM contracts c
JOIN contractors ctr ON ctr.id = c.contractor_id
LEFT JOIN payments p ON p.contract_id = c.id
    AND p.status IN ('draft', 'pending')
LEFT JOIN houses h ON h.id = c.house_id
WHERE c.deleted_at IS NULL
  AND ctr.deleted_at IS NULL
  AND c.status IN ('active')
  AND c.end_date < CURRENT_DATE
GROUP BY c.id, c.number, c.subject, ctr.short_name, c.end_date, h.plot_number
HAVING COUNT(p.id) > 0
ORDER BY overdue_days DESC;


-- ---------------------------------------------------------------------------
-- R-04: ОТСТАВАНИЕ ОТ ПЛАНА — дома, где текущая стадия отстаёт от ожидаемой
-- ---------------------------------------------------------------------------
-- Показывает: сколько домов застряли на одной стадии дольше среднего.
-- Метрика: время с момента начала текущей стадии (house_stage_history.started_at
-- для последней записи по дому) в сравнении с медианой по всем домам
-- на той же стадии.
-- Допущение: "отставание" = время на стадии > 1.5 × медиана по стадии.
-- Ограничение: нет официальной плановой даты перехода между стадиями в схеме;
-- используем медиану как эталон. При появлении planned_end_at в схеме — заменить.
-- ---------------------------------------------------------------------------
WITH latest_stage AS (
    -- Последняя (текущая) запись истории для каждого дома
    SELECT DISTINCT ON (house_id)
        house_id,
        stage_id,
        started_at,
        EXTRACT(
            DAY FROM (CURRENT_TIMESTAMP - started_at)
        )::int                                                AS days_on_stage
    FROM house_stage_history
    ORDER BY house_id, started_at DESC
),
stage_median AS (
    SELECT
        stage_id,
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY days_on_stage
        )                                                     AS median_days
    FROM latest_stage
    GROUP BY stage_id
)
SELECT
    h.plot_number,
    ht.name                                                   AS house_type,
    s.name                                                    AS current_stage,
    ls.days_on_stage,
    ROUND(sm.median_days)                                     AS median_days_on_stage,
    ROUND(ls.days_on_stage - sm.median_days)                  AS days_behind_median
FROM latest_stage ls
JOIN stage_median sm ON sm.stage_id = ls.stage_id
JOIN houses h ON h.id = ls.house_id
JOIN stages s ON s.id = ls.stage_id
JOIN house_types ht ON ht.id = h.house_type_id
WHERE h.deleted_at IS NULL
  AND ls.days_on_stage > sm.median_days * 1.5
ORDER BY days_behind_median DESC;


-- ---------------------------------------------------------------------------
-- R-05: ПОДРЯДЧИКИ В СПОРАХ — договоры со статусом 'cancelled' или без платежей
-- ---------------------------------------------------------------------------
-- Показывает: подрядчиков, у которых есть аннулированные договоры или договоры
-- без единого платежа при статусе 'active'.
-- "Спор" в данном контексте = cancelled-договор (явный разрыв) или active без
-- оплат (признак замороженных отношений).
-- Допущение: таблицы disputes в схеме нет; используем суррогатные признаки.
-- ---------------------------------------------------------------------------
SELECT
    ctr.short_name                                            AS contractor_name,
    ctr.inn,
    ctr.category                                              AS contractor_category,
    COUNT(c.id)                                               AS contracts_total,
    SUM(CASE WHEN c.status = 'cancelled' THEN 1 ELSE 0 END)   AS cancelled_count,
    SUM(
        CASE
            WHEN c.status = 'active' AND NOT EXISTS (
                SELECT 1 FROM payments p2
                WHERE p2.contract_id = c.id
            ) THEN 1
            ELSE 0
        END
    )                                                         AS active_no_payment_count,
    SUM(c.amount_cents) / 100.0                               AS total_contract_value_rub
FROM contractors ctr
JOIN contracts c ON c.contractor_id = ctr.id
    AND c.deleted_at IS NULL
WHERE ctr.deleted_at IS NULL
GROUP BY ctr.id, ctr.short_name, ctr.inn, ctr.category
HAVING
    SUM(CASE WHEN c.status = 'cancelled' THEN 1 ELSE 0 END) > 0
    OR SUM(
        CASE
            WHEN c.status = 'active' AND NOT EXISTS (
                SELECT 1 FROM payments p2
                WHERE p2.contract_id = c.id
            ) THEN 1
            ELSE 0
        END
    ) > 0
ORDER BY cancelled_count DESC, total_contract_value_rub DESC;


-- ---------------------------------------------------------------------------
-- R-06: ТОП-10 РАСХОДОВ ПО КАТЕГОРИЯМ — крупнейшие статьи фактических расходов
-- ---------------------------------------------------------------------------
-- Показывает: какие статьи бюджета съели больше всего денег (фактические
-- платежи, прошедшие в статусе 'approved').
-- Связка: payments → contracts → budget_plan (через project_id, house_id,
-- stage_id) → budget_categories.
-- Допущение: платёж относится к категории через budget_plan контракта; если
-- у контракта нет записи в budget_plan — категория NULL.
-- ---------------------------------------------------------------------------
SELECT
    bc.name                                                   AS category_name,
    COUNT(p.id)                                               AS payments_count,
    SUM(p.amount_cents) / 100.0                               AS fact_spent_rub,
    SUM(bp.amount_cents) / 100.0                              AS plan_amount_rub,
    ROUND(
        SUM(p.amount_cents) * 100.0
        / NULLIF(SUM(bp.amount_cents), 0),
        1
    )                                                         AS fact_vs_plan_pct
FROM payments p
JOIN contracts c ON c.id = p.contract_id
    AND c.deleted_at IS NULL
LEFT JOIN budget_plan bp ON bp.house_id = c.house_id
    AND bp.stage_id = c.stage_id
    AND bp.project_id = c.project_id
    AND bp.deleted_at IS NULL
LEFT JOIN budget_categories bc ON bc.id = bp.category_id
    AND bc.deleted_at IS NULL
WHERE p.status = 'approved'
GROUP BY bc.name
ORDER BY fact_spent_rub DESC
LIMIT 10;


-- ---------------------------------------------------------------------------
-- R-07: ПЛАН/ФАКТ БЮДЖЕТА — сводное сравнение по проектам и стадиям
-- ---------------------------------------------------------------------------
-- Показывает: плановый бюджет vs фактические расходы на уровне
-- проект × стадия × статья расходов.
-- Отклонение: положительное = перерасход, отрицательное = экономия.
-- ---------------------------------------------------------------------------
SELECT
    pr.name                                                   AS project_name,
    s.name                                                    AS stage_name,
    s.order_index                                             AS stage_order,
    bc.name                                                   AS category_name,
    COUNT(DISTINCT bp.house_id)                               AS houses_planned,
    SUM(bp.amount_cents) / 100.0                              AS plan_rub,
    COALESCE(SUM(fact.fact_cents), 0) / 100.0                 AS fact_rub,
    (COALESCE(SUM(fact.fact_cents), 0) - SUM(bp.amount_cents))
        / 100.0                                               AS deviation_rub,
    ROUND(
        (COALESCE(SUM(fact.fact_cents), 0) - SUM(bp.amount_cents))
        * 100.0 / NULLIF(SUM(bp.amount_cents), 0),
        1
    )                                                         AS deviation_pct
FROM budget_plan bp
JOIN projects pr ON pr.id = bp.project_id
LEFT JOIN stages s ON s.id = bp.stage_id
JOIN budget_categories bc ON bc.id = bp.category_id
LEFT JOIN (
    SELECT
        c.project_id,
        c.house_id,
        c.stage_id,
        SUM(p.amount_cents)                                   AS fact_cents
    FROM payments p
    JOIN contracts c ON c.id = p.contract_id
        AND c.deleted_at IS NULL
    WHERE p.status = 'approved'
    GROUP BY c.project_id, c.house_id, c.stage_id
) fact ON fact.project_id = bp.project_id
    AND (fact.house_id = bp.house_id OR bp.house_id IS NULL)
    AND (fact.stage_id = bp.stage_id OR bp.stage_id IS NULL)
WHERE bp.deleted_at IS NULL
  AND bc.deleted_at IS NULL
GROUP BY pr.name, s.name, s.order_index, bc.name
ORDER BY pr.name, stage_order, deviation_pct DESC NULLS LAST;


-- ---------------------------------------------------------------------------
-- R-08: ЗАГРУЗКА ПРОРАБА — количество домов на каждом ответственном пользователе
-- ---------------------------------------------------------------------------
-- Показывает: сколько активных домов ведёт каждый прораб (responsible_user_id),
-- распределение по стадиям, средний возраст домов в работе.
-- Допущение: "загрузка" = количество домов в работе (не завершённых стадий).
-- Ограничение: нет таблицы рабочих часов; только количественный показатель.
-- ---------------------------------------------------------------------------
SELECT
    u.id                                                      AS user_id,
    u.email                                                   AS foreman_email,
    COUNT(h.id)                                               AS active_houses_count,
    COUNT(DISTINCT h.current_stage_id)                        AS distinct_stages_count,
    STRING_AGG(DISTINCT s.name, ', ' ORDER BY s.name)        AS stages_list,
    ROUND(
        AVG(
            EXTRACT(DAY FROM (CURRENT_TIMESTAMP - h.created_at))
        )
    )                                                         AS avg_house_age_days
FROM houses h
JOIN users u ON u.id = h.responsible_user_id
LEFT JOIN stages s ON s.id = h.current_stage_id
WHERE h.deleted_at IS NULL
  AND u.deleted_at IS NULL
GROUP BY u.id, u.email
ORDER BY active_houses_count DESC;


-- ---------------------------------------------------------------------------
-- R-09: СРЕДНИЙ СРОК ЭТАПА VS ПЛАН — медиана фактического времени на стадии
--        в сравнении с медианой по проекту (план-суррогат)
-- ---------------------------------------------------------------------------
-- Показывает: какие стадии в среднем затягиваются, а какие идут быстро.
-- Метрика: для завершённых стадий (completed_at IS NOT NULL) считается
-- фактическое время; для текущих — время с started_at по сегодня.
-- "Плановый" срок = медиана завершённых стадий (лучшая оценка без явных норм).
-- Допущение: в схеме нет поля planned_duration_days; при его появлении — заменить.
-- ---------------------------------------------------------------------------
WITH stage_durations AS (
    SELECT
        hsh.stage_id,
        hsh.house_id,
        CASE
            WHEN hsh.completed_at IS NOT NULL
                THEN EXTRACT(DAY FROM (hsh.completed_at - hsh.started_at))::int
            ELSE
                EXTRACT(DAY FROM (CURRENT_TIMESTAMP - hsh.started_at))::int
        END                                                   AS duration_days,
        hsh.completed_at IS NOT NULL                          AS is_completed
    FROM house_stage_history hsh
    JOIN houses h ON h.id = hsh.house_id
    WHERE h.deleted_at IS NULL
)
SELECT
    s.name                                                    AS stage_name,
    s.order_index,
    COUNT(*)                                                  AS total_entries,
    SUM(CASE WHEN sd.is_completed THEN 1 ELSE 0 END)         AS completed_count,
    ROUND(AVG(sd.duration_days))                              AS avg_duration_days,
    ROUND(
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY sd.duration_days
        )
    )                                                         AS median_duration_days,
    ROUND(
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY sd.duration_days
        ) FILTER (WHERE sd.is_completed)
    )                                                         AS median_completed_days,
    MIN(sd.duration_days)                                     AS min_days,
    MAX(sd.duration_days)                                     AS max_days
FROM stage_durations sd
JOIN stages s ON s.id = sd.stage_id
GROUP BY s.id, s.name, s.order_index
ORDER BY s.order_index;


-- ---------------------------------------------------------------------------
-- R-10: КОНТРАКТЫ БЕЗ ОПЛАТ — активные договоры, по которым ещё не было платежей
-- ---------------------------------------------------------------------------
-- Показывает: договоры в статусе 'active', у которых нет ни одного платежа
-- (ни в каком статусе). Это кандидаты на: (а) забытые договоры, (б) старт
-- без аванса, (в) ошибки ввода данных.
-- Сортировка: по сумме договора убыванием — чтобы крупные провалы были вверху.
-- ---------------------------------------------------------------------------
SELECT
    c.number                                                  AS contract_number,
    c.subject                                                 AS contract_subject,
    c.signed_at,
    c.start_date,
    c.end_date,
    c.amount_cents / 100.0                                    AS contract_amount_rub,
    c.status,
    ctr.short_name                                            AS contractor_name,
    ctr.inn                                                   AS contractor_inn,
    COALESCE(h.plot_number, '—')                              AS house_plot,
    s.name                                                    AS contract_stage,
    CURRENT_DATE - c.signed_at                                AS days_since_signed
FROM contracts c
JOIN contractors ctr ON ctr.id = c.contractor_id
LEFT JOIN houses h ON h.id = c.house_id
LEFT JOIN stages s ON s.id = c.stage_id
WHERE c.deleted_at IS NULL
  AND ctr.deleted_at IS NULL
  AND c.status = 'active'
  AND NOT EXISTS (
      SELECT 1
      FROM payments p
      WHERE p.contract_id = c.id
  )
ORDER BY c.amount_cents DESC;
