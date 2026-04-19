ultrathink

# Дев-бриф US-07 (Sprint 2) — Pluggability: container + 4 DI-точки (data contracts под ADR-0019)

- **Дата:** 2026-04-19
- **Автор:** backend-director (через backend-head при распределении)
- **Получатель:** backend-dev-1 (после сдачи US-04)
- **Фаза:** M-OS-1.1A, Sprint 2 (нед. 3–4), **после мержа US-04 и US-05**
- **Приоритет:** P1 — закрывает Sprint 2 Foundation Core; блокер для Admin UI 1.1B (pluggable NotificationProvider) и BPM 1.3 (bus через DI).
- **Оценка:** M — 2 рабочих дня (0.5 дня container + 4 функции, 0.5 дня in-memory fakes для тестов, 0.5 дня pluggability-инвариант тесты, 0.5 дня self-check).
- **Scope-vs-ADR:** verified (ADR-0019 RESERVED — полный текст в Волне 4; US-07 реализует **каркас под 11 точек**, из которых 4 сейчас + stubs для остальных 7; ADR-0014 — `NotificationProvider`/адаптеры интегрируются в реестр; ADR-0016 — `BusinessEventBus` + `AgentControlBus` — два разных ключа). Gaps: ADR-0019 не ратифицирован — US-07 реализует **каркас**, готовый принять полный реестр без переписывания, когда ADR-0019 станет accepted.
- **Источник формулировки:** `docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md` §Sprint 2 / US-10 + формулировка Координатора 2026-04-19 «data contracts между pod'ами, базовый каркас под ADR-0019».

---

## Контекст

ADR-0019 (Pluggability Contract) — RESERVED, полный текст пишется в Волне 4. Но **каркас** нужен уже сейчас:

- US-04 / US-05 создали `BusinessEventBus` и `AgentControlBus` — обе требуют DI для инжекции в сервисы.
- ADR-0014 (ACL) требует `NotificationProvider` для отправки уведомлений через адаптер (Telegram), выбор провайдера — через реестр.
- ADR 0007 (AuditLog) — `AuditLogger` логично иметь через реестр, чтобы в тестах подменять на in-memory.

В 1.1A реализуем **4 DI-точки**: `BusinessEventBus`, `AgentControlBus`, `NotificationProvider`, `AuditLogger`. Остальные 7 точек из ADR-0019 (`AIProvider`, `BankAdapter`, `OFDAdapter`, `1CAdapter`, `RosreestrAdapter`, `CryptoProvider`, `ConfigurationCache`) — в 1.1B.

**Ключевой инвариант ADR-0019:** `BusinessEventBus` и `AgentControlBus` — **разные DI-точки**, одна реализация не может быть зарегистрирована на оба ключа. Это защита от случайной путаницы, аналог запрета cross-bus-import (будущий US-06 из исходной декомпозиции).

**Формулировка Координатора «data contracts между pod'ами, базовый каркас под ADR-0019»** — это и есть реестр: каждый pod получает зависимости через `Depends()`, не инстанциирует провайдеров сам. Подмена в тестах через `app.dependency_overrides`. Смена реализации — одна правка в `container.py`, не ревизия 50 файлов.

**Почему после US-04:** `container.py` регистрирует фабрику `BusinessEventBus`, для чего нужен импорт класса из `app.core.events.business_bus` — он появляется только после мержа US-04.

---

## Что конкретно сделать

### 1. Протоколы (Protocol classes) для 4 точек

**Файл (создать):** `backend/app/core/pluggability/__init__.py` — пустой.

**Файл (создать):** `backend/app/core/pluggability/protocols.py`

Protocol-классы — контракт, которому должна соответствовать имплементация:

