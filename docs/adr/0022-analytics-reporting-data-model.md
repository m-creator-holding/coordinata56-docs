# ADR 0022 — Analytics & Reporting Data Model

- **Статус**: proposed (ожидает governance)
- **Дата**: 2026-04-18
- **Автор**: backend-director (субагент L2)
- **Утверждающий**: governance-director, затем Владелец (Мартин)
- **Контекст фазы**: M-OS-1 «Скелет», Спринт M-OS-1.3 — Report Builder & Analytics
- **Связанные документы**:
  - ADR 0001 (модель данных v1) — транзакционные таблицы, источник большинства агрегатов
  - ADR 0007 (audit log) — append-only журнал, источник поведенческих событий
  - ADR 0009 (pod-архитектура) — данные принадлежат поду/компании
  - ADR 0011 (Foundation: multi-company, RBAC, crypto audit) — `company_id` во всех объектах, `is_holding_owner`
  - ADR 0017 (Configuration-as-Data, пишется параллельно) — `report_definitions` и `kpi_definitions` как сущности configuration_entity
  - ADR 0020 (Form/Report JSON descriptors, пишется параллельно) — формат описания отчётов, дашбордов, формул
  - `docs/knowledge/construction/03-kpi-catalog.md` — отраслевой каталог 46 KPI (seed)
  - `docs/knowledge/owner-kpi-catalog.md` — конкретные формулы по БД coordinata56 (первичный seed)
  - `docs/m-os-vision.md` §8 (аналитика), §9 (roadmap M-OS-1.3)

> **Forward-references.** На момент написания ADR-0022 ADR 0017 и 0020 находятся в разработке (срок 22 апр.). Ссылки формализуются при утверждении governance. Если к моменту утверждения ADR-0017 или ADR-0020 окажутся несовместимыми по контрактам — ADR-0022 дополняется amendment-ADR, существующий текст не переписывается.

---

## Проблема

M-OS-1.3 вводит Report Builder — конструктор отчётов, дашбордов и KPI для Владельца и Директоров компаний холдинга. По плану (m-os-vision §9) к этому спринту должны быть готовы:

1. Данные, достаточные для вычисления 46 KPI отраслевого каталога и 20+ конкретных метрик `owner-kpi-catalog.md`.
2. Механизм, позволяющий новой роли «аналитик» собирать новые отчёты **без написания кода** — через визуальный конструктор (ADR 0020, JSON-дескриптор).
3. Производительность, приемлемая для типовых запросов Владельца (дашборд «утром перед завтраком» — загрузка ≤2 сек для типовой выборки по одной компании).

Сейчас вся аналитика возможна только через прямые SQL-запросы к транзакционным таблицам. Это создаёт четыре блокирующих риска для M-OS-1.3:

**Риск А — Нет концептуальной модели, что считать как immutable event, что как computed aggregate.** Без этого каждый отчёт будет городить собственные фильтры по `audit_log` или, наоборот, дублировать агрегирование в коде. Через 10 отчётов это превращается в хаос.

**Риск Б — Нет формального каталога KPI.** 46 KPI отраслевого каталога и 20+ из `owner-kpi-catalog.md` описаны текстом. Формула «F2. Отклонение факт/план» живёт в markdown, а не в БД. Когда аналитик хочет добавить KPI через Report Builder — ему негде «зарегистрировать» формулу так, чтобы движок отчётов её понял.

**Риск В — Нет подхода к time-series.** Вопрос «сколько домов было на стадии кровли 15 марта» не решается транзакционными таблицами: `houses.current_stage_id` хранит только текущее значение. Без явного решения по снимкам времени KPI типа «готовность посёлка по неделям» будет либо невозможен, либо сделан через дорогие `audit_log` replay при каждом запросе.

**Риск Г — Нет плана производительности.** Типовой запрос Владельца — «дашборд по одной компании за квартал» — это ~100 тысяч строк payments и ~50 тысяч audit_log. Без индексной стратегии, решения о materialized views и кешировании эти запросы на pgsql без подготовки дают 5–15 секунд отклика. Это убивает UX конструктора.

---

## Контекст

**Что уже есть:**
- Транзакционные таблицы ADR 0001: `houses`, `contracts`, `payments`, `material_purchases`, `house_stage_history`, `budget_plan` и др.
- `audit_log` (ADR 0007): append-only, crypto-chain (ADR 0011), содержит все write-операции с `changes_json`.
- `company_id` во всех объектах (ADR 0011) — обязательный scope любого запроса.
- Pod-архитектура (ADR 0009): cottage-platform-pod сейчас единственный; будущие поды (gas-stations, metal-works) будут иметь собственные предметные таблицы.

**Что сейчас отсутствует:**
- Формальный каталог KPI в БД.
- Разделение «immutable events vs computed aggregates».
- Time-series поддержка для метрик по состоянию объектов на дату X.
- Индексная стратегия под аналитические запросы (сейчас индексы оптимизированы под транзакционные: FK, unique-поля).
- Кеширующий слой.

**Ограничения со стороны других ADR:**
- ADR 0011: любой аналитический запрос обязан включать `WHERE company_id = ?` (исключение — `is_holding_owner`).
- ADR 0007: `audit_log` — append-only, никаких UPDATE/DELETE. Любое «изменение» event трактуется как новый event.
- ADR 0009: аналитика ядра не должна знать о внутренностях pod-ов; pod-ы публикуют свои метрики через общий контракт.
- ADR 0017 (ожидается): `report_definitions` и `kpi_definitions` — это `configuration_entity`, значит версионируются и редактируются через admin-UI.
- ADR 0020 (ожидается): формат описания отчёта — JSON-дескриптор с полями `data_source`, `filters`, `aggregations`, `visualization`.

