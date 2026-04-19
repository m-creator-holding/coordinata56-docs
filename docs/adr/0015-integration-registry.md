---
status: accepted
title: "ADR 0015 — Integration Registry: каталог подключений (таблица integration_catalog)"
date: 2026-04-18
updated_at: 2026-04-19
ratified: 2026-04-19
authors: [architect]
depends_on: [ADR-0014, ADR-0011, ADR-0013]
owner_decisions_applied: OQ1-OQ2-OQ3-2026-04-19-msg-1556
---

# ADR 0015 — Integration Registry: каталог подключений (таблица integration_catalog)

- **Статус**: ACCEPTED (force-majeure — governance-auditor backup-mode 2026-04-19, governance-director недоступен через Agent tool; ретроспективное ревью при восстановлении)
- **Дата создания**: 2026-04-18
- **Дата draft-расширения**: 2026-04-18
- **Дата ratification**: 2026-04-19
- **Дата обновления**: 2026-04-19 (owner-decisions OQ1-OQ2-OQ3, msg 1556)
- **Авторы**: architect (субагент-советник)
- **Утверждающий**: governance-auditor (backup-mode, force-majeure)
- **Контекст фазы**: M-OS-1 «Скелет», Волна 2 Foundation
- **Ratification 2026-04-19**: принят `governance-auditor` в backup-режиме (force-majeure); заявка `docs/governance/requests/2026-04-19-adr-0015-ratification.md`. Закрывает DoD предусловие ADR-0014 (seed-миграция); разблокирует Sprint 3 US-11.

**Связанные документы**:
- ADR-0014 (Anti-Corruption Layer) — определяет каркас адаптеров и три состояния; ADR-0015 предоставляет хранилище состояния
- ADR-0011 (Foundation RBAC) — RBAC-модель: только `owner`-пользователь вправе изменять `state` в реестре
- ADR-0013 (Migrations Evolution Contract) — обязательные правила для создания таблицы и seed-миграции
- ADR-0018 (Production Gate Definition) — `enabled_live` разрешается только после прохождения per-pod gate
- `docs/m-os-vision.md` §3.4 — список внешних интеграций Vision как источник перечня адаптеров
- `docs/agents/CODE_OF_LAWS.md` ст. 45а/45б — запрет живых вызовов без production-gate

---

## Проблема

ADR-0014 определил каркас адаптеров (базовый класс `IntegrationAdapter`, три состояния, runtime-guard), но намеренно вынес хранилище состояния в отдельный документ. Без ADR-0015:

1. Разработчик Sprint 3 (US-11) не знает схему таблицы `integration_catalog` — не может написать миграцию Alembic, не может сделать seed из 7 записей (DoD ADR-0014, пункт «seed-миграция»).
2. Service-слой `IntegrationRegistry` не имеет формального контракта — чтение `state` адаптером, TTL-кеш, инвалидация через шину (ADR-0016) не задокументированы.
3. Admin UI (M-OS-1.1B Sprint 3) не знает, какие поля отображать и какие переходы состояний разрешать.
4. Связь реестра с production-gate (ADR-0018) не задокументирована.

Без данного ADR Sprint 3 не может стартовать, так как US-11 явно заблокирован его ratification.

---

## Контекст

**Что уже принято:**

- ADR-0014 (accepted, 2026-04-18): каркас адаптеров с тремя состояниями — `written`, `enabled_mock`, `enabled_live`. Guard в базовом классе `IntegrationAdapter.call()` читает состояние из реестра через TTL-кеш (60 сек), инвалидация — через `business_events_bus` (ADR-0016). Только Telegram — `enabled_live`, остальные шесть — `written`. DoD ADR-0014 явно указывает: seed-миграция является предусловием ADR-0015.
- ADR-0013 (accepted): правила эволюции схемы; create table — «разрешено без ограничений»; seed-данные идут отдельной миграцией от DDL.
- ADR-0011 (accepted): RBAC; `owner`-роль является единственной ролью с правом изменения состояния интеграций.
- ADR-0018 (proposed): определение production-gate; перевод `state → enabled_live` допустим только после прохождения gate.

