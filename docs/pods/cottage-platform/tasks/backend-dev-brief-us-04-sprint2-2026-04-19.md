ultrathink

# Дев-бриф US-04 (Sprint 2) — BusinessEventBus: таблица + Pydantic базовый класс + discriminator

- **Дата:** 2026-04-19
- **Автор:** backend-director (через backend-head при распределении)
- **Получатель:** backend-dev-1 (ведущий) + db-engineer (миграция таблицы)
- **Фаза:** M-OS-1.1A, Sprint 2 (нед. 3–4)
- **Приоритет:** P0 — фундамент для US-06 (ACL `AdapterStateChanged`) и US-07 (Pluggability).
- **Оценка:** M — 2 рабочих дня (0.5 дня миграция, 0.5 дня Pydantic-модели + discriminator, 0.5 дня `BusinessEventBus.publish` + тесты, 0.5 дня self-check).
- **Scope-vs-ADR:** verified (ADR-0016 §«Базовые классы событий» + §«Расположение в кодовой базе»; ADR 0011 §1.3 — `company_id` обязателен; ADR 0013 safe-migration). Gaps: ADR-0016 статус `proposed` — в 1.1A Sprint 2 реализуем **усечённый scope из декомпозиции** (только tables + Pydantic + publish; Outbox Poller / LISTEN / subscribers — в 1.1B); open-question по «одна таблица event_outbox vs две» эскалирован Координатору в отдельной записке.
- **Источник формулировки:** `docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md` §Sprint 2 / US-04 + US-05 (объединены в одну US по запросу Координатора 2026-04-19).

---

## Контекст

M-OS-1.1A Sprint 1 закрыт (US-01/US-02/US-03 на main): `company_id` на 12 доменных таблицах, JWT-клеймы, RBAC fine-grained. Следующий фундаментальный кирпич — **Dual Event Bus (ADR-0016)**: два независимых транспорта событий, которыми позже будут пользоваться BPM (M-OS-1.3), Admin UI (инвалидация кеша конфигурации), ACL (`AdapterStateChanged`, US-06 этого спринта).

Владелец в Решении 3 (`project_m_os_1_decisions.md`) зафиксировал: **два независимых базовых класса событий** (`BusinessEvent`, `AgentControlEvent`), подписчики одной шины не видят события другой. US-04 реализует **бизнес-половину** (BusinessEventBus). US-05 отдельным брифом — AgentControlBus, строго симметрично и параллельно.

**Сжатый scope Sprint 2 (решение Координатора 2026-04-19):** в M-OS-1.1A реализуем только tables + Pydantic-контракты + метод `publish`, атомарно записывающий событие в ту же транзакцию БД. OutboxPoller, LISTEN/NOTIFY, подписчики, polling fallback, cleanup — в 1.1B (Sprint 4+). Это снижает риск и позволяет US-06 (ACL) и US-07 (Pluggability) работать с готовым контрактом.

---

## Что конкретно сделать

### 1. Миграция Alembic

**Файл:** `backend/alembic/versions/2026_04_19_XXXX_us04_business_events_table.py`

Одна таблица `business_events`, append-only:

```
business_events
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid()
  event_type      TEXT NOT NULL           -- 'PaymentCreated', 'ContractSigned', 'AdapterStateChanged', ...
  aggregate_id   UUID NOT NULL            -- id основного объекта-источника (payment.id, contract.id, ...)
  company_id     INTEGER NULLABLE FK companies.id  -- nullable для платформенных событий (например, AdapterStateChanged глобального адаптера)
  correlation_id UUID NULLABLE            -- связывание событий одного бизнес-сценария
  payload         JSONB NOT NULL
  occurred_at    TIMESTAMPTZ NOT NULL DEFAULT now()
  schema_version SMALLINT NOT NULL DEFAULT 1
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()

INDEX ix_business_events_company_id_occurred_at (company_id, occurred_at DESC)
INDEX ix_business_events_event_type_occurred_at (event_type, occurred_at DESC)
INDEX ix_business_events_correlation_id (correlation_id) WHERE correlation_id IS NOT NULL
```

**Правила миграции:**
- `company_id` — NULLABLE: платформенные события (`AdapterStateChanged`) не привязаны к юрлицу. Это **отклонение от ADR-0011 §1.3** — но ADR-0016 §«Базовые классы» прямо допускает, что для `AgentControlEvent` company_id отсутствует; `business_events.company_id NULLABLE` расширяется на платформенные события бизнес-шины. Фиксируется в docstring миграции как `# ADR-0011-exception: platform-level business events allowed`.
- `event_type` — свободный TEXT, не enum: enum потребовал бы expand/contract при каждом новом типе события — нерационально на раннем этапе. Линтер ADR-0013 это допускает.
- `occurred_at` с `DEFAULT now()` — не требует `server_default` дополнительно.
- Downgrade симметричный: `op.drop_index` × 3, `op.drop_table('business_events')`. Учитываем что это новая таблица — drop_table разрешён в downgrade одной миграции.

