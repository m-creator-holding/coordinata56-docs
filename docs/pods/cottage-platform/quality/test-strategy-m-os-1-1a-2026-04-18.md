# Test Strategy — M-OS-1.1A Foundation Core

- **Дата**: 2026-04-18
- **Автор**: quality-director (субагент L2)
- **Версия**: 1.2
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
  - v1.2 — 2026-04-19 — добавлены §13 (BPM test scenarios), §14 (Subagent Status test scenarios), §15 (Notifications test scenarios), §16 (Telegram adapter test scenarios); обновлены §3 coverage targets Sprint 3, §4 Sprint 3 gate (17 total), §7 делегирование Sprint 3 (qa-1 BPM engine, qa-2 Agents+Notifications) (qa-head, coordinata56)
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
| **BPM models** (US-11 BPM, `workflow_definition`, `workflow_instance`, `workflow_step`) — добавлено v1.2 | ≥90% | ≥85% | Модели и репозитории BPM — новый контрактный слой; дефекты versioning/archive нарушают целостность всего BPM-движка |
| **BPM services** (`WorkflowService`, `InstanceService`, step execution) — добавлено v1.2 | ≥85% | ≥80% | Сервисный слой содержит бизнес-логику versioning и routing; заглушки для step execution требуют явного покрытия happy+error path |
| **BPM API endpoints** (Admin API US-12, Engine subscriber US-13) — добавлено v1.2 | ≥80% | ≥75% | Тонкий слой wiring; ключевые риски — RBAC и 404-vs-403 для чужих workflow |
| **Subagent Status** (`/summary`, `/status/{id}`, heartbeat) — добавлено v1.2 | ≥85% | ≥80% | SQL GROUP BY и polling semantics требуют точного покрытия; role=owner-only — security-critical |
| **Notifications** (CRUD, filters, read-all, cross-company isolation) — добавлено v1.2 | ≥90% | ≥85% | IDOR — critical; cross-company — critical; atomicity read-all — data integrity |
| **Telegram ACL adapter** (US-16, mock transport, state routing) — добавлено v1.2 | ≥70% | ≥65% | Mock-first; live transport в dev запрещён; покрывается happy+error paths через mock |

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

### Sprint 3 gate — «Integration Registry + BPM + Notifications контракт»

Добавляются:

13. **`test_seed_has_7_records`** — 7 записей, Telegram `enabled_live`, 6 остальных `written`/`enabled=False`
14. **`test_telegram_dev_env_uses_mock`** — `APP_ENV=dev` → Telegram использует `_mock_transport`
15. **`integration-registry contract`** — схема таблицы соответствует ADR-0015 (поля, типы, индексы)
16. **`bpm-gate`** — добавлено v1.2: (а) `test_workflow_version_immutable`: попытка изменить опубликованный `workflow_definition` → 409 Conflict; (б) `test_event_routes_to_correct_instance`: event с `workflow_id` роутится к нужному `workflow_instance` без cross-instance leakage; (в) `test_archive_restore_idempotent`: двойной вызов archive/restore → всегда корректный конечный статус, не ошибка; (г) coverage BPM models ≥90%
17. **`notifications-idor-gate`** — добавлено v1.2: (а) `test_notification_idor_blocked`: GET `/notifications/{id}` с чужим `id` → 404 (не 403); (б) `test_read_all_atomic`: параллельный `mark_all_read` → ни одно уведомление не остаётся непрочитанным; (в) `test_cross_company_notification_isolation`: пользователь компании A не видит уведомления компании B; (г) coverage Notifications ≥90%

**Exit criterion 1.1A**: все 17 gates зелёные + DoD-пункт 3 декомпозиции (+80-100 новых тестов поверх 351 = ~431-451).

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

