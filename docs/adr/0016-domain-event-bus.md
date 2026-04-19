# ADR 0016 — Domain Event Bus: транспорт событий между модулями M-OS

- **Статус**: proposed (черновик на ревью Координатора; не утверждать без governance approval)
- **Дата**: 2026-04-18 (Amendment 2026-04-19)
- **Автор**: architect (субагент-советник)
- **Утверждающий**: governance-director, затем Владелец (Мартин)
- **Контекст фазы**: M-OS-1.1A Foundation Core
- **Связанные документы**:
  - ADR 0008 (определение M-OS) — принцип 10 «разомкнутая архитектура»
  - ADR 0009 (pod-архитектура) — поды не вызывают друг друга напрямую
  - ADR 0011 (Foundation) — multi-company, company_id обязателен во всех бизнес-событиях
  - ADR 0014 (Anti-Corruption Layer) — ссылается на `business_events_bus (ADR-0016)` для инвалидации кеша адаптеров
  - `project_m_os_1_decisions.md` — Решение 3 (два раздельных Event Bus), Решение 14 (ratification gate)
  - `docs/m-os-vision.md` §3.3 (процессный движок BPM в составе ядра)

---

## Проблема

Поды и модули M-OS не могут вызывать методы друг друга напрямую — это нарушило бы изоляцию (ADR 0009). При этом бизнес-события должны пересекать границы подов: оплата в `cottage-platform-pod` запускает шаг BPM-процесса; смена статуса договора инициирует уведомление в Telegram; активация нового адаптера в ACL-слое требует инвалидации кеша (ADR 0014).

Параллельно в M-OS существует отдельный канал: команды к ИИ-субагентам (запустить задачу, остановить процесс, heartbeat, ping). Смешивать их с бизнес-событиями опасно по двум причинам: бизнес-подписчики не должны видеть команды управления агентами (утечка внутренней механики), и наоборот — агент-диспетчер не должен реагировать на бизнес-поток.

Владелец в Решении 3 (msg 1094, 2026-04-17) зафиксировал: два независимых транспорта, разные базовые классы событий, **физически разные таблицы**.

---

## Контекст

**Ограничения стека**: Python 3.12, FastAPI, PostgreSQL 16, Docker. Никакого Kubernetes и оркестраторов уровня production в M-OS-1. Инфраструктура — один сервер, два контейнера (backend, db).

**Принцип минимальной достаточности**: M-OS-1 — скелет одного pod-а, ~85 домов, единицы одновременных пользователей, несколько бизнес-событий в час. Throughput на уровне десятков событий в минуту — предел требований M-OS-1..3.

**Что уже решено Владельцем (Решение 3, msg 1094, project_m_os_1_decisions.md)**:
- `business_events_bus` — бизнес-события (платежи, договоры, приёмки, этапы, изменения конфигурации)
- `agent_control_bus` — команды ИИ-субагентам (task, heartbeat, ping, stop)
- Подписчики бизнес-модулей не видят agent-события, и наоборот
- Бизнес-события привязаны к `company_id` (multi-tenant), команды ИИ — нет (управление агентами cross-company, на уровне платформы)

**Что нужно закрыть данным ADR**:
- Выбор транспортного механизма для обеих шин
- Контракт базовых классов событий
- Гарантии доставки и поведение при сбоях
- Схема данных верхнего уровня — **две отдельные таблицы**
- Путь миграции с текущего состояния (нет шины → есть шина)

---

## Рассмотренные варианты

### Вариант A — Postgres LISTEN/NOTIFY + Outbox Pattern на двух таблицах (рекомендуется)

**Механика.** Публикация события: в той же транзакции, что и бизнес-запись, строка вставляется в соответствующую таблицу (`business_events` или `agent_control_events`). Отдельный фоновый процесс (`OutboxPoller`) читает непрочитанные строки из обеих таблиц, публикует их в PostgreSQL channels через `pg_notify()` (`memos_business` для бизнес-потока, `memos_agent_control` для управления агентами). Подписчики получают уведомление через `LISTEN`. Строка помечается `delivered_at`, удаляется по расписанию (TTL 7 дней для `delivered`, `failed` — бессрочно).

**Transactional outbox** — признанный паттерн для «at-least-once delivery» без внешнего брокера. Событие либо записано в outbox вместе с изменением данных (атомарно), либо не записано вовсе — нет расщепления между «данные изменились» и «событие не ушло». Две отдельные таблицы дают физическую изоляцию двух шин на уровне схемы БД.

