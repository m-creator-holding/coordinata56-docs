# Фаза 3 — Батч C — Декомпозиция

**Автор**: backend-director
**Дата**: 2026-04-15
**Статус**: готов к старту
**Контекст**: Батчи A и B закрыты reviewer-approve. 263 pytest зелёные. Паттерн эталона Батча B (BudgetCategory → BudgetPlan с bulk-upsert и enum-полем) подтверждён. Переиспользуем его.

---

## 0. Предпосылки (проверено по коду)

### Модели — уже есть в `backend/app/models/contract.py` и `material.py`
- `Contractor` (SoftDeleteMixin + TimestampMixin, уникальный `inn`)
- `Contract` (SoftDeleteMixin + TimestampMixin, FK project_id/contractor_id/house_id/stage_id, `status: ContractStatus`)
- `Payment` (TimestampMixin, FK contract_id, `status: PaymentStatus`, server_default `draft`, `payment_method: PaymentMethod`)
- `MaterialPurchase` (TimestampMixin, FK project_id/house_id/stage_id)

### Enum-ы — уже есть в `backend/app/models/enums.py`
- `ContractStatus {draft, active, completed, cancelled}`
- `PaymentStatus {draft, pending, approved, rejected}`
- `PaymentMethod {bank_transfer, cash, card, other}`

### Миграции — уже применены
- `48b652e20e99_payment_status_enum.py` — enum `payment_status` уже в БД (Батч A).
- Таблицы `contractors`, `contracts`, `payments`, `material_purchases` созданы в initial schema `f80b758cadef`.

### Чего в модели Payment НЕ ХВАТАЕТ для approve-flow
Нужно доложить миграцией (см. §2 «Запрос к db-engineer»):
1. `approved_at: datetime | None` (timezone=True)
2. `approved_by_user_id: int | None` (FK users.id, SET NULL, index)
3. `rejected_at: datetime | None`
4. `rejected_by_user_id: int | None` (FK users.id, SET NULL, index)
5. `rejection_reason: str | None` (Text) — заполняется при переводе в `rejected`

Это нужно, потому что:
- DoD требует иммутабельность после `approved` и тест на это — значит нужно знать «кто и когда подтвердил» для аудита и UI.
- Владелец Q12 утвердил approve/reject как отдельный flow — без полей `rejected_at` и `rejection_reason` reject-эндпоинт теряет смысл.

---

## 1. Граф зависимостей

```
       Contractor (Шаг 1) ─── эталон Батча C
              │
              ▼
          Contract (Шаг 2) ─── зависит от Contractor (FK contractor_id)
              │
              ▼
          Payment (Шаг 3) ─── зависит от Contract (FK contract_id)
                              + approve/reject action-endpoints

       MaterialPurchase (Шаг 4) ─── независим от остальных трёх
                                    (FK только на project/house/stage, уже есть в БД)

       Шаг 5 — замыкание (сверка DoD, финальный прогон тестов, ретро)
```

**Возможный параллелизм**:
- Шаг 1 (Contractor) и Шаг 4 (MaterialPurchase) — параллельно. Разные файлы, разные тесты, FK не пересекаются.
- Шаг 2 (Contract) — после Шага 1.
- Шаг 3 (Payment) — после Шага 2 (в тестах Payment нужны фабрики Contract).
- Шаг 5 — после всех остальных.

**Рекомендация Директора**: на старте — запускаем Шаг 1 и Шаг 4 параллельно (два worker-ов `backend-dev` через `backend-head`). Риск расхождения стиля низкий: оба берут эталон `BudgetCategory` / `BudgetPlan`.

---

## 2. Запрос к db-engineer (до старта Шага 3)

**Задача**: миграция `payment_approval_fields`

