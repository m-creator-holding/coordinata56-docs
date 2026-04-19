ultrathink

# Дев-бриф US-05 (Sprint 2) — AgentControlBus: таблица + Pydantic базовый класс + publish

- **Дата:** 2026-04-19
- **Автор:** backend-director (через backend-head при распределении)
- **Получатель:** backend-dev-2 (ведущий) + db-engineer (миграция таблицы)
- **Фаза:** M-OS-1.1A, Sprint 2 (нед. 3–4)
- **Приоритет:** P1 — требуется US-07 (Pluggability) для регистрации `AgentControlBus` как отдельной DI-точки. US-05 может отстать на 1 день от US-04 без блокировки других US.
- **Оценка:** M — 2 рабочих дня (0.5 дня миграция, 0.5 дня Pydantic-контракты, 0.5 дня `AgentControlBus.publish` + тесты, 0.5 дня self-check).
- **Scope-vs-ADR:** verified (ADR-0016 §«Базовые классы» + §«Структура двух шин» — Решение 3 Владельца, два независимых корня событий, подписчики не пересекаются; ADR 0013 safe-migration). Gaps: ADR-0016 `proposed` — реализуем усечённый scope по декомпозиции (таблица + Pydantic + publish; подписчики — в 1.1B).
- **Источник формулировки:** `docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md` §Sprint 2 / US-05 (в оригинальной декомпозиции это часть US-04/05 объединённая, по формулировке Координатора 2026-04-19 — отдельная US-05 Sprint 2).

---

## Контекст

Вторая шина M-OS — **AgentControlBus** — транспорт команд к ИИ-субагентам: «запустить задачу», «остановить», «получить статус». Владелец в Решении 3 (`project_m_os_1_decisions.md`) зафиксировал:

> Подписчики бизнес-модулей не видят agent-события, и наоборот. Физически раздельные таблицы и каналы.

US-05 — симметричное зеркало US-04 для agent-стороны:
- Отдельная таблица `agent_control_events` (не `business_events` с полем `bus`).
- Отдельный базовый класс `AgentControlEvent` (не наследует `BusinessEvent`).
- Отдельный класс-шина `AgentControlBus` с методом `publish`.
- **`AgentControlEvent` намеренно не имеет `company_id`**: управление субагентами происходит на уровне платформы, не юрлица (ADR-0016 §«Базовые классы событий»).

**Сжатый scope как в US-04:** tables + Pydantic + publish. Subscribers, LISTEN/NOTIFY, polling fallback — в 1.1B.

В M-OS-1 пока нет активных потребителей agent-шины: первые реальные команды появятся в M-OS-1.3/1.4 (Telegram-кнопки BPM → запуск субагента). Но фундамент закладываем сейчас, чтобы при появлении потребителей не переделывать архитектуру.

---

## Что конкретно сделать

### 1. Миграция Alembic

**Файл:** `backend/alembic/versions/2026_04_19_XXXX_us05_agent_control_events_table.py`

Таблица `agent_control_events`, append-only:

```
agent_control_events
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid()
  event_type     TEXT NOT NULL           -- 'TaskAssigned', 'AgentStop', 'AgentStatusRequested', ...
  target_agent   TEXT NOT NULL           -- имя субагента ('backend-director', 'qa-head', ...)
  correlation_id UUID NULLABLE           -- связывание команд одной цепочки управления
  payload         JSONB NOT NULL
  occurred_at    TIMESTAMPTZ NOT NULL DEFAULT now()
  schema_version SMALLINT NOT NULL DEFAULT 1
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()

INDEX ix_agent_control_events_target_agent_occurred_at (target_agent, occurred_at DESC)
INDEX ix_agent_control_events_event_type_occurred_at (event_type, occurred_at DESC)
INDEX ix_agent_control_events_correlation_id (correlation_id) WHERE correlation_id IS NOT NULL
```