**Обязательно перед сдачей:**
- `cd backend && python -m tools.lint_migrations alembic/versions/2026_04_19_*us04*` — зелёный
- `cd backend && alembic upgrade head && alembic downgrade -1 && alembic upgrade head` — зелёный

### 2. ORM-модель

**Файл (создать):** `backend/app/models/business_event.py`

```python
from datetime import datetime
from uuid import UUID

from sqlalchemy import ForeignKey, Index
from sqlalchemy.dialects.postgresql import JSONB, UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class BusinessEventRecord(Base):
    __tablename__ = "business_events"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, server_default="gen_random_uuid()")
    event_type: Mapped[str] = mapped_column(nullable=False)
    aggregate_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    company_id: Mapped[int | None] = mapped_column(ForeignKey("companies.id", ondelete="RESTRICT"), nullable=True)
    correlation_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), nullable=True)
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False)
    occurred_at: Mapped[datetime] = mapped_column(nullable=False)
    schema_version: Mapped[int] = mapped_column(default=1, nullable=False)
    created_at: Mapped[datetime] = mapped_column(nullable=False)
```

**Не добавлять модель в `backend/app/models/__init__.py` если это не требуется миграцией** — сверить с существующим паттерном (если остальные модели импортируются через `__init__` — добавить; иначе оставить локальный импорт).

### 3. Pydantic-контракты событий (discriminator)

**Файл (создать):** `backend/app/core/events/__init__.py` — пустой init.

**Файл (создать):** `backend/app/core/events/business.py`

Базовый класс `BusinessEvent` + первый конкретный наследник `AdapterStateChanged` (нужен US-06):

```python
from datetime import datetime, timezone
from typing import Annotated, Literal, Union
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict, Field


class BusinessEvent(BaseModel):
    """Базовый класс всех событий бизнес-шины. Дискриминатор — поле event_type."""

    model_config = ConfigDict(frozen=True, extra="forbid")

    event_id: UUID = Field(default_factory=uuid4)
    event_type: str
    aggregate_id: UUID
    company_id: int | None = None
    correlation_id: UUID | None = None
    occurred_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    schema_version: int = 1


class AdapterStateChanged(BusinessEvent):
    """Состояние адаптера в integration_catalog изменилось (US-06 ACL подписан для инвалидации кеша)."""

    event_type: Literal["AdapterStateChanged"] = "AdapterStateChanged"
    # aggregate_id = integration_catalog.id
    adapter_name: str
    old_state: Literal["written", "enabled_mock", "enabled_live"]
    new_state: Literal["written", "enabled_mock", "enabled_live"]
    changed_by_user_id: UUID


# Discriminated union для парсинга из БД/внешних источников
BusinessEventUnion = Annotated[
    Union[AdapterStateChanged],  # при добавлении новых событий — расширять этот Union
    Field(discriminator="event_type"),
]
```

**Правила расширения union:** при появлении нового типа события (`PaymentCreated`, `ContractSigned` в 1.1B) — добавлять конкретный класс с `Literal[...]` и включать в `BusinessEventUnion`. Новых событий в US-04 не создаём, кроме `AdapterStateChanged` (нужен US-06).

### 4. `BusinessEventBus.publish` — минимальная реализация

**Файл (создать):** `backend/app/core/events/business_bus.py`

```python
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.business_event import BusinessEventRecord
from app.core.events.business import BusinessEvent


class BusinessEventBus:
    """Шина бизнес-событий. В 1.1A реализует только publish (запись в таблицу в той же транзакции).

    OutboxPoller, LISTEN/NOTIFY, подписчики — в 1.1B (см. ADR-0016 Migration Path, Шаги 2–5).
    """

    def __init__(self, db: AsyncSession) -> None:
        self._db = db

    async def publish(self, event: BusinessEvent) -> None:
        """Атомарно записывает событие в business_events в текущей транзакции.

        Явный commit не делается — ожидается что вызывающий код управляет транзакцией
        (pattern: write-операция + publish в одной транзакции, ADR 0007 analog для событий).
        """
        record = BusinessEventRecord(
            id=event.event_id,
            event_type=event.event_type,
            aggregate_id=event.aggregate_id,
            company_id=event.company_id,
            correlation_id=event.correlation_id,
            payload=event.model_dump(mode="json", exclude={"event_id", "event_type", "aggregate_id", "company_id", "correlation_id", "occurred_at", "schema_version"}),
            occurred_at=event.occurred_at,
            schema_version=event.schema_version,
        )
        self._db.add(record)
        await self._db.flush()
```