**Что должно быть на выходе ADR-0022:**
1. Решение о разделении event-sourced vs materialized.
2. Схема таблиц `kpi_definitions` и `kpi_values` (или эквивалент).
3. Правила time-series: какие сущности получают `valid_from/valid_to`, какие остаются snapshot.
4. Индексная стратегия и решение о кеше.
5. Контракты интеграции с ADR 0017 и 0020.

---

## Рассмотренные альтернативы

### Вариант A: Полная event-sourcing архитектура

Все изменения состояния системы — от создания Contract до смены стадии дома — записываются в `business_events` (новая таблица), а transactional tables становятся лишь денормализованной проекцией. Все отчёты строятся через replay событий или materialized views поверх `business_events`.

**Плюсы:**
- Идеальная ретроактивность: любой отчёт за любую дату считается точно.
- Естественная поддержка audit (события **есть** аудит).
- Time-travel «из коробки».

**Минусы:**
- Требует переписать весь существующий код сервисов: сервисы работают с транзакционными моделями напрямую (ADR 0004, ADR 0011), переход на event-sourcing — переписывание ~45 сервисов.
- Рост объёма: каждая операция — запись в 2 места (event + проекция). При обильных изменениях `budget_plan` это удваивает нагрузку.
- Производительность чтения: любой отчёт требует либо materialized view (и мы вернулись к той же проблеме кеша), либо replay (секунды на запрос).
- Переписывание всех write-сервисов заблокирует M-OS-1.1 и M-OS-1.2.

**Почему отклонено:** несоизмеримо дорого для MVP холдинга. Event-sourcing имеет смысл когда требования к аудитируемости или time-travel превышают стоимость переделки всех сервисов. У нас стоимость переделки — несколько месяцев работы, а требования покрываются комбинацией `audit_log` + snapshot-таблиц + time-series на отдельных сущностях. ADR 0007 уже дал event-like журнал, дублировать его полноценным event-sourcing-ом не нужно.

---

### Вариант B: Только transactional + ad-hoc SQL для отчётов

Не создаём никаких новых структур. Report Builder пишет SQL-запросы к транзакционным таблицам напрямую, используя JSON-дескриптор как генератор SQL.

**Плюсы:**
- Ноль новых таблиц, ноль миграций.
- Прямая правда: данные в транзакционных таблицах всегда актуальны.

**Минусы:**
- Отсутствует time-series: нельзя ответить на вопрос «сколько домов на стадии кровли 15 марта». `houses.current_stage_id` хранит только текущее; для исторических состояний нужен `house_stage_history`, но для `payments.status` истории нет — только `audit_log` как косвенный источник.
- Отсутствует каталог KPI: каждый отчёт хранит формулу внутри своего JSON-дескриптора. Переиспользовать «F2 Отклонение факт/план» в 5 отчётах — это 5 копий формулы. Если меняем формулу — меняем в 5 местах.
- Производительность: типовой дашборд Владельца делает 10+ подзапросов. Без предварительной агрегации на средней нагрузке (30 компаний × 100 тыс. records) это 10–30 сек отклика.
- Конфликт с принципом 10 ADR 0008 (Configuration-as-data): KPI — это конфигурация, она должна жить в данных, не внутри других сущностей.

**Почему отклонено:** блокирует P1 (time-series) и P2 (каталог KPI) из scope ADR-0022. Такой Report Builder не масштабируется за пределы 10–15 отчётов.

---

### Вариант C (выбран): Гибрид — immutable events в `audit_log` + каталог KPI в БД + выборочные snapshot/time-series + materialized views для тяжёлых агрегатов

Разделяем три слоя ответственности:

1. **Источники истины (source of truth)** — существующие транзакционные таблицы (ADR 0001) + `audit_log` (ADR 0007). Ничего не переписываем.
2. **Каталог метрик** — новые таблицы `kpi_definitions`, `report_definitions`, `dashboard_definitions` (все — configuration_entity по ADR 0017). Формула KPI хранится как JSON-дескриптор (ADR 0020).
3. **Кеш вычислений** — таблица `kpi_values` (computed aggregates) + при необходимости materialized views по pgsql. Пересчёт — по расписанию (scheduled) для периодических KPI и on-read с кешем для ad-hoc.
4. **Time-series** — избирательно: только для сущностей, у которых историческое состояние на дату X — бизнес-требование. Остальные — snapshot (текущее значение).

**Плюсы:**
- Не переписываем существующий код.
- Формула KPI — одна на весь холдинг, редактируется через admin-UI (ADR 0017).
- Time-series там, где он реально нужен; остальное — дёшево.
- Производительность: тяжёлые KPI предвычислены в `kpi_values`, лёгкие — on-read.
- Совместимость с ADR 0017 (каталог как config), ADR 0020 (формула — JSON-дескриптор), ADR 0011 (`company_id` в каждой строке `kpi_values`).

**Минусы:**
- Нужно честно решить для каждого KPI: on-read, on-write или scheduled. Это не автоматический выбор, требует явной мысли аналитика при регистрации KPI.
- Рассинхронизация: `kpi_values` может «опаздывать» от транзакционных таблиц. Нужно явно выставлять `computed_at` и показывать пользователю возраст данных.
- Сложнее, чем Вариант B: 3 новых сущности вместо 0.

