---
status: accepted
title: "ADR 0023 — Rule Snapshots Pattern (универсальный паттерн замораживания правила за сущностью)"
date: 2026-04-19
ratified: 2026-04-19
authors: [backend-director]
depends_on: [ADR-0011, ADR-0013, ADR-0024, ADR-0020, ADR-0016]
---

# ADR 0023 — Rule Snapshots Pattern (универсальный паттерн замораживания правила за сущностью)

- **Статус**: ACCEPTED (force-majeure — governance-auditor backup-mode 2026-04-19, governance-director недоступен через Agent tool; ретроспективное ревью при восстановлении)
- **Дата создания**: 2026-04-19
- **Дата ratification**: 2026-04-19
- **Автор**: backend-director (субагент L2)
- **Утверждающий**: governance-auditor (backup-mode, force-majeure); подтверждение Владельца Q4+Q5 msg 1480 2026-04-19
- **Контекст фазы**: M-OS-1.1B — Admin UI конструктора, редактирование правил согласования платежей и договоров
- **Ratification 2026-04-19**: принят `governance-auditor` в backup-режиме (force-majeure); заявка `docs/governance/requests/2026-04-19-adr-0023-ratification.md`. Применение — Sprint 3 M-OS-1.1B (migration `rule_snapshots` + FK Payment/Contract).
- **Связанные документы**:
  - ADR 0011 (Foundation: multi-company, RBAC, crypto audit) — `company_id`, `approved_by_user_id`, аудит
  - ADR 0013 (Migrations Evolution Contract) — правила эволюции схемы для нового паттерна
  - ADR-0024 (RESERVED: Config-as-Data) — настройки компании (лимиты согласования, матрица прав) как данные; ранее ошибочно указывался как ADR-0017, который фактически является Hooks Defense-in-Depth
  - ADR 0020 (Form/Report JSON descriptors) — JSON-формат описания правил
  - Решение Владельца 2026-04-19 msg 1480 Q4 — «уже существующая заявка на согласовании должна обрабатываться по старому правилу»
  - `docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md` — §US-03, RBAC матрица как данные

---

## Проблема

M-OS-1.1B даёт администратору компании Admin UI для изменения бизнес-правил — лимитов согласования платежей, порядка подписания договоров, матрицы прав. Admin UI пишет правило как строку в таблице `company_settings` / `role_permissions` / будущая `approval_policies`. Изменение видно в системе сразу после сохранения.

Это создаёт **три сценария-конфликта**:

**1. Ретроактивность.** В 10:00 администратор ужесточил правило согласования платежей: раньше «≤ 500 тыс. ₽ одобряет директор, выше — владелец», стало «≤ 300 тыс. ₽ директор, выше — владелец». В 09:30 бухгалтер уже создал Payment на 400 тыс. ₽ и отправил директору на согласование. В 10:30 директор открывает очередь и видит: «нужно одобрение владельца». Но решение о создании заявки уже принято под старым правилом. С бизнес-точки зрения (решение Владельца 2026-04-19 Q4) — «старая заявка идёт по старому правилу, новые заявки — по новому».

**2. Аудируемость.** Через полгода спорный Payment #1247 одобрен `director@coordinata56.ru`. Юрист спрашивает: «а какой лимит был у директора на момент одобрения? сейчас у него 300 тыс., а платёж на 480 тыс. — это нарушение?». Без заморозки правила ответа нет — текущее значение `company_settings.approval_limits` не восстанавливает состояние на момент решения.

**3. Обратная совместимость.** То же самое возникнет на Contract (лимит подписания), Action-workflows (BPM), Invoice (лимит одобрения закрывающих). Паттерн повторяющийся.

---

## Контекст

На момент написания ADR:
- Payment содержит `status`, `approved_at`, `approved_by_user_id`, `rejected_at`, `rejected_by_user_id`, `rejection_reason` — идентификаторы решения, но не само правило.
- Contract содержит аналогичные поля для подписания.
- `company_settings` (ADR-0024 RESERVED: Config-as-Data) — текущие значения лимитов, «только сейчас».
- `role_permissions` (ADR 0011) — текущая матрица, «только сейчас».
- `audit_log` (ADR 0007) — пишет факт изменения, но не восстанавливает содержимое строки на момент принятия бизнес-решения без join-а с timestamp-ом.

