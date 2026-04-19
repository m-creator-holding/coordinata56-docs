ultrathink

# Дев-бриф US-06 (Sprint 2) — IntegrationAdapter базовый класс + 3 состояния (ACL по ADR-0014)

- **Дата:** 2026-04-19
- **Автор:** backend-director (через backend-head при распределении)
- **Получатель:** backend-dev-3 (ведущий)
- **Фаза:** M-OS-1.1A, Sprint 2 (нед. 3–4)
- **Приоритет:** P0 — центральный кирпич Anti-Corruption Layer; блокирует будущие US-11/12 (integration_catalog seed + Telegram refactor в Sprint 3).
- **Оценка:** L — 3 рабочих дня (1 день base/exceptions/state, 1 день runtime-guard + TTL-кеш, 1 день тесты + self-check).
- **Scope-vs-ADR:** verified (ADR-0014 §«Базовый класс и интерфейс адаптера», §«Три состояния адаптера», §«Runtime-guard», §«Обязательный mock-режим»; ADR-0013 — миграций в этой US нет). Gaps: `integration_catalog` как таблица — в US-11 Sprint 3; US-06 использует **временный in-memory registry** для чтения состояния до появления реальной таблицы (fallback pattern, описан в §4).
- **Источник формулировки:** `docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md` §Sprint 2 / US-07 + US-08 (объединены в US-06 по формулировке Координатора 2026-04-19).

---

## Контекст

ADR-0014 (Anti-Corruption Layer) — принят force-majeure 2026-04-18 governance-auditor в backup-mode. Требует единого каркаса для всех внешних интеграций: адаптер без mock-режима и без runtime-guard в main не мержится. CODE_OF_LAWS ст. 45а/45б запрещает живые вызовы к банкам/ОФД/1С/Росреестру до production-gate — эта US-06 реализует **техническую защиту** от такого вызова на уровне кода.

Схема работы после US-06:
1. Разработчик пишет `class SberbankAdapter(IntegrationAdapter)` с обязательными `_live_transport` (реальный HTTPS) и `_mock_transport` (фикстурный ответ).
2. Вызов `adapter.call(...)` проходит через `IntegrationAdapter.call()`, который читает состояние из реестра (in-memory кеш, TTL 60 сек).
3. Если `state == 'written'` → `AdapterDisabledError`.
4. Если `state == 'enabled_mock'` → `_mock_transport`, сокет не открывается.
5. Если `state == 'enabled_live'` и `APP_ENV != 'production'` → `AdapterDisabledError`.
6. Если `state == 'enabled_live'` и `APP_ENV == 'production'` → `_live_transport`.

**Зависимости от US-04 в этом Sprint 2:** при изменении состояния адаптера в (будущей) таблице `integration_catalog` публикуется `AdapterStateChanged` в `BusinessEventBus` — подписчик инвалидирует кеш. В US-06 **подписчик не реализуем** (это 1.1B); но инвалидация через модуль-функцию `invalidate_state_cache(adapter_name)` должна быть доступна — её вызовет in-1.1B код, когда появится real subscriber.

**Сжатый scope Sprint 2 (по формулировке Координатора):** базовый класс + 3 состояния + runtime-guard + TTL-кеш + `pytest-socket`. **Без** `integration_catalog` таблицы (это US-11 Sprint 3), **без** Telegram refactor (это US-12 Sprint 3).

---

## Что конкретно сделать

### 1. Enum AdapterState

**Файл (создать):** `backend/app/core/integrations/__init__.py` — пустой.

**Файл (создать):** `backend/app/core/integrations/state.py`

```python
from enum import StrEnum


class AdapterState(StrEnum):
    """Три состояния адаптера по ADR-0014 §«Три состояния адаптера»."""

    WRITTEN = "written"              # код есть, нигде не подключён, mock-only в тестах
    ENABLED_MOCK = "enabled_mock"    # подключён в dev/test, принудительно mock-транспорт
    ENABLED_LIVE = "enabled_live"    # живые вызовы разрешены, только в APP_ENV=production
```

### 2. Исключение AdapterDisabledError

**Файл (создать):** `backend/app/core/integrations/exceptions.py`