**Плюсы**:
- Нулевая новая инфраструктура — PostgreSQL уже есть, уже работает, нет нового сервиса в Docker Compose
- Атомарность «из коробки»: событие записывается в той же транзакции, что и бизнес-данные — невозможно потерять событие при откате
- Полная наблюдаемость: `business_events` и `agent_control_events` — обычные таблицы, доступны для SQL-запросов, дашбордов, отладки; каждую можно независимо исследовать и архивировать
- Физическая изоляция шин на уровне БД: `business_events` имеет `company_id NOT NULL`, `agent_control_events` — нет; ошибочный кросс-запрос невозможен по схеме
- Поддержка at-least-once: если `OutboxPoller` упал после `pg_notify`, при перезапуске он пройдёт по необработанным строкам повторно
- Вписывается в ADR 0013 (миграции Alembic): таблицы создаются стандартными миграциями

**Минусы**:
- LISTEN/NOTIFY — in-memory, не персистентный: если подписчик не подключён в момент `pg_notify`, уведомление теряется. Компенсируется outbox: подписчик при реконнекте читает необработанные строки напрямую из таблицы (polling fallback)
- `pg_notify` имеет ограничение на размер payload: 8000 байт. Крупные payload хранятся в `payload` JSONB, а через notify передаётся только `event_id` + идентификатор таблицы — подписчик делает SELECT по id
- При высокой частоте событий (тысячи/мин) `OutboxPoller` становится узким местом. Для M-OS-1 это не актуально; при переходе к M-OS-3+ — пересмотр в пользу Redis Streams или Kafka

### Вариант B — Redis Streams

**Механика.** Два Redis Stream: `business_events` и `agent_control_events`. Публикация через `XADD`. Consumer groups (`XREADGROUP`) обеспечивают at-least-once на стороне Redis. `XACK` после успешной обработки.

**Плюсы**:
- Персистентный лог, нет проблемы потери при offline-подписчике
- Consumer groups нативно поддерживают параллельную обработку
- Скорость публикации выше, чем у LISTEN/NOTIFY при нагрузке

**Минусы**:
- Новый сервис в Docker Compose: Redis требует настройки, мониторинга, бэкапа, прав
- Нарушается атомарность: транзакция PostgreSQL коммитилась, но `XADD` в Redis — отдельная операция. При сбое между коммитом и публикацией событие теряется навсегда, если не реализован собственный outbox поверх Redis — тогда сложность удваивается
- Данные событий хранятся вне PostgreSQL — нет единого SQL-запроса для аналитики и отладки
- Для масштаба M-OS-1 (десятки событий/час) Redis Streams — явный overkill

**Отклонён для M-OS-1**. При росте до M-OS-3+ (сотни событий/мин, несколько pod-серверов) — пересмотр.

### Вариант C — Синхронные in-process вызовы через EventDispatcher (паттерн Observer)

**Механика.** В памяти Python-процесса — реестр обработчиков. `EventDispatcher.publish(event)` синхронно вызывает всех зарегистрированных подписчиков в том же HTTP-запросе. Ни LISTEN/NOTIFY, ни Redis не нужны.

**Плюсы**:
- Минимальная сложность реализации: один Python-класс, 50 строк
- Нет сетевых операций, нет latency

**Минусы**:
- События живут только внутри одного процесса — горизонтальное масштабирование (два экземпляра backend) делает доставку непредсказуемой
- Нет at-least-once: если обработчик выбросил исключение — событие потеряно, нет механизма повтора
- Нет персистентности: перезапуск процесса = все необработанные события исчезли
- BPM требует надёжной доставки событий (Решение 6: Б2 миграция — «висящие» экземпляры процессов должны продолжать работу); без персистентности BPM невозможен
- **Отклонён**: не масштабируется и не обеспечивает требований BPM.

### Вариант D (отклонён 2026-04-19) — Единая таблица `event_outbox` с дискриминатором `bus`

**Механика.** Одна физическая таблица со столбцом-дискриминатором `bus IN ('business', 'agent_control')`, `company_id` nullable (обязателен для `bus='business'`, пуст для `bus='agent_control'`). `OutboxPoller` фильтрует по `bus` и публикует в разные каналы.

**Плюсы**: одна миграция, один индекс-набор, один TTL-прунер.