---

### Вариант D: Отдельная OLAP-база (ClickHouse / DuckDB / ETL в data warehouse)

Ставим отдельный OLAP-storage (ClickHouse embedded или DuckDB). Раз в сутки — ETL из postgres в OLAP. Report Builder ходит только в OLAP.

**Плюсы:**
- Производительность OLAP на порядки выше на аналитических запросах.
- Классическая Kimball / Inmon архитектура, проверенная индустрией.

**Минусы:**
- Новый инфраструктурный компонент: ClickHouse в проде, мониторинг, бэкапы, обновления.
- ETL-lag: данные в OLAP отстают от OLTP минимум на час. Запрос Владельца «посмотри что сейчас с остатком средств» даёт устаревшее число.
- Удвоение схемы: при каждом изменении ADR-0001 / ADR-0011 — параллельное изменение OLAP-схемы и ETL.
- Несовместимо с масштабом MVP: 30 компаний × 100 тыс. рядов — это масштаб, на котором postgres 16 с правильными индексами справляется за миллисекунды. ClickHouse нужен при миллиардах строк, не при миллионах.

**Почему отклонено:** преждевременная оптимизация. При росте до объёмов, где postgres не тянет (≥10 GB / ≥100 млн строк в аналитических таблицах), возврат к этому варианту будет обсуждаться отдельным ADR в M-OS-3 или M-OS-4.

---

## Решение

Принимается **Вариант C (гибрид)**. Далее — конкретика по пяти частям scope.

### Часть 1. Что хранится как immutable event, что как computed aggregate

**Immutable events (source of truth, не пересоздаются):**
- Всё, что уже есть в транзакционных таблицах ADR 0001 (`payments`, `contracts`, `houses`, `house_stage_history`, `material_purchases`, `budget_plan`, `house_configurations`).
- `audit_log` (ADR 0007) — крипто-заверённый журнал изменений.
- Новой таблицы `business_events` **не вводим** на M-OS-1. Вопрос её введения поднимается отдельным ADR в M-OS-2, если появится требование, которое не закрывается комбинацией `audit_log` + транзакционные таблицы.

**Computed aggregates (кеш вычислений, допускается пересчёт):**
- Таблица `kpi_values` — конкретные вычисленные значения KPI на дату.
- Postgres materialized views — для тяжёлых агрегатов (типа «сводка по 85 домам × 11 стадий × 20 статей бюджета»).
- Redis-кеш — для on-read запросов в горизонте ≤5 минут.

**Правило определения слоя.** При регистрации новой формулы KPI аналитик обязан выбрать один из трёх режимов пересчёта (см. Часть 4) и указать его в `kpi_definitions.recompute_mode`. Дефолт — `scheduled` (раз в сутки в 3:00 по часовому поясу компании).

---

### Часть 2. Каталог KPI и отчётов — data layer

Вводятся четыре новые таблицы (все — `configuration_entity` по ADR 0017, все — `company_id`-scoped по ADR 0011, за исключением holding-wide каталогов).

#### 2.1. `kpi_definitions` — определение метрики

```
kpi_definitions:
  id:                int (PK, autoincrement)
  code:              str(64), NOT NULL
                     -- человекочитаемый код: "F2_budget_variance", "G1_readiness"
                     -- unique в рамках (company_id, code)
  name:              str(255), NOT NULL
                     -- "Отклонение факт/план, руб."
  description:       text | None
                     -- развёрнутое описание, для tooltip в UI
  company_id:        int | None, FK → companies.id
                     -- NULL = holding-wide (виден во всех компаниях; редактируется
                     --        только holding_owner)
                     -- int = принадлежит конкретной компании
  formula:           jsonb, NOT NULL
                     -- JSON-дескриптор формулы по ADR 0020 (см. §2.5)
  data_source:       str(64), NOT NULL
                     -- "payments" | "contracts" | "houses" | "audit_log" | ...
                     -- основная таблица-источник; для валидации прав аналитика
  aggregation_period: enum(day, week, month, quarter, year, project_lifetime), NOT NULL
                     -- по какому периоду агрегируется значение
  unit:              str(32), NOT NULL
                     -- "RUB" | "%" | "pcs" | "days" | "m2" | "RUB_per_m2"
  recompute_mode:    enum(on_read, on_write, scheduled), NOT NULL
                     -- см. Часть 4
  schedule_cron:     str(64) | None
                     -- crontab, только если recompute_mode=scheduled
  benchmark_min:     numeric(20,4) | None
                     -- нижняя граница нормы (для цвета в UI)
  benchmark_max:     numeric(20,4) | None
                     -- верхняя граница нормы
  alert_condition:   jsonb | None
                     -- условие алерта ("value > benchmark_max * 1.1")
  created_at:        timestamptz, NOT NULL, server_default=now()
  created_by:        int, FK → users.id, NOT NULL
  updated_at:        timestamptz, NOT NULL, server_default=now(), onupdate=now()
  is_active:         bool, NOT NULL, default=True

  UNIQUE (company_id, code)  -- partial: WHERE company_id IS NOT NULL
  UNIQUE (code) WHERE company_id IS NULL  -- holding-wide уникальность
```

**Seed при миграции.** 46 KPI из `docs/knowledge/construction/03-kpi-catalog.md` загружаются как holding-wide (`company_id=NULL`). 20+ конкретных KPI из `owner-kpi-catalog.md` — тоже seed, но с `company_id=1` (дефолтная компания холдинга из ADR 0011 §1.5).