```python
from typing import Protocol, runtime_checkable
from uuid import UUID

from app.core.events.business import BusinessEvent
from app.core.events.agent_control import AgentControlEvent


@runtime_checkable
class BusinessEventBusProtocol(Protocol):
    async def publish(self, event: BusinessEvent) -> None: ...


@runtime_checkable
class AgentControlBusProtocol(Protocol):
    async def publish(self, event: AgentControlEvent) -> None: ...


@runtime_checkable
class NotificationProviderProtocol(Protocol):
    async def send(self, recipient: str, title: str, body: str, correlation_id: UUID | None = None) -> None: ...


@runtime_checkable
class AuditLoggerProtocol(Protocol):
    async def log(self, actor_user_id: UUID | None, action: str, resource_type: str, resource_id: str | None, details: dict) -> None: ...
```

**Правило**: протоколы не содержат реализаций — только сигнатуры. `runtime_checkable` позволяет `isinstance(impl, BusinessEventBusProtocol)` для инвариантного теста §5.

### 2. Контейнер (реестр)

**Файл (создать):** `backend/app/core/pluggability/container.py`

```python
from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db
from app.core.events.business_bus import BusinessEventBus
from app.core.events.agent_control_bus import AgentControlBus
from app.core.pluggability.protocols import (
    AgentControlBusProtocol,
    AuditLoggerProtocol,
    BusinessEventBusProtocol,
    NotificationProviderProtocol,
)


async def get_business_event_bus(
    db: Annotated[AsyncSession, Depends(get_db)],
) -> BusinessEventBusProtocol:
    """Реестр-точка BusinessEventBus. Производственная реализация — из app.core.events."""
    return BusinessEventBus(db)


async def get_agent_control_bus(
    db: Annotated[AsyncSession, Depends(get_db)],
) -> AgentControlBusProtocol:
    """Реестр-точка AgentControlBus. Производственная реализация — из app.core.events."""
    return AgentControlBus(db)


async def get_notification_provider(
    # Параметры зависят от реализации — пока заглушка
) -> NotificationProviderProtocol:
    """Реестр-точка NotificationProvider. В 1.1A возвращает no-op провайдер;
    в Sprint 3 / US-12 заменяется на TelegramAdapter."""
    from app.core.pluggability.impls.noop_notification import NoOpNotificationProvider
    return NoOpNotificationProvider()


async def get_audit_logger(
    db: Annotated[AsyncSession, Depends(get_db)],
) -> AuditLoggerProtocol:
    """Реестр-точка AuditLogger. В 1.1A — обёртка над существующим audit_service."""
    from app.core.pluggability.impls.db_audit_logger import DbAuditLogger
    return DbAuditLogger(db)
```

**Ключевой момент:** возвращаемый тип — **Protocol**, не конкретный класс. Это позволяет подменять в тестах любой имплементацией, соответствующей сигнатуре.

### 3. In-memory / no-op реализации

**Файл (создать):** `backend/app/core/pluggability/impls/__init__.py` — пустой.

**Файл (создать):** `backend/app/core/pluggability/impls/noop_notification.py`

```python
import logging
from uuid import UUID

logger = logging.getLogger(__name__)


class NoOpNotificationProvider:
    """Нулевая имплементация для 1.1A. В Sprint 3 заменяется на TelegramAdapter."""

    async def send(self, recipient: str, title: str, body: str, correlation_id: UUID | None = None) -> None:
        # Маскируем телефоны/chat_id в логах по правилу CLAUDE.md «Данные / ПД»
        masked_recipient = recipient[-4:].rjust(len(recipient), "*") if len(recipient) > 4 else "****"
        logger.info(
            "noop notification to=%s title=%s correlation_id=%s",
            masked_recipient, title, correlation_id,
        )
```

**Файл (создать):** `backend/app/core/pluggability/impls/db_audit_logger.py`

```python
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.services.audit import AuditService  # существующий сервис


class DbAuditLogger:
    """Адаптер над существующим AuditService под протокол AuditLoggerProtocol."""

    def __init__(self, db: AsyncSession) -> None:
        self._service = AuditService(db)

    async def log(
        self,
        actor_user_id: UUID | None,
        action: str,
        resource_type: str,
        resource_id: str | None,
        details: dict,
    ) -> None:
        await self._service.log(
            actor_user_id=actor_user_id,
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            details=details,
        )
```