- **qa-1 — US-11 integration_catalog + BPM Engine tests (US-13)**
  - Файлы:
    - `backend/tests/integrations/test_integration_catalog_seed.py`
    - `backend/tests/integrations/test_integration_catalog_schema.py`
    - `backend/tests/bpm/test_bpm_engine_subscriber.py`
    - `backend/tests/bpm/test_bpm_event_routing.py`
  - Покрытие: 7 записей seed, idempotency, schema-контракт с ADR-0015, `get_state()` через repository; BPM engine subscriber — event→instance routing (§13.4), step execution заглушка (§13.5), archive/restore idempotency (§13.6). Добавлено v1.2.
  - Ориентир: ~6–8 тестов (catalog) + ~10–12 тестов (BPM engine) = ~16–20 новых.
  - Зависимость: ADR-0015 ratified (catalog); US-13 Worker E merge (BPM engine). Если ADR-0015 не ratified — catalog-тесты готовятся в черновой ветке.

- **qa-2 — Agents Status + Notifications + Telegram ACL (US-12, US-14, US-15, US-16)**
  - Файлы:
    - `backend/tests/integrations/test_telegram_adapter_refactor.py` + прогон существующих Telegram-тестов
    - `backend/tests/agents/test_subagent_status.py`
    - `backend/tests/notifications/test_notifications_idor.py`
    - `backend/tests/notifications/test_notifications_filters.py`
    - `backend/tests/integrations/test_telegram_acl_adapter.py`
  - Покрытие: `test_telegram_dev_env_uses_mock`, mock transport, ACL state routing (§16); polling semantics, role filter owner-only, SQL GROUP BY в /summary, heartbeat header auth, 40+ fixture data (§14); IDOR защита, tab/type/period filter, read-all atomicity, cross-company isolation, channel settings per-user (§15). Добавлено v1.2.
  - Ориентир: ~5–7 тестов (Telegram) + ~12–15 тестов (Agents) + ~15–18 тестов (Notifications) = ~32–40 новых.

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

---

## 13. Sprint 3 BPM test scenarios (v1.2)

> Секция добавлена qa-head 2026-04-19 (v1.2). Координировать с Worker D (US-12 BPM Admin API) и Worker E (US-13 BPM Engine subscriber): их тесты обязаны покрывать сценарии §13.1–§13.6.

### 13.1. workflow_definition CRUD

Файл: `backend/tests/bpm/test_workflow_definition_crud.py`

| Тест | Класс эквивалентности | Assertion |
|---|---|---|
| `test_create_workflow_definition_valid` | Валидный payload: `name`, `steps[]`, `trigger_event` | HTTP 201, `id` в ответе, `version=1`, `status=draft` |
| `test_create_workflow_missing_steps` | Невалидный: `steps=[]` | HTTP 422, `error.code=VALIDATION_ERROR` (ADR 0005) |
| `test_get_workflow_definition_own_company` | Получить definition своей компании | HTTP 200, тело соответствует созданному |
| `test_get_workflow_definition_foreign_company` | Получить definition чужой компании | HTTP 404 (не 403 — не раскрывать существование) |
| `test_update_workflow_definition_draft` | Обновить definition в статусе `draft` | HTTP 200, `version` не меняется до publish |
| `test_delete_workflow_definition_draft` | Удалить `draft` | HTTP 204 |
| `test_delete_workflow_definition_published` | Удалить `published` | HTTP 409, `error.code=WORKFLOW_PUBLISHED` |

**Ориентир: 7 тестов.** Параметризация по ролям (owner / member / guest) добавляется к `test_create` и `test_delete` — проверка RBAC.

### 13.2. Versioning

Файл: `backend/tests/bpm/test_workflow_versioning.py`

| Тест | Сценарий | Assertion |
|---|---|---|
| `test_publish_increments_version` | Publish `draft` → повторный publish после edit | `version` увеличивается на 1 каждый раз |
| `test_published_definition_immutable` | PUT/PATCH на `published` definition | HTTP 409, `error.code=WORKFLOW_IMMUTABLE` |
| `test_draft_from_published` | `POST /workflows/{id}/draft` — создать новый draft из published | HTTP 201, новый `id`, `version=prev+1`, `status=draft` |
| `test_versions_listed_in_order` | GET `/workflows/{id}/versions` | Список упорядочен по `version DESC` |
| `test_concurrent_publish_idempotent` | Два одновременных `publish` на одном draft (race) | Ровно одна успешная публикация, второй → 409 |

