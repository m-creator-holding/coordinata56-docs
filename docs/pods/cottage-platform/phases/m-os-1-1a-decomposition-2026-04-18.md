# M-OS-1.1A Foundation Core — декомпозиция

- **Дата**: 2026-04-18
- **Автор**: backend-director (субагент L2)
- **Версия**: 1.0 (draft — ждёт ratification ADR-0014)
- **Контекст**: M-OS-1.1 Foundation, под-фаза 1.1A (Решения Владельца 13, 19 от 2026-04-17)
- **Оценка**: 4–5 недель (3 спринта по 2 недели; Sprint 3 — усечённый, 1 неделя)
- **Предусловие старта**: Gate-0 разблокирован (ADR-0014 ratified governance-director)
- **Связанные документы**:
  - `docs/pods/cottage-platform/m-os-1-plan.md` v1.3 — скоуп M-OS-1.1
  - `docs/pods/cottage-platform/m-os-1-foundation-adr-plan.md` v3 — Волны 1-4 ADR
  - ADR 0011 (Foundation) — A1/A2 уже утверждён, часть кода в `backend/app/models/`
  - ADR-0013 (Migrations) — accepted (force-majeure)
  - ADR-0014 (ACL) — proposed, ожидает ratification
  - ADR-0016 (Dual Event Bus) — кандидат, разрабатывается параллельно Волна 2

---

## 1. Контекст и границы

### Что уже сделано (ADR 0011, до старта 1.1A)

Модели в `backend/app/models/`: `Company`, `UserCompanyRole`, `Role`, `Permission`, `RolePermission`, `AuditLog` с crypto-chain — **созданы**. CRUD и проверка `can(user, action, resource)` существуют в базовом виде. 351 тест зелёный.

### Что делает 1.1A (скоуп)

1. **Multi-company data model completeness.** Добиваем `company_id` на всех сущностях cottage-platform (16 таблиц — проверить гап), `CompanyScopedService` как базовый класс для всех сервисов, JWT-клеймы `company_ids` + `is_holding_owner`, X-Company-ID заголовок.
2. **Fine-grained RBAC completeness.** Матрица `role_permissions` seed-ится полностью; декоратор `require_permission` заменяет `require_role` во всех write-эндпоинтах; deprecated-alias живёт до конца M-OS-1.
3. **Dual Event Bus foundation (ADR-0016).** Две таблицы: `business_events` и `agent_control_events` (append-only). Два интерфейса: `BusinessEventBus.publish(BusinessEvent)`, `AgentControlBus.publish(AgentControlEvent)`. Pydantic-валидация на входе. CI-grep-проверка на cross-import.
4. **Anti-Corruption Layer foundation (ADR-0014).** Базовый класс `IntegrationAdapter`, enum `AdapterState`, `AdapterDisabledError`, runtime-guard (5 шагов), TTL-кеш 60 сек на in-memory dict, `pytest-socket` в корневом conftest. Telegram-адаптер приводится к новому каркасу.
5. **Pluggability foundation (ADR-0019 частично).** Реестр `app/core/container.py` + FastAPI `Depends()` для 4 точек: `NotificationProvider`, `BusinessEventBus`, `AgentControlBus`, `AuditLogger`. Остальные 7 точек — в 1.1B.
6. **Integration Registry каркас (ADR-0015 частично).** Таблица `integration_catalog` с минимальной схемой (без полной CRUD-поверхности — она в 1.1B). Seed 7 записей (Telegram — `enabled_live`, 6 остальных — `written`).
7. **Migration contract adoption (ADR-0013).** `lint-migrations` + `round-trip` в CI зелёные на всех новых миграциях 1.1A.

### Что НЕ входит в 1.1A (отложено в 1.1B)