**Если `AuditService` имеет другую сигнатуру** (например, не принимает `details: dict` напрямую) — адаптер маппит в корректную. **Не менять существующий AuditService** — это вне scope US-07.

**In-memory реализации для тестов:**

**Файл (создать):** `backend/app/core/pluggability/impls/in_memory_buses.py`

```python
from uuid import UUID

from app.core.events.business import BusinessEvent
from app.core.events.agent_control import AgentControlEvent


class InMemoryBusinessEventBus:
    def __init__(self) -> None:
        self.published: list[BusinessEvent] = []

    async def publish(self, event: BusinessEvent) -> None:
        self.published.append(event)


class InMemoryAgentControlBus:
    def __init__(self) -> None:
        self.published: list[AgentControlEvent] = []

    async def publish(self, event: AgentControlEvent) -> None:
        self.published.append(event)


class InMemoryNotificationProvider:
    def __init__(self) -> None:
        self.sent: list[tuple[str, str, str, UUID | None]] = []

    async def send(self, recipient: str, title: str, body: str, correlation_id: UUID | None = None) -> None:
        self.sent.append((recipient, title, body, correlation_id))


class InMemoryAuditLogger:
    def __init__(self) -> None:
        self.logs: list[dict] = []

    async def log(self, actor_user_id: UUID | None, action: str, resource_type: str, resource_id: str | None, details: dict) -> None:
        self.logs.append({
            "actor_user_id": actor_user_id, "action": action,
            "resource_type": resource_type, "resource_id": resource_id, "details": details,
        })
```

### 4. Заглушки (stubs) для 7 будущих точек

**Файл (создать):** `backend/app/core/pluggability/reserved.py`

Явный список зарезервированных ключей под ADR-0019, чтобы каркас был расширяемым:

```python
"""Зарезервированные pluggable points для 1.1B+ (ADR-0019).

Добавляются в container.py при реализации соответствующей US.
"""

RESERVED_PLUGGABLE_POINTS: tuple[str, ...] = (
    "AIProvider",
    "BankAdapter",
    "OFDAdapter",
    "1CAdapter",
    "RosreestrAdapter",
    "CryptoProvider",
    "ConfigurationCache",
)
```

Это просто константа, документирующая full scope ADR-0019. Используется в тесте § 5.4.

### 5. Тесты (≥3, реально ≥5)

**Файл (создать):** `backend/tests/unit/core/pluggability/__init__.py` — пустой.

**Файл (создать):** `backend/tests/unit/core/pluggability/test_container.py`

1. **`test_get_business_event_bus_returns_bus_instance`** — вызов `await get_business_event_bus(db)` возвращает объект, подтверждающий `BusinessEventBusProtocol` через `isinstance(obj, BusinessEventBusProtocol)`.
2. **`test_get_agent_control_bus_returns_different_type_than_business`** — `isinstance(bus, AgentControlBusProtocol)` и `not isinstance(bus, BusinessEventBus)` (через прямой импорт). Ключевой инвариант ADR-0019.
3. **`test_business_and_agent_bus_are_different_instances`** — `get_business_event_bus` и `get_agent_control_bus` возвращают классы разных типов (id != id, type != type). Даже если обе имплементации кастомные — `BusinessEventBusProtocol` проверкой через `issubclass` ловит случай, когда один класс реализует обе сигнатуры.
4. **`test_dependency_override_works`** — через `app.dependency_overrides[get_business_event_bus] = lambda: InMemoryBusinessEventBus()` подменяем имплементацию, FastAPI-endpoint использует in-memory. Интеграционный — через `TestClient`.
5. **`test_noop_notification_masks_recipient`** — `NoOpNotificationProvider.send("79991234567", ...)` → в логах `****4567` (проверка через `caplog`), никаких PII в plain text.
6. **`test_reserved_points_count`** — `len(RESERVED_PLUGGABLE_POINTS) == 7` (документируется scope 1.1B).
7. **`test_no_impl_satisfies_both_buses_protocols`** — для всех классов в `app.core.pluggability.impls.*` утверждаем: если `isinstance(inst, BusinessEventBusProtocol)` то `not isinstance(inst, AgentControlBusProtocol)` и наоборот. Ключевой инвариант — одна реализация не может быть зарегистрирована на оба ключа (ADR-0019).

