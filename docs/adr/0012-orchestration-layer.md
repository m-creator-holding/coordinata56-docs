# ADR 0012 — Orchestration Layer: переход Координатора из data plane в control plane

- **Статус**: черновик (ожидает утверждения governance-комиссии)
- **Дата**: 2026-04-16
- **Автор**: Архитектор (субагент `architect`, Claude Code)
- **Контекст фазы**: M-OS-1 «Скелет», инфраструктура управления субагентами
- **Связанные документы**:
  - ADR 0009 (pod-архитектура, event bus)
  - ADR 0010 (таксономия субагентов)
  - ADR 0011 (foundation RBAC — PostgreSQL уже присутствует)
  - docs/agents/regulations_addendum_v1.6.md (паттерн «Координатор-транспорт»)
  - docs/m-os-vision.md §9 (roadmap)

---

## Контекст

Система управления субагентами M-OS работает по паттерну «Координатор-транспорт» (регламент v1.6): единственный агент, способный технически вызывать субагентов через инструмент `Agent`, — это Координатор (main-session). Это следствие жёсткого ограничения платформы Claude Code: «subagents cannot spawn other subagents» (Anthropic docs, 2026-04-16).

На масштабе одного пода (cottage-platform, Фазы 1–3) паттерн работает: 6–8 Agent-вызовов на задачу M-размера выполнимы вручную. Координатор тратит ~80% токенов на транспорт — дословный перенос брифов и результатов между уровнями иерархии.

---

## Проблема

При росте до пяти подов и 10+ параллельных задач Координатор-транспорт становится узким горлышком (Риск №1, GPT-аудит). Каждая задача M-уровня требует 6–8 последовательных Agent-вызовов:

```
Coordinator → Director (brief) → Head (instructions) → Worker (execute)
  → Head (review) → Director (verdict) → Reviewer (independent) → Commit
```

При 5 подах и 3 задачах на под одновременно Координатор вынужден держать в голове 15+ активных цепочек, переключаясь между ними. Управленческие функции вытесняются транспортными. Токенный бюджет Координатора расходуется на передачу данных, а не на принятие решений.

Конкретные проявления:
- Задержка до первого Agent-вызова Worker'а — несколько минут ожидания (5 стадий до исполнения).
- При сбое на стадии 4 (Head review) вся цепочка перезапускается с начала.
- Состояние цепочки хранится только в оперативной памяти сессии — потеря при разрыве соединения.
- Параллельные Workers не могут стартовать до завершения Head-распределения, хотя технически это независимые вызовы.

---

## Решение

Координатор переходит из **data plane** (ручная передача каждого промпта) в **control plane** (пять управленческих функций):

1. Triage — определить приоритет, направление, маршрут.
2. Выбор маршрута — Director → Head → Worker.
3. Утверждение рамок — scope, files_allowed, done_criteria.
4. Приём эскалаций — события `blocked`, `needs-decision`.
5. Финальный отчёт Владельцу.

Транспорт делегируется внешнему **Orchestration Layer** — Python-сервису на сервере, который берёт на себя механическое прогон артефактов по стадиям state machine.

Логическая иерархия ответственности (Director → Head → Worker) не меняется. Меняется только кто физически нажимает кнопку «вызвать следующего агента».

---

## Компоненты

### 1. TaskPacket — типизированный пакет задачи

Единица передачи между Координатором и Orchestration Layer. Координатор формирует `TaskPacket` один раз, вместо формирования отдельного промпта на каждую стадию.

```python
@dataclass
class TaskPacket:
    task_id: str              # UUID, глобальный идентификатор
    title: str
    priority: str             # P0 / P1 / P2
    department: str           # backend / frontend / governance / ...
    pod: str | None           # cottage_platform / gas_stations / ...
    scope: str                # описание задачи в свободном тексте
    files_allowed: list[str]  # абсолютные пути или glob-паттерны
    files_forbidden: list[str]
    authority_level: str      # XS / S / M / L
    done_criteria: list[str]
    escalation_rules: dict    # условия: когда поднимать Координатора
    required_reviews: list[str]  # роли, обязательные для review
    output_format: str        # structured-report / diff / adr / ...
```

`TaskPacket` — контракт данных, не промпт. Каждое поле проверяется на полноту до передачи в очередь.