- Admin UI 6 разделов конструктора (юрлица, пользователи/роли, матрица прав, company_settings, реестр интеграций, system config) — фронтендная работа.
- `company_settings` — 7 полей, Pydantic `CompanySettingsDefinition`, CRUD (ADR-0017 Развилка В).
- Configuration-as-Data full layer (ADR-0017) — мета-таблица `configuration_entities` + 9 child-таблиц.
- ADR-0015 полная реализация: CRUD-эндпоинты `/api/v1/integration-catalog`, health-checks, admin-UI.
- ADR-0019 полный реестр из 11 pluggable points.
- Contract: `file_id`, `start_date`, `end_date` — tech-debt из Фазы 3, можно подтянуть в 1.1A Sprint 3, но опционально.

---

## 2. User Stories

Всего **12 US**, распределены по 3 спринтам.

### Sprint 1 (нед. 1–2) — Data model + RBAC completeness

#### US-01. Company scoping для всех существующих сущностей
**Как** архитектор
**хочу** чтобы все сущности cottage-platform имели `company_id` и были доступны только через `CompanyScopedService`
**чтобы** сотрудник компании A не видел данные компании B

**Acceptance criteria:**
- Таблицы `projects`, `contracts`, `contractors`, `payments`, `houses`, `stages`, `materials`, `budgets`, `house_configurations` (и все остальные из `backend/app/models/*` без `company_id`) получают колонку `company_id: int NOT NULL FK → companies.id`, индекс.
- Миграция Alembic создаёт колонки, бэкфиллит `company_id=1` для существующих записей, ставит NOT NULL после бэкфилла (safe-migration pattern по ADR-0013).
- `lint-migrations` и `round-trip` в CI зелёные.
- Тест `test_cross_company_isolation`: user компании A с role=accountant делает GET `/projects`, получает только свои; GET `/projects/<id_компании_B>` → 404 (не 403).
- Все 351 существующих теста зелёные.

**Зависимости**: нет (стартовая).
**Исполнитель**: db-engineer (миграция) + backend-dev-1 (`CompanyScopedService` refactor).
**Размер**: L (5-7 дней).

---

#### US-02. JWT-клеймы и X-Company-ID
**Как** сотрудник с ролями в нескольких компаниях
**хочу** иметь возможность переключаться между компаниями через заголовок
**чтобы** работать с одним юрлицом за раз

**Acceptance criteria:**
- JWT payload расширяется `company_ids: list[int]` и `is_holding_owner: bool`, вычисляется при логине.
- FastAPI dependency `get_user_context` читает заголовок `X-Company-ID`; если нет и у пользователя одна компания — берётся она; если несколько и заголовка нет — 400 с кодом `COMPANY_ID_REQUIRED`.
- Holding-owner (`is_holding_owner=True`) получает bypass во всех `CompanyScopedService._scoped_query_conditions`.
- Тесты: позитивный (одна компания — работает без заголовка), негативный (две компании без заголовка — 400), holding-owner видит всё.

**Зависимости**: US-01.
**Исполнитель**: backend-dev-2.
**Размер**: M (3 дня).

---

#### US-03. require_permission на всех write-эндпоинтах
**Как** security engineer
**хочу** чтобы все POST/PATCH/DELETE эндпоинты использовали `require_permission(action, resource_type)`
**чтобы** RBAC был fine-grained (роль + объект + действие), не role-based

**Acceptance criteria:**
- Все existing POST/PATCH/DELETE ручки в `backend/app/api/*` переведены с `require_role(...)` на `require_permission(action=..., resource_type=...)`.
- `require_role` сохранён как deprecated alias с warning в логе (удаляется в M-OS-1.3).
- Матрица `role_permissions` в seed-скрипте содержит минимум 20 строк (4 роли × 5 действий); администрирование матрицы — через SQL в 1.1A, admin-UI — в 1.1B.
- Тесты: на каждом write-эндпоинте минимум 2 позитивных + 2 негативных сценария RBAC.

**Зависимости**: US-01.
**Исполнитель**: backend-dev-1.
**Размер**: L (5 дней).

---

### Sprint 2 (нед. 3–4) — Event Bus + ACL + Pluggability