**Минусы**:
- Смешивание ответственностей: multi-tenant бизнес-данные и cross-company управление агентами в одной таблице; любая ошибка WHERE-фильтрации даёт утечку между контурами
- `company_id nullable` противоречит ADR 0011 §1 (multi-company Foundation: company_id обязателен для всех бизнес-таблиц)
- Дискриминатор `bus` — runtime-проверка вместо schema-проверки: ошибка подписчика легко обходит изоляцию
- Различная семантика retention (бизнес-события — часть аудита; agent-команды — операционный шум) требует разных политик TTL и индексов — одна таблица плодит `WHERE bus=...` везде
- Прямо противоречит Решению 3 Владельца msg 1094: «две отдельные шины, разные базовые классы, не смешивать»

**Отклонён**. Принят Вариант A с двумя физическими таблицами.

---

## Решение

**Принят Вариант A — Postgres LISTEN/NOTIFY + Outbox Pattern на двух отдельных таблицах.**

Amendment 2026-04-19: ранняя версия ADR-0016 (2026-04-18) предлагала единую таблицу `event_outbox` с дискриминатором `bus`. Это противоречило Решению 3 Владельца (msg 1094): две раздельные шины с разными контрактами. Раздел «Решение» переписан под две физические таблицы.

### Две физически раздельные таблицы

| Шина | Таблица | PostgreSQL channel | Базовый класс | `company_id` |
|---|---|---|---|---|
| Бизнес-шина | `business_events` | `memos_business` | `BusinessEvent` | NOT NULL FK |
| Шина агентов | `agent_control_events` | `memos_agent_control` | `AgentControlEvent` | отсутствует |

Подписчики бизнес-шины регистрируются на channel `memos_business` через `LISTEN` и читают fallback'ом только `business_events`. Диспетчер агентов — на `memos_agent_control` и `agent_control_events`. Между ними нет перекрёстных подписок и нет общих SQL-запросов.

### Схема `business_events`

```sql
CREATE TABLE business_events (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      UUID NOT NULL REFERENCES companies(id),
  event_type      TEXT NOT NULL,          -- 'payment.created' | 'contract.signed' | 'stage.passed' | ...
  aggregate_id    UUID NOT NULL,          -- id основного объекта-источника (Payment, Contract, Stage)
  payload         JSONB NOT NULL,
  subscribers     TEXT[] NOT NULL DEFAULT '{}',  -- имена подписчиков, которым событие предназначено (пусто = broadcast)
  schema_version  SMALLINT NOT NULL DEFAULT 1,
  occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  published_at    TIMESTAMPTZ,            -- когда OutboxPoller выполнил pg_notify
  delivered_at    TIMESTAMPTZ,            -- когда все подписчики подтвердили обработку (или NULL, если ещё идёт)
  retry_count     SMALLINT NOT NULL DEFAULT 0
);

CREATE INDEX ix_business_events_pending ON business_events (company_id, published_at) WHERE published_at IS NULL;
CREATE INDEX ix_business_events_undelivered ON business_events (company_id, delivered_at) WHERE delivered_at IS NULL;
CREATE INDEX ix_business_events_aggregate ON business_events (aggregate_id, event_type);
```

`event_type` — строковый домен (enum-дисциплина на уровне сервиса, не БД-enum, чтобы добавление новых типов шло через код, а не миграцию). Допустимые значения на M-OS-1: `payment.*`, `contract.*`, `stage.*`, `acceptance.*`, `configuration.*`, `adapter.*`. Реестр — `backend/app/core/events/business_types.py`.

`subscribers` — необязательная адресная таргетизация. Пустой массив = broadcast всем подписчикам channel'а. Непустой — явный список имён подписчиков (для сценариев «уведомить только BPM», «уведомить только аудит»).

### Схема `agent_control_events`

```sql
CREATE TABLE agent_control_events (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  command_type    TEXT NOT NULL,          -- 'task.assign' | 'task.cancel' | 'heartbeat' | 'ping' | 'stop'
  target_agent    TEXT NOT NULL,          -- идентификатор субагента: 'backend-director', 'review-head', ...
  payload         JSONB NOT NULL,
  schema_version  SMALLINT NOT NULL DEFAULT 1,
  occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  published_at    TIMESTAMPTZ,
  delivered_at    TIMESTAMPTZ,
  retry_count     SMALLINT NOT NULL DEFAULT 0
);

CREATE INDEX ix_agent_control_events_pending ON agent_control_events (published_at) WHERE published_at IS NULL;
CREATE INDEX ix_agent_control_events_target ON agent_control_events (target_agent, command_type);
```