### 2. State Machine — переходы задачи

```
CREATED → TRIAGED → DIRECTOR_BRIEFED → HEAD_ROUTED → WORKER_EXECUTING
  → REVIEW → INTEGRATED → REPORTED → CLOSED

(любое состояние) → BLOCKED → NEEDS_OWNER → (resume)
(любое состояние) → FAILED → POSTMORTEM
```

Каждый переход:
- Фиксируется в таблице `task_events` с меткой времени.
- Может иметь guard condition (например, переход `REVIEW → INTEGRATED` только при вердикте `approve` от reviewer).
- При недопустимом переходе — событие `BLOCKED` с диагностикой.

### 3. Task Queue — PostgreSQL таблица

Хранение задач и событий использует PostgreSQL (уже присутствует по ADR 0011). Не вводится новый брокер сообщений — это решение M-OS-2 (ADR 0009 §5, event bus phase 2).

```sql
-- Таблица задач
tasks:
  task_id        uuid PK
  title          text NOT NULL
  priority       text NOT NULL          -- P0/P1/P2
  department     text NOT NULL
  pod            text
  status         text NOT NULL          -- состояния state machine
  authority_level text NOT NULL         -- XS/S/M/L
  payload        jsonb NOT NULL         -- сериализованный TaskPacket
  created_at     timestamptz NOT NULL DEFAULT now()
  updated_at     timestamptz NOT NULL DEFAULT now()
  escalated_at   timestamptz           -- момент перехода в BLOCKED/NEEDS_OWNER

-- Лог событий (append-only)
task_events:
  id             bigserial PK
  task_id        uuid NOT NULL REFERENCES tasks(task_id)
  event_type     text NOT NULL         -- 8 типов из v1.6 §11.3
  from_state     text
  to_state       text
  agent_role     text                  -- кто был вызван
  requested_by   text                  -- логическая делегация
  spawned_by     text                  -- технический запуск (всегда task_router)
  artifact       jsonb                 -- бриф / результат / вердикт
  ts             timestamptz NOT NULL DEFAULT now()
```

Схема совместима с 8-типовой системой событий из регламента v1.6 §11.3 (`task_created`, `delegation_requested`, `agent_spawned`, `result_returned`, `review_requested`, `review_completed`, `memory_written`, `user_reported`).

### 4. Session Manager — вызовы Claude SDK

Session Manager вызывает `claude -p "..." --json` через Agent SDK Python (`claude-code-sdk`, PyPI) от имени каждой роли. Каждый вызов изолирован: своя сессия, свой список `files_allowed`.

Для параллельных Workers — изоляция через Git Worktree: каждый Worker получает отдельную рабочую копию репозитория. По завершению — `git merge` с разрешением конфликтов через Head.

### 5. Artifact Store — передача результатов между стадиями

Результаты каждой стадии (бриф от Director, план от Head, результат Worker, вердикт Reviewer) сохраняются в поле `task_events.artifact` (jsonb). Следующая стадия получает артефакт предыдущей из БД, а не из памяти сессии Координатора.

Это устраняет потерю состояния при разрыве соединения: при перезапуске сервис читает последний `task_events` и продолжает с прерванной стадии.

### 6. Notification Layer — уведомления Координатора

Координатор получает событие только в трёх случаях:
- `TASK_COMPLETED` — готово к отчёту Владельцу.
- `BLOCKED` — кто-то заблокирован, нужно решение.
- `NEEDS_OWNER` — требуется бизнес-решение Владельца.

Уведомление публикуется в event bus (ADR 0009 §5) и доставляется через `EventBus.publish(event)` — интерфейс скрывает транспорт (PostgreSQL queue на M-OS-1, брокер на M-OS-2+).

---

## Что меняется для Координатора

**Было (v1.6, M-уровень):** 6–8 последовательных Agent-вызовов:
```
Coordinator → Director (brief)
Coordinator → Head (instructions)
Coordinator → Worker-1 (execute)
Coordinator → Worker-2 (execute, параллельно)
Coordinator → Head (review)
Coordinator → Director (verdict)
Coordinator → Reviewer (pre-commit)
Coordinator → commit + report
```