**Ограничения Владельца (CODE_OF_LAWS ст. 45а/45б):**
- Живые вызовы к банкам, Росреестру, 1С, ОФД запрещены до production-gate.
- Единственная разрешённая живая интеграция в M-OS-1 — Telegram.
- Переход в `enabled_live` — явное решение Владельца, фиксируется в AuditLog.

**Sprint-контекст:**
- Sprint 1 (US-01/02/03): backend активен сейчас.
- Sprint 3 (US-11): `integration_catalog` table + seed — основная работа. Стартует после ratification ADR-0015.
- M-OS-1.1B Sprint 3: Admin UI — toggle state для 7 записей.

---

## Рассмотренные альтернативы

### Альтернатива A — Таблица в PostgreSQL (выбранная)

Состояние каждого адаптера хранится в таблице `integration_catalog` в основной базе данных PostgreSQL. Service-слой `IntegrationRegistry` предоставляет API для чтения и записи. Guard `IntegrationAdapter.call()` обращается к сервису через TTL-кеш.

**Плюсы:**
- Единый источник правды; всё в одной базе, нет синхронизации.
- CRUD-API интеграции с RBAC и AuditLog (ADR-0007, ADR-0011) из коробки — каждый toggle фиксируется в audit-цепочке.
- Admin UI читает из той же таблицы.
- Seed-данные — стандартная Alembic-миграция (ADR-0013).
- Транзакционная гарантия: изменение `state` атомарно с записью в AuditLog.

**Минусы:**
- Зависимость guard от доступности БД при старте кеша.
- При выходе из строя БД TTL-кеш продолжает работать 60 сек по последнему состоянию (приемлемо для MVP; риск фиксируется в разделе «Риски»).

**Вердикт**: принимается.

---

### Альтернатива B — Конфигурационные файлы (YAML/JSON в репозитории)

Состояние адаптеров хранится в файлах `config/integrations/*.yaml`, которые читаются при запуске приложения и закешированы на весь срок работы процесса.

**Плюсы:**
- Нет зависимости от БД при чтении состояния.
- История изменений в git-истории.

**Минусы:**
- Изменение состояния требует перезапуска приложения — недопустимо в production (downtime при каждом toggle).
- RBAC и AuditLog не применимы к файловым операциям из коробки.
- Admin UI не может менять файлы в репозитории напрямую — нужен отдельный pipeline.
- Нарушает принцип «конфигурация в БД, не в коде» (ADR-0014 раздел «Feature flag»).
- Требует синхронизации между репозиторием и runtime — два источника правды.

**Вердикт**: отклоняется. Противоречит ADR-0014 и принципу единого источника правды.

---

### Альтернатива C — Отдельная Redis-таблица / KV-хранилище

Состояние адаптеров хранится в Redis как key-value: `integration:{name}:state = enabled_live`.

**Плюсы:**
- Скорость чтения выше PostgreSQL.
- Инвалидация кеша через Redis Pub/Sub без дополнительного bus.

**Минусы:**
- Добавляет Redis в стек там, где его нет (ADR-0002 — утверждённый стек не включает Redis на M-OS-1).
- Два хранилища данных: транзакционные данные в PostgreSQL + оперативное состояние в Redis — риск расхождения.
- AuditLog в Redis нет из коробки, нужно дублировать в PostgreSQL.
- Принцип минимальной достаточности нарушен.

**Вердикт**: отклоняется для M-OS-1. Пересмотр допустим при масштабировании в M-OS-3+ если задержка чтения реестра станет проблемой.

---

### Альтернатива D — Multi-tenant реестр (отдельная таблица на компанию)

Для каждой компании (ADR-0011) — отдельный реестр интеграций. Таблица `company_integration_catalog` с полем `company_id`.

**Плюсы:**
- Полная изоляция конфигурации интеграций между компаниями.

**Минусы:**
- В текущей модели (cottage-platform, один pod, одна компания) избыточно.
- Адаптеры (Telegram, банки) — системные, не per-company. Per-company нужны только `credentials_ref`, не `state`.
- Добавляет сложность без покрываемого кейса.