```python
class AdapterDisabledError(RuntimeError):
    """Вызов адаптера заблокирован политикой (ADR-0014)."""

    def __init__(self, adapter_name: str, state: str, reason: str) -> None:
        self.adapter_name = adapter_name
        self.state = state
        self.reason = reason
        super().__init__(f"Adapter '{adapter_name}' (state={state}) blocked: {reason}")
```

### 3. Базовый класс IntegrationAdapter

**Файл (создать):** `backend/app/core/integrations/base.py`

```python
import time
from abc import ABC, abstractmethod
from typing import Any, ClassVar

from app.core.config import settings
from app.core.integrations.exceptions import AdapterDisabledError
from app.core.integrations.state import AdapterState


# Module-level TTL-кеш: {adapter_name: (state, cached_at_monotonic)}
_state_cache: dict[str, tuple[AdapterState, float]] = {}


def invalidate_state_cache(adapter_name: str | None = None) -> None:
    """Сбросить кеш состояния адаптера. adapter_name=None → сбросить весь кеш.

    Вызывается из подписчика BusinessEventBus на событие AdapterStateChanged (1.1B).
    В 1.1A вызывается вручную (например, при seed-миграции US-11 Sprint 3).
    """
    if adapter_name is None:
        _state_cache.clear()
    else:
        _state_cache.pop(adapter_name, None)


class IntegrationAdapter(ABC):
    """Базовый класс всех внешних интеграций M-OS. ADR-0014."""

    adapter_name: ClassVar[str]  # обязателен в каждом наследнике

    def __init_subclass__(cls, **kwargs: Any) -> None:
        super().__init_subclass__(**kwargs)
        if not hasattr(cls, "adapter_name") or not cls.adapter_name:
            raise TypeError(f"{cls.__name__} must define non-empty class attribute 'adapter_name'")

    async def get_state(self) -> AdapterState:
        """Чтение состояния из реестра (TTL-кеш 60 сек)."""
        now = time.monotonic()
        cached = _state_cache.get(self.adapter_name)
        if cached is not None:
            state, cached_at = cached
            if now - cached_at < settings.ADAPTER_STATE_CACHE_TTL:
                return state
        state = await self._read_state_from_registry()
        _state_cache[self.adapter_name] = (state, now)
        return state

    async def _read_state_from_registry(self) -> AdapterState:
        """Чтение из реестра. В 1.1A — заглушка (in-memory registry), в 1.1B/Sprint 3 —
        чтение из integration_catalog через repository (US-11).
        """
        # Fallback-реализация на 1.1A: всё, кроме явно зарегистрированных в in-memory registry — written
        return _InMemoryRegistry.get(self.adapter_name, AdapterState.WRITTEN)

    async def call(self, *args: Any, **kwargs: Any) -> Any:
        """Публичный метод вызова. Всегда проходит через guard по ADR-0014 §«Runtime-guard»."""
        state = await self.get_state()

        if state == AdapterState.WRITTEN:
            raise AdapterDisabledError(
                self.adapter_name, state, "Adapter not enabled in any environment"
            )
        if state == AdapterState.ENABLED_MOCK:
            return await self._mock_transport(*args, **kwargs)
        if state == AdapterState.ENABLED_LIVE:
            if settings.APP_ENV != "production":
                raise AdapterDisabledError(
                    self.adapter_name, state,
                    f"enabled_live not allowed in APP_ENV={settings.APP_ENV}",
                )
            return await self._live_transport(*args, **kwargs)

        raise AdapterDisabledError(self.adapter_name, str(state), "Unknown adapter state")

    @abstractmethod
    async def _live_transport(self, *args: Any, **kwargs: Any) -> Any:
        """Реальный сетевой вызов. Запрещено: прямые httpx/requests вне этого метода."""

    @abstractmethod
    async def _mock_transport(self, *args: Any, **kwargs: Any) -> Any:
        """Детерминированный mock-ответ. Обязателен у каждого наследника (ADR-0014)."""


# In-memory registry для 1.1A — заменяется чтением из integration_catalog в US-11 Sprint 3
_InMemoryRegistry: dict[str, AdapterState] = {}


def _register_for_tests(adapter_name: str, state: AdapterState) -> None:
    """Helper для тестов — регистрирует состояние адаптера в in-memory registry.

    Не использовать в production-коде. В US-11 заменяется на БД-репозиторий.
    """
    _InMemoryRegistry[adapter_name] = state
    invalidate_state_cache(adapter_name)
```