**Стало:** 1 вызов создания задачи + ожидание событий:
```
Coordinator: create_task(TaskPacket{...})
  ↓
task_router автоматически прогоняет все стадии state machine
  ↓
Coordinator получает event: TASK_COMPLETED / BLOCKED / NEEDS_DECISION
  ↓
Coordinator: отчёт Владельцу (Telegram)
```

Логическая цепочка ответственности (Director → Head → Worker → Head review → Director verdict → Reviewer) сохраняется полностью. Task Router только физически вызывает каждую роль в правильном порядке.

---

## Диаграмма

```
┌─────────────────────────────────────────────────────────────────┐
│                    CONTROL PLANE                                 │
│                                                                  │
│  Владелец ──► Координатор                                        │
│               │  (triage, маршрут, рамки, эскалации, отчёт)     │
│               │                                                  │
│               │  create_task(TaskPacket)                         │
│               ▼                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                ORCHESTRATION LAYER                          │  │
│  │                                                            │  │
│  │  Task Queue (PostgreSQL tasks / task_events)               │  │
│  │       ↓                                                    │  │
│  │  State Machine ──► CREATED→TRIAGED→DIRECTOR_BRIEFED→...   │  │
│  │       ↓                     ↕ BLOCKED / FAILED             │  │
│  │  Session Manager                                           │  │
│  │  ┌──────────────────────────────────────────────┐         │  │
│  │  │  Director (briefing)  → artifact → DB        │         │  │
│  │  │  Head (routing)       → artifact → DB        │         │  │
│  │  │  Worker-1 (exec)  ─┐  → artifact → DB        │         │  │
│  │  │  Worker-2 (exec)  ─┴► merge via Head         │         │  │
│  │  │  Head (review)        → verdict  → DB        │         │  │
│  │  │  Director (verdict)   → verdict  → DB        │         │  │
│  │  │  Reviewer (pre-commit)→ approve  → DB        │         │  │
│  │  └──────────────────────────────────────────────┘         │  │
│  │       ↓                                                    │  │
│  │  Event Emitter ──► EventBus.publish(event)                 │  │
│  └────────────────────────────────────────────────────────────┘  │
│               │                                                  │
│               ▼  TASK_COMPLETED / BLOCKED / NEEDS_OWNER          │
│          Координатор (control plane resume)                      │
└─────────────────────────────────────────────────────────────────┘

   Git Worktree isolation: Worker-1 ─► /worktree/task-<id>-w1/
                            Worker-2 ─► /worktree/task-<id>-w2/
```

---

## Обратная совместимость

Паттерн v1.6 «Координатор-транспорт» **не отменяется**. Он остаётся рабочим режимом для:
- XS-задач (1 файл, <1 час, 1 Worker) — накладные расходы Router'а не оправданы.
- Ситуаций когда task_router недоступен (деградация) — Координатор переключается на ручной режим.
- Советников (architect, analyst и др.) — они вне иерархии, прямой Agent-вызов.

Выбор режима:
```
authority_level == XS    → паттерн v1.6 (ручной транспорт)
authority_level in S/M/L → task_router (автоматический транспорт)
task_router DOWN         → fallback на v1.6 для любого уровня
```

Иерархия L0–L4 и governance-комиссия для ADR — не меняются.

---

## Фазы реализации

### Phase 1 — Схема данных и state machine (без SDK)
- Таблицы `tasks`, `task_events` в PostgreSQL.
- Python-класс `StateMachine` с переходами и guard conditions.
- `TaskPacket` dataclass с валидацией.
- Цель: проверить, что state machine корректно обрабатывает 8 типов событий.
- Зависимость: PostgreSQL (есть по ADR 0011).

### Phase 2 — Session Manager с Claude SDK
- Интеграция с `claude-code-sdk` (PyPI).
- Каждая роль вызывается через `--json` mode.
- Artifact Store: сохранение/чтение результатов стадий.
- Цель: конец-в-конец прогон одной задачи S-уровня.
- Зависимость: `claude-code-sdk` (найдено R&I).

### Phase 3 — Параллельные Workers через Worktree
- Изоляция Worker-сессий через `git worktree add`.
- Автоматический merge по завершению через Head.
- Цель: 2 Worker'а по одной задаче без конфликтов в файлах.
- Зависимость: Phase 2 завершена.