**Вердикт**: отклоняется для M-OS-1. Partial multi-tenancy (`credentials_ref` per company) — допустимо как amendment при появлении второй компании. Схема таблицы `company_integration_credentials` определена ниже (OQ3).

---

## Решение

**Принята альтернатива A: таблица `integration_catalog` в PostgreSQL.**

### Схема таблицы

```sql
-- Enum: тип интеграции
CREATE TYPE integration_kind AS ENUM (
    'bank',
    '1c',
    'rosreestr',
    'ofd',
    'telegram',
    'email',
    'sms',
    'other'
);

-- Enum: состояние адаптера (совпадает с AdapterState в ADR-0014)
CREATE TYPE integration_state AS ENUM (
    'written',
    'enabled_mock',
    'enabled_live'
);

CREATE TABLE integration_catalog (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(64)     NOT NULL,           -- уникальный ключ адаптера: "telegram", "sberbank" и т.д.
    kind            integration_kind NOT NULL,          -- тип: bank / 1c / rosreestr / ofd / telegram / email / sms / other
    state           integration_state NOT NULL DEFAULT 'written',  -- текущее состояние адаптера
    version         VARCHAR(16)     NOT NULL DEFAULT '1.0.0',      -- версия адаптера (semver)
    config_json     JSONB           NOT NULL DEFAULT '{}'::jsonb,  -- нечувствительная конфигурация: base_url, timeout_ms, retry_count
    credentials_ref VARCHAR(255)    NULL,               -- ссылка на секрет в vault (не сам секрет); NULL если не нужны
    description     TEXT            NULL,               -- человекочитаемое описание назначения адаптера
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- Индексы
CREATE UNIQUE INDEX uq_integration_catalog_name
    ON integration_catalog (name);

CREATE INDEX idx_integration_catalog_kind_state
    ON integration_catalog (kind, state);
```

**Примечания к схеме:**

- `name` — уникальный текстовый ключ, используется в коде адаптера (`adapter_name`). Регистр фиксирован: строчные буквы, без пробелов.
- `config_json` — только нечувствительные параметры (URL-адреса, таймауты, флаги). Секреты (ключи API, токены) — исключительно в `credentials_ref`.
- `credentials_ref` — строка-ссылка вида `vault:secret/telegram/bot-token`. Фактическое значение никогда не хранится в БД. В dev/staging — `NULL` или `mock:...`-префикс. **OQ1 (msg 1556)**: для Telegram в dev-среде допустимо значение `mock:telegram` как плейсхолдер до подключения реального vault. Dev-vault интеграция запланирована в M-OS-1.2 Security/Audit.
- `version` — версия реализации адаптера в semver; при изменении публичного интерфейса адаптера — bump обязателен.
- Оба enum определены как PostgreSQL native enum, `native_enum=True` в Alembic. Значения строго в нижнем регистре (совместимость с Python-enum в ADR-0014).

### Seed-данные (7 записей)

Seed идёт отдельной Alembic-миграцией после DDL-миграции (ADR-0013: DDL и DML — отдельные ревизии).

| name | kind | state | version | config_json (фрагмент) | credentials_ref |
|---|---|---|---|---|---|
| `telegram` | telegram | enabled_live | 1.0.0 | `{"base_url": "https://api.telegram.org", "timeout_ms": 5000}` | `mock:telegram` |
| `sberbank` | bank | written | 1.0.0 | `{"base_url": "https://api.sberbank.ru", "timeout_ms": 10000}` | NULL |
| `tinkoff` | bank | written | 1.0.0 | `{"base_url": "https://api.tinkoff.ru", "timeout_ms": 10000}` | NULL |
| `ofd` | ofd | written | 1.0.0 | `{"base_url": "https://api.ofd.ru", "timeout_ms": 8000}` | NULL |
| `1c` | 1c | written | 1.0.0 | `{"base_url": "", "timeout_ms": 15000}` | NULL |
| `rosreestr` | rosreestr | written | 1.0.0 | `{"base_url": "https://rosreestr.gov.ru/api", "timeout_ms": 30000}` | NULL |
| `kryptopro` | other | written | 1.0.0 | `{"base_url": "", "timeout_ms": 5000}` | NULL |