#### US-04. Dual Event Bus — схема и таблицы (ADR-0016)
**Как** архитектор
**хочу** две append-only таблицы `business_events` и `agent_control_events` с Pydantic-контрактами
**чтобы** бизнес и AI-управление физически не пересекались

**Acceptance criteria:**
- Миграция Alembic создаёт две таблицы с полями `id`, `event_type`, `payload: jsonb`, `published_at`, `company_id nullable`, `correlation_id nullable`.
- Pydantic-модели `BusinessEvent` (базовая) и `AgentControlEvent` (базовая) в `backend/app/core/events/`.
- `lint-migrations` + `round-trip` зелёные.
- Тест схемы: нельзя через Pydantic создать `AgentControlEvent` из payload `BusinessEvent` (discriminator по `event_type`).

**Зависимости**: US-01 (для `company_id`).
**Исполнитель**: db-engineer + backend-dev-3.
**Размер**: M (3 дня).

---

#### US-05. BusinessEventBus и AgentControlBus — интерфейсы и publish
**Как** разработчик сервиса
**хочу** публиковать событие одним вызовом `bus.publish(event)` с идемпотентностью
**чтобы** не писать SQL и не дублировать код транзакций

**Acceptance criteria:**
- Класс `BusinessEventBus` с методом `publish(event: BusinessEvent) -> None` — пишет в `business_events` в той же транзакции, что и основная запись (через `Depends(get_db)`).
- Класс `AgentControlBus` с методом `publish(event: AgentControlEvent) -> None` — пишет в `agent_control_events`.
- Runtime-запрет: попытка `BusinessEventBus.publish(AgentControlEvent(...))` → ValidationError.
- Подписчики (subscribe) — в 1.1B; в 1.1A только publish.
- Тест `test_bus_isolation`: публикация в бизнес-шину не попадает в agent-control и наоборот.

**Зависимости**: US-04.
**Исполнитель**: backend-dev-3.
**Размер**: M (3 дня).

---

#### US-06. CI-инвариант: cross-bus-import запрещён
**Как** ревьюер
**хочу** grep-проверку в CI, что бизнес-модули не импортируют `AgentControlBus` и наоборот
**чтобы** правило изоляции держалось технически

**Acceptance criteria:**
- Скрипт `backend/tools/check_bus_isolation.py`: grep на `from app.core.events.agent_control_bus import` в `backend/app/services/*` и `backend/app/pods/*` → exit 1.
- Job `bus-isolation` в `.github/workflows/ci.yml`, запускается на `pull_request`.
- Документировано в `docs/agents/departments/backend.md` раздел «Правила работы».

**Зависимости**: US-05.
**Исполнитель**: backend-head (CI-скрипт, 1 день).
**Размер**: S (1 день).

---

#### US-07. IntegrationAdapter базовый класс (ADR-0014)
**Как** разработчик адаптера
**хочу** наследоваться от `IntegrationAdapter` и реализовать `_live_transport` + `_mock_transport`
**чтобы** не переживать про guard, состояния и mock-режим

**Acceptance criteria:**
- `backend/app/core/integrations/base.py`: ABC `IntegrationAdapter` с `adapter_name`, `get_state()`, `call()`, `_live_transport()`, `_mock_transport()`.
- `backend/app/core/integrations/exceptions.py`: `AdapterDisabledError(RuntimeError)`.
- `backend/app/core/integrations/state.py`: enum `AdapterState {written, enabled_mock, enabled_live}`.
- Runtime-guard в `call()` реализует 5 шагов из ADR-0014 раздел «Решение».
- Тест `test_all_adapters_have_mock`: все наследники имеют реализованный `_mock_transport`.
- Тест `test_adapter_state_transitions`: переход в `enabled_live` без `APP_ENV=production` → `AdapterDisabledError`.

**Зависимости**: нет (параллельно Sprint 1 задачам, но нужно до US-09).
**Исполнитель**: backend-dev-1 (после US-03).
**Размер**: L (5 дней).

---