**Что добавить** в таблицу `payments`:
| Колонка | Тип | Nullable | FK |
|---|---|---|---|
| `approved_at` | `TIMESTAMP WITH TIME ZONE` | ✅ | — |
| `approved_by_user_id` | `INTEGER` | ✅ | `users.id` ON DELETE SET NULL |
| `rejected_at` | `TIMESTAMP WITH TIME ZONE` | ✅ | — |
| `rejected_by_user_id` | `INTEGER` | ✅ | `users.id` ON DELETE SET NULL |
| `rejection_reason` | `TEXT` | ✅ | — |

**Индексы**: `ix_payments_approved_by_user_id`, `ix_payments_rejected_by_user_id`.

**Требования**:
- Round-trip `alembic downgrade -1 && upgrade head` — чисто.
- Параллельно с миграцией — обновить `backend/app/models/contract.py` (класс `Payment`): добавить 5 полей в Mapped-стиле.

**Срочность**: запрос отправить сразу при старте батча. К моменту начала Шага 3 миграция должна быть применена и смёржена.

**Не срочно**: Contractor / Contract / MaterialPurchase — не требуют новых миграций. Все FK и колонки уже в initial schema.

---

## 3. Шаги батча

### Шаг C.1 — Contractor (эталон Батча C)

**Цель**: CRUD `Contractor`, взять как эталон для всех остальных шагов.

**RBAC**:
- Create / Update / Delete: `owner`, `accountant`
- Read list / Read one: все роли (owner, accountant, construction_manager, read_only)

**Бизнес-правила**:
- `inn` — уникальный (12 цифр для ЮЛ-ИП), нарушение → 409 `CONTRACTOR_INN_DUPLICATE`. Хэндлер IntegrityError глобальный, но явная проверка в сервисе до insert — тоже нужна (лучше UX).
- Soft-delete: стандартный через `SoftDeleteMixin`. Запрет delete, если есть активные `Contract` (где `deleted_at IS NULL`) → 409 `CONTRACTOR_HAS_CONTRACTS`. Сценарий аналогичен `BudgetCategory` ↔ `BudgetPlan` (эталон Батча B).
- Валидация `inn`: только цифры, длина 10 или 12. Pydantic-валидатор.
- Валидация `kpp`: если указан — 9 цифр.

**FILES_ALLOWED**:
- `backend/app/schemas/contractor.py` (new)
- `backend/app/repositories/contractor.py` (new)
- `backend/app/services/contractor.py` (new)
- `backend/app/api/contractors.py` (new)
- `backend/tests/test_contractors.py` (new)
- `backend/app/main.py` (только регистрация роутера)

**FILES_FORBIDDEN**: всё остальное. Модели не трогать. Другие роутеры не трогать.

**DoD Шага C.1**:
- 5 эндпоинтов: `POST /contractors`, `GET /contractors`, `GET /contractors/{id}`, `PATCH /contractors/{id}`, `DELETE /contractors/{id}`.
- Пагинация ADR 0006 на list, фильтр по `category` и `search` (по `short_name` ILIKE) через `extra_conditions` — не Python-постфильтр.
- Аудит ADR 0007 на все write.
- Swagger: summary, description, response_model, пример на каждом эндпоинте.
- Тесты ≥12: happy × 5, 409 duplicate INN, 409 has contracts on delete, 403 × 4 роли × 3 write, 404 на несуществующий, 422 на невалидный ИНН, аудит проверка.
- `ruff check backend/app` чисто.
- `pytest` зелёный.

**Ориентир времени**: 60–90 мин worker.

### Шаг C.2 — Contract (зависит от C.1)

**RBAC**:
- Create / Update / Delete: `owner`, `accountant`
- Read list / Read one: `owner`, `accountant`, `construction_manager` (read_only НЕ имеет доступа — это чувствительная коммерческая информация, суммы и подрядчики)