**DI-точка:** создать функцию `get_business_event_bus(db: AsyncSession = Depends(get_db)) -> BusinessEventBus` в `backend/app/core/events/deps.py` — на её основе US-07 сделает реестр pluggability.

**Не публикуем через AgentControlEvent.** Runtime-запрет обеспечивается тайп-чеком Pydantic: `publish(event: BusinessEvent)` — `AgentControlEvent` не наследует `BusinessEvent`, типизация отвергает. Плюс unit-тест (см. §5).

### 5. Тесты (≥3)

**Файл (создать):** `backend/tests/unit/core/events/test_business_bus.py`

1. **`test_publish_writes_record`** — вызов `publish(AdapterStateChanged(...))` создаёт ровно одну строку в `business_events` с корректными полями (event_type, aggregate_id, payload). Использует `AsyncSession` фикстуру (in-memory или test-tx).
2. **`test_publish_atomic_with_business_write`** — в одной транзакции: `db.add(Company(...))` → `bus.publish(event)` → `rollback` → ни компании, ни события в БД нет.
3. **`test_discriminator_rejects_wrong_event_type`** — попытка Pydantic-валидации `AdapterStateChanged.model_validate({"event_type": "PaymentCreated", ...})` падает `ValidationError` (discriminator enforces Literal).
4. **`test_business_bus_rejects_agent_control_event`** (опционально, если `AgentControlEvent` уже будет существовать из US-05, запускаемой параллельно) — pyright/mypy-check через `# type: ignore[arg-type]` НЕ допускается; runtime-проверка: попытка передать объект без `BusinessEvent`-наследования падает через `isinstance` check внутри `publish` (добавить `assert isinstance(event, BusinessEvent)` в начале `publish`).

### 6. Самопроверка (перед сдачей backend-head)

- [ ] Прочитан `/root/coordinata56/CLAUDE.md` (секции «Данные и БД», «API», «Код», «Git»)
- [ ] Прочитан `docs/agents/departments/backend.md` (ADR-gate A.1–A.5, правила 1–11)
- [ ] Прочитан ADR-0016 §«Решение» + §«DoD для внедрения (M-OS-1.1A)» — реализован **только** Шаг 1 (Структура), Шаги 2–6 — не реализуем
- [ ] Прочитан ADR-0013 «Правила для авторов миграций»
- [ ] Выполнен ADR-gate:
  - A.1 — никаких литералов секретов
  - A.2 — `BusinessEventBus.publish` использует `self._db.add()` (не `execute(insert(...))`) — ORM-паттерн через session, это допустимо в `core/events/` как в слое-репозитории событий; явно задокументировано в docstring класса
  - A.3 — не применимо (US-04 не трогает write-эндпоинты)
  - A.4 — не применимо (US-04 не трогает API)
  - A.5 — не применимо (события — сами являются аудит-следом бизнеса; AuditLog для write-операций с событиями пишется в 1.1B при подключении BPM)
- [ ] `cd backend && python -m tools.lint_migrations alembic/versions/2026_04_19_*us04*` — зелёный
- [ ] `cd backend && alembic upgrade head && alembic downgrade -1 && alembic upgrade head` — зелёный
- [ ] `cd backend && pytest backend/tests/unit/core/events/test_business_bus.py -v` — ≥3 тестов зелёные
- [ ] `cd backend && pytest` — все существующие тесты (после US-01/02/03 — ~410+) зелёные
- [ ] `cd backend && ruff check app tests` — 0 ошибок
- [ ] `cd backend && mypy app/core/events app/models/business_event.py` — 0 новых ошибок
- [ ] `git status` — только файлы из FILES_ALLOWED
- [ ] Не коммитить

---

## DoD

1. Миграция `2026_04_19_*_us04_business_events_table.py` создаёт таблицу `business_events` + 3 индекса; round-trip и lint-migrations зелёные.
2. ORM-модель `BusinessEventRecord` в `backend/app/models/business_event.py`.
3. Pydantic-контракты `BusinessEvent` + `AdapterStateChanged` + `BusinessEventUnion` в `backend/app/core/events/business.py`.
4. Класс `BusinessEventBus` с методом `publish(event: BusinessEvent) -> None` в `backend/app/core/events/business_bus.py`, DI-функция `get_business_event_bus` в `backend/app/core/events/deps.py`.
5. ≥3 тестов в `backend/tests/unit/core/events/test_business_bus.py`, все зелёные.
6. `ruff`, `mypy`, `lint-migrations`, `round-trip` — все зелёные.
7. Все существующие тесты зелёные.

---

## FILES_ALLOWED