#### US-08. TTL-кеш состояния адаптера — in-memory
**Как** разработчик
**хочу** чтобы `get_state()` не делал SQL при каждом вызове адаптера
**чтобы** overhead был минимальным

**Acceptance criteria:**
- In-memory dict `{adapter_name: (state, cached_at)}` в `IntegrationAdapter` (module-level, не в экземпляре — общий для процесса).
- TTL 60 сек, сброс через module-level функцию `invalidate_state_cache(adapter_name)`.
- До реализации инвалидации через business-шину (1.1B) — только TTL-истечение.
- Конфигурируется через `settings.ADAPTER_STATE_CACHE_TTL` (default 60).
- Тест `test_state_cache_ttl`: первый вызов читает из БД, второй — из кеша (mock БД-вызов считается), после 61 сек — снова из БД.

**Зависимости**: US-07.
**Исполнитель**: backend-dev-1.
**Размер**: S (1 день).

---

#### US-09. pytest-socket и CI-защита от сетевых вызовов
**Как** security engineer
**хочу** чтобы тесты падали при любой попытке открыть сокет
**чтобы** случайный вызов к продуктивному endpoint из CI был технически невозможен

**Acceptance criteria:**
- `pytest-socket` в `backend/requirements.txt`.
- Корневой `backend/conftest.py`: autouse-fixture `disable_network(socket_disabled)`.
- Интеграционные тесты Telegram помечены `@pytest.mark.allow_network`, запускаются отдельным job в CI (если такой появится — сейчас 0 штук).
- Тест `test_no_hardcoded_external_urls`: grep по `backend/app/` не находит `http(s)://` вне `_live_transport` и `settings.py`.

**Зависимости**: US-07.
**Исполнитель**: backend-dev-2.
**Размер**: S (1 день).

---

#### US-10. Pluggability — container + 4 точки
**Как** архитектор
**хочу** явный реестр DI-точек в `app/core/container.py`
**чтобы** добавление нового поставщика было конфигурацией, а не правкой сервисов

**Acceptance criteria:**
- `backend/app/core/container.py`: функции `get_notification_provider()`, `get_business_event_bus()`, `get_agent_control_bus()`, `get_audit_logger()` — все возвращают singleton, используются через `Depends()` в FastAPI.
- Prod-имплементации и in-memory fake-имплементации для тестов зарегистрированы через `settings.ENVIRONMENT`.
- Правило «`BusinessEventBus` и `AgentControlBus` — разные точки, одна имплементация не может быть в обеих» проверяется unit-тестом.
- Остальные 7 pluggable points (AIProvider, BankAdapter, OFDAdapter, 1CAdapter, RosreestrAdapter, CryptoProvider, ConfigurationCache) — в 1.1B.

**Зависимости**: US-05 (нужны bus-интерфейсы).
**Исполнитель**: backend-dev-3.
**Размер**: M (3 дня).

---

### Sprint 3 (нед. 5) — Integration Registry каркас + Telegram + cleanup

#### US-11. integration_catalog таблица + seed (ADR-0015 каркас)
**Как** администратор
**хочу** каталог интеграций в БД с 7 записями из ADR-0014
**чтобы** адаптеры читали состояние из единого источника

**Acceptance criteria:**
- Миграция Alembic создаёт таблицу `integration_catalog` с полями: `id UUID PK`, `adapter_name varchar unique`, `adapter_version varchar`, `base_url varchar nullable`, `credentials_ref varchar nullable`, `state enum(AdapterState)`, `enabled bool`, `last_healthcheck_at timestamptz nullable`, `last_healthcheck_status varchar nullable`, `company_id int nullable`, аудит-поля.
- Seed-миграция создаёт 7 записей: telegram (`enabled_live`, `enabled=True`), sberbank/tinkoff/ofd/1c/rosreestr/kryptopro (`written`, `enabled=False`).
- CRUD-эндпоинты **не создаются** в 1.1A (это 1.1B).
- `IntegrationAdapter.get_state()` читает из этой таблицы через repository.
- Тест `test_seed_has_7_records`.
- Предусловие уже снято: ADR-0014 Amendment 2026-04-18 явно фиксирует, что схема `integration_catalog` определяется в ADR-0015; поэтому ADR-0015 должен быть принят до реализации US-11. **Блокирует старт US-11, не старт 1.1A.**