**Ориентир: 5 тестов.**

### 13.3. Seed-шаблоны

Файл: `backend/tests/bpm/test_workflow_seed_templates.py`

| Тест | Сценарий | Assertion |
|---|---|---|
| `test_seed_templates_idempotent` | Запустить seed дважды | Число шаблонов не изменилось, no `IntegrityError` |
| `test_seed_templates_have_required_fields` | Каждый seed-шаблон | `name`, `trigger_event`, `steps` — не пустые |
| `test_seed_template_status_is_draft` | Статус всех seed-шаблонов | `status=draft` (шаблоны не публикуются автоматически) |

**Ориентир: 3 теста.**

### 13.4. Event→instance routing

Файл: `backend/tests/bpm/test_bpm_event_routing.py`

| Тест | Сценарий | Assertion |
|---|---|---|
| `test_event_routes_to_matching_workflow` | Публикуем `BusinessEvent` с `trigger_event=payment.created`; опубликован workflow с тем же триггером | Создаётся `workflow_instance` с `workflow_definition_id` = тому workflow |
| `test_event_no_matching_workflow_ignored` | Публикуем event с триггером без опубликованного workflow | Экземпляр не создаётся; ошибки нет (graceful no-op) |
| `test_event_routes_to_correct_company_instance` | Два workflow в двух компаниях с одинаковым триггером; event от компании A | Instance создаётся только для компании A |
| `test_event_does_not_route_to_draft_workflow` | Workflow в статусе `draft` с совпадающим триггером | Instance не создаётся (только published workflows активны) |
| `test_multiple_events_create_multiple_instances` | Три события с одним триггером | Три независимых `workflow_instance`, не один повторный |

**Ориентир: 5 тестов.** Все используют `mock_business_event_bus` (без живого bus), `in-memory db`.

### 13.5. Step execution (заглушка)

Файл: `backend/tests/bpm/test_bpm_step_execution.py`

> Замечание: Worker E реализует step execution как заглушку в Sprint 3. Тесты проверяют контракт заглушки, а не реальное исполнение.

| Тест | Сценарий | Assertion |
|---|---|---|
| `test_step_execute_stub_returns_pending` | `POST /instances/{id}/steps/{step_id}/execute` | HTTP 200, `status=pending` (заглушка), `result=null` |
| `test_step_execute_unknown_step` | step_id не принадлежит instance | HTTP 404 |
| `test_step_execute_foreign_instance` | instance_id чужой компании | HTTP 404 (не 403) |
| `test_step_status_transition_valid` | `pending → running → completed` через mock stub | Каждый переход возвращает корректный `status` |
| `test_step_status_transition_invalid` | `completed → running` (откат назад) | HTTP 409, `error.code=INVALID_STEP_TRANSITION` |

**Ориентир: 5 тестов.**

### 13.6. Archive/restore idempotency

Файл: `backend/tests/bpm/test_bpm_archive_restore.py`

| Тест | Класс эквивалентности | Assertion |
|---|---|---|
| `test_archive_published_workflow` | Валидный: опубликованный workflow | HTTP 200, `status=archived`; новые instances не создаются |
| `test_archive_draft_workflow` | Граничный: draft (не published) | HTTP 409 или HTTP 200 в зависимости от бизнес-правила — qa-1 уточняет у Worker D |
| `test_archive_already_archived_idempotent` | Двойной archive | HTTP 200 (idempotent), `status=archived`, не ошибка |
| `test_restore_archived_workflow` | Restore archived → published | HTTP 200, `status=published` |
| `test_restore_already_published_idempotent` | Двойной restore | HTTP 200 (idempotent), `status=published` |
| `test_archive_blocks_new_event_routing` | После archive: event с триггером этого workflow | Instance не создаётся (archived не активен) |

