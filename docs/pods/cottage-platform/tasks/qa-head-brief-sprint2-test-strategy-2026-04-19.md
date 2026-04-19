# Бриф qa-head (+ ri-analyst advisory): расширение Test Strategy под Sprint 2

**Дата:** 2026-04-19
**От:** quality-director
**Кому:** qa-head (primary, формирует практический план) + ri-analyst (advisory — консультирует по bus/ACL-контрактам и pod-boundary)
**Приоритет:** P1 — должно быть готово до старта Sprint 2 (ориентир: конец текущей недели)
**Оценка:** 1 рабочий день (qa-head: 4–6 часов, ri-analyst: 1–2 часа консультации через Координатора)
**Триггер:** закрытие Sprint 1 gate → подготовка Sprint 2 (US-04 Event Bus tables, US-05 Bus publish intfs, US-06 cross-bus-import CI-gate, US-07 IntegrationAdapter base)
**Коммит:** НЕ коммитить — передать артефакты Координатору для sign-off quality-director

---

## ultrathink

## Цель

Расширить существующий документ `docs/pods/cottage-platform/quality/test-strategy-m-os-1-1a-2026-04-18.md` секциями, детализирующими тестирование US-04 / US-05 / US-06 / US-07 (всего Sprint 2 скоуп по декомпозиции 1.1A). Базовая стратегия уже описывает эти US в §2 Sprint 2 и §4 Sprint 2 gate, но на уровне «что», не на уровне «как». Этот бриф — про расширение «как».

**Фокус расширения:**
1. **Bus isolation** — практические тесты: как изолируем `BusinessEventBus` от `AgentControlBus` на контрактном, рантайм- и CI-уровне.
2. **Adapter state transitions** — полная матрица 3 state × 2 env = 6 случаев + негативные пути + состояния гонки при смене `enabled` во время `call()`.
3. **Pod-boundary contracts** — новая зона: как тестируем, что cottage-platform pod не утечёт в core или другой pod через Event Bus payload или ACL-adapter. Это первый pod в M-OS, precedent для будущих.

**Exit criterion:** существующий `test-strategy-m-os-1-1a-2026-04-18.md` получает новый §12 (или правится §2 Sprint 2 + §4 Sprint 2 gate — на усмотрение qa-head, главное не ломать нумерацию), содержащий конкретные pytest-файлы с именами тестов и покрываемыми сценариями, готовые для делегирования qa-1/qa-2 в начале Sprint 2.

## Обязательно прочесть

1. `/root/coordinata56/CLAUDE.md`
2. `/root/coordinata56/docs/agents/departments/quality.md` v1.3 (всё)
3. `/root/coordinata56/docs/pods/cottage-platform/quality/test-strategy-m-os-1-1a-2026-04-18.md` — **расширяем его**, не дублируем
4. `/root/coordinata56/docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md` §Sprint 2
5. ADR 0009 (pod-архитектура), ADR 0010 (таксономия субагентов), ADR 0014 (ACL + Amendment 2026-04-18), ADR 0016 (Dual Event Bus, кандидат)
6. Существующий code:
   - `backend/app/core/events/` (если уже появились первые файлы)
   - `backend/app/core/integrations/` (ACL base class)
   - `backend/app/pods/cottage_platform/` (pod boundary)

## Скоуп работ

### 1. Bus isolation — расширение §2 Sprint 2 US-04/05

qa-head должен прописать **минимум 6 контрактных тестов** bus-isolation и **минимум 4 integration**. Базовый лист:

| Тест | Файл | Уровень | Сценарий |
|---|---|---|---|
| `test_business_bus_rejects_agent_event` | `tests/events/test_bus_contracts.py` | Contract | `BusinessEventBus.publish(AgentControlEvent(...))` → ValidationError с конкретным message |
| `test_agent_bus_rejects_business_event` | `tests/events/test_bus_contracts.py` | Contract | зеркально |
| `test_business_bus_accepts_only_business_subclasses` | `tests/events/test_bus_contracts.py` | Contract | `__subclasses__()` проверка: все допускаемые — наследники `BusinessEvent` |
| `test_bus_distinct_singleton_instances` | `tests/events/test_bus_wiring.py` | Unit | `get_business_event_bus()` и `get_agent_control_bus()` возвращают разные объекты (`id()` проверка) |
| `test_discriminator_by_event_type_strict` | `tests/events/test_bus_contracts.py` | Contract | Pydantic discriminator на `event_type`; payload с чужим `event_type` → ValidationError |
| `test_schema_evolution_adds_new_event_type` | `tests/events/test_bus_contracts.py` | Contract | Добавление нового BusinessEvent подкласса не ломает существующую публикацию (regression-защита на будущее) |
| `test_publish_transactional_rollback` | `tests/events/test_bus_publish.py` | Integration | publish внутри DB-транзакции, rollback → событие не в таблице |
| `test_publish_atomic_with_domain_write` | `tests/events/test_bus_publish.py` | Integration | одна транзакция: Payment.create + BusinessEvent.publish; если payment.INSERT упал — event не записан |
| `test_cross_bus_no_leakage_in_db` | `tests/events/test_bus_publish.py` | Integration | after `BusinessEventBus.publish(...)` → `agent_control_events` таблица остаётся пустой |
| `test_append_only_constraint_db_level` | `tests/events/test_bus_publish.py` | Integration | UPDATE/DELETE на `business_events` в чистой БД → IntegrityError (constraint) |