Что нужно:
- Универсальный, **типонезависимый** механизм, позволяющий привязать к строке сущности (Payment, Contract, …) конкретную «версию правила» на момент принятия бизнес-решения.
- Паттерн должен легко распространяться на новые сущности без копипаста DDL.
- Производительность: чтение Payment с правилом — без лишних join-ов на hot-path (reader увидит только `rule_snapshot_id`, а сам snapshot достаётся отдельным запросом, когда нужно отобразить детали).

---

## Рассмотренные варианты

### Вариант A — единая базовая таблица `rule_snapshots` + FK от сущностей (принятый)

Одна шина для всех снапшотов всех правил холдинга. Каждая сущность, которой нужна заморозка, добавляет nullable FK `rule_snapshot_id → rule_snapshots.id`.

**Плюсы:**
- Одна миграция для новой сущности — добавить колонку `rule_snapshot_id`, FK, индекс. DDL повторяемо.
- Админ UI показывает универсальную вьюху «какие снапшоты использует компания» без UNION-а по 10 таблицам.
- Запросы для аудита — одно место чтения.

**Минусы:**
- Таблица быстро растёт: ≈10-50 тыс. строк в год на одну компанию (каждое изменение правила = 1 строка, каждое принятие решения — чтение). Для MVP не критично.
- Поле `rule_json` — большой JSONB (~1-5 кб). Компенсируется архивированием старых снапшотов (>5 лет) в отдельную cold-storage таблицу.

### Вариант B — per-module subtable (payment_rule_snapshots, contract_rule_snapshots)

Отдельная таблица на каждую сущность: `payment_rule_snapshots`, `contract_rule_snapshots`, `action_rule_snapshots`.

**Плюсы:**
- Партиционирование «естественное» — каждый модуль растёт своей скоростью.
- Схема rule_json может быть более строгой per-module (не generic JSONB).

**Минусы:**
- Копипаст DDL на каждый модуль, ломает DRY.
- Универсальная Admin UI вьюха через UNION — неудобно и медленно.
- При добавлении новой сущности (например, Invoice) — опять миграция и копирование структуры.

### Вариант C — колонка `rule_snapshot_json` прямо в Payment/Contract

`Payment.approval_rule_snapshot_json: JSONB` — хранить снапшот внутри самой записи.

**Плюсы:**
- Ноль join-ов. Всё в одной строке.

**Минусы:**
- **Не масштабируется.** Каждая новая сущность добавляет свою колонку — схема раздувается, версии правила дублируются между строками (тысяча Payment на одном правиле = тысяча копий rule_json в таблице).
- Размер строки Payment растёт с ~1 кб до ~5-10 кб, серьёзно бьёт по vacuum-производительности при big-table scenarios.
- Нельзя сослаться на один и тот же snapshot из двух разных сущностей (например, если лимит согласования влияет и на Payment, и на Invoice — snapshot должен быть один).
- Нет общего места для Admin UI / аудита.

**Отклонено.** На решении Владельца 2026-04-19 msg 1480 было предложено как default, но Владелец подтвердил «отдельная таблица» — это закрывает дискуссию в пользу Варианта A.

---

## Решение (Вариант A)

### 1. Таблица `rule_snapshots`

```sql
CREATE TABLE rule_snapshots (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id    INTEGER NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
    entity_type   VARCHAR(64) NOT NULL,        -- 'payment', 'contract', 'invoice', ...
    rule_key      VARCHAR(128) NOT NULL,        -- 'approval_limits', 'signature_policy', ...
    version       INTEGER NOT NULL,              -- локальная версия правила (monotonic для pair (entity_type, rule_key, company_id))
    rule_json     JSONB NOT NULL,                -- само содержимое правила, формат — ADR 0020 descriptor
    created_by    INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    description   VARCHAR(512),                  -- человекочитаемое «почему это правило создано»

    UNIQUE (company_id, entity_type, rule_key, version)
);

CREATE INDEX ix_rule_snapshots_company_entity ON rule_snapshots (company_id, entity_type, rule_key);
CREATE INDEX ix_rule_snapshots_created_at ON rule_snapshots (created_at);
```