**Ориентир: 6 тестов.**

**Итого §13 (BPM): 31 тест** (7 CRUD + 5 versioning + 3 seed + 5 routing + 5 step execution + 6 archive/restore).

---

## 14. Subagent Status test scenarios (v1.2)

> Секция добавлена qa-head 2026-04-19 (v1.2). US-14 реализована в Волне A (ed792ed). Тесты пишет qa-2. Ключевые риски: SQL GROUP BY некорректный → /summary врёт; role filter — утечка данных между ролями.

### 14.1. Polling semantics

Файл: `backend/tests/agents/test_subagent_status_polling.py`

| Тест | Сценарий | Assertion |
|---|---|---|
| `test_status_returns_latest_heartbeat` | Агент отправил 3 heartbeat с интервалом; GET `/status/{id}` | Возвращается последний heartbeat, `last_seen` актуален |
| `test_status_stale_after_timeout` | Агент не отправлял heartbeat > threshold | `status=offline` или `status=stale` (уточнить у Worker F) |
| `test_status_online_after_heartbeat` | Агент был stale → отправил heartbeat | `status=online` |
| `test_status_unknown_agent` | `GET /status/{unknown_id}` | HTTP 404 |
| `test_polling_no_thundering_herd` | 10 параллельных GET запросов к /status/{id} | Все 10 возвращают одинаковый результат; БД не блокируется (проверяется через spy на `db_session.execute`) |

**Ориентир: 5 тестов.**

### 14.2. Role filter (owner-only)

Файл: `backend/tests/agents/test_subagent_status_rbac.py`

Матрица параметризованная через `pytest.mark.parametrize(("role", "expected_status"), [...])`:

| Роль | GET /status/{id} | GET /summary | Ожидание |
|---|---|---|---|
| `owner` | Свой агент | Своя компания | HTTP 200 |
| `owner` | Чужой агент (другой компании) | Другая компания | HTTP 404 |
| `manager` | Любой агент | — | HTTP 403 |
| `accountant` | Любой агент | — | HTTP 403 |
| `guest` | Любой агент | — | HTTP 403 |

| Тест | Assertion |
|---|---|
| `test_owner_sees_own_agents` | HTTP 200, данные совпадают |
| `test_owner_cannot_see_foreign_company_agents` | HTTP 404 |
| `test_non_owner_roles_forbidden` | HTTP 403 для всех ролей кроме owner (параметризованный тест) |
| `test_unauthenticated_blocked` | HTTP 401 |

**Ориентир: 4 теста** (один параметризованный = 3 sub-кейса).

### 14.3. SQL GROUP BY в /summary

Файл: `backend/tests/agents/test_subagent_summary.py`

| Тест | Сценарий | Assertion |
|---|---|---|
| `test_summary_counts_by_status` | 40+ фикстурных агентов: 15 online, 12 offline, 8 stale, 5 error | `summary.online==15`, `summary.offline==12`, `summary.stale==8`, `summary.error==5` (точные значения) |
| `test_summary_empty_company` | Компания без агентов | `{online:0, offline:0, stale:0, error:0}` — не пустой ответ |
| `test_summary_isolation_between_companies` | Компания A — 10 агентов, компания B — 20 агентов; запрос от A | `total=10` (не 30) |
| `test_summary_uses_sql_groupby_not_python` | Spy на `db_session.execute` | SQL содержит `GROUP BY status`; постобработки в Python нет (антипаттерн из CLAUDE.md) |
| `test_summary_total_equals_sum_of_statuses` | Произвольное распределение статусов | `total == online + offline + stale + error` всегда |

**Ориентир: 5 тестов.** Фикстура `fixture_40_agents(company_id, statuses_distribution)` — одна на все тесты §14.3, генерирует агентов случайными секретами (CLAUDE.md правило секретов).