**Бизнес-правила**:
- Уникальность `(contractor_id, number)` — 409 `CONTRACT_NUMBER_DUPLICATE`.
- `signed_at` не в будущем → 422.
- `amount_cents > 0` → 422.
- Если передан `house_id` — проверить, что дом принадлежит `project_id` (иначе 422 `HOUSE_PROJECT_MISMATCH`). Аналогично для `stage_id`: стадия существует.
- Переходы `status`: `draft → active → completed`, либо `draft → cancelled`, либо `active → cancelled`. Обратные переходы → 409 `BUSINESS_RULE_VIOLATION`. Проверка в сервисе.
- Soft-delete: запрет delete при наличии непустых `Payment` по этому договору → 409 `CONTRACT_HAS_PAYMENTS`.

**FILES_ALLOWED**:
- `backend/app/schemas/contract.py`
- `backend/app/repositories/contract.py`
- `backend/app/services/contract.py`
- `backend/app/api/contracts.py`
- `backend/tests/test_contracts.py`
- `backend/app/main.py` (регистрация)

**FILES_FORBIDDEN**: всё остальное.

**DoD Шага C.2**:
- 5 эндпоинтов CRUD.
- Фильтры list: `contractor_id`, `project_id`, `house_id`, `status` — все через SQL WHERE.
- Тесты ≥14: CRUD happy, 409 duplicate number, 409 has payments, 422 amount<=0, 422 signed_at future, 422 house/project mismatch, 409 bad status transition, RBAC (все 4 роли × create/update/delete/read), 404.
- Аудит + Swagger + ruff + pytest.

**Ориентир времени**: 90–120 мин.

### Шаг C.3 — Payment (+ approve/reject, зависит от C.2 и миграции db-engineer)

**RBAC**:
- Create / Update (только в `draft` / `pending`) / Delete (только `draft`): `owner`, `accountant`
- Read: все роли
- Approve / Reject: **только `owner`** (финальное решение по деньгам — владельца)

**Бизнес-правила (критично, DoD батча)**:
- Переходы статусов: `draft ⇄ pending → approved`, `draft ⇄ pending → rejected`. `approved`, `rejected` — терминальные.
- **Иммутабельность**: `PATCH /payments/{id}` при `status in (approved, rejected)` → 409 `PAYMENT_IMMUTABLE`.
- **Запрет delete**: `DELETE /payments/{id}` при `status in (approved, rejected)` → 409 `PAYMENT_IMMUTABLE`.
- `POST /payments/{id}/approve`: разрешено только из `draft` или `pending`. Проставляет `status=approved`, `approved_at=now()`, `approved_by_user_id=current_user.id`. 409 `INVALID_STATUS_TRANSITION` иначе. Тело запроса пустое.
- `POST /payments/{id}/reject`: разрешено только из `draft` или `pending`. Body: `{"reason": "..."}` (обязательное, min_length=3). Проставляет `status=rejected`, `rejected_at`, `rejected_by_user_id`, `rejection_reason`. 409 из других статусов.
- `contract_id` должен ссылаться на договор в статусе `active` или `completed` (не `draft`, не `cancelled`) → 422 `CONTRACT_NOT_PAYABLE`.
- `amount_cents > 0`, сумма всех approved платежей по договору не должна превышать `contract.amount_cents * 1.2` (допуск 20% на перерасход) → 409 `PAYMENT_EXCEEDS_CONTRACT`. Проверка на approve, не на create (draft-платежи могут быть любыми).
- `paid_at` не в будущем → 422.

**FILES_ALLOWED**:
- `backend/app/schemas/payment.py`
- `backend/app/repositories/payment.py`
- `backend/app/services/payment.py`
- `backend/app/api/payments.py`
- `backend/tests/test_payments.py`
- `backend/app/main.py`

**FILES_FORBIDDEN**: всё остальное. Модель Payment уже будет обновлена db-engineer — НЕ трогать.