**`company_id` в этой таблице отсутствует намеренно** — управление агентами происходит на уровне платформы (M-OS), а не юрлица. Heartbeat'ы, ping'и, task-ассайны — cross-company. Это явное отклонение от общего правила ADR 0011 §1, зафиксированное Решением 3 Владельца.

`command_type` — также строковый домен на уровне сервиса (`backend/app/core/events/agent_command_types.py`). M-OS-1 не использует эту таблицу live (см. Шаг 6 пути миграции) — она создаётся в рамках Foundation, но наполняется, начиная с M-OS-1.3/1.4.

### Базовые классы событий

Два раздельных иерархических корня — принципиальное требование Решения 3.

`BusinessEvent` — корень для всех бизнес-событий:
```
BusinessEvent
  event_id:       UUID
  event_type:     str           # 'payment.created', 'contract.signed', ...
  aggregate_id:  UUID
  company_id:     UUID          # обязателен — M-OS multi-company (ADR 0011)
  occurred_at:    datetime
  payload:        dict
  subscribers:    list[str]     # опц. таргетизация
  schema_version: int = 1       # эволюция контракта
```

`AgentControlEvent` — корень для команд субагентам:
```
AgentControlEvent
  event_id:       UUID
  command_type:   str           # 'task.assign', 'heartbeat', 'ping', 'stop'
  target_agent:   str           # идентификатор субагента
  occurred_at:    datetime
  payload:        dict
  schema_version: int = 1
```

`AgentControlEvent` намеренно не содержит `company_id` — зеркально отражает схему таблицы.

### Гарантии доставки

**At-least-once** для обеих шин. Обоснование: M-OS требует, чтобы каждое бизнес-событие было обработано хотя бы один раз (BPM-шаг, уведомление, аудит). Потеря хуже дубликата — дубликат можно идемпотентно проигнорировать (поле `event_id` — ключ идемпотентности на стороне подписчика). Exactly-once гарантии требуют дополнительного координационного слоя, несоразмерного масштабу M-OS-1.

**Механизм повтора**: `OutboxPoller` при каждом цикле запрашивает строки с `published_at IS NULL` или `published_at < now() - interval '5 minutes' AND delivered_at IS NULL` И `retry_count < 5` в **каждой из двух таблиц независимо**. Если `retry_count >= 5` — строка помечается `failed` (отдельный флаг в payload или `failed_at`), алерт в AuditLog.

**Polling fallback**: при восстановлении упавшего подписчика он читает свою таблицу напрямую — бизнес-подписчик делает `SELECT ... FROM business_events WHERE delivered_at IS NULL AND published_at IS NOT NULL AND company_id = ANY($1)`; агент-подписчик — аналогичный запрос к `agent_control_events`. Так ни одно событие не пропускается при offline-подписчике.

### Взаимодействие с ADR 0014 (Anti-Corruption Layer)

ADR 0014 §«Runtime-guard» требует инвалидации кеша адаптеров при изменении их состояния в `integration_catalog`. Механизм: при сохранении изменения в `integration_catalog` сервис пишет событие `adapter.state_changed` в `business_events` с соответствующим `company_id`. `IntegrationAdapter` подписан на `memos_business` и по типу `adapter.state_changed` инвалидирует свой in-memory кеш.

### Взаимодействие с BPM (M-OS-1.3)

BPM-движок является подписчиком `memos_business`. Каждый бизнес-шаг (`contract.signed`, `payment.approved`, `acceptance.passed`) генерирует событие через `business_events`. BPM-движок получает его и продвигает соответствующий экземпляр процесса. Это закладывает фундамент для Решения 6 (Б2 — миграция запущенных экземпляров BPM).

### Расположение в кодовой базе

```
backend/app/core/events/
  base.py                   — BusinessEvent, AgentControlEvent (Pydantic v2)
  business_types.py         — реестр допустимых event_type (домен бизнес-шины)
  agent_command_types.py    — реестр допустимых command_type (домен шины агентов)
  outbox.py                 — OutboxWriter (две реализации: BusinessOutboxWriter, AgentControlOutboxWriter); OutboxPoller (читает обе таблицы независимыми циклами)
  dispatcher.py             — EventDispatcher (publish + subscribe) с разделением по шинам
  channels.py               — константы: CHANNEL_BUSINESS='memos_business', CHANNEL_AGENT_CONTROL='memos_agent_control'
```

---

## Последствия

### Положительные