**Зависимости**: US-07, US-08. **ADR-0015 ratified** (предусловие Sprint 3).
**Исполнитель**: db-engineer + backend-dev-1.
**Размер**: M (3 дня).

---

#### US-12. Telegram-адаптер приведён к каркасу ADR-0014
**Как** разработчик Telegram-интеграции
**хочу** чтобы текущий Telegram-код жил в `backend/app/core/integrations/telegram.py` и наследовал `IntegrationAdapter`
**чтобы** правила ACL применялись и к нему

**Acceptance criteria:**
- Существующий Telegram-код рефакторится в `TelegramAdapter(IntegrationAdapter)`.
- `_live_transport()` — реальный вызов Bot API.
- `_mock_transport()` — детерминированные ответы (успех, сетевая ошибка, бизнес-ошибка).
- Seed-запись `telegram` со `state='enabled_live'` используется.
- Все существующие Telegram-тесты зелёные; новый тест `test_telegram_dev_env_uses_mock` (при `APP_ENV=dev` → `_mock_transport`).

**Зависимости**: US-11.
**Исполнитель**: backend-dev-2 (integrator-head консультирует по Telegram).
**Размер**: M (3 дня).

---

## 3. Распределение по спринтам

| Sprint | Недели | US | Суть |
|---|---|---|---|
| **1** | 1–2 | US-01, US-02, US-03 | Data model + RBAC completeness (фундамент для остального) |
| **2** | 3–4 | US-04, US-05, US-06, US-07, US-08, US-09, US-10 | Event Bus + ACL base + Pluggability (параллелизм) |
| **3** | 5 | US-11, US-12 | Integration Registry каркас + Telegram refactor |

Итого: 12 US / 5 недель / 3 спринта.

---

## 4. Граф зависимостей

```
US-01 (company_id data model)
  ├─> US-02 (JWT / X-Company-ID)
  ├─> US-03 (require_permission)
  └─> US-04 (event bus tables) ─> US-05 (bus interfaces) ─┬─> US-06 (CI isolation)
                                                          └─> US-10 (container)

US-07 (IntegrationAdapter base)  [может стартовать после US-01, параллельно US-03]
  ├─> US-08 (TTL cache)
  ├─> US-09 (pytest-socket)
  └─> US-11 (integration_catalog) [ждёт ADR-0015 ratification]
       └─> US-12 (Telegram refactor)
```

---

## 5. Параллелизм

- **Sprint 1.** US-01 — критический путь. US-02 и US-03 стартуют после US-01 миграции (можно параллельно — разные разработчики).
- **Sprint 2.** После US-04 (event bus tables):
  - Ветка A: US-05 → US-06 → US-10 (backend-dev-3, последовательно).
  - Ветка B: US-07 → US-08 + US-09 (backend-dev-1 и backend-dev-2, параллельно в Ветке B).
  - Две ветки идут параллельно.
- **Sprint 3.** US-11 и US-12 последовательно; US-11 должен быть завершён до US-12.

---

## 6. Ресурсы — кого привлекать

| Роль | Задачи | Загрузка в 5 нед. |
|---|---|---|
| backend-head | Ревью всех PR, распределение US между dev'ами, CI-скрипты (US-06) | 100% |
| backend-dev-1 | US-01 refactor `CompanyScopedService`, US-03, US-07, US-08, US-11 код | ~100% |
| backend-dev-2 | US-02, US-09, US-12 Telegram refactor | ~60% (свободен — помогает ревьюеру) |
| backend-dev-3 | US-04 Pydantic models, US-05, US-10 container | ~80% |
| db-engineer (через db-head) | US-01 миграция, US-04 миграция, US-11 миграция | ~40% (три миграции) |
| integrator-head (через integrator-head, dormant) | Консультация по US-12 Telegram — какие mock-ответы нужны | ~5% (консультация, 1 раз) |
| architect | Консультация при расхождениях с ADR-0011, ADR-0014, ADR-0016 | ad hoc |
| qa-director + review-head | Ревью каждого PR до коммита (правило v1.3) | 20% qa / 80% review |