**Ключевые моменты:**
- `__init_subclass__` — ловит наследников без `adapter_name` в момент импорта класса (fail-fast).
- `_state_cache` — module-level dict, общий для процесса (ADR-0014 §«Runtime-guard», ADR-0014 US-08 из исходной декомпозиции).
- `invalidate_state_cache` — module-level функция, будет вызвана из `BusinessEventBus`-подписчика в 1.1B.
- `_read_state_from_registry` — заглушка через `_InMemoryRegistry`; явно помечено как fallback под замену в US-11.
- Абстрактные `_live_transport` и `_mock_transport` — если наследник не реализует — `TypeError` при создании экземпляра (Python native ABC).

### 4. Настройка в config

**Файл:** `backend/app/core/config.py` (существует, **менять осторожно**)

Добавить в `Settings`:

```python
class Settings(BaseSettings):
    ...
    APP_ENV: Literal["dev", "test", "staging", "production"] = "dev"
    ADAPTER_STATE_CACHE_TTL: int = 60  # сек, ADR-0014
    ...
```

Если `APP_ENV` уже есть — не дублировать, только проверить что тип `Literal` корректен.

### 5. pytest-socket автоматический блок сети

**Файл:** `backend/requirements.txt` (или `pyproject.toml` — сверить текущий паттерн)

Добавить `pytest-socket>=0.7.0`.

**Файл:** `backend/conftest.py` (корневой, существует)

```python
# Добавить (если ещё нет)
import pytest
from pytest_socket import disable_socket, enable_socket


@pytest.fixture(autouse=True)
def _disable_network():
    """ADR-0014: pytest-socket блокирует все сокеты по умолчанию.
    Интеграционные тесты с реальной сетью помечаются @pytest.mark.allow_network.
    """
    disable_socket()
    yield
    enable_socket()


def pytest_collection_modifyitems(config, items):
    """@pytest.mark.allow_network разрешает сеть для конкретного теста."""
    for item in items:
        if item.get_closest_marker("allow_network"):
            item.fixturenames = [f for f in item.fixturenames if f != "_disable_network"]
```

**Важно:** изменение корневого `conftest.py` потенциально ломает существующие 410+ тестов (те, которые используют БД через сеть Postgres). Проверить: `pytest-socket` по умолчанию разрешает Unix-сокеты и `localhost`/`127.0.0.1` через параметр `--allow-hosts` или отдельную настройку `socket_allow_hosts`. **Обязательно перед сдачей** — убедиться что все 410+ тестов зелёные. Если падают — сконфигурировать `pytest-socket` так, чтобы Postgres-соединения проходили (через `ALLOWED_HOSTS=localhost,127.0.0.1,db` или аналогичный механизм).

Если это ломает тесты критически — **стоп, эскалация backend-head → backend-director**. Тогда `pytest-socket` подключается только для `tests/unit/core/integrations/`.

### 6. Тесты (≥3, реально ≥5)

**Файл (создать):** `backend/tests/unit/core/integrations/__init__.py` — пустой.

**Файл (создать):** `backend/tests/unit/core/integrations/test_adapter_base.py`

1. **`test_subclass_without_adapter_name_fails`** — попытка создать класс без `adapter_name` падает `TypeError` в момент определения класса.
2. **`test_state_written_raises_disabled`** — адаптер с `state=WRITTEN` при `call()` → `AdapterDisabledError`, socket не открывается (pytest-socket это гарантирует).
3. **`test_state_enabled_mock_calls_mock_transport`** — `state=ENABLED_MOCK` → `_mock_transport` вызван ровно 1 раз, `_live_transport` — 0 раз.
4. **`test_state_enabled_live_in_dev_raises_disabled`** — `state=ENABLED_LIVE`, `APP_ENV=dev` → `AdapterDisabledError`.
5. **`test_state_enabled_live_in_production_calls_live`** — `state=ENABLED_LIVE`, `APP_ENV=production` (через monkeypatch) → `_live_transport` вызван. **Важно:** сам `_live_transport` должен быть mock-фикстурой, не реальным сокетом (pytest-socket всё равно защитит, но тест должен быть чистым).
6. **`test_state_cache_ttl`** — первый `get_state()` читает из registry (фиксируем counter), второй — из кеша (counter не растёт), после `time.monotonic()+=61` — снова читает.
7. **`test_invalidate_state_cache_works`** — после `invalidate_state_cache("foo")` следующий `get_state()` читает из registry.
8. **`test_abstract_methods_enforced`** — попытка создать экземпляр наследника без `_live_transport` / `_mock_transport` → `TypeError` (ABC native).