qa-head расписывает для каждого теста: ожидаемый assertion, фикстуры, параметризация.

### 2. Adapter state transitions — расширение §2 Sprint 2 US-07 + §6 Risk R4

Базовый лист уже упоминает 6 case'ов. Расширить до полной матрицы + edge:

| case | state | APP_ENV | ожидание |
|---|---|---|---|
| 1 | `written` | dev | `AdapterDisabledError("state=written")` |
| 2 | `written` | production | `AdapterDisabledError("state=written")` |
| 3 | `enabled_mock` | dev | `_mock_transport` вызывается |
| 4 | `enabled_mock` | production | `_mock_transport` вызывается (mock разрешён в prod как fallback) **или** `AdapterDisabledError` — решение за ADR-0015, qa-head фиксирует обе ветки и параметризует по ADR-решению |
| 5 | `enabled_live` | dev | `AdapterDisabledError("live disabled in dev")` |
| 6 | `enabled_live` | production | `_live_transport` вызывается (единственный путь через сеть) |

Добавить **edge-cases** (qa-head должен прописать явно):
- `test_state_change_during_call` — во время исполнения `call()` другой поток меняет `enabled` в БД. Поведение: уже начатый вызов не прерывается (TTL-кеш держит старое), новый вызов после TTL видит новое state.
- `test_missing_mock_transport_fails_import` — наследник `IntegrationAdapter` без `_mock_transport` → ImportError / ABC abstractmethod error.
- `test_live_transport_gated_by_settings_not_state_alone` — даже при `state=enabled_live` и `APP_ENV=production`, если `settings.EXTERNAL_INTEGRATIONS_ALLOWED=False` — `AdapterDisabledError`. Дополнительный guard.
- `test_socket_block_in_test_env` — под pytest-socket autouse попытка live-вызова в тесте → `SocketBlockedError` (безопасность-по-умолчанию).
- `test_call_records_audit_on_success_and_failure` — любой `call()` пишет в audit_log: `integration_called` с `adapter_name`, `success/fail`, `latency_ms`. Provides trace for incidents.

### 3. Pod-boundary contracts — **новая §12** (или расширение §2)

Это впервые появляется в M-OS: cottage-platform pod — первый domain_pod (ADR 0009/0010). Нужно зафиксировать тестовый pattern на будущее.

qa-head должен прописать:

#### 3.1. Import-layer tests (static)

| Тест | Файл | Что проверяет |
|---|---|---|
| `test_pod_does_not_import_other_pods` | `tests/pod_boundary/test_imports.py` | Grep `backend/app/pods/cottage_platform/**` на `from app.pods.<other>` → пустой результат |
| `test_pod_does_not_import_core_private` | `tests/pod_boundary/test_imports.py` | pods не импортируют `app.core.events._internal` / `app.core.integrations._internal` — только публичные интерфейсы |
| `test_core_does_not_import_any_pod` | `tests/pod_boundary/test_imports.py` | Grep `backend/app/core/**` на `from app.pods` → пустой (core pod-agnostic) |
| `test_bus_payload_has_no_pod_specific_types` | `tests/pod_boundary/test_imports.py` | `BusinessEvent` subclasses в `app/core/events/` — ни одно поле не имеет type из `app.pods.cottage_platform.*`. Pod-specific events живут в pod'е и публикуются с Pydantic dict-payload, не ORM-type |

#### 3.2. Contract tests (runtime)

| Тест | Файл | Что проверяет |
|---|---|---|
| `test_pod_publishes_only_through_public_bus_api` | `tests/pod_boundary/test_contracts.py` | Mock `BusinessEventBus.publish`, прогнать сервис pod'а — должен дёргать только публичный API, не внутренние методы |
| `test_acl_adapter_hides_external_type_from_pod` | `tests/pod_boundary/test_contracts.py` | Pod вызывает `TelegramAdapter.send_message(...)`, адаптер возвращает domain-type (не telegram-API-response). Pod не видит `telegram.types.Message` |
| `test_migration_confined_to_pod_schema` | `tests/pod_boundary/test_migrations.py` | Миграции в `app/pods/cottage_platform/migrations/` (если они там живут — ADR 0013) не трогают таблицы вне cottage_platform (no-touch-other-pod) |

#### 3.3. Boundary integration tests

| Тест | Файл | Что проверяет |
|---|---|---|
| `test_second_pod_isolated_from_first` | `tests/pod_boundary/test_cross_pod.py` | Создать **фейковый** второй pod `tests/pod_boundary/fake_azs_pod/` с мини-моделью, прогнать — данные cottage-platform не видны |
| `test_event_subscribed_by_multiple_pods` | `tests/pod_boundary/test_cross_pod.py` | (Sprint 3+ feature) Один BusinessEvent, два subscribe — оба получают. Sprint 2: xfail-заглушка, unblock в Sprint 3. |