**Примечания к seed-данным:**

- `telegram.credentials_ref = 'mock:telegram'` — плейсхолдер для dev. **OQ1 (msg 1556)**: реальная ссылка `vault:secret/telegram/bot-token` подставляется при подключении dev-vault в M-OS-1.2 Security/Audit. В production-seed значение заменяется через миграцию M-OS-1.2.
- `kryptopro.kind = 'other'` — **OQ2 (msg 1556)**: КриптоПро получает kind `other` до появления реального use-case (ЭЦП в нескольких модулях). При первом реальном use-case выделить отдельный kind `kryptopro` через amendment к этому ADR + Alembic-миграцию ADD VALUE к enum `integration_kind`.
- `1c` и `kryptopro` имеют пустой `base_url` — URL известен только после настройки конкретной инсталляции 1С/КриптоПро, не глобальный.

### Таблица company_integration_credentials (OQ3 — Multi-tenancy)

**OQ3 (msg 1556)**: при появлении второй компании в холдинге потребуется per-company `credentials_ref` (у каждой компании свой токен Telegram-бота или ключ банковского API). Решение Владельца: отдельная таблица `company_integration_credentials`.

```sql
CREATE TABLE company_integration_credentials (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id       UUID        NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    integration_id   UUID        NOT NULL REFERENCES integration_catalog(id) ON DELETE CASCADE,
    credentials_ref  VARCHAR(255) NOT NULL,  -- ссылка на vault-секрет конкретной компании
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (company_id, integration_id)
);
```

Таблица **не создаётся в M-OS-1** — DDL зарезервирован, будет реализован в M-OS-1.1B при появлении второго tenant. Миграция добавляется отдельным Alembic-шагом. Логика в `IntegrationRegistry.get_state()`: если для company_id существует запись в `company_integration_credentials` — использовать её `credentials_ref` вместо поля в `integration_catalog`.

### Service-слой: IntegrationRegistry

Расположение: `backend/app/core/integration_registry.py`.

Публичный интерфейс service-слоя (не код, только контракт):

```
get_state(name: str) -> AdapterState
    Читает state из кеша (TTL 60 сек). При cache-miss — SELECT из БД. 
    Выбрасывает AdapterNotFoundError если name не найден в catalog.

get_all() -> list[IntegrationCatalogDTO]
    Полный список для Admin UI. Без кеша (прямой SELECT).

set_state(name: str, new_state: AdapterState, actor_id: UUID) -> None
    Обновляет state. Атомарно с записью в AuditLog (ADR-0007).
    Проверяет: переход в enabled_live разрешён только при APP_ENV=production.
    После записи публикует событие AdapterStateChanged в business_events_bus
    (ADR-0016) для инвалидации кеша в других процессах.
    RBAC-проверка: только owner-роль (ADR-0011).

invalidate_cache(name: str) -> None
    Вызывается при получении события AdapterStateChanged из шины.
    Очищает TTL-кеш для конкретного адаптера.
```

`IntegrationAdapter.get_state()` (ADR-0014) вызывает `IntegrationRegistry.get_state(self.adapter_name)`.

### Инвалидация кеша

TTL-кеш в `IntegrationRegistry` — in-process (словарь с временными метками). При изменении `state` через `set_state()`:

1. Запись обновляется в БД (в транзакции с AuditLog).
2. Публикуется событие `AdapterStateChanged(name, new_state)` в `business_events_bus` (ADR-0016).
3. Все запущенные процессы приложения подписаны на этот тип события — при получении вызывают `invalidate_cache(name)`.

В dev (один процесс) инвалидация происходит немедленно. В production (несколько реплик) — через шину. Гарантия: между инвалидацией и следующим вызовом адаптера кеш будет обновлён за TTL не более 60 сек.

### Правила перехода состояний