### Phase 4 — Полная интеграция с event bus и дашбордом
- `EventBus.publish(event)` по каждому переходу state machine.
- Command Center dashboard получает live-события из task_events.
- Retrospective: сравнение «было» vs «стало» по метрике токенов Координатора.
- Зависимость: Phase 3 завершена, event bus M-OS-1 (ADR 0009 §5).

---

## Последствия

### Положительные

**Разгрузка Координатора.** Токенный бюджет тратится на triage и принятие решений, а не на механический перенос брифов. Оценка: с ~80% транспорт → ~20% транспорт при M/L задачах.

**Персистентность состояния.** Состояние цепочки в PostgreSQL. Разрыв сессии — не потеря прогресса. Задача возобновляется с прерванной стадии.

**Наблюдаемость.** `task_events` — полный аудит-трейл каждой задачи: кто вызван, когда, что вернул. Совместимо с дашбордом (v1.6 §11.4).

**Параллельность.** Workers стартуют одновременно (один Agent-message с несколькими tool_calls по v1.6 §7.2). Воркстри-изоляция исключает конфликты.

**Масштабируемость.** При добавлении нового пода или нового типа задачи — добавляется маршрут в `escalation_rules` TaskPacket'а. Код Router'а не меняется.

### Отрицательные

**Новый сервис для поддержки.** `task_router.py` — отдельный компонент с жизненным циклом: деплой, мониторинг, healthcheck. Добавляет операционную сложность.

**Начальная сложность TaskPacket.** Координатор должен правильно заполнить все поля перед созданием задачи. Ошибка в `files_allowed` или `done_criteria` не будет поймана до стадии Worker.

**Latency Phase 1–2.** До реализации Phase 3 параллельные Workers работают последовательно через task_router. Выигрыш по скорости — только с Phase 3.

---

## Риски

| Риск | Вероятность | Влияние | Контрмера |
|---|---|---|---|
| task_router падает — все задачи встают | Средняя | Высокое | Fallback на паттерн v1.6. Healthcheck endpoint. Retry с exponential backoff при transient ошибках |
| Session Manager вызывает Agent с неправильным промптом — Director принимает задачу на исполнение | Средняя | Среднее | Защитный механизм по v1.6 §4.2: Директор обязан отказать. Шаблоны промптов по ролям фиксируются в `task-routing-template.md` |
| Worktree merge конфликт после параллельных Workers | Средняя | Среднее | Head получает оба результата и явно разрешает конфликт как часть стадии review. Задача не переходит в INTEGRATED до чистого merge |
| task_events разрастается — замедляет запросы | Низкая на M-OS-1 | Среднее на M-OS-2+ | Партиционирование по `created_at` при достижении >1M записей. До этого порога — нет действий |
| Claude SDK API изменится — Session Manager ломается | Низкая | Высокое | Слой абстракции `AgentSessionAdapter`: конкретный вызов SDK скрыт за интерфейсом. Замена SDK — без изменений в state machine и task queue |
| Координатор создаёт TaskPacket с неполными `done_criteria` | Высокая | Среднее | Валидация TaskPacket при `create_task()` — обязательные поля не могут быть пустыми. Rejected на входе, не на стадии REVIEW |

---

## Что явно не входит в этот ADR

- Реализация `task_router.py` (продуктивный код) — отдельная задача, передаётся backend-director.
- UI для управления задачами (task management dashboard) — отдельный ADR M-OS-2.
- Интеграция с GitHub Issues — вне scope MVP.
- Выбор брокера сообщений для event bus M-OS-2 — ADR 0009 §5.
- Переход конкретных Директоров в main-session режим — отдельный governance-запрос при достижении критерия >5 параллельных M-задач в направлении (v1.6 §11.6).

---

## Зависимости

| Компонент | Источник | Статус |
|---|---|---|
| `claude-code-sdk` (PyPI) | Anthropic Agent SDK Python | Найден R&I |
| PostgreSQL 16 | ADR 0002, ADR 0011 | Есть в инфраструктуре |
| Git Worktree | Git встроенный | Доступен |
| EventBus интерфейс | ADR 0009 §5 | Определён, реализация — M-OS-1 |

---

*ADR составлен субагентом `architect` (Claude Code) в рамках задачи «Orchestration Layer» (Риск №1, GPT-аудит). Черновик передаётся governance-director для утверждения через стандартную процедуру.*