#### 2.2. `kpi_values` — вычисленные значения

```
kpi_values:
  id:            int (PK, autoincrement)
  kpi_id:        int, FK → kpi_definitions.id, NOT NULL
  company_id:    int, FK → companies.id, NOT NULL
                 -- для holding-wide KPI значение вычисляется per-company
                 -- (одна kpi_definition → N строк kpi_values по компаниям)
  pod_id:        str(64) | None
                 -- опционально: значение внутри конкретного pod (ADR 0009)
  period_start:  date, NOT NULL
  period_end:    date, NOT NULL
  value:         numeric(20,4), NOT NULL
                 -- основное число; для % хранится как 85.23, не 0.8523
  value_details: jsonb | None
                 -- для метрик, возвращающих более одного числа (top-5, distribution)
  computed_at:   timestamptz, NOT NULL, server_default=now()
  source_hash:   str(64) | None
                 -- SHA-256 от формулы + границ периода + company_id, для идемпотентности
                 -- пересчёта и обнаружения устаревших кешей

  UNIQUE (kpi_id, company_id, pod_id, period_start, period_end)
  INDEX (company_id, kpi_id, period_end DESC)  -- типовой запрос "последние значения"
```

При пересчёте KPI — **не DELETE + INSERT**, а `INSERT … ON CONFLICT (kpi_id, company_id, pod_id, period_start, period_end) DO UPDATE SET value=EXCLUDED.value, value_details=EXCLUDED.value_details, computed_at=now(), source_hash=EXCLUDED.source_hash`. Это идемпотентно и сохраняет PK для FK-ссылок (если будут).

#### 2.3. `report_definitions` — определение отчёта

```
report_definitions:
  id:            int (PK)
  code:          str(64), NOT NULL
  name:          str(255), NOT NULL
  description:   text | None
  company_id:    int | None, FK → companies.id
                 -- NULL = holding-wide, int = per-company
  descriptor:    jsonb, NOT NULL
                 -- JSON-дескриптор отчёта по ADR 0020: фильтры,
                 -- столбцы, группировки, визуализация
  kpi_ids:       int[] | None
                 -- массив id из kpi_definitions, используемых в отчёте
                 -- для валидации прав аналитика и бустинга кеша
  access_roles:  str[] | None
                 -- список role_template, которым отчёт доступен
                 -- NULL = доступен всем с правом 'report.read'
  created_at:    timestamptz, NOT NULL, server_default=now()
  created_by:    int, FK → users.id, NOT NULL
  updated_at:    timestamptz, NOT NULL, server_default=now(), onupdate=now()
  is_active:     bool, NOT NULL, default=True

  UNIQUE (company_id, code)
```

#### 2.4. `dashboard_definitions` — набор отчётов на одном экране

```
dashboard_definitions:
  id:            int (PK)
  code:          str(64), NOT NULL
  name:          str(255), NOT NULL
  company_id:    int | None, FK → companies.id
  layout:        jsonb, NOT NULL
                 -- JSON-дескриптор: сетка, позиции report_id на экране,
                 -- refresh_interval по каждому виджету
  owner_id:      int | None, FK → users.id
                 -- личный дашборд пользователя; NULL = публичный для company_id
  created_at:    timestamptz, NOT NULL, server_default=now()
  created_by:    int, FK → users.id, NOT NULL
  updated_at:    timestamptz, NOT NULL, server_default=now(), onupdate=now()
  is_active:     bool, NOT NULL, default=True

  UNIQUE (company_id, code)
```

#### 2.5. Связь с ADR 0020 (JSON-дескриптор формулы)

Поле `kpi_definitions.formula` — это JSON-дескриптор формата, определённого ADR 0020. На момент написания ADR-0022 контракт ADR-0020 ещё не утверждён; минимальный ожидаемый интерфейс:

```json
{
  "version": 1,
  "type": "ratio",                  // "ratio" | "sum" | "count" | "avg" | "custom"
  "numerator": {
    "source": "payments",
    "aggregation": "sum",
    "field": "amount_cents",
    "filters": [
      {"field": "paid_at", "op": "between", "params": ["@period_start", "@period_end"]},
      {"field": "status",  "op": "in",      "params": ["approved"]}
    ]
  },
  "denominator": {
    "source": "budget_plan",
    "aggregation": "sum",
    "field": "amount_cents",
    "filters": [
      {"field": "house_id", "op": "in_project", "params": ["@project_id"]}
    ]
  },
  "post": {"multiply": 100}          // (numerator / denominator) * 100 = %
}
```

Важно: ADR-0022 не фиксирует синтаксис дескриптора полностью — это зона ответственности ADR-0020. Здесь фиксируется только требование: «поле `formula` — валидный дескриптор по ADR-0020 на момент вставки, проверяется через JSON Schema в сервисном слое до записи».

**При разрыве контракта ADR-0020 и ADR-0022** (ADR-0020 меняет формат дескриптора после утверждения ADR-0022) — миграция `kpi_definitions.formula` делается отдельным ADR amendment, существующие значения конвертируются backfill-скриптом.

---

### Часть 3. Time-series vs snapshot

Делим все аналитически-значимые атрибуты на три класса.

**Класс TS-1: собственная time-series таблица (_history).**

Атрибут меняется часто (≥1 раза в неделю), исторические состояния нужны для бизнес-отчётов за произвольную дату в прошлом.