**Файл (создать):** `backend/tests/unit/core/integrations/test_no_network_leak.py`

Мета-тест:
9. **`test_pytest_socket_blocks_external_http`** — попытка `httpx.get("https://example.com")` в unit-тесте падает `SocketBlockedError`.
10. **`test_no_hardcoded_external_urls`** — grep по `backend/app/` не находит `http(s)://` вне `_live_transport`-методов, `settings.py`, docstring-ов. Список allowlist: `backend/app/core/config.py`, любой `**/adapters/*._live_transport` метод. Реализовать через `pathlib.rglob` + regex, без зависимостей.

### 7. Самопроверка

- [ ] Прочитан `CLAUDE.md`, `departments/backend.md`, ADR-0014 полностью, ADR-0013
- [ ] Выполнен ADR-gate:
  - A.1 — никаких литералов секретов
  - A.2 — в `_read_state_from_registry` сейчас заглушка (dict), SQL-запросов нет; в 1.1B/US-11 — через repository
  - A.3 / A.4 / A.5 — не применимо (US-06 не трогает API)
- [ ] `pytest-socket` подключён, все 410+ существующих тестов зелёные (Postgres-соединения проходят)
- [ ] Новые тесты (≥9) зелёные
- [ ] `ruff check app/core/integrations tests/unit/core/integrations` — чисто
- [ ] `mypy app/core/integrations` — чисто
- [ ] `git status` — только FILES_ALLOWED
- [ ] Не коммитить

---

## DoD

1. Пакет `backend/app/core/integrations/` с файлами: `__init__.py`, `base.py`, `exceptions.py`, `state.py`.
2. Класс `IntegrationAdapter` реализует 5-шаговый guard ADR-0014.
3. TTL-кеш 60 сек (module-level), `invalidate_state_cache()` работает.
4. `AdapterDisabledError` — подкласс `RuntimeError`.
5. Enum `AdapterState` с 3 значениями.
6. `pytest-socket` блокирует все нелокальные сокеты в CI; все 410+ тестов зелёные.
7. ≥9 тестов в `backend/tests/unit/core/integrations/test_adapter_base.py` + `test_no_network_leak.py` зелёные.
8. `ruff`, `mypy` — чисто.

---

## FILES_ALLOWED

- `backend/app/core/integrations/__init__.py` — **создать**
- `backend/app/core/integrations/base.py` — **создать**
- `backend/app/core/integrations/exceptions.py` — **создать**
- `backend/app/core/integrations/state.py` — **создать**
- `backend/app/core/config.py` — добавить `APP_ENV` (если отсутствует) + `ADAPTER_STATE_CACHE_TTL`
- `backend/requirements.txt` (или `pyproject.toml`) — добавить `pytest-socket`
- `backend/conftest.py` — добавить autouse-fixture `_disable_network`
- `backend/tests/unit/core/integrations/__init__.py` — **создать**
- `backend/tests/unit/core/integrations/test_adapter_base.py` — **создать**
- `backend/tests/unit/core/integrations/test_no_network_leak.py` — **создать**

## FILES_FORBIDDEN

- `backend/app/core/events/**` — US-04 / US-05 (параллельные разработчики).
- `backend/app/core/container.py` — US-07.
- `backend/app/api/**`, `backend/app/services/**` — не трогать.
- Существующие модели, ADR, docs, frontend, CI workflows — не трогать.
- `backend/alembic/**` — в US-06 **нет миграций** (они в US-11 Sprint 3 с таблицей `integration_catalog`).
- `backend/app/core/integrations/telegram.py` — US-12 Sprint 3 (это Telegram refactor).
- Существующий Telegram-код (если есть в `backend/app/services/notifications/` или подобном) — не трогать.