### 4. Coverage targets — дополнить §3

Добавить строки в таблицу §3:

| Зона | % строк | % веток | Обоснование |
|---|---|---|---|
| Pod-boundary tests | N/A — 100% проходят | N/A | Это gate, не coverage. Либо pass, либо фаза блокируется. |
| Bus contracts (US-04/05) | ≥90% | ≥85% | Contract-слой, дефекты ловятся Pydantic compile-time + рантайм |
| Adapter state machine (US-07) | ≥95% | ≥90% | Security-critical, каждая ветка обязана покрыться явным тестом |

### 5. CI-gate additions — дополнить §4 Sprint 2 gate

Пункты 8–12 уже в документе. Добавить:

13. **`pod-boundary-layer-check`** — скрипт, прогоняющий grep-проверки из §3.1. exit 1 при нарушении.
14. **`test_pod_not_import_other_pods`** (pytest отдельной job) — self-test: на отдельной ветке временно добавить запрещённый import, job должен fail (valid-gate-test, правило RFC-006 self-testing CI-gates).
15. **`test_adapter_call_records_audit`** — включает pytest, который проверяет каждый IntegrationAdapter: после `call()` в audit_log появляется `integration_called` запись.

### 6. Делегирование qa-head в Sprint 2 (уточнение §7)

Существующий §7 перечисляет qa-1 → US-04/05 и qa-2 → US-07/08/09. Добавить в список qa-1:
- **Pod-boundary tests** — qa-1 пишет `tests/pod_boundary/` пакет целиком (~10 тестов, 0.5 дня).

qa-2 получает дополнительно:
- **Adapter edge-cases** — 5 дополнительных тестов (state change during call, missing mock, gated by settings, socket block, audit records).

### 7. Обновление §11 (обновление регламента)

Добавить в чек-лист обновлений:
- Правило 14: «Каждый новый pod обязан иметь `tests/pod_boundary/test_imports.py` перед merge первого PR»
- Правило 15: «Каждый `IntegrationAdapter` subclass обязан иметь тест на `call()` пишет в audit_log»

## Ограничения

- **quality-director не пишет тесты сам.** Этот бриф — расширение **стратегии**, то есть плана для qa-head. qa-head прописывает **детальный план**, реальные файлы тестов пишут qa-1/qa-2 в Sprint 2 (не сейчас).
- **ri-analyst — только advisory.** Консультирует по вопросам bus/ACL-контрактов, pod-boundary семантики. Не пишет сам. Координатор передаёт вопросы qa-head → ri-analyst → qa-head. Если ri-analyst не активен — qa-head делает без него и помечает в отчёте.
- **Не дублировать существующую стратегию.** Если пункт уже есть в `test-strategy-m-os-1-1a-2026-04-18.md` §2/§4 — ссылаться, не переписывать.
- **Не коммитить.** Обновлённый файл передать Координатору для sign-off quality-director.
- `FILES_ALLOWED`:
  - `docs/pods/cottage-platform/quality/test-strategy-m-os-1-1a-2026-04-18.md` (правки/расширение)
- `FILES_FORBIDDEN`: `backend/**`, `frontend/**`, остальные docs.

## Критерии приёмки (DoD)

- [ ] Документ `test-strategy-m-os-1-1a-2026-04-18.md` обновлён, версия повышена до 1.1
- [ ] Добавлены все 10 тестов bus-isolation с именами файлов и сценариями
- [ ] Adapter state matrix расширена до 6 case + 5 edge-cases
- [ ] Добавлена новая секция (§12 или расширение §2) про pod-boundary tests
- [ ] Coverage §3 обновлён
- [ ] CI-gate §4 Sprint 2 дополнен пунктами 13–15
- [ ] §7 обновлён с распределением pod-boundary тестов между qa-1/qa-2
- [ ] §11 обновлён новыми правилами 14–15
- [ ] Все имена тестов следуют pytest-конвенции (`test_<scenario>_<expected>`)
- [ ] ri-analyst консультация учтена либо помечено «ri-analyst dormant, proceeded without»
- [ ] Сводка qa-head → quality-director ≤ 300 слов: что добавлено, сколько новых тестов в плане, зависимости от ADR-0016 и Amendment ADR-0014

## Зависимости

- Этот бриф **не блокирует** Sprint 1 regression (qa-head-brief-sprint1-regression-2026-04-19) и OWASP аудит (security-auditor-brief-sprint1-owasp-2026-04-19). Все три — параллельные.
- Этот бриф **блокирует старт Sprint 2**: без расширенной стратегии qa-1/qa-2 получат неточные промпты.
- Частично зависит от ratification ADR-0016 (Dual Event Bus). Если ADR не ratified — bus-isolation секция пишется условно, с пометкой «pending ADR-0016», и обновляется после ratification.

---

*Бриф составил quality-director 2026-04-19. Маршрут: quality-director → Координатор (транспорт) → qa-head (+ ri-analyst advisory parallel). Возврат — обратным маршрутом.*