Примеры на M-OS-1:
- `houses.current_stage_id` — уже хранится в `house_stage_history` (ADR 0001). Не трогаем.
- `payments.status` — для KPI «оплачено/одобрено/отклонено по неделям» нужна история. На M-OS-1 источник — `audit_log`, выборка по `entity_type='Payment' AND action='update' AND changes_json ? 'status'`. Если эта выборка станет узким местом (замер после первой волны отчётов M-OS-1.3) — вводится `payment_status_history` отдельным ADR amendment.
- `contracts.status` — аналогично через `audit_log`. Отдельная таблица — только при реальной необходимости.

Правило: **не создаём новые _history таблицы преждевременно.** Стартуем с `audit_log` как источник истории. Создаём _history только когда (а) замер показал ≥500ms на типовом запросе, (б) запрос встречается ≥3 раз в активных report_definitions.

**Класс TS-2: `valid_from / valid_to` на самой сущности (slowly changing dimension, SCD type 2).**

Атрибут меняется редко (≤1 раза в месяц), исторические состояния нужны для отчётов.

Примеры: справочники (`option_catalog.base_price_cents`, `stages.duration_days`), конфигурация компании (`company_settings`), матрица прав (`role_permissions` из ADR 0011).

На M-OS-1: **не вводим SCD type 2 сейчас.** Для справочников на текущем горизонте достаточно `audit_log`. SCD type 2 вводится отдельным ADR, если появится требование «покажи price_list который действовал на дату X» в Report Builder.

**Класс TS-3: snapshot (текущее значение).**

Атрибут интересен только в текущем состоянии. История не нужна или малоценна.

Примеры: `users.email`, `users.full_name`, `contractors.inn`, `companies.short_name`.

Для отчётов за прошлое время используем snapshot **на момент запроса отчёта** (современное значение атрибута). Для бизнеса это допустимо: если подрядчик сменил имя, в старом отчёте показываем текущее имя как «поставщик по договору №...», но сумму и даты — исторические.

**Правило определения класса при проектировании новой сущности.** В M-OS-1.3 при регистрации нового KPI, требующего time-series данных, которых ещё нет — аналитик эскалирует через backend-director: нужен ли отдельный _history, SCD type 2, или достаточно `audit_log`. Решение фиксируется в `kpi_definitions.description`.

---

### Часть 4. Ретроактивные правки данных и режимы пересчёта

Три режима пересчёта `kpi_definitions.recompute_mode`:

**`on_read`** — значение вычисляется в момент запроса отчёта. Результат кладётся в Redis с TTL 60 секунд.

- Применяется для лёгких KPI (≤100ms на запрос).
- Плюс: всегда актуально (в пределах 60 сек).
- Минус: нагрузка на каждый просмотр.

**`on_write`** — значение пересчитывается синхронно внутри транзакции, изменившей source data. Реализуется через event listener на уровне сервиса (не ORM, см. ADR 0007 §Вариант D).

- Применяется для критичных KPI, где отставание недопустимо (F7 «Остаток денежных средств» после каждого платежа).
- Плюс: 100% актуальность.
- Минус: нагрузка на write-операцию (латентность endpoint + 5–20ms за KPI).
- Ограничение: максимум **3 `on_write` KPI на одну сущность**. Если больше — Директор обязан перевести часть в `scheduled`.

**`scheduled`** (дефолт) — значение пересчитывается по расписанию (`schedule_cron`).

- Применяется для большинства KPI.
- Плюс: нет нагрузки на transactional path.
- Минус: отставание в пределах периода (ежедневный KPI — до 24 часов устаревания).
- Реализуется через cron-job в backend-worker (выбор конкретного планировщика — отдельная задача M-OS-1.3, APScheduler или Celery Beat).

**Ретроактивные правки.** Если данные в источнике исправлены задним числом (redated payment, изменённая сумма contract) — все зависимые `kpi_values` с `period_start ≤ updated_at ≤ period_end` помечаются как stale и пересчитываются по следующему запуску планировщика. Обнаружение stale — по `source_hash`: если хеш текущих входов не совпадает с `kpi_values.source_hash`, значение считается устаревшим.

**Публичный контракт возраста данных.** Каждый отчёт в API-ответе возвращает `kpi_values.computed_at`. UI показывает «обновлено N минут назад». Для `on_write` KPI это значение совпадает с `updated_at` источника ±1 сек; для `scheduled` — может отставать на период.

---

### Часть 5. Производительность

#### 5.1. Индексы

Обязательные индексы для аналитических таблиц (включаются в миграцию Part 2):

```
kpi_values:
  INDEX (company_id, kpi_id, period_end DESC)   -- "последние N значений KPI X в компании Y"
  INDEX (company_id, period_end) WHERE computed_at IS NOT NULL  -- "все KPI компании за период"

report_definitions:
  INDEX (company_id, is_active) WHERE is_active = TRUE
  GIN INDEX ON kpi_ids   -- "какие отчёты используют этот KPI" (для инвалидации)

dashboard_definitions:
  INDEX (company_id, owner_id, is_active) WHERE is_active = TRUE
```

Дополнительные индексы на существующие таблицы (отдельной миграцией для ADR-0022):

```
payments:
  INDEX (company_id, paid_at, status)   -- типовой финансовый срез "за период по статусу"
  INDEX (company_id, contract_id, paid_at)

contracts:
  INDEX (company_id, status, end_date)  -- просроченные/активные договоры

audit_log:
  INDEX (company_id, entity_type, timestamp DESC)  -- time-travel по сущности в компании
  GIN INDEX ON changes_json              -- поиск по содержимому changes
```