**Overlap-риск:** с US-04/US-05 — нулевой (разные пакеты). С US-07 — может возникнуть если US-07 захочет регистрировать `IntegrationAdapter`-наследники в `container.py`; backend-head следит что US-07 пишется **после** мержа US-06.

---

## Зависимости

- **Блокирует:** US-11 Sprint 3 (реестр `integration_catalog` — реальный source of truth для `_read_state_from_registry`); US-12 Sprint 3 (Telegram refactor); US-07 Sprint 2 (Pluggability — может регистрировать фабрику адаптеров).
- **Блокируется:** US-04 в смысле события `AdapterStateChanged` — но US-06 не реализует subscriber, поэтому **не ждёт** US-04 строго. Разработчик US-06 может использовать `AdapterStateChanged` только если US-04 замержен; если нет — реализуем без упоминания события (просто runtime-guard + TTL-кеш + `invalidate_state_cache` как module-level функция).
- **Параллелен с:** US-04, US-05 (разные пакеты, overlap = 0).

---

## COMMUNICATION_RULES

- Перед стартом — прочитать `CLAUDE.md`, `departments/backend.md`, ADR-0014 **полностью**, ADR-0013.
- Если `pytest-socket` ломает существующие тесты (Postgres через сеть) — **не пытаться «починить в лоб»** через allowlist на весь хост. **Стоп, эскалация backend-head**. Возможно, нужна точечная настройка `socket_allow_hosts=["localhost", "127.0.0.1", "db"]` в `conftest.py`. Если и это не работает — подключать `pytest-socket` только в `tests/unit/core/integrations/conftest.py` (локальный conftest), не корневой.
- Если `AdapterStateChanged` не доступен (US-04 ещё не замержен) — **не импортировать** его в US-06. Используем только module-level `invalidate_state_cache()` (без подписчика). Подписчик на `AdapterStateChanged` — в 1.1B.
- Если при реализации `APP_ENV` обнаруживается, что в `config.py` уже есть поле с другим именем (`ENVIRONMENT`, `ENV`) — **не переименовывать** существующее; использовать имеющееся, обновить константы тестов. Эскалация backend-head если сомневаетесь.
- Никаких литеральных URL в коде (даже в docstring-ах) — только `_live_transport` может содержать `settings.TELEGRAM_API_BASE` (в US-12).
- Никаких сторонних зависимостей кроме `pytest-socket`.

---

## Обязательно прочитать перед началом

1. `/root/coordinata56/CLAUDE.md` — секции «Секреты и тесты», «API», «Код»
2. `/root/coordinata56/docs/agents/departments/backend.md` — ADR-gate A.1–A.5
3. `/root/coordinata56/docs/adr/0014-anti-corruption-layer.md` — §«Три состояния», §«Базовый класс», §«Runtime-guard», §«DoD для внедрения» (реализуем пункты 1–9 + 14; пункт 10 `integration_catalog` seed — НЕ в US-06)
4. `/root/coordinata56/docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md` — §Sprint 2 / US-07 + US-08
5. `backend/app/core/config.py` — посмотреть имеющуюся структуру Settings
6. `backend/conftest.py` — посмотреть имеющиеся autouse-fixtures
7. pytest-socket docs — `socket_allow_hosts`, `socket_disabled`

---

## Отчёт (≤ 250 слов)

Структура:
1. **Пакет integrations** — список созданных файлов + LOC.
2. **IntegrationAdapter** — краткое описание реализации guard (5 шагов).
3. **TTL-кеш** — paradigm (module-level), инвалидация.
4. **AdapterState + AdapterDisabledError** — пути.
5. **pytest-socket** — как подключён, как прошли 410+ существующих тестов (или какая настройка потребовалась).
6. **Тесты** — число, результат.
7. **ADR-gate** — A.1 / A.2 pass/fail.
8. **Отклонения от scope** — если были (например, `pytest-socket` ограничил до tests/unit/core).