### 6. Самопроверка

- [ ] Прочитан `CLAUDE.md`, `departments/backend.md`, ADR-0019 (RESERVED — суть + 11 точек), ADR-0014, ADR-0016.
- [ ] Выполнен ADR-gate:
  - A.1 — никаких литералов секретов
  - A.2 — новый код не делает SQL в сервисах/API; DbAuditLogger обёртка над существующим AuditService (через сервис — не через прямой execute)
  - A.3 — US-07 не трогает write-эндпоинты
  - A.4 — US-07 не трогает API-формат
  - A.5 — `AuditLogger` — pluggable version audit-логгера; production-реализация использует существующий путь ADR 0007
- [ ] Все протоколы `runtime_checkable`, тест-инвариант §5.7 проходит
- [ ] Маскирование ПД в логах `NoOpNotificationProvider` — обязательно (CLAUDE.md «Данные / ПД»)
- [ ] `pytest backend/tests/unit/core/pluggability/ -v` — ≥7 тестов зелёных
- [ ] Все 410+ существующих тестов зелёные
- [ ] `ruff`, `mypy app/core/pluggability` — чисто
- [ ] `git status` — только FILES_ALLOWED
- [ ] Не коммитить

---

## DoD

1. Пакет `backend/app/core/pluggability/` с файлами: `__init__.py`, `protocols.py`, `container.py`, `reserved.py`, `impls/__init__.py`, `impls/noop_notification.py`, `impls/db_audit_logger.py`, `impls/in_memory_buses.py`.
2. 4 pluggable points зарегистрированы и работают через `Depends()`.
3. `BusinessEventBusProtocol` и `AgentControlBusProtocol` — разные типы, инвариант «одна реализация не на обе точки» покрыт тестом.
4. 7 зарезервированных точек задокументированы в `RESERVED_PLUGGABLE_POINTS`.
5. Маскирование ПД в `NoOpNotificationProvider` (CLAUDE.md «Данные / ПД»).
6. ≥7 тестов в `backend/tests/unit/core/pluggability/`.
7. `ruff`, `mypy` — чисто. Существующие тесты зелёные.

---

## FILES_ALLOWED

- `backend/app/core/pluggability/__init__.py` — **создать**
- `backend/app/core/pluggability/protocols.py` — **создать**
- `backend/app/core/pluggability/container.py` — **создать**
- `backend/app/core/pluggability/reserved.py` — **создать**
- `backend/app/core/pluggability/impls/__init__.py` — **создать**
- `backend/app/core/pluggability/impls/noop_notification.py` — **создать**
- `backend/app/core/pluggability/impls/db_audit_logger.py` — **создать**
- `backend/app/core/pluggability/impls/in_memory_buses.py` — **создать**
- `backend/tests/unit/core/pluggability/__init__.py` — **создать**
- `backend/tests/unit/core/pluggability/test_container.py` — **создать**

## FILES_FORBIDDEN

- `backend/app/core/events/**` — US-04 / US-05. Только импортировать классы в `container.py`.
- `backend/app/core/integrations/**` — US-06. Только импортировать при необходимости (в 1.1A — нет, это в 1.1B).
- `backend/app/services/audit.py` — существующий сервис, не менять. `DbAuditLogger` — адаптер поверх.
- `backend/app/api/**` — US-07 не трогает эндпоинты. Если какой-то существующий API начал использовать `Depends(get_business_event_bus)` — это в отдельной US (Sprint 3 или 1.1B).
- `backend/app/api/deps.py` — **не трогать**. `get_db` уже там.
- Существующие модели, ADR, docs, frontend, CI workflows — не трогать.

