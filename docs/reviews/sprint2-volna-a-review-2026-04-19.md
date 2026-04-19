# Sprint 2 Volna A — финальное пост-merge ревью (Волна 12 Трек Y)

**Дата:** 2026-04-19
**Автор:** `review-head` (Начальник отдела ревью и безопасности, финальное cross-audit)
**Режим:** информативное ревью (код уже в main) — P0/P1 эскалируются в `bug_log.md` + alarm на revert/hotfix; P2/P3 — в отчёт без alarm.
**Источник распределения:** Pattern 5 §4 «финальное cross-audit делает review-head лично» (`departments/quality.md` v1.3). Reviewer-1 и Reviewer-2 не были физически спавнены (Anthropic-limit: Head не делает Agent-вызов); полный чек-лист прошёл лично Head с учётом, что в Sprint 2 все 4 US тематически связаны (two-bus + ACL + DI — один архитектурный слой Foundation Core).

**Объём:** 4 коммита, 23 файла (~2760 LoC), 30 тестов.

**Коммиты:**
- `6c2427e` US-04 BusinessEventBus skeleton (6 файлов, 561 LoC)
- `94d0f30` US-05 AgentControlBus skeleton (9 файлов, 597 LoC)
- `8c0ed94` US-06 IntegrationAdapter base / ACL (10 файлов, 740 LoC)
- `42f12c5` US-07 Pluggability container / Protocol-based DI (10 файлов, 862 LoC)

---

## Вердикты

| US | Коммит | Вердикт | P0 | P1 | P2 | P3 |
|---|---|---|---|---|---|---|
| US-04 BusinessEventBus | `6c2427e` | **accept-with-follow-up** | 0 | 0 | 1 | 2 |
| US-05 AgentControlBus | `94d0f30` | **accept-with-follow-up** | 0 | 0 | 2 | 1 |
| US-06 ACL (ADR-0014) | `8c0ed94` | **approve** | 0 | 0 | 0 | 1 |
| US-07 Pluggability | `42f12c5` | **approve** | 0 | 0 | 0 | 2 |

**Итог по волне:** 0 P0, 0 P1, 3 P2, 6 P3. AlarmCoordinator: **НЕ ТРЕБУЕТСЯ** (hotfix/revert не нужен). Sprint 2 Volna A принят с минорными follow-up.

---

## Полный прогон vs spot-check (калибровка)

**Режим:** полный прогон по всем 4 US.

**Обоснование:**
- US-04: коммит упоминает «ADR-gate A.1/A.2/A.5 pass», но **без ссылок на конкретные артефакты** (grep-вывод, diff-строки, test-id). По `departments/quality.md` правило 11 (RFC-007 Amendment B): критерий валидности self-check — артефакт-доказательство на каждый pass. Отсутствует → полный прогон.
- US-05: self-check A.1–A.5 в коммит-сообщении не упомянут → полный прогон.
- US-06: упоминает «ADR-gate A.1/A.2 pass» без артефактов → полный прогон.
- US-07: self-check не упомянут → полный прогон.

**Итог калибровки:** 4/4 без валидных self-check отчётов — backend-dev'ы Sprint 2 не выполнили требование артефакт-доказательств. **Рекомендация Директору качества:** при следующем запуске backend-head напомнить разработчикам: цитата CLAUDE.md + шаблон `A.1 pass: grep "password" backend/app/core/events/ → 0 hits` в PR-брифе.

---

## Дефекты

### US-04 BusinessEventBus (`6c2427e`)

- **P2-1 | Пароль БД-литерал в тесте US-05, не в US-04.** См. US-05 P2-1 (тест US-05 не затрагивает US-04, но шаблон — общий для обоих).
- **P3-1 | `__init__.py` events устарел.**
  `backend/app/core/events/__init__.py:8` — docstring утверждает «AgentControlBus — в M-OS-1.1B (Sprint 4+)», но `agent_control_bus.py` уже существует (US-05). Docstring не отражает реальную структуру пакета.
  Fix: обновить docstring в follow-up.
- **P3-2 | `BusinessEventRecord.created_at` использует строковый `server_default="now()"` вместо `server_default=func.now()`.**
  `backend/app/models/business_event.py:59`. Стилистика SQLA 2.0 требует `func.now()`. Поведение идентично (Postgres принимает оба), но теряется переносимость.
  Fix: заменить на `func.now()` в follow-up.