```
written       → enabled_mock  : разрешено в dev/staging; RBAC owner; AuditLog
written       → enabled_live  : ЗАПРЕЩЕНО напрямую; нарушение CODE_OF_LAWS ст. 45б
enabled_mock  → enabled_live  : разрешено ТОЛЬКО при APP_ENV=production + ratification production-gate (ADR-0018); RBAC owner; AuditLog
enabled_mock  → written       : разрешено; RBAC owner; AuditLog
enabled_live  → enabled_mock  : разрешено (откат); RBAC owner; AuditLog; событие шине
enabled_live  → written       : ЗАПРЕЩЕНО без явного решения governance-director
```

Прямой переход `written → enabled_live` блокируется на уровне сервиса, не только конвенцией.

---

## Последствия

### Положительные

- ADR-0014 DoD выполним: seed-миграция имеет утверждённую схему.
- US-11 (Sprint 3) может стартовать после ratification этого ADR.
- `IntegrationAdapter.get_state()` имеет конкретный вызываемый сервис.
- Admin UI получает конкретный список полей и единый endpoint.
- Каждый toggle `state` аудируется в hash-chain AuditLog — соответствие CODE_OF_LAWS ст. 45б.
- Новый адаптер добавляется без изменения схемы: INSERT в `integration_catalog` + новый enum-значение `kind` при необходимости.

### Отрицательные

- Зависимость guard от доступности PostgreSQL. Митигация: TTL-кеш 60 сек обеспечивает работу при кратковременных сбоях.
- Два отдельных Alembic-шага (DDL + seed) — чуть больше работы для разработчика.

### Нейтральные

- `config_json` в JSONB допускает расширение без изменения схемы — JSONB выбран намеренно (принцип расширяемости ADR-0013).
- **OQ3**: при появлении второй компании потребуется миграция M-OS-1.1B, добавляющая таблицу `company_integration_credentials` (схема зарезервирована выше). Это не требует изменения `integration_catalog`.

### Файловые артефакты Sprint 3

| Файл | Что делает |
|---|---|
| `backend/app/core/integration_registry.py` | Service-слой: get_state / get_all / set_state / invalidate_cache |
| `backend/alembic/versions/NNNN_create_integration_catalog.py` | DDL-миграция: CREATE TABLE + enum types |
| `backend/alembic/versions/MMMM_seed_integration_catalog.py` | DML-миграция: INSERT 7 записей |
| `backend/app/api/admin/integrations.py` | Admin API: GET список, PATCH state (RBAC owner) |

Admin UI (M-OS-1.1B Sprint 3):
- Таблица 7 строк с колонками: name / kind / state / version / updated_at
- Toggle `state` — кнопка с confirmation dialog (переход в `enabled_live` дополнительно показывает предупреждение о production-gate)
- Переход в `enabled_live` в dev/staging — кнопка disabled + tooltip «Требует production-gate (ADR-0018)»

---

## Связи с другими ADR

| ADR | Тип связи | Описание |
|---|---|---|
| ADR-0014 | depends-on (upstream) | Определяет каркас адаптеров; ADR-0015 — хранилище состояния для него |
| ADR-0011 | depends-on | RBAC: только owner изменяет state; AuditLog с crypto-chain |
| ADR-0013 | depends-on | Правила DDL/DML миграций; два отдельных шага |
| ADR-0016 | integrates-with | Шина событий: AdapterStateChanged для инвалидации кеша |
| ADR-0018 | governance-link | Production-gate — предусловие перехода в enabled_live |

---

## Риски

| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| PostgreSQL недоступен при старте кеша | Низкая | Высокое | Fail-fast при старте приложения: если БД недоступна — не запускаться |
| Guard читает устаревший кеш после смены state | Низкая (TTL 60 сек) | Среднее | Инвалидация через business_events_bus сокращает окно; TTL как страховка |
| Разработчик ставит `enabled_live` в seed для нового адаптера | Низкая | Критическое (нарушение ст. 45б) | CI-тест: seed не должен содержать `enabled_live` для адаптеров кроме `telegram` |
| `credentials_ref` заполняется не vault-ссылкой, а живым токеном | Средняя | Критическое (утечка секрета) | lint-правило: значение `credentials_ref` должно начинаться с `vault:` или `mock:` или быть NULL; проверка в CI |
| Base URL одного адаптера изменился, кеш держит старый | Низкая | Среднее | `config_json` не кешируется в TTL-кеше guard; кешируется только `state` |
| Прямой переход written → enabled_live обойдёт сервис (raw SQL) | Очень низкая | Критическое | Тест `test_no_direct_enabled_live_from_written` в CI; grant-политика БД: UPDATE разрешён только через приложение |