### 14.4. Heartbeat header auth

Файл: `backend/tests/agents/test_subagent_heartbeat.py`

| Тест | Сценарий | Assertion |
|---|---|---|
| `test_heartbeat_valid_token` | `POST /heartbeat` с корректным `X-Agent-Token` | HTTP 204, `last_seen` обновлён |
| `test_heartbeat_invalid_token` | Неверный `X-Agent-Token` | HTTP 401 |
| `test_heartbeat_missing_token` | Нет заголовка | HTTP 401 |
| `test_heartbeat_expired_token` | Истёкший `X-Agent-Token` | HTTP 401 |
| `test_heartbeat_wrong_company_token` | Токен агента компании B на POST агента компании A | HTTP 403 или HTTP 404 (уточнить у Worker F) |
| `test_heartbeat_updates_status_to_online` | Агент был stale; POST heartbeat | `GET /status/{id}` → `status=online` |

**Ориентир: 6 тестов.**

**Итого §14 (Subagent Status): 20 тестов** (5 polling + 4 RBAC + 5 summary + 6 heartbeat).

---

## 15. Notifications test scenarios (v1.2)

> Секция добавлена qa-head 2026-04-19 (v1.2). US-15 реализована в Волне A (0537217). Тесты пишет qa-2. Критические риски: IDOR (P0), cross-company isolation (P0), atomicity read-all (P1).

### 15.1. IDOR защита (critical)

Файл: `backend/tests/notifications/test_notifications_idor.py`

| Тест | Сценарий | Assertion |
|---|---|---|
| `test_get_notification_own` | GET `/notifications/{id}` — своё уведомление | HTTP 200 |
| `test_get_notification_foreign_user_same_company` | GET `/notifications/{id}` — уведомление другого пользователя той же компании | HTTP 404 (не 403) |
| `test_get_notification_foreign_company` | GET `/notifications/{id}` — уведомление пользователя другой компании | HTTP 404 |
| `test_mark_read_foreign_notification` | PATCH `/notifications/{id}/read` чужого уведомления | HTTP 404 |
| `test_delete_foreign_notification` | DELETE `/notifications/{id}` чужого | HTTP 404 |
| `test_idor_sequential_ids_not_guessable` | Попытка перебора id+1, id+2 для чужих уведомлений | Каждый → HTTP 404 (параметризованный диапазон 10 id) |

**Ориентир: 6 тестов** (последний даёт 10 sub-кейсов). Все IDOR-тесты помечаются `@pytest.mark.security`.

### 15.2. Filter в SQL (tab/type/period)

Файл: `backend/tests/notifications/test_notifications_filters.py`

| Тест | Фильтр | Assertion |
|---|---|---|
| `test_filter_by_tab_unread` | `?tab=unread` | Только уведомления с `read=False` |
| `test_filter_by_tab_read` | `?tab=read` | Только уведомления с `read=True` |
| `test_filter_by_type` | `?type=payment_alert` | Только нотификации данного типа |
| `test_filter_combined_tab_type` | `?tab=unread&type=payment_alert` | Пересечение двух условий |
| `test_filter_period_today` | `?period=today` | `created_at >= today_start`, `< tomorrow_start` |
| `test_filter_period_week` | `?period=week` | `created_at >= 7 дней назад` |
| `test_filter_period_invalid` | `?period=yesterday_invalid` | HTTP 422, `error.code=VALIDATION_ERROR` |
| `test_filter_uses_sql_where_not_python` | Spy на `db_session.execute` при `?tab=unread` | SQL содержит `WHERE read = false`; postprocessing в Python отсутствует (антипаттерн CLAUDE.md) |
| `test_pagination_with_filter` | `?tab=unread&limit=5&offset=5` | `total` = число unread всего, `items` = 5 элементы; `total` из COUNT с тем же WHERE (не постобработка) |

**Ориентир: 9 тестов.**

### 15.3. Read-all atomicity

Файл: `backend/tests/notifications/test_notifications_read_all.py`