### US-05 AgentControlBus (`94d0f30`)

- **P2-1 | Литерал пароля тестовой БД в unit-тесте.**
  `backend/tests/unit/core/events/test_agent_control_bus.py:33`:
  ```python
  "postgresql+psycopg://coordinata:change_me_please_to_strong_password@localhost:5433/coordinata56_test"
  ```
  CLAUDE.md §Секреты: «Никогда не литералить пароли, токены, секреты — нигде (src/, tests/, conftest.py)». Однако это **повторение существующего паттерна Sprint 1** (BUG-005, открытый) — пароль тестовой БД разбросан по 15+ файлам. Новый тест копирует известный баг, не создаёт регрессию; исправлять централизованно (BUG-005) — не в этом ревью.
  Severity: P2 (паттерн-долг, не secret-leak). При закрытии BUG-005 — поправить и здесь.
- **P2-2 | Два разных подхода к тестам одинаковых классов.**
  `test_business_bus.py` (US-04) использует `AsyncMock/MagicMock`; `test_agent_control_bus.py` (US-05) использует **реальную AsyncSession + apply_migrations**. Разные инфра-требования для одинаковых юнит-тестов. Принцип «минимальной достаточности» нарушен — US-05 требует живой Postgres для тех же 4 тестов, которые US-04 гоняет на моках.
  Fix: в follow-up привести US-05 тесты к паттерну `AsyncMock` (как US-04), удалить зависимость от БД в unit-тестах. Текущая реализация работает, но нарушает консистентность слоя.
- **P3-1 | `AgentControlEventRecord.occurred_at` имеет `server_default=func.now()`, `BusinessEventRecord.occurred_at` — нет.**
  Models: `business_event.py:51` (без default) vs `agent_control_event.py:62-65` (`server_default=func.now()`). Miграции согласованны с ORM. Но два brother-класса имеют разную семантику `occurred_at` по дефолту — в US-05 можно пропустить `occurred_at`, в US-04 нельзя.
  Pydantic-слой компенсирует (`BusinessEvent.occurred_at = Field(default_factory=...)`), но на уровне БД поведение различается. Нефункциональное расхождение, но P3 на стиль.

### US-06 ACL / ADR-0014 (`8c0ed94`)

- **P3-1 | Лишний `allow_unix_socket=True` в локальном conftest.**
  `tests/unit/core/integrations/conftest.py:30` — документирован как «asyncio требует socketpair». Корректно, но это **диагностический workaround**, а не обязательное требование pytest-socket. Прагматично; объяснено в docstring. Без исправления.

**US-06 approve.** Все 5 шагов ADR-0014 guard реализованы в `base.py:140-167`. TTL = 60 (settings default). `AdapterDisabledError` — дефолт при unknown state (строки 163-167). pytest-socket — **локальный** conftest (не сломает 420 существующих тестов). ABC-контракт через `__init_subclass__` + abstractmethod. 11 тестов покрывают все 5 шагов + TTL + invalidation + fail-fast.

### US-07 Pluggability / ADR-0019 (`42f12c5`)

- **P3-1 | `DbAuditLogger` делает downcast UUID → int (`_resolve_entity_id`) молча.**
  `impls/db_audit_logger.py:61-64` — при невозможности int-конвертации resource_id возвращается None без логирования. «В 1.1B AuditService получит поддержку UUID». Трассировочно теряется entity_id без warning.
  Fix: добавить `logger.warning("UUID resource_id downcast to None ...")`.
- **P3-2 | `test_no_impl_satisfies_both_buses_protocols` проверяет subclass, но не Protocol.**
  `tests/.../test_container.py:256-261` — `not issubclass(BusinessEventBus, AgentControlBus)` — корректный структурный инвариант, но runtime-guard остаётся ключевой защитой (тесты 2-3 в том же файле). Документировано, без исправления.

**US-07 approve.** Protocol-based DI через `typing.Protocol` + `runtime_checkable` — прямое соответствие ADR-0019. 4 pluggable точки в container.py, 7 зарезервированных в `reserved.py`. Маскирование ПД (`recipient[-4:]`) в `NoOpNotificationProvider:42-45`. Ключевой инвариант `BusinessEventBus ≠ AgentControlBus` verified через 5 проверок в test 7.

---

## Положительные моменты (для replication)