### 2. FK от потребляющих сущностей

**Payment:**
```sql
ALTER TABLE payments ADD COLUMN approval_rule_snapshot_id UUID NULL
    REFERENCES rule_snapshots(id) ON DELETE RESTRICT;
CREATE INDEX ix_payments_approval_snapshot ON payments (approval_rule_snapshot_id);
```

**Contract:**
```sql
ALTER TABLE contracts ADD COLUMN signature_rule_snapshot_id UUID NULL
    REFERENCES rule_snapshots(id) ON DELETE RESTRICT;
```

**Future (Invoice, Action, …)** — по тому же паттерну.

Колонки nullable, потому что:
- Существующие записи, созданные до введения паттерна, не имеют snapshot.
- Создание записи сразу при `status='draft'` может не нуждаться в snapshot — заморозка происходит в момент `send_to_approval` или при `status='approved'`.

### 3. Когда создаётся snapshot и когда привязывается

**Событие создания snapshot:** каждый раз, когда администратор компании через Admin UI меняет содержимое правила и нажимает «Сохранить». Backend:
1. Пишет новое значение в `company_settings` (current).
2. Создаёт запись в `rule_snapshots` с `version = MAX(version) + 1` для данной пары (entity_type, rule_key, company_id).
3. Пишет событие `RuleChanged` в business-событийную шину (ADR 0016) — подписчики инвалидируют кеши.

**Событие привязки snapshot к сущности:** в момент, когда для данной сущности «замораживается» бизнес-решение. Для Payment это — момент перехода в `status='pending_approval'`:
1. Backend читает текущий snapshot для `(company_id, 'payment', 'approval_limits')` — **последний по version**.
2. Проставляет `payment.approval_rule_snapshot_id = snapshot.id`.
3. Коммитит в той же транзакции, что и смену статуса.

**Использование snapshot при принятии решения:**
1. Когда директор открывает Payment #1247 и нажимает «Одобрить», backend:
2. Загружает Payment, загружает `rule_snapshots[approval_rule_snapshot_id]`.
3. Проверяет лимит **из snapshot.rule_json**, не из текущего `company_settings`.
4. Если проверка пройдена — пишет `approved_at`, `approved_by_user_id` и аудит-запись со ссылкой на `snapshot.id`.

### 4. UI/UX индикация

Admin UI в списке Payment должен показывать маркер: «Одобрено по правилу v7 от 2026-03-15» со ссылкой на snapshot — открывается модал, где видно rule_json и diff с текущим правилом.

### 5. Версионирование и миграция правил

Если правило меняется не просто значением, а структурой (rename поля в rule_json, добавление нового поля) — старые snapshot остаются на старой структуре, новые — на новой. Reader должен уметь читать все версии (via `version` поля в `rule_json` самого — schema version). Это ADR 0020 (JSON descriptor versioning) — здесь повторно не фиксируем.

---

## Последствия

### Положительные

1. **Аудируемость.** Через год можно восстановить «какое правило было на момент одобрения Payment #1247» — join на `rule_snapshots` по `approval_rule_snapshot_id`.
2. **Ретроактивность.** Изменение правила не ломает уже отправленные заявки — каждая ссылается на свой snapshot.
3. **DRY.** Новая сущность (Invoice, Expense, AgendaItem) добавляется одной колонкой `<entity>_rule_snapshot_id`.
4. **Shared snapshots.** Если два модуля используют одно и то же правило (например, `approval_limits` общее для Payment и Invoice) — ссылаются на один snapshot.
5. **Admin UI единообразен.** Одна вьюха «история правил компании» без UNION.

### Отрицательные