Все индексы на существующие таблицы создаются через `CREATE INDEX CONCURRENTLY` для избежания блокировки write-операций на проде (см. ADR 0013).

#### 5.2. Materialized views

Для тяжёлых агрегатов (план/факт по 85 домам × 11 стадий × 20 статей) — postgres materialized views. Рефреш — через тот же планировщик, что и `scheduled` KPI.

На M-OS-1.3: **создаются по необходимости,** по результатам замеров. Кандидаты (предположительно):
- `mv_budget_plan_fact_per_house_stage` — план/факт на уровне (house_id, stage_id, category_id).
- `mv_house_current_state` — текущее состояние дома (stage, подрядчики, процент готовности).

Каждая materialized view регистрируется как `data_source` в `kpi_definitions` наравне с обычной таблицей. Фактическое создание — отдельная задача M-OS-1.3 через db-engineer.

#### 5.3. Кеш

**Redis** — для on_read KPI и типовых дашбордов. TTL:
- `on_read` KPI — 60 сек.
- Дашборд целиком (полный JSON ответа /dashboards/{id}) — 30 сек.
- Каталог KPI/отчётов (редко меняется) — 5 минут, инвалидация по событию update в `configuration_entity`.

Redis на M-OS-1 — **обязательный компонент** (уже планируется в ADR 0011 §2.3 для user_context). ADR-0022 расширяет его использование.

**In-memory кеш backend-процесса** — не используем. Причина: multi-process (gunicorn/uvicorn workers) даёт рассинхронизацию, это хуже чем ходить в Redis.

#### 5.4. Read replicas

На M-OS-1 **не вводятся.** Причина: нагрузка холдинга на MVP не требует (30 компаний × максимум 10 активных пользователей = ~300 concurrent sessions, что postgres single-primary тянет). Вопрос read replicas возвращается в M-OS-2, когда (а) появляются реальные замеры, (б) реплика оправдана операционно (HA, а не только чтение).

#### 5.5. Пагинация

Все API-эндпоинты отчётов используют envelope ADR 0006 (`items/total/offset/limit`), `limit` клиппится к 200. Для экспорта больших отчётов (>200 строк) — отдельный эндпоинт `/reports/{id}/export` с streaming-ответом (CSV/XLSX), не постраничный.

**Total для тяжёлых запросов.** `SELECT COUNT(*)` на join-ах из 4+ таблиц может стоить 500ms+. Компромисс: для отчётов с кешированным результатом — `total` берётся из кеша (точный). Для on-read live-запросов — возвращается `total_approx` с флагом `is_approximate=true` (через `pg_class.reltuples` или `EXPLAIN estimate`), если запрос превышает 200ms на COUNT.

---

## Диаграмма

```
┌───────────────────────────────────────────────────────────────────┐
│                          ОБЩЕЕ ЯДРО                                │
│                                                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                  Источники истины (SoT)                     │  │
│  │                                                              │  │
│  │  [Транзакционные таблицы ADR 0001]   [audit_log ADR 0007]   │  │
│  │  houses, contracts, payments,         append-only,          │  │
│  │  house_stage_history, ...             crypto-chain           │  │
│  └─────────────────────┬───────────────────────────┬────────────┘  │
│                        │                            │               │
│                        ▼                            ▼               │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                Computed layer (кеш вычислений)              │  │
│  │                                                              │  │
│  │   [kpi_values]     [materialized views]     [Redis]          │  │
│  │   идемпотентный    тяжёлые агрегаты         TTL 30–300s     │  │
│  │   upsert по        с plan_refresh           on_read + full  │  │
│  │   (kpi, comp,                               dashboard       │  │
│  │    period)                                                   │  │
│  └─────────────────────┬────────────────────────────────────────┘  │
│                        │                                           │
│                        ▼                                           │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │               Каталог (configuration_entity ADR 0017)       │  │
│  │                                                              │  │
│  │   [kpi_definitions]       [report_definitions]              │  │
│  │   формула = JSON-         descriptor = JSON-                │  │
│  │   дескриптор ADR 0020     дескриптор ADR 0020               │  │
│  │                                                              │  │
│  │   [dashboard_definitions]                                    │  │
│  │   layout = JSON (сетка из report_id)                        │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                    │
│       (всё scoped по company_id согласно ADR 0011)                 │
└───────────────────────────────────────────────────────────────────┘

                  ┌─────────────────────────────┐
                  │   Report Builder UI (FE)    │
                  │   (M-OS-1.3)                │
                  └─────────────────────────────┘
                           │  создаёт / редактирует
                           ▼
                  ┌─────────────────────────────┐
                  │   /api/v1/kpi-definitions   │
                  │   /api/v1/report-defs       │
                  │   /api/v1/dashboards        │
                  │   /api/v1/reports/{id}/run  │
                  └─────────────────────────────┘
```

---

## Последствия

### Положительные

**Каталог как данные.** Добавление нового KPI — INSERT в `kpi_definitions`, без деплоя. Редактирование формулы — update. Это делает возможным self-service аналитику уже на M-OS-1.3.

**Ретроспективность без event-sourcing.** Исторические состояния доступны через комбинацию `house_stage_history` (что было) и `audit_log` (что менялось). Для 80% запросов этого достаточно без переделки существующего кода.