**Ключевое отличие от `business_events`:**
- **Нет поля `company_id`** — команды агентам не привязаны к юрлицу. Это обязательное требование ADR-0016: «`AgentControlEvent` намеренно не содержит `company_id` — управление агентами происходит на уровне платформы».
- **Нет `aggregate_id`** — у команды агенту нет «агрегата-источника» в бизнес-смысле; есть `target_agent` (кому команда).

**Правила миграции:**
- `target_agent` — свободный TEXT, валидация на уровне Pydantic (допустимые значения — из реестра субагентов). Enum сейчас не делаем — субагенты добавляются/выходят из dormant, expand/contract на каждом изменении нерационально.
- `event_type` — свободный TEXT, аналогично US-04.
- Downgrade симметричный.

**Обязательно перед сдачей:**
- `cd backend && python -m tools.lint_migrations alembic/versions/2026_04_19_*us05*` — зелёный
- `cd backend && alembic upgrade head && alembic downgrade -1 && alembic upgrade head` — зелёный

### 2. ORM-модель

**Файл (создать):** `backend/app/models/agent_control_event.py`

```python
from datetime import datetime
from uuid import UUID

from sqlalchemy.dialects.postgresql import JSONB, UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class AgentControlEventRecord(Base):
    __tablename__ = "agent_control_events"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, server_default="gen_random_uuid()")
    event_type: Mapped[str] = mapped_column(nullable=False)
    target_agent: Mapped[str] = mapped_column(nullable=False)
    correlation_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), nullable=True)
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False)
    occurred_at: Mapped[datetime] = mapped_column(nullable=False)
    schema_version: Mapped[int] = mapped_column(default=1, nullable=False)
    created_at: Mapped[datetime] = mapped_column(nullable=False)
```

### 3. Pydantic-контракты событий

**Файл (создать):** `backend/app/core/events/agent_control.py`

Базовый класс `AgentControlEvent` + один пример-наследник `TaskAssigned` (как разрезающий пример; реальные события появятся в M-OS-1.3).

```python
from datetime import datetime, timezone
from typing import Annotated, Literal, Union
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict, Field


class AgentControlEvent(BaseModel):
    """Базовый класс команд ИИ-субагентам. НЕ наследует BusinessEvent — физическая изоляция шин."""

    model_config = ConfigDict(frozen=True, extra="forbid")

    event_id: UUID = Field(default_factory=uuid4)
    event_type: str
    target_agent: str
    correlation_id: UUID | None = None
    occurred_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    schema_version: int = 1


class TaskAssigned(AgentControlEvent):
    """Команда: агенту назначена задача (пример для US-05; реальные use-cases — в M-OS-1.3)."""

    event_type: Literal["TaskAssigned"] = "TaskAssigned"
    task_id: UUID
    task_prompt: str


AgentControlEventUnion = Annotated[
    Union[TaskAssigned],
    Field(discriminator="event_type"),
]
```

**Важно:** `AgentControlEvent` и `BusinessEvent` — **два разных корня**, не имеют общего родителя кроме `pydantic.BaseModel`. Это техническая гарантия изоляции: функция `BusinessEventBus.publish(event: BusinessEvent)` не примет `AgentControlEvent`, и наоборот — тип-чекер (`mypy`) отвергает.

### 4. `AgentControlBus.publish`

**Файл (создать):** `backend/app/core/events/agent_control_bus.py`

```python
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.agent_control_event import AgentControlEventRecord
from app.core.events.agent_control import AgentControlEvent


class AgentControlBus:
    """Шина команд субагентам. В 1.1A реализует только publish (запись в таблицу).

    Подписчики (dispatcher, runner) — в 1.1B (см. ADR-0016 Migration Path Шаг 6).
    """

    def __init__(self, db: AsyncSession) -> None:
        self._db = db

    async def publish(self, event: AgentControlEvent) -> None:
        """Атомарно записывает команду в agent_control_events в текущей транзакции."""
        record = AgentControlEventRecord(
            id=event.event_id,
            event_type=event.event_type,
            target_agent=event.target_agent,
            correlation_id=event.correlation_id,
            payload=event.model_dump(mode="json", exclude={"event_id", "event_type", "target_agent", "correlation_id", "occurred_at", "schema_version"}),
            occurred_at=event.occurred_at,
            schema_version=event.schema_version,
        )
        self._db.add(record)
        await self._db.flush()
```