---

## План внедрения

| Sprint | Задача | Исполнитель |
|---|---|---|
| Sprint 3 (US-11) | DDL-миграция: CREATE TABLE integration_catalog + enum types | backend-dev |
| Sprint 3 (US-11) | DML-миграция: INSERT 7 seed-записей (telegram.credentials_ref = 'mock:telegram') | backend-dev |
| Sprint 3 (US-11) | `backend/app/core/integration_registry.py`: get_state / get_all / set_state | backend-dev |
| Sprint 3 (US-11) | Интеграция `IntegrationAdapter.get_state()` с registry | backend-dev |
| Sprint 3 (US-11) | Тесты: переходы состояний, блокировка written→enabled_live, lint credentials_ref | qa-engineer |
| M-OS-1.1B Sprint 3 | Admin API: GET /admin/integrations, PATCH /admin/integrations/{name}/state | backend-dev |
| M-OS-1.1B Sprint 3 | Admin UI: таблица 7 записей + toggle + production-gate lock | frontend-dev |
| M-OS-1.1B (при втором tenant) | Миграция: CREATE TABLE company_integration_credentials (OQ3) | backend-dev |
| M-OS-1.2 Security/Audit | Замена mock:telegram → реальный vault-ref в prod-seed | backend-dev |

**Предусловие старта Sprint 3 US-11**: ratification ADR-0015 governance-director. **Закрыто 2026-04-19** (governance-auditor backup-mode).

---

## Открытые вопросы для Владельца

~~1. `credentials_ref` для Telegram в dev~~ — **Закрыто OQ1 (msg 1556)**: `mock:telegram` как плейсхолдер в dev; dev-vault интеграция в M-OS-1.2 Security/Audit.

~~2. kind enum для `kryptopro`~~ — **Закрыто OQ2 (msg 1556)**: `other` до первого реального use-case; выделить отдельный kind при первом использовании.

~~3. Multi-tenancy credentials~~ — **Закрыто OQ3 (msg 1556)**: отдельная таблица `company_integration_credentials`; схема зарезервирована в разделе «Решение»; миграция в M-OS-1.1B.

---

## DoD для ratification

- [x] ADR-0015 прочитан governance-auditor (backup-mode), вопросы к схеме сняты
- [x] Схема таблицы согласована с db-engineer (поля, типы, индексы) — через ADR-0013 compliance
- [x] Открытые вопросы Владельцу переданы и закрыты (OQ1-OQ2-OQ3, msg 1556)
- [x] ADR-0015 получает статус `accepted` от governance-auditor (backup-mode, force-majeure)

---

*ADR составлен architect (субагент-советник) в рамках M-OS-1, Волна 2 Foundation. 2026-04-18.*
*Draft-расширение из stub: добавлены разделы «Проблема», «Контекст», «Рассмотренные альтернативы» (4 варианта), «Решение» (схема таблицы, seed 7 записей, service-слой, инвалидация кеша, правила переходов), «Последствия», «Связи», «Риски», «План внедрения», «Открытые вопросы».*
*Ratification 2026-04-19 (governance-auditor, backup-mode, force-majeure): статус `proposed → accepted`. Заявка: `docs/governance/requests/2026-04-19-adr-0015-ratification.md`. Закрывает DoD предусловие ADR-0014; разблокирует Sprint 3 US-11.*
*Обновление 2026-04-19 (architect): применены решения Владельца OQ1-OQ2-OQ3 (msg 1556): credentials_ref dev=mock:telegram; kryptopro kind=other; зарезервирована таблица company_integration_credentials для M-OS-1.1B.*