1. **Больше join-ов на hot-path.** Каждое чтение Payment с деталями правила = +1 запрос. Смягчение: lazy-load (не тянуть snapshot в листинге, только в карточке).
2. **Рост таблицы.** При интенсивных правках правил (≥ 1 раз/день) — 365 строк/год/пара (entity, rule). 10 пар × 5 компаний = ≈18 тыс. строк/год. Не критично. Cleanup старых snapshot (>5 лет, не привязанных ни к одной сущности) — cron-задача M-OS-2.
3. **JSONB не типобезопасен.** Чтение rule_json требует Pydantic-валидации на каждом использовании. Смягчение: `RuleSnapshot.get_typed(rule_key: Literal[...])` — фабрика, возвращающая типизированный Pydantic-объект.
4. **Миграция существующих данных.** Payment, уже находящиеся в `pending_approval` на момент деплоя, не имеют snapshot. Решение: одноразовый backfill-script при деплое создаёт snapshot v1 из текущих `company_settings` и привязывает ко всем «висящим» записям.

---

## Проверяемые критерии принятия (DoD ADR)

1. Миграция создаёт таблицу `rule_snapshots` + FK `payments.approval_rule_snapshot_id` + FK `contracts.signature_rule_snapshot_id`. `lint-migrations` и `round-trip` зелёные (ADR 0013).
2. `RuleSnapshotService.create(entity_type, rule_key, rule_json, created_by)` создаёт запись с правильной `version`.
3. `PaymentService.send_to_approval()` проставляет `approval_rule_snapshot_id` на текущий snapshot.
4. `PaymentService.approve()` читает правило из `snapshot.rule_json`, не из `company_settings`.
5. Тест `test_retroactive_rule_change`: создать Payment, отправить на согласование, изменить правило через Admin UI, одобрить Payment — одобрение проходит по старому лимиту.
6. Тест `test_snapshot_immutable`: попытка `UPDATE rule_snapshots SET rule_json=... WHERE id=...` либо полностью запрещена (триггер), либо дублирует в новую version — проверяется явно.
7. Admin UI `/admin/rules/history` показывает список snapshot'ов с фильтром по `entity_type` и `rule_key`.

---

## Реализация

- **Спринт M-OS-1.1B Sprint 3** — миграция `rule_snapshots` + базовая модель + сервис `RuleSnapshotService`.
- **Спринт M-OS-1.1B Sprint 3** — интеграция с Payment и Contract.
- **Спринт M-OS-1.2** — распространение на Invoice и Action-workflows.
- **M-OS-2** — cleanup-cron, cold-storage для старых snapshot.

---

## Влияние на существующие ADR

- **ADR 0011** — не меняется. `approved_by_user_id`, `approved_at` остаются; добавляется `approval_rule_snapshot_id`.
- **ADR-0024 (RESERVED: Config-as-Data)** — уточняется: изменение правила в `company_settings` публикует событие `RuleChanged`, которое подхватывает `RuleSnapshotService.create_snapshot_on_change`. Дополнение описывается в amendment к ADR-0024 при его написании. Ранее ошибочно указывался как ADR-0017, который фактически является Hooks Defense-in-Depth.
- **ADR 0020 (JSON descriptors)** — `rule_json` наследует формат дескриптора.
- **ADR 0016 (Event Bus)** — добавляется событие `RuleChanged` в перечень business-событий.

---

## Альтернативы и почему отклонены

См. раздел «Рассмотренные варианты» — Вариант B (per-module) отклонён по DRY, Вариант C (колонка с JSON) отклонён по scalability и размеру строки.

---

*Черновик составлен backend-director 2026-04-19 в рамках подготовки Sprint 3 M-OS-1.1B и по решению Владельца 2026-04-19 msg 1480 Q4. Не блокирует старт Sprint 1 M-OS-1.1A — используется начиная со Sprint 3.*
*Ratification 2026-04-19 (governance-auditor, backup-mode, force-majeure): статус `proposed → accepted`. Заявка: `docs/governance/requests/2026-04-19-adr-0023-ratification.md`. Применение: Sprint 3 M-OS-1.1B (migration + FK Payment/Contract). Warnings (не блокеры): зависимости на `proposed`/`reserved` ADR-0016/ADR-0024/0020 — уточнения возможны при их ratification; amendment к ADR-0024 оформляется отдельной заявкой.*
*Обновление 2026-04-19 (architect): исправлены ссылки ADR-0017 → ADR-0024 (RESERVED: Config-as-Data) во frontmatter, «Связанные документы», «Контекст», «Влияние на существующие ADR». ADR-0017 = Hooks Defense-in-Depth, не Config-as-Data.*