- `backend/alembic/versions/2026_04_19_*_us04_business_events_table.py` — **создать**
- `backend/app/models/business_event.py` — **создать**
- `backend/app/models/__init__.py` — добавить экспорт `BusinessEventRecord`, если файл используется для регистрации моделей (проверить паттерн)
- `backend/app/core/events/__init__.py` — **создать** (пустой или с экспортами)
- `backend/app/core/events/business.py` — **создать**
- `backend/app/core/events/business_bus.py` — **создать**
- `backend/app/core/events/deps.py` — **создать** (DI-функция `get_business_event_bus`)
- `backend/tests/unit/core/events/__init__.py` — **создать** (пустой)
- `backend/tests/unit/core/events/test_business_bus.py` — **создать**

## FILES_FORBIDDEN

- `backend/app/core/events/agent_control.py`, `agent_control_bus.py` — US-05 (другой разработчик, параллельная работа). **Ни строчки.**
- `backend/app/core/integrations/**` — US-06 (другой разработчик).
- `backend/app/core/container.py` — US-07 (другой разработчик).
- `backend/app/api/**`, `backend/app/services/**` — US-04 не трогает бизнес-код.
- `backend/app/models/company.py`, `user.py`, `audit.py` и прочие существующие модели — не трогать.
- `docs/adr/**`, `docs/agents/**` — не трогать (кроме отчёта в сообщении).
- `.github/workflows/**` — CI не меняем (отдельная задача infra).
- `frontend/**` — не касается.

---

## Зависимости

- **Блокирует:** US-06 (ACL) — `AdapterStateChanged` нужен для инвалидации кеша адаптеров; US-07 (Pluggability) — `BusinessEventBus` должен быть зарегистрирован в контейнере.
- **Блокируется:** US-01 (`company_id` FK на таблицах уже замержен на main после Sprint 1) — доступен.
- **Параллелен с:** US-05 (AgentControlBus) — разные классы, разные пакеты, overlap = 0.

---

## COMMUNICATION_RULES

- Перед стартом — прочитать `/root/coordinata56/CLAUDE.md`, `docs/agents/departments/backend.md`, ADR-0016, ADR-0013.
- Если в существующих моделях (`backend/app/models/__init__.py`) паттерн регистрации моделей неясен — **стоп, эскалация backend-head**. Не «угадывать».
- Если Pydantic v2 discriminator не работает как ожидается (например, `Annotated[Union[...], Field(discriminator=...)]` отвергается mypy) — **стоп, эскалация backend-head**. Возможно, нужна обёртка `TypeAdapter`.
- Если миграция падает на round-trip из-за отсутствия `gen_random_uuid()` в Postgres — проверить что расширение `pgcrypto` или `uuid-ossp` включено (`CREATE EXTENSION IF NOT EXISTS pgcrypto`); добавить в миграцию **только** если его нет в baseline; иначе — использовать `uuid_generate_v4()`.
- Если в процессе реализации обнаружится конфликт между ADR-0016 («одна таблица `event_outbox` с полем `bus`») и декомпозицией Координатора («две таблицы `business_events` / `agent_control_events`») — **стоп, эскалация backend-head → backend-director**. Фиксируем: делаем по декомпозиции Координатора (решение Владельца из `project_m_os_1_decisions.md` Решение 3), open-question эскалирован.
- Никаких сторонних зависимостей — только SQLAlchemy, Pydantic v2, уже присутствующие в `backend/requirements.txt`.

---

## Обязательно прочитать перед началом

1. `/root/coordinata56/CLAUDE.md` — секции «Данные и БД», «API», «Код», «Git»
2. `/root/coordinata56/docs/agents/departments/backend.md` — ADR-gate A.1–A.5, правила 1–11, §«Правила для авторов миграций»
3. `/root/coordinata56/docs/adr/0016-domain-event-bus.md` — §«Решение» + §«DoD для внедрения (M-OS-1.1A)» (Шаг 1 из Migration Path)
4. `/root/coordinata56/docs/adr/0013-migrations-evolution-contract.md` — safe-migration pattern, enum rules
5. `/root/coordinata56/docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md` — §Sprint 2 / US-04 + US-05
6. `backend/app/models/base.py` — declarative Base
7. `backend/alembic/versions/2026_04_17_0900_multi_company_foundation.py` — паттерн миграции с FK на `companies`

---

## Отчёт (≤ 200 слов)

Структура:
1. **Миграция** — путь, размер (LOC), результаты `lint-migrations` и `round-trip`.
2. **ORM-модель** — путь, поля.
3. **Pydantic-контракты** — путь, список классов (BusinessEvent, AdapterStateChanged, BusinessEventUnion).
4. **BusinessEventBus** — путь, краткое описание `publish`.
5. **Тесты** — путь, число тестов, результат `pytest`.
6. **Существующие тесты** — число и результат.
7. **ADR-gate** — A.1/A.2 pass/fail + артефакт.
8. **Отклонения от scope** — если были.