- Полная атомарность публикации: событие невозможно потерять при откате транзакции
- Нулевая новая инфраструктура в M-OS-1: PostgreSQL уже используется, новых сервисов в Docker Compose не добавляется
- **Физическая изоляция двух шин**: подписчики бизнес-логики не имеют доступа к таблице `agent_control_events` по SQL (можно закрыть на уровне прав БД в будущем); разные PostgreSQL channels — runtime изоляция
- **Явное соответствие multi-company контракту (ADR 0011)**: `business_events.company_id NOT NULL` — schema-level гарантия tenant-scoping; `agent_control_events` — явное cross-company, без нарушения правил бизнес-доступа
- Наблюдаемость: обе таблицы — обычные, запросы в psql, дашборды, аналитика без дополнительных инструментов
- Эволюционируемость контракта: поле `schema_version` в обеих моделях позволяет вводить breaking changes поэтапно
- Прямая поддержка BPM M-OS-1.3: движок подписывается на `business_events` без дополнительной архитектурной работы
- Разные политики retention: бизнес-события можно держать дольше (частично — как аудиторский след), agent-команды — коротко (операционный шум)

### Отрицательные

- `pg_notify` без polling fallback: если подписчик offline в момент notify — он пропустит уведомление. Компенсируется polling fallback (обязателен в реализации)
- Ограничение 8000 байт на payload `pg_notify`: payload в notify должен содержать только `event_id` + имя таблицы, полные данные — в соответствующей таблице. Это ограничение реализации, не контракта
- `OutboxPoller` должен опрашивать **две таблицы** независимо — чуть больше кода, чем единый поллер; компенсируется общим базовым классом `BaseOutboxPoller[T]`
- При горизонтальном масштабировании (два backend-контейнера) `OutboxPoller` должен быть только на одном экземпляре или иметь блокировку через `SELECT ... FOR UPDATE SKIP LOCKED` для каждой таблицы. Для M-OS-1 один контейнер — не актуально; для M-OS-3+ требуется явный пересмотр

### Нейтральные

- Две таблицы создаются отдельными миграциями Alembic по правилам ADR 0013 (сначала `business_events`, затем `agent_control_events`, или одной миграцией — на усмотрение backend-director; важно, чтобы обе прошли round-trip)
- Хранение событий: TTL 7 дней для `delivered` строк в обеих таблицах; `failed` строки хранятся бессрочно до ручного разбора. Возможна разная политика TTL в будущем (agent_control короче).
- Подписчики обязаны реализовывать идемпотентную обработку (использовать `event_id` как ключ)

---

## Риски

| ID | Описание | Вероятность | Последствие | Митигация |
|---|---|---|---|---|
| R1 | Polling fallback не реализован: подписчик пропускает события при рестарте | Средняя | BPM-экземпляры «зависают», уведомления теряются | DoD включает тест на recovery при offline-подписчике для обеих шин |
| R2 | `OutboxPoller` не останавливается корректно при shutdown: двойная обработка события | Средняя | Дубликаты действий (двойное уведомление, двойной BPM-шаг) | Идемпотентность подписчиков обязательна; тест на дубликаты |
| R3 | payload > 8000 байт передаётся через `pg_notify` напрямую | Низкая | Уведомление обрезается, подписчик падает | Линтер-правило: в `pg_notify` передаётся только `event_id` + имя таблицы |
| R4 | Таблицы не очищаются: рост на сотни тысяч строк | Низкая для M-OS-1 | Замедление `OutboxPoller` | Cron-задача удаления `delivered_at < now() - interval '7 days'` отдельно для каждой таблицы |
| R5 | Подписчик случайно читает «чужую» таблицу | Низкая | Утечка agent-команд в бизнес-логику или наоборот | Code review: классы подписчиков привязаны к конкретной таблице через тип события; тест на изоляцию таблиц и channels |
| R6 | Забыли добавить `company_id` в INSERT в `business_events` | Низкая | INSERT падает на NOT NULL (ранний отказ) | Schema-level гарантия — намеренно; отказ лучше, чем tenant-leak |

---

## Путь миграции (Migration Path)

**Состояние сейчас**: шины событий не существуют. Модули общаются либо через прямые вызовы сервисов в одном процессе, либо никак.

**Шаг 1 — Структура (M-OS-1.1A)**: создать таблицы `business_events` и `agent_control_events` миграциями Alembic (одной или двумя — на усмотрение backend-director). Создать базовые классы `BusinessEvent`, `AgentControlEvent`, `BusinessOutboxWriter`, `AgentControlOutboxWriter`. Все тесты проходят, функциональность не изменена — просто появился инструмент.