| Тест | Сценарий | Assertion |
|---|---|---|
| `test_mark_all_read_marks_all` | 20 непрочитанных; `POST /notifications/read-all` | Все 20 → `read=True`; `GET ?tab=unread` возвращает 0 |
| `test_mark_all_read_idempotent` | Двойной вызов `read-all` | Второй вызов → HTTP 200 (или 204), не ошибка; count остаётся 0 |
| `test_mark_all_read_concurrent` | 5 параллельных `read-all` через `asyncio.gather` | После завершения `?tab=unread` = 0; нет дубликатов записей аудита |
| `test_mark_all_read_only_own_user` | Пользователь A — `read-all`; у пользователя B той же компании остаются непрочитанные | Уведомления B не затронуты |
| `test_mark_all_read_audit_log` | `POST /notifications/read-all` | В `audit_log` запись `notifications_read_all` с `user_id` и `count` прочитанных (ADR 0007) |

**Ориентир: 5 тестов.**

### 15.4. Cross-company isolation

Файл: `backend/tests/notifications/test_notifications_isolation.py`

| Тест | Сценарий | Assertion |
|---|---|---|
| `test_list_shows_only_own_company` | Компания A — 10 уведомлений, компания B — 15; GET `/notifications` от A | `total=10` (не 25) |
| `test_create_notification_for_foreign_user` | POST уведомление с `user_id` из другой компании | HTTP 404 или 403 (пользователь не найден в scope компании) |
| `test_notification_event_does_not_leak_cross_company` | BPM notification event от компании A; пользователь компании B слушает | Пользователь B не получает уведомление |

**Ориентир: 3 теста.**

### 15.5. Channel settings per-user

Файл: `backend/tests/notifications/test_notification_channel_settings.py`

| Тест | Сценарий | Assertion |
|---|---|---|
| `test_get_channel_settings_default` | Новый пользователь без настроек | Возвращаются default-значения (email=true, telegram=false или согласно spec) |
| `test_update_channel_settings` | PATCH `/notifications/settings` → `{telegram: true}` | HTTP 200, последующий GET возвращает `telegram=true` |
| `test_channel_settings_per_user_isolated` | Пользователь A отключает email; GET настроек пользователя B | Настройки B не изменились |
| `test_notification_respects_channel_disabled` | Пользователь отключил `telegram`; BPM генерирует уведомление | В `notification_deliveries` запись для telegram отсутствует |

**Ориентир: 4 теста.**

**Итого §15 (Notifications): 27 тестов** (6 IDOR + 9 filters + 5 read-all + 3 isolation + 4 channel settings).

---

## 16. Telegram adapter test scenarios (v1.2)

> Секция добавлена qa-head 2026-04-19 (v1.2). US-16 реализована Worker F (в работе, Волна B). Тесты пишет qa-2. Зависимость: Worker F merge US-16. Живые вызовы запрещены в dev (CODE_OF_LAWS ст. 45а/45б, CLAUDE.md).

### 16.1. ACL states matrix

Файл: `backend/tests/integrations/test_telegram_acl_adapter.py`

Параметризованная матрица через `pytest.mark.parametrize(("acl_state", "app_env", "expected"), [...])`:

| case | acl_state | APP_ENV | Ожидание | Assertion |
|---|---|---|---|---|
| 1 | `written` | `dev` | `AdapterDisabledError` | `pytest.raises(AdapterDisabledError)` |
| 2 | `written` | `production` | `AdapterDisabledError` | `pytest.raises(AdapterDisabledError)` |
| 3 | `enabled_mock` | `dev` | `_mock_transport` вызван | `spy_mock.called == True`, `spy_live.called == False` |
| 4 | `enabled_mock` | `production` | `_mock_transport` вызван (mock не зависит от env) | `spy_mock.called == True` |
| 5 | `enabled_live` | `dev` | `AdapterDisabledError("live disabled in dev")` | `pytest.raises(AdapterDisabledError, match="live disabled in dev")` |
| 6 | `enabled_live` | `production` | `_live_transport` вызван | `spy_live.called == True`; `@pytest.mark.allow_network` не ставится — используется mock-транспортный слой |