**ACL-специфика (US-07/US-08/US-09/US-11/US-12).** Реализует backend-dev-1 по детальному DoD ADR-0014. backend-head проверяет, что `pytest-socket` блокирует сеть на CI. architect консультирует только по вопросу «ACL-каркас реализуется без ADR-0015 — как именно» (см. задачу 1 ниже, вердикт подтверждающий).

---

## 7. DoD под-фазы 1.1A

Под-фаза 1.1A закрыта, когда:

1. Все 12 US прошли review и замержены в main.
2. `alembic upgrade head && alembic downgrade -1 && alembic upgrade head` зелёный.
3. Все 351 существующих теста + новые тесты (ориентир +60–80 новых) зелёные.
4. `ruff check backend/` чисто; `mypy backend/app/` без новых ошибок.
5. `lint-migrations` + `round-trip` + `bus-isolation` — все CI-jobs зелёные.
6. Документация обновлена: `docs/agents/departments/backend.md` (правила по двум шинам, ACL), `CLAUDE.md` (если добавились новые антипаттерны).
7. ADR-0015 ratified до начала Sprint 3 (предусловие US-11).
8. Gate-0 → Gate-1 переход оформлен: статус-документ `docs/pods/cottage-platform/phases/m-os-1-1a-status-final.md`.

---

## 8. Риски

| Риск | Вероятность | Влияние | Контрмера |
|---|---|---|---|
| US-01 backfill `company_id` ломает существующие fixture | Высокая | Высокое | Миграция через safe-pattern (add nullable → bulk update → NOT NULL), тесты запускаются на каждом шаге |
| US-07 TTL-кеш без инвалидации из 1.1B — stale state при ручной смене `enabled` в БД | Средняя | Низкое | Документировано: на 1.1A сменить `enabled` — рестарт приложения или ожидание 60 сек; полная инвалидация через business-шину в 1.1B |
| US-11 блокируется ожиданием ADR-0015 ratification | Средняя | Среднее | Параллельно со Sprint 2 Координатор ведёт Волну 2 ADR (0015 + 0016); запас времени 4 нед. достаточный |
| US-12 Telegram refactor ломает живую интеграцию с ботом | Низкая | Высокое | Feature flag `USE_NEW_TELEGRAM_ADAPTER` на 1 неделю; двойной маршрут до подтверждения стабильности |
| Параллелизм Sprint 2 двух веток — merge-конфликты в `app/core/` | Средняя | Низкое | Backend-head координирует merge-окна; ветки разносятся по подпакетам (`events/` и `integrations/`) |

---

## 9. Что происходит после 1.1A (1.1B preview)

- Admin-UI 6 разделов (юрлица, пользователи/роли, матрица прав, `company_settings`, `integration_catalog` CRUD, system config) — frontend.
- `company_settings` 7 полей + CRUD (ADR-0017 Развилка В).
- Configuration-as-Data full (ADR-0017 мета + 9 child-таблиц).
- ADR-0015 full implementation: CRUD-эндпоинты, health-checks.
- ADR-0019 полный реестр 11 pluggable points.
- Contract tech-debt: `file_id`, `start_date`, `end_date`.
- Инвалидация TTL-кеша ACL через `ConfigurationPublished` business-событие.

---

*Документ составлен backend-director в рамках декомпозиции под-фазы M-OS-1.1A по запросу Координатора 2026-04-18. Не является ADR. Является операционным планом под-фазы. Старт кода блокируется Gate-0 (ADR-0014 ratification governance-director).*