**DI-точка:** `get_agent_control_bus(db: AsyncSession = Depends(get_db)) -> AgentControlBus` в `backend/app/core/events/deps.py`.

**Ключевой инвариант US-05:** `AgentControlBus.publish` принимает **только** `AgentControlEvent` (тайп-чек Pydantic + runtime `assert isinstance(event, AgentControlEvent)`). Попытка передать `BusinessEvent` — `TypeError` (mypy отвергнет, в тесте — RuntimeError через assert).

### 5. Тесты (≥3)

**Файл (создать):** `backend/tests/unit/core/events/test_agent_control_bus.py`

1. **`test_publish_writes_record`** — вызов `bus.publish(TaskAssigned(target_agent="qa-head", task_id=uuid4(), task_prompt="run tests"))` создаёт строку в `agent_control_events`.
2. **`test_publish_atomic`** — `publish` + rollback → строки нет.
3. **`test_agent_control_bus_rejects_business_event`** — попытка `bus.publish(AdapterStateChanged(...))` падает `TypeError` / `AssertionError` (runtime-guard через `assert isinstance(event, AgentControlEvent)`). Если US-04 ещё не замержен — использовать mock-класс `class FakeBusinessEvent(BaseModel): ...` вместо `AdapterStateChanged`.
4. **`test_no_company_id_on_agent_event`** (опционально) — модель `AgentControlEvent` не имеет поля `company_id` (проверка через `hasattr` или `TypeAdapter(AgentControlEvent).json_schema()` inspect).

### 6. Самопроверка (перед сдачей backend-head)

- [ ] Прочитан `CLAUDE.md`, `departments/backend.md` (ADR-gate A.1–A.5, правила 1–11)
- [ ] Прочитан ADR-0016 §«Базовые классы событий» — убедиться, что `AgentControlEvent` НЕ имеет `company_id`
- [ ] Выполнен ADR-gate:
  - A.1 — никаких литералов секретов
  - A.2 — ORM-паттерн через session.add (аналогично US-04)
  - A.3 / A.4 / A.5 — не применимо
- [ ] `lint-migrations` + `round-trip` — зелёные
- [ ] `pytest backend/tests/unit/core/events/test_agent_control_bus.py -v` — ≥3 зелёных
- [ ] Все существующие тесты зелёные
- [ ] `ruff`, `mypy app/core/events app/models/agent_control_event.py` — чисто
- [ ] `git status` — только FILES_ALLOWED
- [ ] Не коммитить

---

## DoD

1. Миграция `2026_04_19_*_us05_agent_control_events_table.py` создаёт таблицу `agent_control_events` + 3 индекса; round-trip и lint-migrations зелёные.
2. ORM-модель `AgentControlEventRecord` в `backend/app/models/agent_control_event.py`.
3. Pydantic `AgentControlEvent` + `TaskAssigned` + `AgentControlEventUnion` в `backend/app/core/events/agent_control.py`.
4. Класс `AgentControlBus.publish` в `backend/app/core/events/agent_control_bus.py`, DI-функция `get_agent_control_bus` в `backend/app/core/events/deps.py`.
5. `AgentControlEvent` **не наследует** `BusinessEvent` и **не содержит** `company_id` — проверено тестом.
6. ≥3 тестов в `backend/tests/unit/core/events/test_agent_control_bus.py`, все зелёные.
7. `ruff`, `mypy`, `lint-migrations`, `round-trip` — все зелёные. Существующие тесты зелёные.

---

## FILES_ALLOWED

- `backend/alembic/versions/2026_04_19_*_us05_agent_control_events_table.py` — **создать**
- `backend/app/models/agent_control_event.py` — **создать**
- `backend/app/models/__init__.py` — добавить экспорт `AgentControlEventRecord`, если это паттерн
- `backend/app/core/events/agent_control.py` — **создать**
- `backend/app/core/events/agent_control_bus.py` — **создать**
- `backend/app/core/events/deps.py` — добавить функцию `get_agent_control_bus` **(осторожно: US-04 тоже пишет в этот файл; согласовать очередь через backend-head)**
- `backend/tests/unit/core/events/test_agent_control_bus.py` — **создать**