**DoD Шага C.3**:
- 7 эндпоинтов: 5 CRUD + `POST /payments/{id}/approve` + `POST /payments/{id}/reject`.
- Иммутабельность: тесты на 409 при PATCH/DELETE approved+rejected.
- Approve: тесты happy (draft→approved, pending→approved) + 409 (approved→approved, rejected→approved) + 403 (accountant не может approve).
- Reject: аналогично, + 422 на отсутствие/короткий `reason`.
- Запрет превышения суммы договора +20% на approve → 409.
- Каскад: `DELETE /contracts/{id}` при наличии любых платежей → 409 (уже в C.2).
- Аудит: approve/reject тоже пишут в audit (action = `update`, meta с old/new status и reason). Проверка тестом.
- Swagger + ruff + pytest.

**Ориентир времени**: 2–3 часа (самый нагруженный шаг).

### Шаг C.4 — MaterialPurchase (параллелится с C.1)

**RBAC**:
- Create / Update / Delete: `construction_manager`, `accountant`, `owner`
- Read: все роли

**Бизнес-правила**:
- `quantity > 0` (Decimal → 422).
- `unit_price_cents > 0` → 422.
- `total_price_cents` — если пришёл, проверить `== round(quantity * unit_price_cents)` с точностью до копейки (защита от опечатки) → 422 `TOTAL_PRICE_MISMATCH`. Если не пришёл — сервис вычисляет сам.
- `house_id` + `stage_id` — опциональны, но если оба null, флаг: это общепроектная закупка (разрешено).
- Если `house_id` указан, проверить принадлежность `project_id` → 422 `HOUSE_PROJECT_MISMATCH`.
- `purchased_at` не в будущем → 422.
- MaterialPurchase **не SoftDelete** (в модели нет mixin'а) → hard delete, но с аудитом.

**FILES_ALLOWED**:
- `backend/app/schemas/material_purchase.py`
- `backend/app/repositories/material_purchase.py`
- `backend/app/services/material_purchase.py`
- `backend/app/api/material_purchases.py`
- `backend/tests/test_material_purchases.py`
- `backend/app/main.py`

**DoD Шага C.4**:
- 5 эндпоинтов CRUD.
- Фильтры list: `project_id`, `house_id`, `stage_id`, `material_name` (ILIKE), `purchased_at__from`, `purchased_at__to` через SQL.
- Тесты ≥12: CRUD happy, 422 quantity<=0, 422 price mismatch, 422 future purchased_at, 422 house/project mismatch, RBAC × 4 роли, 404.
- Аудит + Swagger + ruff + pytest.

**Ориентир времени**: 60–90 мин.

### Шаг C.5 — Замыкание

- Финальный прогон `pytest backend/tests` (ожидаем ~310+ тестов).
- `ruff check backend/app` чисто.
- Ручная проверка Swagger: 4 новых тэга (Contractors, Contracts, Payments, MaterialPurchases), 22 эндпоинта (5+5+7+5).
- Reviewer-pass на Батч C как целое (после per-step ревью).
- Ретро Батча C: 1 страница, что улучшить в Фазе 4.
- Обновить `docs/pods/cottage-platform/phases/phase-3-status.md`: Батч C ✅ done, Фаза 3 ✅ closed (если все 3 батча approved).

---

## 4. Риски и митигации

| # | Риск | Вероятность | Митигация |
|---|---|---|---|
| R1 | db-engineer затянет с миграцией `payment_approval_fields` → Шаг 3 заблокирован | Средняя | Запрос к db-engineer отправляем В ПЕРВУЮ ОЧЕРЕДЬ, до запуска шагов. Шаги 1, 2, 4 идут параллельно — время миграции покроется. |
| R2 | Worker на Шаге 3 смешает approve-flow с generic update (нарушение ADR 0004 amendment «action endpoints») | Средняя | В промпте C.3 явный запрет менять status через PATCH; явное требование — отдельные handler'ы. |
| R3 | Payment total overrun check (20% допуск) — бизнес-логика, которой не было в Q12. Может быть спорной. | Средняя | См. §5 «открытые вопросы» Q-C-1. Есть fallback: если Владелец запретит правило — удалить до merge. |
| R4 | Тесты на иммутабельность покроют не все поля Payment (только status, а не amount/paid_at/…) | Высокая | В промпте C.3 явное требование: тест PATCH любого поля approved Payment → 409. Параметризовать по полям. |
| R5 | Параллельные C.1 и C.4 закоммитят `main.py` оба → merge-конфликт на строке register_router | Средняя | В промпте обоим явно: «git add только свои файлы; изменение `main.py` — одна строка с `app.include_router`, новая строка, без правки порядка». |
| R6 | Пропустят проверку house_id/project_id match (IDOR-класс) | Средняя (Батч A уже ловил P1-1) | Чек-лист самопроверки + явная строка в промпте C.2 и C.4. |
| R7 | `read_only` в Contract сможет прочитать суммы — нежелательно | Низкая | C.2: явно заблокировать read_only в list/read. Тест. |

---

## 5. Открытые бизнес-вопросы (от Владельца)

### Q-C-1 — Допустимый перерасход суммы договора при approve Payment
В decisions явно не зафиксировано. Предлагается +20% (стандарт для стройки — «удорожание материалов»). Если Владелец хочет жёсткое равенство или другой процент — решить до Шага 3.

**Рекомендация Директора**: НЕ эскалировать сразу. Реализуем с дефолтом +20% и порогом в конфиге (`PAYMENT_OVERRUN_LIMIT_PCT=20`). Владелец увидит на Swagger-демо Батча C и откорректирует, если нужно. Откат в случае изменения — 10-минутное изменение константы и тестов. *(Следуем правилу CLAUDE.md: не дёргать Владельца, если решение выводимо и откатываемо.)*

### Q-C-2 — Rejection flow: допустим ли возврат rejected → draft?
В decisions Q12 сказано «approved — терминальный», но про `rejected` явно не сказано. Возможны два варианта:
- (a) `rejected` — тоже терминальный (нужно создать новый Payment).
- (b) `rejected → draft` допустим (платёж можно пересобрать и подать заново).

**Рекомендация Директора**: реализуем (a) — `rejected` терминальный, для симметрии с `approved` и простоты аудита. Это прямо следует из decisions Q12 формулировки `draft ⇄ pending → approved/rejected` (стрелка односторонняя). **Не эскалирую** — решение выводится из документа.

### Q-C-3 — Contract delete: жёсткое RESTRICT или soft с каскадным soft-delete payments?
Модель: Contract — SoftDeleteMixin. Payment — без SoftDeleteMixin, hard-delete.

**Рекомендация Директора**: запрещаем soft-delete Contract при наличии любых Payment (включая draft). Чтобы удалить договор — сначала удалить/отклонить его платежи. Это проще для аудита и согласуется с эталоном BudgetCategory ↔ BudgetPlan. **Не эскалирую**, паттерн уже утверждён Батчем B.

**Итог по эскалации к Владельцу**: по трём вопросам эскалации нет — решения выводятся из документов или откатываемы.

---

## 6. Итоговый план отправки к backend-head

1. Отправить db-engineer запрос на миграцию `payment_approval_fields` (через db-head / координатор).
2. Параллельно запустить у backend-head два потока:
   - Поток α: Шаг C.1 (Contractor, эталон)
   - Поток β: Шаг C.4 (MaterialPurchase)
3. После C.1 approve — Шаг C.2 (Contract).
4. После C.2 approve И миграции Payment approved — Шаг C.3 (Payment).
5. Замыкание C.5.

Ожидаемый календарь: 3–4 рабочих дня (с ревью).

---

## Готовые промпты для backend-head

В отдельных блоках ниже — каждый промпт самодостаточный, готов к копипасте в Agent-вызов `subagent_type: backend-head`.

### Промпт C.1 — Contractor

```
Задача: Шаг C.1 Батча C Фазы 3 — CRUD Contractor (эталон Батча C).

ОБЯЗАТЕЛЬНО прочитай:
1. /root/coordinata56/CLAUDE.md
2. /root/coordinata56/docs/agents/departments/backend.md
3. /root/coordinata56/docs/pods/cottage-platform/specs/phase-3-batch-c-decomposition.md (§3 Шаг C.1)
4. /root/coordinata56/docs/adr/0004,0005,0006,0007
5. Эталон Батча B: backend/app/services/budget_category.py, backend/app/api/budget_categories.py,
   backend/tests/test_budget_categories.py

Модель уже есть: backend/app/models/contract.py класс Contractor (SoftDeleteMixin, unique inn).
Миграции НЕ требуются — таблица contractors в initial schema.

Реализуй CRUD:
- schemas/contractor.py: ContractorCreate, ContractorUpdate, ContractorRead
- repositories/contractor.py: ContractorRepository(BaseRepository[Contractor])
- services/contractor.py: ContractorService (аудит на все write, проверка has_active_contracts)
- api/contractors.py: 5 эндпоинтов + фильтр list (category, search по short_name)
- tests/test_contractors.py: ≥12 тестов
- main.py: регистрация роутера

RBAC:
- write (create/update/delete): owner, accountant
- read (list/one): все роли

Бизнес-правила:
- inn уникальный. 409 CONTRACTOR_INN_DUPLICATE явной проверкой до insert. IntegrityError fallback — глобальный.
- Валидация Pydantic: inn — только цифры, длина 10 или 12; kpp — 9 цифр если задан.
- Soft-delete через SoftDeleteMixin. Запрет delete, если есть активные Contract (deleted_at IS NULL) → 409 CONTRACTOR_HAS_CONTRACTS.
- Фильтры list — только через SQL WHERE extra_conditions, не Python-пост-фильтр.

FILES_ALLOWED:
- backend/app/schemas/contractor.py
- backend/app/repositories/contractor.py
- backend/app/services/contractor.py
- backend/app/api/contractors.py
- backend/tests/test_contractors.py
- backend/app/main.py (только одна строка include_router)

FILES_FORBIDDEN: всё остальное. Модели не трогать. Существующие роутеры не трогать.

COMMUNICATION_RULES:
- backend-head делегирует одному backend-dev; два раунда ревью максимум до эскалации ко мне.
- При отклонениях от ADR — стоп и эскалация к backend-director (мне).
- Не коммить. Только git add своих файлов после зелёного ревью.

DoD: см. §3 Шаг C.1 в decomposition.md.
Отчёт: ≤250 слов, включить список тестов, итог ruff/pytest, время работы.
```

### Промпт C.2 — Contract

```
Задача: Шаг C.2 Батча C Фазы 3 — CRUD Contract.
Предусловие: Шаг C.1 (Contractor) — approved и в main.

ОБЯЗАТЕЛЬНО прочитай:
1. /root/coordinata56/CLAUDE.md
2. /root/coordinata56/docs/agents/departments/backend.md
3. /root/coordinata56/docs/pods/cottage-platform/specs/phase-3-batch-c-decomposition.md (§3 Шаг C.2)
4. /root/coordinata56/docs/adr/0004,0005,0006,0007
5. Эталон: свежесделанный backend/app/services/contractor.py (Шаг C.1).

Модель уже есть: backend/app/models/contract.py класс Contract (SoftDeleteMixin).
Миграции НЕ требуются.

RBAC:
- write: owner, accountant
- read: owner, accountant, construction_manager (read_only БЛОКИРОВАН — явный тест).

Бизнес-правила:
- Уникальность (contractor_id, number) → 409 CONTRACT_NUMBER_DUPLICATE.
- signed_at не в будущем → 422.
- amount_cents > 0 → 422.
- house_id, если указан, должен принадлежать project_id → 422 HOUSE_PROJECT_MISMATCH.
- stage_id, если указан, должен существовать.
- Переходы status: draft→active→completed | draft→cancelled | active→cancelled. Иначе 409 BUSINESS_RULE_VIOLATION. Переход делается через PATCH (update-схема содержит status).
- Запрет soft-delete при наличии любых Payment (включая soft-deleted нет — Payment hard-delete) → 409 CONTRACT_HAS_PAYMENTS.
- Фильтры list: contractor_id, project_id, house_id, status — SQL WHERE.

FILES_ALLOWED:
- backend/app/schemas/contract.py
- backend/app/repositories/contract.py
- backend/app/services/contract.py
- backend/app/api/contracts.py
- backend/tests/test_contracts.py
- backend/app/main.py

FILES_FORBIDDEN: всё остальное.

COMMUNICATION_RULES: как в C.1.

DoD: §3 Шаг C.2. Тесты ≥14.
Отчёт ≤250 слов.
```

### Промпт C.3 — Payment

```
Задача: Шаг C.3 Батча C Фазы 3 — CRUD Payment + action-endpoints approve/reject.
Предусловия:
- Шаги C.1 и C.2 — approved и в main.
- Миграция payment_approval_fields от db-engineer — применена. Поля approved_at, approved_by_user_id,
  rejected_at, rejected_by_user_id, rejection_reason в модели Payment — уже есть.
  Проверь это чтением backend/app/models/contract.py перед началом работы. Если нет —
  немедленно эскалируй к backend-director, НЕ реализуй поля сам.

ОБЯЗАТЕЛЬНО прочитай:
1. /root/coordinata56/CLAUDE.md
2. /root/coordinata56/docs/agents/departments/backend.md
3. /root/coordinata56/docs/pods/cottage-platform/specs/phase-3-batch-c-decomposition.md (§3 Шаг C.3)
4. /root/coordinata56/docs/adr/0004,0005,0006,0007
5. Эталоны Шагов C.1 и C.2.
6. /root/coordinata56/docs/pods/cottage-platform/phases/phase-3-decisions.md §Q12 (иммутабельность).

RBAC:
- Create / Update (только draft+pending) / Delete (только draft): owner, accountant.
- Read: все роли.
- POST /payments/{id}/approve: ТОЛЬКО owner.
- POST /payments/{id}/reject: ТОЛЬКО owner.

Бизнес-правила (критично для DoD):
- Переходы: draft⇄pending → approved|rejected. approved и rejected терминальны.
- PATCH /payments/{id} при status in (approved, rejected) → 409 PAYMENT_IMMUTABLE для ЛЮБОГО поля.
  Параметризовать тест по всем полям Payment: amount_cents, paid_at, payment_method, document_ref, note.
- DELETE /payments/{id} при status in (approved, rejected) → 409 PAYMENT_IMMUTABLE.
- Update схема НЕ содержит поле status. Изменение статуса ТОЛЬКО через approve/reject (action-endpoints,
  ADR 0004 amendment).
- POST /payments/{id}/approve:
    - Разрешено из draft или pending. Иначе 409 INVALID_STATUS_TRANSITION.
    - Проверить: сумма всех approved платежей по contract_id (включая этот) <= contract.amount_cents * 1.2.
      Иначе 409 PAYMENT_EXCEEDS_CONTRACT. Порог 20% — в конфиге PAYMENT_OVERRUN_LIMIT_PCT (default 20).
    - Проставить status=approved, approved_at=now(), approved_by_user_id=current_user.id.
    - Audit action=update, meta: {"transition": "approved", "from_status": "<old>"}.
- POST /payments/{id}/reject:
    - Body: {"reason": str} (min_length=3), иначе 422.
    - Разрешено из draft или pending. Иначе 409.
    - Проставить status=rejected, rejected_at, rejected_by_user_id, rejection_reason.
    - Audit action=update, meta: {"transition": "rejected", "from_status": "<old>", "reason": "<...>"}.
- Create Payment: contract.status in (active, completed). Иначе 422 CONTRACT_NOT_PAYABLE.
- amount_cents > 0, paid_at не в будущем.

FILES_ALLOWED:
- backend/app/schemas/payment.py
- backend/app/repositories/payment.py
- backend/app/services/payment.py
- backend/app/api/payments.py
- backend/tests/test_payments.py
- backend/app/main.py
- backend/app/config.py (только добавить PAYMENT_OVERRUN_LIMIT_PCT если его нет)

FILES_FORBIDDEN: всё остальное. Модель Payment — read-only, её правит db-engineer.

COMMUNICATION_RULES: как в C.1.

DoD: §3 Шаг C.3. Тесты ≥18 (CRUD + иммутабельность × 5 полей × 2 статуса + approve happy/fail + reject happy/fail
+ overrun + RBAC).
Отчёт ≤300 слов.
```

### Промпт C.4 — MaterialPurchase

```
Задача: Шаг C.4 Батча C Фазы 3 — CRUD MaterialPurchase. Может идти параллельно с C.1.

ОБЯЗАТЕЛЬНО прочитай:
1. /root/coordinata56/CLAUDE.md
2. /root/coordinata56/docs/agents/departments/backend.md
3. /root/coordinata56/docs/pods/cottage-platform/specs/phase-3-batch-c-decomposition.md (§3 Шаг C.4)
4. /root/coordinata56/docs/adr/0004,0005,0006,0007
5. Эталон Батча B: BudgetCategory / BudgetPlan.

Модель уже есть: backend/app/models/material.py класс MaterialPurchase (БЕЗ SoftDeleteMixin — hard delete).
Миграции НЕ требуются.

RBAC:
- write: construction_manager, accountant, owner.
- read: все роли.

Бизнес-правила:
- quantity > 0, unit_price_cents > 0 → 422.
- total_price_cents: если передан — проверить равенство round(quantity * unit_price_cents) с точностью до 1
  копейки → 422 TOTAL_PRICE_MISMATCH. Если не передан — сервис вычисляет.
- house_id и stage_id опциональны. Если house_id указан — проверить house.project_id == project_id → 422
  HOUSE_PROJECT_MISMATCH.
- purchased_at не в будущем → 422.
- DELETE — hard delete с аудитом (MaterialPurchase не SoftDelete).

Фильтры list (SQL WHERE):
- project_id, house_id, stage_id, material_name (ILIKE), purchased_at__from, purchased_at__to.

FILES_ALLOWED:
- backend/app/schemas/material_purchase.py
- backend/app/repositories/material_purchase.py
- backend/app/services/material_purchase.py
- backend/app/api/material_purchases.py
- backend/tests/test_material_purchases.py
- backend/app/main.py

FILES_FORBIDDEN: всё остальное.

COMMUNICATION_RULES: как в C.1.

DoD: §3 Шаг C.4. Тесты ≥12.
Отчёт ≤250 слов.
```

### Промпт C.5 — Замыкание

```
Задача: Замыкание Батча C Фазы 3.

Выполни:
1. pytest backend/tests — полный прогон, приложить итог (должно быть ~310+ тестов, 0 failed).
2. ruff check backend/app — должно быть чисто.
3. Проверить Swagger (GET /openapi.json): наличие тэгов Contractors, Contracts, Payments, MaterialPurchases;
   суммарно 22 эндпоинта новых; у каждого — summary, description, response_model.
4. Обновить /root/coordinata56/docs/pods/cottage-platform/phases/phase-3-status.md: Батч C ✅ done.
5. Написать /root/coordinata56/docs/retros/phase-3-batch-c-retro.md (1 страница): что сработало, что улучшить.

FILES_ALLOWED:
- docs/pods/cottage-platform/phases/phase-3-status.md
- docs/retros/phase-3-batch-c-retro.md

FILES_FORBIDDEN: код.

Отчёт ≤200 слов.
```