1. **Физическая изоляция двух шин выполнена эталонно.**
   - Раздельные таблицы (`business_events` с `company_id` nullable + FK, `agent_control_events` без company_id).
   - Раздельные Pydantic-корни без общего предка.
   - Раздельные Bus-классы с `assert isinstance(event, X)` в `publish()`.
   - Протоколы `BusinessEventBusProtocol` ≠ `AgentControlBusProtocol` — нельзя зарегистрировать одну реализацию на оба ключа DI.
   - Тест-инварианты в обоих местах (business_bus тест 4, agent_control_bus тест 3, container тест 7).
2. **ADR-0011 exception правильно задокументирован в US-04.**
   `company_id` nullable в `business_events` — комментарии в миграции (строка 54), ORM (строка 41), Pydantic (строка 27-29), docstring миграции (строки 8-11). Каждое место ссылается на ADR-0016 §«Две физически раздельные таблицы». **Это эталон документирования ADR-exception — рекомендую promote в `departments/backend.md`.**
3. **ADR-0014 §Runtime-guard 5 шагов — hook-free implementation.**
   `base.py:140-167` — чистый линейный if/elif/raise без side-effects. TTL-кеш на module-level с явной инвалидацией (`invalidate_state_cache(name | None)`). `__init_subclass__` fail-fast.
4. **pytest-socket в ЛОКАЛЬНОМ conftest.** Не сломал 420 pre-existing тестов. Решение, принятое в брифе US-06, корректно реализовано и задокументировано в docstring conftest.

---

## Метрики волны

| Метрика | Значение |
|---|---|
| Worker'ов в волне | 4 (US-04 + US-05 + US-06 + US-07) |
| Reviewer'ов (Pattern 5 §4 финал) | 1 (review-head лично) |
| Раундов ревью | 1 (post-merge, односторонний) |
| Тесты: total / pass | 30 / 30 |
| Время прогона unit-тестов core/ | 1.28 сек |
| Flaky-тесты | 0 |
| Время финального ревью | ~55 мин (read + test + grep + отчёт) |
| % approve с первого раза | 50% (2/4 approve, 2/4 accept-with-follow-up) |
| LoC added | 2 760 |
| Самых значимых P0/P1 | 0 / 0 |
| P2 / P3 | 3 / 6 |

**Сравнение с Батчем A (2026-04-15):** Батч A — 4 P0 + 5 P1 на 4 сущности; Sprint 2 Volna A — 0 P0 + 0 P1 на 4 US. **Улучшение 100%.** Критерий `departments/quality.md` таблицы метрик (≤2 P0 + ≤3 P1 на батч) — перевыполнен.

---

## Open questions (архитектурные)

1. **Единый тестовый DSN.** Литерал пароля `change_me_please_to_strong_password` в 15+ файлах (BUG-005 + новый тест US-05). Требуется централизация в `conftest.py` через os.environ.get с dev-default через `.env.example`. Амендмент в `backend.md` §Правил: «DSN тестовой БД — только через `TEST_DATABASE_URL` env; fallback — в корневом conftest, никогда не в локальном тесте».
2. **Разные подходы unit-тестов для двух симметричных шин (US-04 mocks vs US-05 real DB).** Нужен регламент: в `departments/backend.md` зафиксировать: «unit-тесты `publish()` используют `AsyncMock`; integration-тесты `publish()` + FK/constraints — отдельный файл в `tests/integration/`».
3. **ORM consistency для `occurred_at`.** Решение — Amendment ADR-0016: должен ли `occurred_at` иметь server_default или всегда задаётся Pydantic? Рекомендация: `server_default=func.now()` в обеих моделях + Pydantic `default_factory` — двойная защита.

---

## Следующие шаги

1. **Директор качества → Координатору** (верхний уровень ≤300 слов, см. сводный отчёт ниже).
2. **Follow-up задача backend-head:** 3 P2 + 6 P3 в один дев-бриф (1-2 часа работы одного Sonnet backend-dev) как часть Sprint 2 Volna B tidying.
3. **Governance-director → ADR-0016 Amendment:** вопрос 3 (`occurred_at` ORM consistency) — короткий amendment без ratification.
4. **Quality-director → `bug_log.md`:** P2-1 US-05 — **НЕ добавлять отдельным BUG**, т.к. это проявление открытого BUG-005.