## FILES_FORBIDDEN

- `backend/app/core/events/business.py`, `business_bus.py` — US-04 (параллельный разработчик). **Ни строчки.**
- `backend/app/core/events/__init__.py` — создаёт US-04 (first-writer-wins через backend-head). Не трогать.
- `backend/app/models/business_event.py` — US-04.
- `backend/app/core/integrations/**` — US-06.
- `backend/app/core/container.py` — US-07.
- `backend/app/api/**`, `backend/app/services/**` — не трогать.
- Существующие модели, ADR, docs, frontend, CI workflows — не трогать.

**Overlap-риск с US-04:** `backend/app/core/events/deps.py` — общий. **Правило:** backend-head выставляет очередь: US-04 пишет свой `get_business_event_bus` первым (1 раунд), US-05 добавляет `get_agent_control_bus` вторым (1 раунд). Никаких slaшей в очереди.

---

## Зависимости

- **Блокирует:** US-07 (Pluggability регистрирует `AgentControlBus` как отдельную DI-точку, отличную от `BusinessEventBus`).
- **Блокируется:** ничем (независим от US-04 по смыслу — разные классы/таблицы/пакеты; физический overlap только в `deps.py` через backend-head).
- **Параллелен с:** US-04 (BusinessEventBus).

---

## COMMUNICATION_RULES

- Перед стартом — прочитать `CLAUDE.md`, `departments/backend.md`, ADR-0016 (§«Решение» + §«Базовые классы»), ADR-0013.
- **`AgentControlEvent` не имеет поля `company_id` — это принципиально.** Если возникнет желание добавить «чтобы было единообразно с BusinessEvent» — **стоп, эскалация backend-head → backend-director**. ADR-0016 прямо запрещает.
- Если при реализации тесты `test_business_bus` падают (US-04 ещё не замержен) — **не трогать тесты US-04**, использовать mock-события для `test_agent_control_bus_rejects_business_event`.
- Если deps.py уже содержит `get_business_event_bus` (US-04 домержился первым) — просто дописать `get_agent_control_bus`. Не переписывать существующую функцию.
- Если US-04 ещё не домержен на момент старта US-05 — создать `deps.py` только с `get_agent_control_bus`; US-04 дорегистрирует свой при мерже.
- Никаких сторонних зависимостей.

---

## Обязательно прочитать перед началом

1. `/root/coordinata56/CLAUDE.md` — секции «Данные и БД», «API», «Код», «Git»
2. `/root/coordinata56/docs/agents/departments/backend.md` — ADR-gate A.1–A.5
3. `/root/coordinata56/docs/adr/0016-domain-event-bus.md` — §«Структура двух шин», §«Базовые классы событий» (ключевой инвариант — AgentControlEvent без company_id)
4. `/root/coordinata56/docs/adr/0013-migrations-evolution-contract.md`
5. `/root/coordinata56/docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md` — §Sprint 2 / US-05
6. `backend/app/models/base.py`
7. Файлы дев-брифа US-04 (`backend-dev-brief-us-04-sprint2-2026-04-19.md`) — для согласованности паттернов. **Не копировать код механически** — US-05 симметричен, но не идентичен.

---

## Отчёт (≤ 200 слов)

Структура:
1. **Миграция** — путь, LOC, результаты `lint-migrations` и `round-trip`.
2. **ORM-модель** — путь.
3. **Pydantic-контракты** — путь, список классов, явное подтверждение «AgentControlEvent не имеет company_id».
4. **AgentControlBus** — путь.
5. **Тесты** — путь, число, результат.
6. **Изоляция от BusinessEvent** — как проверена (тест-id).
7. **ADR-gate** — A.1/A.2 pass/fail.
8. **Отклонения от scope** — если были.
