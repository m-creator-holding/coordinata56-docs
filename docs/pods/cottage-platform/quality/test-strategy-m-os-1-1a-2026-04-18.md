# Test Strategy — M-OS-1.1A Foundation Core

- **Дата**: 2026-04-18
- **Автор**: quality-director (субагент L2)
- **Версия**: 1.1
- **Скоуп**: под-фаза M-OS-1.1A, 12 User Stories, 3 спринта, ~5 недель
- **Входные данные**:
  - Декомпозиция: `docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md`
  - ADR-0013 (Migration Evolution Contract)
  - ADR-0014 (Anti-Corruption Layer) + Amendment 2026-04-18
  - ADR-0016 (Dual Event Bus, кандидат Волны 2) — **pending ratification**
  - Регламент отдела качества `docs/agents/departments/quality.md` v1.3
- **История версий**:
  - v1.0 — 2026-04-18 — первая редакция (quality-director)
  - v1.1 — 2026-04-19 — расширение Sprint 2 зон: bus isolation (§12.1), adapter state matrix (§12.2), pod-boundary contracts (§12.3); обновлены §3 coverage, §4 Sprint 2 gate, §7 делегирование, §11 правила (qa-head, coordinata56)
- **Базовая линия**: 351 pytest зелёный на M-OS-0 (контракт-уровень CRUD коттеджного pod'а)
- **Цель стратегии**: дать qa-head точный план тестирования по каждой US, описать CI-гейты по спринтам, зафиксировать risk-митигации и targets покрытия

---

## 1. Принципы тестирования 1.1A

1. **Не откатывать 351.** Любая миграция US-01 обязана оставлять всю существующую regression-suite зелёной. Падение хоть одного старого теста = P0, возврат до зелёного.
2. **Contract-first для новых модулей.** Event Bus и ACL тестируются от контрактов Pydantic-моделей и интерфейсов, не от внутренней реализации.
3. **Mock-first для адаптеров.** Никаких живых сетевых вызовов. `pytest-socket` autouse + `_mock_transport` для всех наследников `IntegrationAdapter`.
4. **Safe-migration обязателен.** Каждая миграция с NOT NULL проходит трёхшаговую проверку: add nullable → backfill → enforce NOT NULL, на dry-run с копией боевой БД (скелет-объём, но реальная схема).
5. **Дифференцированные targets.** Critical paths (миграция, RBAC, bus-isolation) — 95% строк/веток. Адаптеры — 70%. View-слой — 60%. Не «80 везде».
6. **QA не чинит код.** Баги → `bug_log.md` с BUG-id, тест помечен `xfail`, фикс возвращается backend-dev через Координатора.

---

## 2. Test pyramid по каждой US

Легенда уровней:
- **Unit** — изолированные функции/классы, моки зависимостей
- **Contract** — проверка интерфейсов между слоями (Pydantic-схемы, сигнатуры методов)
- **Integration** — FastAPI TestClient + in-memory БД + реальные сервисы
- **Migration** — Alembic upgrade/downgrade/round-trip/backfill на копии БД
- **CI-gate** — скрипт в pipeline, exit-code gate (не pytest)
- **Regression** — прогон существующих 351 тестов

### Sprint 1 — Data model + RBAC

| US | Unit | Contract | Integration | Migration | CI-gate | Regression | Приоритет |
|---|---|---|---|---|---|---|---|
| **US-01** company_id на 16 таблиц | CompanyScopedService filter logic | — | cross_company_isolation (A не видит B), 404 а не 403 | **Критично**: three-step safe-migration test (add nullable → backfill → NOT NULL); round-trip; dry-run на копии | lint-migrations, round-trip | **все 351 должны остаться зелёными** | **P0** |
| **US-02** JWT + X-Company-ID | JWT payload builder, X-Company-ID resolver | — | happy (одна компания, без заголовка), negative (две компании без заголовка → 400 `COMPANY_ID_REQUIRED`), holding-owner bypass | — | — | regression на auth | **P0** |
| **US-03** require_permission | decorator logic, permission matrix seed | — | **RBAC-матрица**: 4 роли × все write-эндпоинты, позитив/негатив. `require_role` deprecated-warning test | — | — | regression на auth | **P0** |

### Sprint 2 — Event Bus + ACL + Pluggability

| US | Unit | Contract | Integration | Migration | CI-gate | Regression | Приоритет |
|---|---|---|---|---|---|---|---|
| **US-04** bus tables + Pydantic | Pydantic validators, discriminator по event_type | **test_bus_schema_discriminator** (AgentControlEvent из Business payload → ValidationError) | DB insert append-only constraint | round-trip на новых таблицах | lint-migrations | — | P0 |
| **US-05** Bus publish intfs | publish() transactional behavior | **test_bus_isolation**: BusinessEventBus.publish(AgentControlEvent) → ValidationError; публикация в одну шину не попадает в другую | publish + rollback в одной транзакции с основной записью | — | — | — | P0 |
| **US-06** cross-bus-import grep | — | — | — | — | **bus-isolation job**: grep на `from app.core.events.agent_control_bus` в `services/*`, `pods/*` → exit 1; self-test: добавить заведомо неправильный import → job должен fail | — | P0 |
| **US-07** IntegrationAdapter base | `call()` guard 5 шагов, state transitions | ABC signature: все наследники реализуют `_live_transport` и `_mock_transport` | adapter_state_transitions: `enabled_live` без `APP_ENV=production` → AdapterDisabledError | — | **test_all_adapters_have_mock** (pytest фэйлит CI) | — | P0 |
| **US-08** TTL cache in-memory | cache hit/miss, TTL expiry (freezegun) | — | первый вызов читает БД (spy), второй — из кеша, после 61 сек — снова БД | — | — | — | P1 |
| **US-09** pytest-socket | — | — | любой вызов socket() в тесте без `@allow_network` → `SocketBlockedError` | — | **test_no_hardcoded_external_urls**: grep `http(s)://` вне `_live_transport`/`settings.py` | — | P0 |
| **US-10** container + 4 points | `get_*` singleton behavior | **test_bus_distinct_instances**: `BusinessEventBus` и `AgentControlBus` не один и тот же объект | FastAPI Depends() override в тестах (in-memory fakes) | — | — | — | P1 |

### Sprint 3 — Integration Registry + Telegram

| US | Unit | Contract | Integration | Migration | CI-gate | Regression | Приоритет |
|---|---|---|---|---|---|---|---|
| **US-11** integration_catalog + seed | repository `get_by_name()` | Схема таблицы соответствует ADR-0015 (поля, типы) | `get_state()` адаптера читает из таблицы, TTL-кеш корректен | seed round-trip, **test_seed_has_7_records** (telegram=enabled_live, 6 других=written) | lint-migrations | — | **P0 (блокирован ADR-0015)** |
| **US-12** Telegram refactor | `_live_transport` и `_mock_transport` TelegramAdapter | — | **test_telegram_dev_env_uses_mock** (APP_ENV=dev → mock), все существующие Telegram-тесты зелёные | — | — | regression на Telegram-integration | P0 |

### Особые замечания по узким US

- **US-01 (16 таблиц).** Главная зона риска всего 1.1A. Гарантия «351 не сломается» достигается: (а) миграция делается через safe-pattern с промежуточным NULL-периодом; (б) на каждом из трёх шагов запускается полный `pytest backend/tests`; (в) перед `NOT NULL` — проверка `SELECT COUNT(*) FROM <tbl> WHERE company_id IS NULL = 0`; (г) backfill засеивает `company_id=1` (единственная компания в dev-фикстурах).
- **US-02/03 (RBAC).** Комбинаторный взрыв избегается **параметризацией**: `pytest.mark.parametrize(("role", "action", "resource"), matrix)`. Базовая матрица — 4 роли × N write-эндпоинтов × 2 сценария (позитив/негатив). Seed `role_permissions` загружается один раз на conftest. Holding-owner отдельным классом, не параметром (другой branch).
- **US-04/05 (Dual Event Bus).** Contract-тест в ядре: `BusinessEventBus.publish(AgentControlEvent)` **не должен** компилироваться с mypy-строгим режимом и **обязан** падать ValidationError в runtime. Проверяется через discriminated union Pydantic. CI-grep (US-06) — второй эшелон.
- **US-07 (IntegrationAdapter).** Mock-first: все тесты используют `_mock_transport`. Ни один тест не вызывает `_live_transport` без `@pytest.mark.allow_network` (которых в 1.1A — 0 штук). Сам ABC проверяется тестом `test_all_adapters_have_mock` через `IntegrationAdapter.__subclasses__()`.
- **US-11 (integration_catalog).** Зависит от ratification ADR-0015. План на отсутствие: **тесты готовятся, но не мержатся** до ratification; qa-1 заводит отдельную ветку `feat/us-11-tests-draft`, на ратификации — rebase и прогон. Если ADR-0015 задерживается ≥3 дня после старта Sprint 3 — Координатор эскалирует Владельцу или переносит US-11 в 1.1B (решение не quality-director).

---

## 3. Coverage targets (дифференцированно)

Цели задаются на **новый код** подфазы 1.1A. Существующий код (351-пакет) сохраняет текущие метрики.

| Зона | % строк | % веток | Обоснование |
|---|---|---|---|
| **Critical paths** (миграция US-01, RBAC decorator US-03, bus isolation US-05, guard US-07) | ≥95% | ≥90% | Failure стоит дороже всего: утечка данных между компаниями, эскалация прав, случайный сетевой вызов |
| Event Bus infrastructure (US-04, US-05, US-10) | ≥85% | ≥80% | Контрактный слой, проще тестировать, дефекты ловятся compile-time |
| IntegrationAdapter base (US-07) | ≥90% | ≥85% | Security-critical: guard защищает ст. 45а/45б CODE_OF_LAWS |
| Adapters (Telegram US-12, будущие наследники) | ≥70% | ≥65% | Mock-first, сам транспорт не покрывается без live — достаточно happy+error paths |
| Cache layer (US-08) | ≥80% | ≥75% | Простая логика, freezegun даёт полное покрытие бранчей |
| View/FastAPI endpoint wiring | ≥60% | ≥50% | Тонкие слои, большая часть покрывается интеграционными |
| **Bus contracts (US-04/05)** — добавлено v1.1 | ≥90% | ≥85% | Contract-слой; дефекты ловятся Pydantic compile-time + runtime; граница шин security-critical |
| **Adapter state machine (US-07)** — добавлено v1.1 | ≥95% | ≥90% | Security-critical: каждая ветка state×env обязана быть явным тестом; защита ст. 45а/45б CODE_OF_LAWS |
| **Pod-boundary tests** — добавлено v1.1 | N/A | N/A | Это gate, не coverage-метрика. Либо все проходят, либо фаза блокируется. Первый domain_pod — прецедент для всех будущих. |

**Инструмент**: `pytest --cov=backend/app --cov-branch --cov-report=term-missing --cov-fail-under=<target>`. Per-module targets через `.coveragerc` с секциями `[report] fail_under` per-path.

**Не превращать coverage в цель ради цели**. Если модуль имеет 99% coverage, но его RBAC-матрица покрыта только одной ролью из четырёх — coverage лжёт. Главная проверка — матрица из регламента отдела + чек-лист reviewer.

---

## 4. CI-инварианты (gates) по спринтам

### Sprint 1 gate — «Data foundation не сломала regression»

Все следующие jobs обязаны быть зелёными перед merge в main:

1. **`pytest backend/tests`** — 351 + новые (ориентир +20-25 новых по US-01/02/03) = ~370-376
2. **`lint-migrations`** — ADR-0013 линтер, новые миграции US-01 соответствуют safe-pattern
3. **`round-trip`** — `alembic upgrade head && alembic downgrade -1 && alembic upgrade head` зелёный на каждой новой ревизии
4. **`coverage (critical paths)`** — US-01 миграция + CompanyScopedService ≥95% строк
5. **`ruff check backend/`** чисто
6. **`mypy backend/app/`** без новых ошибок
7. **RBAC-матрица явно проверена** — test file `test_rbac_matrix.py` содержит параметризованный тест на 4 роли × все новые write-ендпоинты

**Exit criterion sprint 1**: Gate все 7 пунктов — зелёные, qa-head signed off в Коммит-плане.

### Sprint 2 gate — «Bus isolation и ACL каркас не пропускают сетевых вызовов»

Добавляются:

8. **`bus-isolation` job** — grep-скрипт из US-06, exit 1 при нарушении; self-test job с заведомо сломанным импортом, который **должен** упасть (проверка, что сам gate работает)
9. **`pytest-socket`** — autouse fixture блокирует сеть; любой тест с случайным `httpx.get()` падает
10. **`test_all_adapters_have_mock`** — проверка через `__subclasses__()` для всех наследников `IntegrationAdapter`
11. **`test_no_hardcoded_external_urls`** — grep по `backend/app/` на `http(s)://` вне allowlist
12. **Layer-check** — импорты: `backend/app/services/*` НЕ импортирует `backend/app/core/integrations/*._live_transport` напрямую
13. **`pod-boundary-layer-check`** — скрипт, прогоняющий grep-проверки из §12.3.1 (import-layer). `exit 1` при нарушении любого из четырёх правил. Добавлено v1.1.
14. **`test_pod_boundary_self_test`** — отдельная pytest job: на временной ветке вводится заведомо запрещённый import `from app.pods.azs import ...` в cottage_platform, gate обязан упасть. Самопроверка корректности самого gate (RFC-006). Добавлено v1.1.
15. **`test_adapter_call_records_audit`** — pytest job: каждый `IntegrationAdapter` subclass после `call()` пишет в `audit_log` запись `integration_called` с полями `adapter_name`, `success/fail`, `latency_ms`. Проверяется через фикстуру `mock_audit_service`. Добавлено v1.1.

**Exit criterion sprint 2**: все 15 gates зелёные.

### Sprint 3 gate — «Integration Registry контракт»

Добавляются:

13. **`test_seed_has_7_records`** — 7 записей, Telegram `enabled_live`, 6 остальных `written`/`enabled=False`
14. **`test_telegram_dev_env_uses_mock`** — `APP_ENV=dev` → Telegram использует `_mock_transport`
15. **`integration-registry contract`** — схема таблицы соответствует ADR-0015 (поля, типы, индексы)
16. **Regression prod-критичных**: все 4 Telegram-теста, которые уже существуют, зелёные с новым adapter-каркасом

**Exit criterion 1.1A**: все 16 gates зелёные + DoD-пункт 3 декомпозиции (+60-80 новых тестов поверх 351 = ~411-431).

---

## 5. Тесты миграции (safe-migration pattern)

Ключевая зона риска — US-01 (добавление `company_id` на 16 таблиц). Ниже — протокол, который qa-1 должен пройти **до merge US-01**.

### 5.1. Трёхшаговый тест миграции

Миграция разбивается на три Alembic-ревизии:

- **R1 add_company_id_nullable**: добавить колонку `company_id INT NULL FK companies(id)` + индекс. Старый код продолжает работать (ничего не читает/пишет company_id).
- **R2 backfill_company_id**: `UPDATE <table> SET company_id = 1 WHERE company_id IS NULL` для каждой из 16 таблиц. В отдельной миграции, **не в R1**.
- **R3 enforce_not_null**: `ALTER COLUMN company_id SET NOT NULL`. До этого шага — обязательная проверка `SELECT COUNT(*) WHERE company_id IS NULL = 0`.

### 5.2. Pytest-контракт на миграцию

```
backend/tests/migrations/test_us_01_safe_migration.py
```

Тесты (псевдокод):

- `test_r1_adds_nullable_column` — после R1: колонка есть, nullable, индекс есть; **полный pytest backend/tests** зелёный (351 прогнать в цикле).
- `test_r2_backfills_no_nulls` — после R2: `SELECT COUNT(*) WHERE company_id IS NULL` = 0 для каждой из 16 таблиц.
- `test_r3_enforces_not_null` — после R3: попытка INSERT без `company_id` → IntegrityError.
- `test_round_trip_r1_r2_r3` — `upgrade R3 → downgrade R1 → upgrade R3` зелёный; данные в backfill-ed строках сохраняются (downgrade не удаляет company_id, только снимает NOT NULL).
- `test_existing_351_pass_after_r1`, `test_existing_351_pass_after_r2`, `test_existing_351_pass_after_r3` — regression на каждом шаге. Реализуется как pytest-parameter, запускающий базовую сьюту после каждой ревизии.

### 5.3. Dry-run на копии боевой БД

«Боевая» БД на 1.1A — это фикстурная БД M-OS-0 после Фазы 0-3 (скелет, 85 домов, несколько пользователей). Процедура:

1. db-engineer делает snapshot (pg_dump) фикстурной БД.
2. Создаётся отдельный тест-контейнер `postgres-dry-run` с восстановленным dump.
3. `alembic upgrade head` применяет R1 → R2 → R3.
4. Проверка: (а) все existing данные имеют `company_id=1`; (б) FK-целостность не нарушена; (в) индексы есть; (г) round-trip downgrade/upgrade зелёный.
5. Pytest-отчёт: `backend/tests/migrations/reports/dry_run_us_01_<date>.md` — артефакт доказательства для reviewer.

**Без даунтайма**: в 1.1A продакшна нет, но pattern обкатывается. В production-фазе этот же pattern применяется с live-БД.

### 5.4. Аналогично для US-04 (bus tables) и US-11 (integration_catalog)

- US-04: таблицы создаются с нуля, backfill не нужен — только round-trip + append-only constraint тест.
- US-11: seed-миграция должна быть idempotent (`ON CONFLICT DO NOTHING`) — тест `test_seed_idempotent` (прогнать дважды, записей по-прежнему 7).

---

## 6. Risk matrix (top-5 рисков качества)

| # | Риск | Вероятность | Влияние | Митигация (тесты/gates) |
|---|---|---|---|---|
| **R1** | Отсутствие `company_id` на какой-то из 16 таблиц позволит Accountant компании A создать Payment, привязанный к компании B | Средняя (человеческая ошибка — пропустить таблицу из 16) | **Критическое** (data leak между юрлицами холдинга) | (а) автоматический скрипт: grep всех моделей в `backend/app/models/*.py` без `company_id` column → exit 1 в CI; (б) integration test `test_cross_company_isolation_all_resources` параметризованный на все CRUD-ресурсы из реестра; (в) RLS-policy на уровне PostgreSQL как второй эшелон (опционально в 1.1A, обязательно к 1.1B) |
| **R2** | Существующие 351 тестов ломаются после миграции US-01 из-за стукрутных фикстур без `company_id` | **Высокая** (почти все фикстуры писались до multi-company) | Высокое (блокирует merge US-01, остановит sprint 1) | (а) трёхшаговая миграция с backfill, pytest запускается после каждого шага; (б) фикстуры в `conftest.py` обновляются сразу — `company_id=1` по умолчанию; (в) `session.execute("SET app.current_company_id = 1")` через autouse-fixture для backward-совместимости на период миграции |
| **R3** | `BusinessEventBus` случайно оказывается той же имплементацией, что `AgentControlBus` (shared factory ошибка) → всё пишется в одну таблицу | Низкая | **Критическое** (разрушает весь смысл Dual Bus, ст. изоляции AI от бизнеса) | (а) unit `test_bus_distinct_instances` (разные объекты в памяти); (б) contract `test_bus_isolation` (публикация через одну не попадает в другую таблицу); (в) CI-grep `bus-isolation` job (US-06); (г) ADR-review: явное разделение `business_events` и `agent_control_events` в схеме |
| **R4** | `IntegrationAdapter.call()` guard пропускает live-вызов при `state='enabled_live'` в dev (баг в логике 5 шагов) | Средняя (сложная условная логика) | **Критическое** (нарушение CODE_OF_LAWS ст. 45а/45б) | (а) exhaustive test_adapter_state_transitions: 3 state × 2 env = 6 случаев + негативные (state='enabled_live' + env=dev → AdapterDisabledError); (б) pytest-socket autouse как второй эшелон; (в) iptables egress как третий (вне 1.1A, заявка к infra-director); (г) линтер: grep `httpx\.|requests\.` вне `_live_transport` → fail |
| **R5** | US-11 блокируется ожиданием ADR-0015, Sprint 3 не завершается в срок | Средняя | Среднее (сдвиг 1.1A → 1.1B) | (а) quality-director готовит тесты US-11 в отдельной ветке на Sprint 2, мержит после ratification; (б) явный план переноса в 1.1B, если задержка ≥3 дня — эскалация Координатора; (в) Sprint 3 не блокирует закрытие US-07/08/09/12, они могут сдаваться отдельно |

**Дополнительные риски, отслеживаемые, но не топ-5:**
- R6: TTL-кеш (US-08) кеширует stale state при ручной смене `enabled` в БД — смягчено документацией, не тестами (1.1A-ограничение, полная инвалидация в 1.1B).
- R7: Merge-конфликты в `app/core/` между двумя параллельными ветками Sprint 2 — процессный риск, митигируется backend-head merge-окнами.

---

## 7. Делегирование qa-head (по спринтам)

quality-director **не пишет тесты сам**. Ниже — план тест-задач для qa-head; qa-1 и qa-2 активируются Координатором под конкретные US.

### Sprint 1 (нед. 1–2) — qa-head распределяет:

- **qa-1 — US-01 миграция + cross-company isolation**
  - Файлы: `backend/tests/migrations/test_us_01_safe_migration.py`, `backend/tests/test_cross_company_isolation.py`
  - Покрытие: три-шаговый миграционный тест (§5.1–5.3), dry-run артефакт, параметризованный isolation-тест на все 16 таблиц (404 а не 403 для чужого id).
  - Ориентир: ~15–20 новых тестов.
  - Зависимость: ждёт merge R1-миграции от db-engineer.

- **qa-2 — US-02 JWT / X-Company-ID + US-03 RBAC matrix**
  - Файлы: `backend/tests/test_jwt_multi_company.py`, `backend/tests/test_rbac_matrix.py`
  - Покрытие: JWT payload builder, X-Company-ID resolver (3 сценария из US-02 AC), параметризованная RBAC-матрица 4 роли × все write-эндпоинты × позитив/негатив.
  - Ориентир: ~10–15 новых тестов.
  - Зависимость: ждёт US-01 merge.

### Sprint 2 (нед. 3–4) — qa-head распределяет:

- **qa-1 — US-04/05 Event Bus contract + isolation + Pod-boundary tests**
  - Файлы:
    - `backend/tests/events/test_bus_contracts.py` — контрактные тесты шин (6 тестов)
    - `backend/tests/events/test_bus_wiring.py` — unit singleton-wiring (1 тест)
    - `backend/tests/events/test_bus_publish.py` — integration: транзакционность, rollback, cross-bus leakage, append-only (4 теста)
    - `backend/tests/pod_boundary/test_imports.py` — static import-layer (4 теста, §12.3.1)
    - `backend/tests/pod_boundary/test_contracts.py` — runtime contracts (2 теста, §12.3.2)
    - `backend/tests/pod_boundary/test_migrations.py` — migration confinement (1 тест, §12.3.2)
    - `backend/tests/pod_boundary/test_cross_pod.py` — boundary integration (2 теста, §12.3.3)
    - `backend/tests/pod_boundary/fake_azs_pod/` — минимальный фейковый pod-фикстура для cross-pod тестов
  - Покрытие: Pydantic discriminator, publish transactional behavior, contract test «`BusinessEventBus.publish(AgentControlEvent)` → ValidationError», полный пакет pod-boundary (§12.3).
  - Ориентир: ~8–10 тестов bus + ~9–10 тестов pod-boundary = **~18–20 новых тестов**. Добавлено v1.1.

- **qa-2 — US-07/08/09 IntegrationAdapter guard + pytest-socket + edge-cases**
  - Файлы:
    - `backend/tests/integrations/test_adapter_state_transitions.py` — 6 state×env + 5 edge-cases (§12.2)
    - `backend/tests/integrations/test_adapter_cache_ttl.py`
    - `backend/tests/integrations/test_no_hardcoded_urls.py`
    - `backend/tests/integrations/test_all_adapters_have_mock.py`
  - Покрытие: 6 state×env комбинаций guard (§12.2, §R4), 5 edge-cases (state change during call, missing mock transport, gated by settings, socket block, audit records), TTL-кеш через freezegun, grep-тест на hard-coded URL, проверка `__subclasses__()`.
  - Ориентир: ~12–15 базовых + 5 edge-cases = **~17–20 новых тестов**. Добавлено v1.1.

- **CI-скрипт `bus-isolation` (US-06)** — пишет backend-head (не qa). qa-2 валидирует: добавить заведомо неправильный импорт на отдельной ветке, убедиться что gate fails.

### Sprint 3 (нед. 5) — qa-head распределяет:

- **qa-1 — US-11 integration_catalog seed + schema contract**
  - Файлы: `backend/tests/integrations/test_integration_catalog_seed.py`, `backend/tests/integrations/test_integration_catalog_schema.py`
  - Покрытие: 7 записей seed, idempotency, schema-контракт с ADR-0015, `get_state()` через repository.
  - Ориентир: ~6–8 тестов.
  - Зависимость: ADR-0015 ratified. Если не ratified — тесты готовятся в черновой ветке.

- **qa-2 — US-12 Telegram refactor regression**
  - Файлы: `backend/tests/integrations/test_telegram_adapter_refactor.py` + прогон существующих Telegram-тестов
  - Покрытие: `test_telegram_dev_env_uses_mock`, совместимость с existing live Telegram-ботом (через mock, конечно), feature-flag dual-routing.
  - Ориентир: ~5–7 тестов + регрессия.

### Что qa-head делает сам (не делегирует)

- Свод отчётов qa-1/qa-2, валидация чек-листа самопроверки (регламент §«Чек-лист самопроверки qa»).
- Еженедельный random-full-audit одного PR (правило 11 регламента, калибровка spot-check reviewer).
- Ведение `bug_log.md` — каждый найденный баг получает BUG-id, тест помечается xfail.
- Sign-off на каждый sprint gate перед передачей Координатору для merge.

---

## 8. Метрики по 1.1A (отслеживаемые quality-director)

| Метрика | Цель 1.1A | Способ замера |
|---|---|---|
| Покрытие новым кодом (строки, critical paths) | ≥95% | `pytest --cov --cov-fail-under=95` на selected paths |
| Покрытие новым кодом (строки, общее) | ≥80% | `pytest --cov --cov-fail-under=80` |
| Среднее число P0-дефектов на PR | ≤1 | Журнал bug_log.md, агрегация по PR |
| % PR прошедших ревью с первого раза | ≥60% (цель Батча B +10%) | Подсчёт round1 в именах review-отчётов |
| Regression breakage (351 тест после US-01) | 0 | Финальный прогон перед merge |
| Flaky tests | 0 | CI-логи, отметка `@pytest.mark.flaky` запрещена |

Отклонение от любой метрики → эскалация Координатору + обновление `docs/agents/departments/quality.md`.

---

## 9. Что НЕ входит в эту стратегию

- **Performance-тесты.** В 1.1A нет боевой нагрузки, perf-профилирование event bus и TTL-кеша откладывается на 1.1B / 1.2 (когда появится subscribe + реальная нагрузка от субагентов).
- **E2E UI-тесты.** Admin UI в 1.1B, не в 1.1A. Frontend-плейсхолдеры не покрываются Playwright/Cypress.
- **Security-pentest.** Полный OWASP Top 10 прогон — раз в фазу (регламент §«Стандарты security-аудита»), делегируется review-head после закрытия 1.1A.
- **Live Telegram integration test.** Единственная `@allow_network` зона — в отдельном CI-pipeline (пока 0 штук по US-09), планируется в 1.1B.
- **Load/chaos-testing event bus.** — M-OS-2.

---

## 10. Календарь quality-работ

| Неделя | Sprint | Quality-работы |
|---|---|---|
| 1 | S1 | qa-1 готовит draft тестов US-01 миграции, qa-2 draft RBAC-матрицы. quality-director согласует с backend-head точный список 16 таблиц. |
| 2 | S1 | Merge US-01 R1 → qa-1 прогоняет regression + новые миграционные тесты на каждом шаге. US-02/03 тесты параллельно. **Sprint 1 gate**. |
| 3 | S2 | qa-1 на Event Bus (US-04/05), qa-2 на ACL (US-07/08/09). CI-gate bus-isolation validated. |
| 4 | S2 | Интеграция тестов двух веток. Layer-check. `test_all_adapters_have_mock`. **Sprint 2 gate**. |
| 5 | S3 | Ожидание ADR-0015 ratification → US-11 тесты. US-12 Telegram regression. Финальный coverage-отчёт. **1.1A exit gate**. |

---

## 11. Обновление регламента отдела по итогам 1.1A

По завершении 1.1A quality-director обязан обновить `docs/agents/departments/quality.md`:

- Добавить правило 12: «Для любой миграции с NOT NULL — обязательный трёхшаговый safe-pattern + прогон regression на каждом шаге» (если это ещё не в CI-линтере ADR-0013).
- Добавить правило 13: «Для любого адаптера — тест на `_mock_transport` обязателен, проверяется `__subclasses__()`».
- Добавить правило 14 (добавлено v1.1): «Каждый новый pod обязан иметь `tests/pod_boundary/test_imports.py` перед merge первого PR. Без этого файла PR блокируется на ревью.»
- Добавить правило 15 (добавлено v1.1): «Каждый `IntegrationAdapter` subclass обязан иметь тест на то, что `call()` пишет в `audit_log` запись `integration_called` с `adapter_name`, `success/fail`, `latency_ms`.»
- Обновить метрики Батча B → фактические значения 1.1A.

Если обнаружены новые системные паттерны дефектов — правила формулируются по итогам, а не заранее.

---

---

## 12. Sprint 2 — детальный план тестирования (v1.1)

> Секция добавлена qa-head 2026-04-19 (v1.1). Детализирует §2 Sprint 2 на уровне «как», готова для делегирования qa-1/qa-2 в начале Sprint 2.
>
> **ВАЖНО — bus isolation (§12.1):** секция написана условно, pending ADR-0016 ratification. При отклонении ADR-0016 вся §12.1 пересматривается: архитектура Dual Bus меняется, контрактные тесты перепишутся под новую схему. При ratification — секция принимается без изменений.
>
> ri-analyst: dormant, proceeded without.

---

### 12.1. Bus isolation — US-04 / US-05

> Pending ADR-0016 ratification; при отклонении — секция пересматривается.

Цель: доказать, что `BusinessEventBus` и `AgentControlBus` — изолированные шины, и ни payload, ни таблицы не пересекаются.

#### 12.1.1. Контрактные тесты (Contract) — файл `backend/tests/events/test_bus_contracts.py`

| Тест | Сценарий | Assertion | Фикстуры |
|---|---|---|---|
| `test_business_bus_rejects_agent_event` | `BusinessEventBus.publish(AgentControlEvent(...))` | `pytest.raises(ValidationError)` с `match="AgentControlEvent"` в message | `business_bus` (фикстура с in-memory шиной) |
| `test_agent_bus_rejects_business_event` | `AgentControlBus.publish(BusinessEvent(...))` | `pytest.raises(ValidationError)` с `match="BusinessEvent"` | `agent_bus` |
| `test_business_bus_accepts_only_business_subclasses` | Прямой вызов `BusinessEventBus._validate_event_type(cls)` для всех `BusinessEvent.__subclasses__()` | Все допускаются; для `AgentControlEvent` — `ValidationError` | `all_business_event_classes` (параметризованный) |
| `test_discriminator_by_event_type_strict` | Pydantic-парсинг payload с `event_type` от чужой шины | `ValidationError` с указанием discriminator-поля | нет (чистый Pydantic) |
| `test_schema_evolution_adds_new_event_type` | Создание нового `BusinessEvent`-подкласса, публикация через `BusinessEventBus` | Существующие тесты зелёные, новый тип проходит без ошибки | `business_bus` |
| `test_cross_bus_publish_no_leakage_in_memory` | `BusinessEventBus.publish(...)` → проверка внутренней очереди `AgentControlBus` | Очередь AgentControlBus пуста | `business_bus`, `agent_bus` |

#### 12.1.2. Unit тест — файл `backend/tests/events/test_bus_wiring.py`

| Тест | Сценарий | Assertion | Фикстуры |
|---|---|---|---|
| `test_bus_distinct_singleton_instances` | `get_business_event_bus()` vs `get_agent_control_bus()` вызваны дважды каждый | `id(bus1) != id(bus2)` И `id(bus1_call1) == id(bus1_call2)` (singleton) | DI-контейнер тест-режима |

#### 12.1.3. Integration тесты — файл `backend/tests/events/test_bus_publish.py`

| Тест | Уровень | Сценарий | Assertion | Фикстуры |
|---|---|---|---|---|
| `test_publish_transactional_rollback` | Integration | `BusinessEventBus.publish(...)` внутри DB-транзакции, затем rollback | Таблица `business_events` пуста после rollback | `db_session` (rollback autouse), `business_bus` |
| `test_publish_atomic_with_domain_write` | Integration | `Payment.create` + `BusinessEventBus.publish(PaymentCreated(...))` в одной транзакции; `Payment.INSERT` искусственно падает | Таблица `business_events` пуста (транзакция откатилась целиком) | `db_session`, `mock_payment_fail` |
| `test_cross_bus_no_leakage_in_db` | Integration | `BusinessEventBus.publish(PaymentCreated(...))` | После публикации `SELECT COUNT(*) FROM agent_control_events` = 0 | `db_session`, `business_bus` |
| `test_append_only_constraint_db_level` | Integration | `UPDATE business_events SET ...` напрямую через `db_session.execute` | `IntegrityError` (DB constraint) | `db_session` |

**Итого §12.1: 6 контрактных + 1 unit + 4 integration = 11 тестов.**

**Параметризация:** `test_business_bus_accepts_only_business_subclasses` параметризуется через `pytest.mark.parametrize` на `BusinessEvent.__subclasses__()` — число тестов-кейсов растёт автоматически при добавлении новых event-типов.

**Зависимость от ADR-0016:** если ADR-0016 отклонён и Dual Bus не принят — все 11 тестов пересматриваются. Если принят — тесты мержатся без изменений. Ветка: `feat/sprint2-bus-isolation-tests`.

---

### 12.2. Adapter state matrix — US-07

Детализирует §2 Sprint 2 US-07 и §6 Risk R4. Файл: `backend/tests/integrations/test_adapter_state_transitions.py`.

#### 12.2.1. Основная матрица (6 кейсов)

Все 6 кейсов параметризуются через `pytest.mark.parametrize(("state", "app_env", "expected"), [...])`. Фикстуры: `mock_db_with_adapter_state(state)`, `app_env_override(env)`, `mock_audit_service`.

| case | state | APP_ENV | Ожидание | Assertion |
|---|---|---|---|---|
| 1 | `written` | `dev` | `AdapterDisabledError` | `pytest.raises(AdapterDisabledError, match="state=written")` |
| 2 | `written` | `production` | `AdapterDisabledError` | `pytest.raises(AdapterDisabledError, match="state=written")` |
| 3 | `enabled_mock` | `dev` | `_mock_transport` вызван | `spy_mock_transport.called == True`, `spy_live_transport.called == False` |
| 4 | `enabled_mock` | `production` | `_mock_transport` вызван **или** `AdapterDisabledError` — зависит от решения ADR-0015 | Параметризован: `@pytest.mark.parametrize("adr_0015_variant", ["mock_allowed", "disabled"])` |
| 5 | `enabled_live` | `dev` | `AdapterDisabledError("live disabled in dev")` | `pytest.raises(AdapterDisabledError, match="live disabled in dev")` |
| 6 | `enabled_live` | `production` | `_live_transport` вызван | `spy_live_transport.called == True`; `pytest.mark.allow_network` **не** ставится — используется мок транспортного слоя |

**Примечание к case 4:** qa-2 фиксирует обе ветки поведения и параметризует по константе `ADR_0015_MOCK_IN_PROD`. После ratification ADR-0015 один из вариантов помечается `xfail` и убирается.

#### 12.2.2. Edge-cases (5 кейсов) — файл `backend/tests/integrations/test_adapter_state_transitions.py` (продолжение)

| Тест | Сценарий | Assertion | Фикстуры |
|---|---|---|---|
| `test_state_change_during_call` | Во время исполнения `call()` другой «поток» (через `db_session.execute` до TTL-истечения) меняет `enabled` в БД. | Уже начатый `call()` завершается без ошибки (TTL-кеш держит старое состояние). Новый `call()` после `freeze_time(+61s)` видит новое state. | `freezegun.freeze_time`, `threading.Thread` или `asyncio.gather`, `mock_db_with_adapter_state` |
| `test_missing_mock_transport_fails_import` | Наследник `IntegrationAdapter` объявлен без метода `_mock_transport` (нарушение ABC). | При импорте класса или инстанциировании — `TypeError: Can't instantiate abstract class`. Тест убеждается, что ABC enforced на уровне Python, не только рантайм-guard. | Inline-определение класса в теле теста |
| `test_live_transport_gated_by_settings_not_state_alone` | `state=enabled_live`, `APP_ENV=production`, но `settings.EXTERNAL_INTEGRATIONS_ALLOWED=False` | `pytest.raises(AdapterDisabledError, match="EXTERNAL_INTEGRATIONS_ALLOWED")` — дополнительный guard поверх state | `settings_override(EXTERNAL_INTEGRATIONS_ALLOWED=False)`, `app_env_override("production")` |
| `test_socket_block_in_test_env` | Попытка вызова `call()` на реальном live-транспорте без `@pytest.mark.allow_network` (pytester внутри pytest) | `SocketBlockedError` от pytest-socket autouse | `autouse_socket_blocker` (глобальный conftest) |
| `test_call_records_audit_on_success_and_failure` | `call()` при `state=enabled_mock, env=dev` — успешный. Повторно — `_mock_transport` выбрасывает исключение. | После успеха: в `audit_log` запись `integration_called` с `success=True`, `adapter_name=<name>`, `latency_ms > 0`. После ошибки: запись с `success=False`. | `mock_audit_service`, `mock_db_with_adapter_state("enabled_mock")`, `app_env_override("dev")` |

**Итого §12.2: 6 базовых + 5 edge-cases = 11 тестов** (case 4 даёт 2 sub-кейса при параметризации → фактически 12 test-id).

---

### 12.3. Pod-boundary contracts

Первый domain_pod (cottage-platform) — прецедент для всех будущих podов M-OS. Нарушение pod-boundary означает, что core становится зависимым от конкретного домена, что ломает возможность добавлять новые podы без правки ядра.

#### 12.3.1. Import-layer tests (static analysis через pytest) — файл `backend/tests/pod_boundary/test_imports.py`

Реализация: `ast.parse` + `importlib` обход модулей, либо `subprocess.run(["grep", "-r", "from app.pods.<other>", path])` с `returncode` проверкой. Без внешних инструментов — только stdlib + pytest.

| Тест | Что проверяет | Assertion |
|---|---|---|
| `test_pod_does_not_import_other_pods` | `backend/app/pods/cottage_platform/**/*.py` не содержит `from app.pods.<other_pod>` или `import app.pods.<other_pod>` | `grep_result == []` (пустой список совпадений) |
| `test_pod_does_not_import_core_private` | `backend/app/pods/cottage_platform/**/*.py` не содержит `from app.core.events._internal` или `from app.core.integrations._internal` | `grep_result == []` |
| `test_core_does_not_import_any_pod` | `backend/app/core/**/*.py` не содержит `from app.pods` или `import app.pods` | `grep_result == []` (core pod-agnostic) |
| `test_bus_payload_has_no_pod_specific_types` | `BusinessEvent`-подклассы в `app/core/events/` — ни одно поле не аннотировано типом из `app.pods.cottage_platform.*` | AST-обход аннотаций; `pod_types_in_core == []` |

**Все 4 теста — gate-тесты: либо pass, либо PR блокируется (правило 14).** При добавлении нового pod — тесты не меняются (grep автоматически охватит новую директорию).

#### 12.3.2. Contract tests (runtime) — файлы `backend/tests/pod_boundary/test_contracts.py`, `test_migrations.py`

| Тест | Файл | Что проверяет | Assertion |
|---|---|---|---|
| `test_pod_publishes_only_through_public_bus_api` | `test_contracts.py` | Pod-сервис при вызове использует только публичный `BusinessEventBus.publish(...)`, не внутренние `_dispatch`/`_queue` методы | `mock_patch(BusinessEventBus, "_dispatch")` → `_dispatch` не вызван; `publish` — вызван |
| `test_acl_adapter_hides_external_type_from_pod` | `test_contracts.py` | Pod вызывает `TelegramAdapter.send_message(...)` → получает domain-type (например, `MessageSentResult`), а не `telegram.types.Message` | `isinstance(result, MessageSentResult)` — True; `"telegram.types" not in type(result).__module__` — True |
| `test_migration_confined_to_pod_schema` | `test_migrations.py` | Alembic-миграции в `app/pods/cottage_platform/` не создают/меняют таблицы вне namespace `cottage_platform_*` | Парсинг `op.create_table(...)` / `op.add_column(...)` в миграциях; все имена таблиц начинаются с `cottage_platform_` или перечислены в whitelist |

#### 12.3.3. Boundary integration tests — файл `backend/tests/pod_boundary/test_cross_pod.py`

| Тест | Что проверяет | Реализация | Статус |
|---|---|---|---|
| `test_second_pod_isolated_from_first` | Данные cottage-platform не видны фейковому второму pod'у через публичный API | Создать `tests/pod_boundary/fake_azs_pod/` — минимальный FastAPI-роутер с одной моделью `AzsStation`. Вызовы `AzsStation.list()` не возвращают `House` или `Project` | Sprint 2: реализовать |
| `test_event_subscribed_by_multiple_pods` | Один `BusinessEvent`, два subscribe — оба получают событие | Sprint 3+ feature: шина ещё не имеет subscriber-механизма | `@pytest.mark.xfail(reason="Sprint 3+ feature: multi-pod subscribe not implemented")` — заглушка в Sprint 2, unblock в Sprint 3 |

**Итого §12.3: 4 import-layer + 3 contract + 2 boundary integration = 9 тестов** (из них 1 xfail-заглушка на Sprint 3).

---

### 12.4. Сводная таблица новых тестов Sprint 2 (v1.1)

| Секция | Файл | Тестов | qa-исполнитель |
|---|---|---|---|
| Bus contracts (§12.1) | `tests/events/test_bus_contracts.py` | 6 | qa-1 |
| Bus wiring unit (§12.1) | `tests/events/test_bus_wiring.py` | 1 | qa-1 |
| Bus publish integration (§12.1) | `tests/events/test_bus_publish.py` | 4 | qa-1 |
| Adapter state matrix 6×case (§12.2) | `tests/integrations/test_adapter_state_transitions.py` | 6 (+1 sub) | qa-2 |
| Adapter edge-cases (§12.2) | `tests/integrations/test_adapter_state_transitions.py` | 5 | qa-2 |
| Pod import-layer (§12.3.1) | `tests/pod_boundary/test_imports.py` | 4 | qa-1 |
| Pod runtime contracts (§12.3.2) | `tests/pod_boundary/test_contracts.py` + `test_migrations.py` | 3 | qa-1 |
| Pod cross-boundary (§12.3.3) | `tests/pod_boundary/test_cross_pod.py` | 2 (1 xfail) | qa-1 |
| **Итого Sprint 2 новых** | | **31 тест** (30 active + 1 xfail) | |

**Ориентир итогового count после Sprint 2:** 351 (regression) + ~20–25 (Sprint 1) + 31 (Sprint 2) = ~402–407 тестов.

---

*Документ составлен quality-director (субагент L2) 2026-04-18. Не является ADR. Операционный план тестирования под-фазы. Коммит — за Координатором. Активация qa-head — за Координатором.*

*v1.1 расширен qa-head (субагент L3) 2026-04-19: добавлены §12.1 (bus isolation), §12.2 (adapter state matrix), §12.3 (pod-boundary contracts), §12.4 (сводная таблица); обновлены §3 (coverage targets), §4 Sprint 2 gate (пп. 13–15), §7 (делегирование qa-1/qa-2), §11 (правила 14–15). ri-analyst dormant, proceeded without.*