**Шаг 2 — OutboxPoller (M-OS-1.1A)**: реализовать фоновый цикл с двумя независимыми задачами-опросниками (по одной на таблицу). Добавить LISTEN на оба channel в `startup` FastAPI. Задокументировать graceful shutdown. Тест: отправить событие в `business_events`, убедиться что notify доставлен подписчику на `memos_business`; отдельно — для `agent_control_events`.

**Шаг 3 — Перевод ACL-инвалидации (M-OS-1.1A)**: ADR 0014 требует инвалидации кеша адаптеров. Перевести этот механизм на `business_events` (тип `adapter.state_changed`). Убрать прямой вызов, если он был.

**Шаг 4 — Первые бизнес-события (M-OS-1.1B)**: при реализации `company_settings` и Configuration-as-Data — события изменения конфигурации публикуются через `business_events` (`configuration.company_setting_changed`, `configuration.bpm_process_updated`).

**Шаг 5 — BPM-подписчик (M-OS-1.3)**: BPM-движок подписывается на `business_events`. Перевод триггеров шагов процесса на события шины.

**Шаг 6 — Agent Control Bus go-live (M-OS-1.3 / 1.4)**: при появлении реальных agent-задач через Telegram (BPM-кнопки) — активировать запись в `agent_control_events` и подписку на `memos_agent_control`. До этого таблица и channel существуют, но не наполняются.

---

## DoD для внедрения (M-OS-1.1A)

- [ ] Миграция Alembic: таблица `business_events` (индексы `(company_id, published_at) WHERE published_at IS NULL`, `(company_id, delivered_at) WHERE delivered_at IS NULL`, `(aggregate_id, event_type)`), проходит round-trip по ADR 0013
- [ ] Миграция Alembic: таблица `agent_control_events` (индексы `(published_at) WHERE published_at IS NULL`, `(target_agent, command_type)`), проходит round-trip по ADR 0013
- [ ] Базовые классы `BusinessEvent`, `AgentControlEvent` в `backend/app/core/events/base.py` (Pydantic v2)
- [ ] Реестры `business_types.py`, `agent_command_types.py` — списки допустимых `event_type` / `command_type`
- [ ] `BusinessOutboxWriter.write(event)` и `AgentControlOutboxWriter.write(event)` — атомарная запись в транзакции SQLAlchemy
- [ ] `OutboxPoller` — две фоновые asyncio-задачи (по одной на таблицу); корректный shutdown при `lifespan` FastAPI
- [ ] Constants `CHANNEL_BUSINESS = 'memos_business'`, `CHANNEL_AGENT_CONTROL = 'memos_agent_control'` в `channels.py`
- [ ] Тест: событие, записанное в `business_events`, доставляется LISTEN-подписчику `memos_business`; зеркальный тест для `agent_control_events`
- [ ] Тест изоляции: подписчик `memos_business` не получает события из `agent_control_events` (и наоборот); SQL-запрос подписчика к «чужой» таблице не используется
- [ ] Тест multi-tenant: `business_events` INSERT без `company_id` падает на NOT NULL constraint
- [ ] Тест: polling fallback — событие обрабатывается при рестарте подписчика после его offline-периода (обе шины)
- [ ] Тест: дубликат `event_id` игнорируется подписчиком (идемпотентность)
- [ ] Задача очистки зарегистрирована в планировщике (TTL 7 дней для `delivered` строк в обеих таблицах)

---

*Черновик подготовлен architect (субагент-советник) 2026-04-18. Статус: proposed. Требует ревью Координатора и governance approval перед переходом в accepted. Не является основанием для начала реализации без ratification gate (Решение 14, Решение 20).*

---

**Amendment 2026-04-19 (Владелец msg 1552)** — переписано под Решение 3 от msg 1094 (две отдельные шины: `business_events` с NOT NULL `company_id` и `agent_control_events` без `company_id`). Ранняя редакция предлагала единую таблицу `event_outbox` с дискриминатором `bus`, что противоречило Решению 3. Amendment без новой ratification — уточнение соответствия original решению Владельца; статус `proposed` сохранён (финальный ratify — governance-director + Владелец согласно Решению 14/20). Решающий amendment-редакции — `governance-auditor` (backup-mode), запись в CHANGELOG 2026-04-19.