**Производительность прогнозируема.** Три режима пересчёта дают явное обязательство системы о времени отклика. `on_write` — мгновенно, `on_read` — до 60 сек отставания (с кешем), `scheduled` — до периода. Пользователь в UI видит «обновлено N минут назад».

**Безопасность.** Все аналитические таблицы включают `company_id`. `is_holding_owner` bypass работает так же, как в ADR 0011. Ни один отчёт не может случайно показать данные чужой компании — это блокируется на уровне `CompanyScopedService` (ADR 0011 §1.3).

**Совместимость с pod-архитектурой.** `pod_id` в `kpi_values` позволяет разделить метрики cottage-platform и будущих gas-stations / metal-works без переделки схемы.

### Отрицательные

**3 новые сущности + 1 таблица значений.** Миграция — 4 таблицы + ~8 индексов + seed из 46+20 KPI. Это крупная миграция, ~1 спринт работы db-engineer + backend-head для M-OS-1.3.

**Каталог KPI требует поддержки.** При изменении транзакционной схемы (новое поле в `payments`, переименование) — ревизия всех `kpi_definitions.formula`, где упоминается это поле. Митигация: CI-job `validate-kpi-formulas` пробегает все активные формулы и проверяет наличие полей в схеме.

**Stale данные в UI.** Для `scheduled` KPI данные могут отставать на период (до 24 часов). Пользователь должен понимать возраст. Митигация: `computed_at` в ответе API и явное отображение в UI.

**Рассинхронизация ADR-0020.** Формат `kpi_definitions.formula` зависит от ADR-0020, который утверждается параллельно. Если формат изменится после утверждения ADR-0022 — нужен backfill-скрипт и amendment-ADR.

---

## Риски

| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| ADR 0020 меняет формат дескриптора после утверждения ADR-0022 | Средняя | Среднее | `kpi_definitions.formula.version` — обязательное поле; backfill-скрипт при изменении версии; CI-валидация формул против актуальной JSON Schema ADR-0020 |
| `scheduled` планировщик пропускает запуск при сбое backend-worker | Средняя | Низкое | Идемпотентный upsert по `source_hash`; при следующем запуске пересчитываются все stale значения |
| `on_write` KPI замедляет критичные transactional endpoints | Низкая | Высокое | Лимит ≤3 on_write KPI на сущность; мониторинг p95 write-endpoints; при превышении 10ms доп. латентности — перевод в `scheduled` |
| Рост `kpi_values` без границы | Высокая на горизонте 2–3 года | Среднее | Партиционирование `kpi_values` по `period_end` (месяц/квартал) — отдельный ADR при >10М строк; retention policy для high-frequency KPI (ежедневный KPI старше 5 лет — агрегировать в месячный и удалять дневные) |
| Аналитик создаёт формулу со SQL-инъекцией через `formula` | Низкая | Критическое | Формула — **декларативный JSON-дескриптор**, не SQL-строка. Движок Report Builder (ADR 0020) компилирует JSON в параметризованный SQL. В `formula` нельзя передать raw SQL |
| Materialized view блокирует таблицы при REFRESH | Низкая | Среднее | Использовать `REFRESH MATERIALIZED VIEW CONCURRENTLY` (требует unique index); запускать в низкую нагрузку (ночь) |
| Redis недоступен, on_read KPI становится медленным | Средняя | Среднее | Graceful degradation: при недоступности Redis — считать on_read без кеша, добавить в ответ warning; отдельный мониторинг Redis uptime |
| Конфликт с ADR 0017 в версионировании configuration_entity | Средняя | Среднее | На момент утверждения ADR-0022 — явная сверка с ADR-0017 контракта `configuration_entity`; все 4 новые таблицы наследуют стандартный интерфейс `is_active`, `created_at`, `updated_at` и версионирование из ADR-0017 |

---

## Definition of Done (DoD) для ADR-0022

- [ ] Governance-комиссия утвердила proposed→approved.
- [ ] Явная сверка ADR-0017 и ADR-0020 по контрактам configuration_entity и JSON-дескриптора — без конфликтов, либо зафиксированы amendment.
- [ ] Миграция db-engineer реализует 4 таблицы (`kpi_definitions`, `kpi_values`, `report_definitions`, `dashboard_definitions`) с полным составом индексов §5.1.
- [ ] Seed-скрипт загружает 46 KPI из `03-kpi-catalog.md` как holding-wide (`company_id=NULL`) и 20+ KPI из `owner-kpi-catalog.md` как per-company (`company_id=1`).
- [ ] Backend-сервис `KpiService` реализует три режима пересчёта (`on_read`, `on_write`, `scheduled`).
- [ ] `KpiValuesRepository` использует идемпотентный `INSERT … ON CONFLICT … DO UPDATE` с проверкой `source_hash`.
- [ ] API-эндпоинты: `CRUD /api/v1/kpi-definitions`, `CRUD /api/v1/report-definitions`, `CRUD /api/v1/dashboards`, `POST /api/v1/reports/{id}/run`, `POST /api/v1/kpis/{id}/recompute` (только owner).
- [ ] Все write-операции вызывают `audit_service.log()` (ADR 0007).
- [ ] Все запросы `CompanyScopedService` (ADR 0011) — нет прямого `SELECT` без `company_id` фильтра.
- [ ] CI-job `validate-kpi-formulas` проверяет все активные формулы против JSON Schema ADR-0020.
- [ ] Round-trip миграции проходит чисто (ADR 0013).
- [ ] Документация: `docs/m-os-vision.md` §8 обновлён с упоминанием ADR-0022; `docs/knowledge/analytics-architecture.md` — новый файл с диаграммой и примерами.
- [ ] Тесты ≥85% покрытия новых сервисов; интеграционный тест «создать KPI → вычислить значение → убедиться в корректности source_hash при повторном запуске».