**Ориентир: 6 тестов** (параметризованный = 6 test-id).

### 16.2. Mock transport

Файл: `backend/tests/integrations/test_telegram_mock_transport.py`

| Тест | Сценарий | Assertion |
|---|---|---|
| `test_mock_transport_returns_success` | `TelegramAdapter.send_message(...)` при `enabled_mock` | Возвращает `MessageSentResult(success=True, message_id=<fake_id>)` |
| `test_mock_transport_records_call` | Вызов mock-transport | В `spy_mock_calls` фиксируется `chat_id`, `text`, `timestamp` |
| `test_mock_transport_raises_on_bad_payload` | `send_message` с пустым `text` | `pytest.raises(ValidationError)` до вызова транспорта |
| `test_mock_transport_configurable_failure` | `MockTransport(fail=True)` | `pytest.raises(IntegrationCallError)` — симуляция сбоя Telegram API |
| `test_mock_transport_latency_recorded` | `call()` с mock | `audit_log` содержит `latency_ms > 0` и `adapter_name="telegram"` |

**Ориентир: 5 тестов.**

### 16.3. Live запрет в dev

Файл: `backend/tests/integrations/test_telegram_acl_adapter.py` (продолжение)

| Тест | Сценарий | Assertion |
|---|---|---|
| `test_live_blocked_without_allow_network_marker` | `enabled_live` + `APP_ENV=production` в обычном тесте (без `@pytest.mark.allow_network`) | `SocketBlockedError` от `pytest-socket` autouse |
| `test_live_blocked_in_dev_env` | `enabled_live` + `APP_ENV=dev` | `AdapterDisabledError` до любого сетевого вызова (guard срабатывает раньше socket) |
| `test_no_hardcoded_telegram_urls` | Grep по `backend/app/integrations/telegram*.py` на `api.telegram.org` вне `_live_transport` | `matches == []` |

**Ориентир: 3 теста.**

### 16.4. BPM notification delivery flow

Файл: `backend/tests/integrations/test_telegram_bpm_delivery.py`

> Интеграционный тест связки BPM notification event → Telegram adapter. Использует mock transport; не требует живого Telegram.

| Тест | Сценарий | Assertion |
|---|---|---|
| `test_bpm_notification_delivered_via_telegram` | `workflow_instance` завершает шаг → BPM публикует `NotificationEvent` → Notifications сервис → Telegram adapter (mock) | `spy_mock_transport.called == True`; `chat_id` совпадает с `user.telegram_chat_id` |
| `test_bpm_notification_skipped_if_telegram_disabled` | Пользователь отключил `telegram` в channel settings; тот же flow | `spy_mock_transport.called == False`; в `notification_deliveries` статус `skipped` |
| `test_bpm_notification_delivery_audit_logged` | Успешная доставка | `audit_log` содержит `notification_delivered` с `channel=telegram`, `user_id`, `success=True` |
| `test_bpm_notification_delivery_failure_logged` | Mock transport выбрасывает `IntegrationCallError` | `audit_log` содержит `notification_delivered` с `success=False`; уведомление в БД сохраняется (не теряется) |
| `test_bpm_notification_no_cross_company_delivery` | Notification event от компании A; пользователь компании B имеет telegram настроен | Mock transport вызван только для пользователей компании A |

**Ориентир: 5 тестов.**

**Итого §16 (Telegram adapter): 19 тестов** (6 ACL states + 5 mock transport + 3 live-запрет + 5 BPM delivery flow).

---

### Сводная таблица новых тестов Sprint 3 (v1.2)