**Overlap-риск:** US-07 импортирует `BusinessEventBus` и `AgentControlBus` → **блокируется мержем US-04 + US-05 в main**. Backend-head ждёт зелёные мержи US-04/05 перед стартом US-07.

---

## Зависимости

- **Блокирует:** Admin UI 1.1B (pluggable NotificationProvider); BPM M-OS-1.3 (обе шины через DI); US-12 Sprint 3 (TelegramAdapter регистрируется как NotificationProvider).
- **Блокируется:** US-04 (BusinessEventBus класс) + US-05 (AgentControlBus класс) — **обязательно оба замержены в main** до старта US-07.
- **Параллелен с:** ни с чем (US-04/US-05 уже закрыты к этому моменту, US-06 — независим, но может ещё идти параллельно; если US-06 не закрыт к старту US-07 — `NotificationProvider` в US-07 остаётся как `NoOpNotificationProvider`, Telegram-адаптер подменит его в Sprint 3).

---

## COMMUNICATION_RULES

- Перед стартом — убедиться что US-04 и US-05 замержены в main. Если нет — **стоп, эскалация backend-head**. Параллельно US-07 не стартует (иначе импорты будут сломаны).
- Перед стартом — прочитать `CLAUDE.md` (секции «Код», «Данные / ПД» — маскирование обязательно), `departments/backend.md`, ADR-0019 (RESERVED — прочитать суть и список 11 точек), ADR-0014, ADR-0016.
- Если `AuditService` имеет другую сигнатуру, чем ожидает `AuditLoggerProtocol` — **адаптировать в `DbAuditLogger`**, не менять `AuditService` (не в scope). Если адаптация невозможна (например, метода `log` нет вовсе) — **стоп, эскалация backend-head → backend-director**.
- Если `Protocol` не работает с `runtime_checkable` из-за async-методов — использовать `typing.Protocol` + `__subclasshook__` вручную; или в тесте полагаться на duck-typing без `isinstance`. Эскалация — если паттерн неясен.
- В тестах `dependency_overrides` — использовать `TestClient` с `app.dependency_overrides = {get_business_event_bus: lambda: InMemoryBusinessEventBus()}`; после теста — `app.dependency_overrides.clear()`.
- Никаких сторонних зависимостей.

---

## Обязательно прочитать перед началом

1. `/root/coordinata56/CLAUDE.md` — секции «Код», «Данные / ПД» (маскирование обязательно)
2. `/root/coordinata56/docs/agents/departments/backend.md` — ADR-gate A.1–A.5
3. `/root/coordinata56/docs/adr/0019-pluggability-contract.md` — RESERVED, список 11 точек, ключевой инвариант «BusinessEventBus ≠ AgentControlBus»
4. `/root/coordinata56/docs/adr/0014-anti-corruption-layer.md` — NotificationProvider в реестре
5. `/root/coordinata56/docs/adr/0016-domain-event-bus.md` — BusinessEventBus / AgentControlBus
6. `/root/coordinata56/docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md` — §Sprint 2 / US-10
7. Брифы US-04 и US-05 (`backend-dev-brief-us-04-sprint2-2026-04-19.md`, `backend-dev-brief-us-05-sprint2-2026-04-19.md`) — какие сигнатуры `publish` ожидают
8. `backend/app/services/audit.py` — существующий AuditService (сигнатура для DbAuditLogger-адаптера)
9. `backend/app/api/deps.py` — `get_db` (используется в контейнере)

---

## Отчёт (≤ 250 слов)

Структура:
1. **Пакет pluggability** — список файлов + LOC.
2. **4 DI-точки** — какие зарегистрированы, как тестируются.
3. **Протоколы** — `runtime_checkable`, cross-bus инвариант (тест-id).
4. **In-memory реализации** — перечислить.
5. **Маскирование ПД** — где применено, как проверено.
6. **Тесты** — число, результат `pytest`.
7. **Существующие тесты** — число и результат.
8. **ADR-gate** — A.1/A.2 pass/fail.
9. **Отклонения от scope** — если были.