---

## Открытые вопросы

1. **Выбор планировщика для `scheduled` KPI.** APScheduler (in-process, проще) vs Celery Beat (отдельный worker, сложнее но надёжнее). Решается в M-OS-1.3 по результатам замера нагрузки; ADR-0022 оставляет вопрос открытым.
2. **Партиционирование `kpi_values`.** При какой плотности записей вводим партиции по `period_end`? Ориентировочно — >10 млн строк или >5 лет истории. Точное решение — отдельным ADR при достижении порога.
3. **Audit формул KPI.** Изменение `kpi_definitions.formula` — это изменение метрики, потенциально меняющее смысл всех исторических `kpi_values`. Нужно ли при изменении формулы (а) помечать все связанные `kpi_values` как stale и пересчитывать, (б) создавать новую версию KPI с историей, (в) запрещать изменение после первого вычисления? Рекомендация — вариант (б) через версионирование `configuration_entity` ADR 0017, но финал — после утверждения ADR-0017.
4. **Формат `alert_condition`.** ADR-0022 оставил его как `jsonb` с минимальным контрактом. Полный синтаксис условий (`>`, `<`, `between`, `trend_down`) — зона ответственности ADR-0020 или отдельного ADR по alerts/notifications (предположительно в M-OS-1.2).
5. **Экспорт больших отчётов.** Формат (CSV vs XLSX vs оба), предел по размеру (1 млн строк?), механизм доставки (streaming vs async с email-ссылкой) — отдельная задача M-OS-1.3, не в scope ADR-0022.
6. **Data lineage / provenance.** Нужно ли для каждого `kpi_values.value` хранить ссылки на конкретные входные записи (например, какие `payment.id` вошли в сумму)? На M-OS-1 — не нужно (достаточно `source_hash` для проверки актуальности). В M-OS-2+ — обсуждается как отдельный ADR при появлении требования «покажи из чего сложилось это число».

---

## Что явно не входит в этот ADR

- Полный синтаксис JSON-дескриптора формулы и отчёта — ADR 0020.
- Версионирование `configuration_entity` — ADR 0017.
- ACL на уровне отчёта (row-level security внутри отчёта) — на M-OS-1 покрывается `company_id`-scope; расширенный RLS — отдельный ADR при появлении требования.
- Внешние BI-инструменты (Metabase, Superset) — не используем; Report Builder встроен в M-OS.
- Alerts/notifications по KPI (push в Telegram при алерте) — ADR по alerts в M-OS-1.2.
- Экспорт во внешние системы (1C, Excel с макросами) — отдельные адаптеры через ACL ADR 0014, не зона ADR-0022.
- ML/forecasting — M-OS-3+.

---

## Порядок реализации (рекомендация для M-OS-1.3)

**Шаг 1 — Миграции и seed** (db-engineer + backend-head) — оценка **3–4 дня**:
- Миграция: 4 новые таблицы + индексы по §5.1.
- Индексы на существующие таблицы (payments, contracts, audit_log) через `CREATE INDEX CONCURRENTLY`.
- Seed-скрипт 46+20 KPI.
- Round-trip миграции чистый, CI зелёный.

**Шаг 2 — CRUD API для каталога** (backend-head → backend-dev) — оценка **5–7 дней**:
- CRUD `kpi_definitions`, `report_definitions`, `dashboard_definitions` по эталону ADR 0004.
- Audit log во всех write-операциях.
- RBAC: по умолчанию только `owner` + `holding_owner` могут создавать/редактировать KPI; `accountant` + `construction_manager` — только читать.
- Валидация `formula` через JSON Schema (зависит от ADR 0020).
- Тесты ≥85%.

**Шаг 3 — Вычислительный движок KPI** (backend-head → backend-dev) — оценка **7–10 дней**:
- `KpiService` с тремя режимами `on_read`, `on_write`, `scheduled`.
- Движок компиляции JSON-дескриптора в параметризованный SQL (интерфейс с ADR 0020).
- Идемпотентный upsert `kpi_values` с `source_hash`.
- Endpoint `POST /api/v1/reports/{id}/run`.
- Redis-кеш для `on_read` и full dashboard.
- Тесты на 5 эталонных KPI из каждой группы отраслевого каталога (финансы, производство, качество, безопасность, люди, продажи).

**Шаг 4 — Планировщик `scheduled` KPI** (backend-head + devops) — оценка **3–5 дней**:
- Выбор (APScheduler/Celery Beat), обоснование в отдельной записке.
- Background-процесс пересчёта.
- Мониторинг: метрики запусков, p95 времени пересчёта, алерт на пропуск.

**Шаг 5 — Integration с Report Builder UI** (frontend-director, вне scope backend-director) — оценка **10–14 дней**:
- UI каталога KPI, конструктор отчёта, конструктор дашборда.
- Формат запросов согласуется с ADR 0020 на стыке FE/BE.

**Итого по бэкенду M-OS-1.3: 3–4 недели** (1 спринт для backend-head + поддержка db-engineer и devops). Фронтенд — параллельно.

---

*ADR составлен backend-director (субагент L2) 2026-04-18 в рамках параллельного потока ADR 0017–0022 для M-OS-1. Передаётся governance-director для утверждения. Статус: proposed.*