| Секция | Файл | Тестов | qa-исполнитель |
|---|---|---|---|
| BPM CRUD (§13.1) | `tests/bpm/test_workflow_definition_crud.py` | 7 | qa-1 |
| BPM versioning (§13.2) | `tests/bpm/test_workflow_versioning.py` | 5 | qa-1 |
| BPM seed templates (§13.3) | `tests/bpm/test_workflow_seed_templates.py` | 3 | qa-1 |
| BPM event routing (§13.4) | `tests/bpm/test_bpm_event_routing.py` | 5 | qa-1 |
| BPM step execution (§13.5) | `tests/bpm/test_bpm_step_execution.py` | 5 | qa-1 |
| BPM archive/restore (§13.6) | `tests/bpm/test_bpm_archive_restore.py` | 6 | qa-1 |
| Subagent polling (§14.1) | `tests/agents/test_subagent_status_polling.py` | 5 | qa-2 |
| Subagent RBAC (§14.2) | `tests/agents/test_subagent_status_rbac.py` | 4 | qa-2 |
| Subagent summary SQL (§14.3) | `tests/agents/test_subagent_summary.py` | 5 | qa-2 |
| Subagent heartbeat (§14.4) | `tests/agents/test_subagent_heartbeat.py` | 6 | qa-2 |
| Notifications IDOR (§15.1) | `tests/notifications/test_notifications_idor.py` | 6 | qa-2 |
| Notifications filters (§15.2) | `tests/notifications/test_notifications_filters.py` | 9 | qa-2 |
| Notifications read-all (§15.3) | `tests/notifications/test_notifications_read_all.py` | 5 | qa-2 |
| Notifications isolation (§15.4) | `tests/notifications/test_notifications_isolation.py` | 3 | qa-2 |
| Notifications channel settings (§15.5) | `tests/notifications/test_notification_channel_settings.py` | 4 | qa-2 |
| Telegram ACL states (§16.1) | `tests/integrations/test_telegram_acl_adapter.py` | 6 | qa-2 |
| Telegram mock transport (§16.2) | `tests/integrations/test_telegram_mock_transport.py` | 5 | qa-2 |
| Telegram live-запрет (§16.3) | `tests/integrations/test_telegram_acl_adapter.py` | 3 | qa-2 |
| Telegram BPM delivery (§16.4) | `tests/integrations/test_telegram_bpm_delivery.py` | 5 | qa-2 |
| Integration catalog (Sprint 3 §7) | `tests/integrations/test_integration_catalog_*.py` | 7 | qa-1 |
| **Итого Sprint 3 новых** | | **104 теста** | |

**Ориентир итогового count после Sprint 3:** 351 (regression) + ~20–25 (Sprint 1) + 31 (Sprint 2) + 104 (Sprint 3) = ~506–511 тестов.

---

*Документ составлен quality-director (субагент L2) 2026-04-18. Не является ADR. Операционный план тестирования под-фазы. Коммит — за Координатором. Активация qa-head — за Координатором.*

*v1.1 расширен qa-head (субагент L3) 2026-04-19: добавлены §12.1 (bus isolation), §12.2 (adapter state matrix), §12.3 (pod-boundary contracts), §12.4 (сводная таблица); обновлены §3 (coverage targets), §4 Sprint 2 gate (пп. 13–15), §7 (делегирование qa-1/qa-2), §11 (правила 14–15). ri-analyst dormant, proceeded without.*

*v1.2 расширен qa-head (субагент L3) 2026-04-19: добавлены §13 (BPM test scenarios, 31 тест), §14 (Subagent Status test scenarios, 20 тестов), §15 (Notifications test scenarios, 27 тестов), §16 (Telegram adapter test scenarios, 19 тестов), сводная таблица Sprint 3 (104 теста итого); обновлены §3 (coverage targets Sprint 3 — 6 новых строк), §4 Sprint 3 gate (gate 16 bpm-gate + gate 17 notifications-idor-gate, итого 17 gates), §7 делегирование Sprint 3 (qa-1 берёт BPM engine + catalog; qa-2 берёт Agents+Notifications+Telegram).*
