# Фаза 3 — User Stories

**Дата**: 2026-04-15
**Статус**: готово к ревью Владельца
**Автор**: business-analyst (субагент)
**Связанные документы**: `phase-3-scope.md`, ADR 0003, ADR 0001

---

## US-3.1 — Создание проекта и первичная загрузка домов

**Как** owner
**Я хочу** создать новый проект и зарегистрировать в нём все 85 домов одной операцией
**Чтобы** получить исходную структуру посёлка в системе и сразу видеть полный реестр объектов

### Критерии приёмки

**AC1 (happy path — создание проекта):**
Given: пользователь с ролью `owner` отправляет `POST /projects` с телом `{code: "coordinata56", name: "Координата 56", status: "active"}`
When: запрос обработан
Then: проект создан, в ответе `201 Created` с полями `id`, `code`, `name`, `status`, `created_at`; в `audit_log` появилась запись `action=create, entity=project, entity_id=<новый id>, user_id=<owner>`

**AC2 (happy path — bulk-создание домов):**
Given: проект с `id=1` существует, справочник `HouseType` содержит хотя бы один тип, пользователь с ролью `owner` отправляет `POST /projects/1/houses/bulk` со списком из N объектов `[{plot_number: "1", house_type_id: 2}, ...]`
When: запрос обработан
Then: в БД созданы N записей `House` с `project_id=1`, `current_stage_id=null`; ответ `201 Created` содержит список созданных `id`; в `audit_log` появилась N записей `action=create, entity=house`

**AC3 (permission-denied — чужая роль):**
Given: пользователь с ролью `accountant` или `construction_manager` отправляет `POST /projects`
When: запрос обработан
Then: ответ `403 Forbidden`, тело содержит `error_code: "permission_denied"`, проект не создан, в `audit_log` появилась запись `action=access_denied`

**AC4 (validation error — дубликат кода):**
Given: проект с `code="coordinata56"` уже существует в БД, пользователь с ролью `owner` отправляет `POST /projects` с тем же `code`
When: запрос обработан
Then: ответ `409 Conflict`, тело содержит `error_code: "duplicate_code"`, новый проект не создан

**AC5 (validation error — несуществующий тип при bulk):**
Given: проект существует, один из объектов в bulk-списке содержит `house_type_id=9999` (не существует)
When: запрос обработан
Then: ответ `422 Unprocessable Entity`, ни один из домов не создан (транзакция откатывается целиком), тело содержит индекс ошибочного элемента и `error_code: "house_type_not_found"`

### Скрытые допущения / вопросы

- **Q1**: Существует ли эндпоинт `POST /projects/{id}/houses/bulk` в скоупе Батча A, или дома создаются поштучно через `POST /projects/{id}/houses`? Скоуп говорит об отдельном bulk-эндпоинте для `HouseTypeOptionCompat`, но для домов явно не оговорено. **Требует решения Владельца до кодинга.**
- **Q2**: При bulk-создании 85 домов — поведение «всё или ничего» (транзакция) или частичный успех с отчётом об ошибках? AC5 зафиксирует «всё или ничего» как дефолт; если нужна частичность — необходимо уточнение.
- **Q3**: Значения `status` поля `Project` нигде не перечислены как enum в модели (тип `String(32)`). Допустимые значения: только `active`? Или возможны `archived`, `completed`? **Нужен список допустимых статусов от Владельца.**

---

## US-3.2 — Создание дома и привязка опций

**Как** owner или construction_manager
**Я хочу** создать запись конкретного дома и прикрепить к нему выбранные покупателем опции
**Чтобы** система знала точную комплектацию дома с зафиксированными на момент выбора ценами

### Критерии приёмки

**AC1 (happy path — создание дома):**
Given: проект существует, тип дома существует, пользователь с ролью `owner` или `construction_manager` отправляет `POST /projects/{project_id}/houses` с телом `{plot_number: "42", house_type_id: 1}`
When: запрос обработан
Then: дом создан, в ответе `201 Created` с полями `id`, `plot_number`, `house_type_id`, `current_stage_id: null`, `created_at`; в `audit_log` запись `action=create, entity=house`

**AC2 (happy path — привязка опций):**
Given: дом с `id=42` существует, опция с `id=5` существует, совместимость `HouseTypeOptionCompat(house_type_id=X, option_id=5)` есть в БД, пользователь с ролью `owner` или `construction_manager` отправляет `POST /houses/42/configurations` с телом `{option_id: 5, chosen_at: "2026-04-15T10:00:00Z"}`
When: запрос обработан
Then: запись `HouseConfiguration` создана с `locked_price_cents` и `locked_cost_cents`, скопированными из `OptionCatalog.price_cents` и `cost_cents` на момент вызова; ответ `201 Created`; в `audit_log` запись `action=create, entity=house_configuration`

**AC3 (permission-denied — read_only):**
Given: пользователь с ролью `read_only` отправляет `POST /projects/{project_id}/houses`
When: запрос обработан
Then: ответ `403 Forbidden`, дом не создан

**AC4 (business-rule — несовместимая опция):**
Given: дом имеет тип `A`, опция с `id=7` совместима только с типом `B` (нет записи в `HouseTypeOptionCompat` для типа `A`), пользователь отправляет `POST /houses/{id}/configurations` с `option_id=7`
When: запрос обработан
Then: ответ `422 Unprocessable Entity` с `error_code: "option_incompatible_with_house_type"`, запись `HouseConfiguration` не создана

**AC5 (validation — дубликат участка):**
Given: в проекте уже есть дом с `plot_number="42"`, пользователь отправляет `POST /projects/{project_id}/houses` с тем же `plot_number`
When: запрос обработан
Then: ответ `409 Conflict` с `error_code: "plot_number_duplicate"`, новый дом не создан

### Скрытые допущения / вопросы

- **Q4**: Может ли одна и та же опция быть добавлена к одному дому дважды (дубликат в `HouseConfiguration`)? Модель явного `UniqueConstraint(house_id, option_id)` не содержит. **Нужно решение: запрещать на уровне API или разрешать (например, для разных `chosen_at`)?**
- **Q5**: Кто устанавливает `chosen_at` — клиент в теле запроса или сервер автоматически? Это важно для аудита — если клиент может передать любую дату, история будет фиктивной.

---

## US-3.3 — Смена стадии дома

**Как** construction_manager
**Я хочу** перевести дом на следующую стадию строительства
**Чтобы** в системе автоматически зафиксировалась история переходов и было видно реальное состояние стройки

### Критерии приёмки

**AC1 (happy path — переход на следующую стадию):**
Given: дом с `id=10` находится на стадии `фундамент` (`current_stage_id=3`), стадия `стены` имеет `id=4` и `order_index=4`, пользователь с ролью `construction_manager` отправляет `PATCH /houses/10/stage` с телом `{new_stage_id: 4}`
When: запрос обработан
Then:
- в таблице `House` обновлено `current_stage_id=4`
- в таблице `HouseStageHistory` создана запись: `house_id=10`, `stage_id=4`, `started_at=<текущее время UTC>`, `completed_at=null`, `moved_by_user_id=<id вызвавшего пользователя>`
- предыдущая запись истории для `stage_id=3` получает `completed_at=<текущее время UTC>`
- в `audit_log` запись `action=update, entity=house, entity_id=10`
- ответ `200 OK` с актуальным состоянием дома и ссылкой на новую запись истории

**AC2 (permission-denied — accountant не может менять стадию):**
Given: пользователь с ролью `accountant` отправляет `PATCH /houses/10/stage`
When: запрос обработан
Then: ответ `403 Forbidden` с `error_code: "permission_denied"`, стадия не изменена, запись в `HouseStageHistory` не создана

**AC3 (business-rule — попытка перейти на предыдущую стадию):**
Given: дом на стадии `стены` (`order_index=4`), пользователь отправляет `PATCH /houses/10/stage` с `new_stage_id`, у которого `order_index=2` (регресс)
When: запрос обработан
Then: ответ `422 Unprocessable Entity` с `error_code: "stage_regression_not_allowed"`, стадия не изменена

**AC4 (validation — несуществующая стадия):**
Given: пользователь отправляет `PATCH /houses/10/stage` с `new_stage_id=9999`
When: запрос обработан
Then: ответ `404 Not Found` с `error_code: "stage_not_found"`

**AC5 (edge case — первая стадия):**
Given: дом с `current_stage_id=null` (только что создан, стадия не назначена), пользователь отправляет `PATCH /houses/10/stage` с любым валидным `new_stage_id`
When: запрос обработан
Then: переход разрешён (нет предыдущей стадии для сравнения `order_index`), запись `HouseStageHistory` создана, `House.current_stage_id` обновлён

### Скрытые допущения / вопросы

- **Q6**: Разрешён ли **пропуск стадий** (например, с `order_index=1` сразу на `order_index=5`)? Или только переход на ближайшую следующую? **Критично — определяет бизнес-правило в AC3. Требует решения Владельца.**
- **Q7**: Кто ещё может менять стадию? Только `construction_manager`, или `owner` тоже? ADR 0003 говорит `owner > construction_manager` по иерархии, но скоуп явно не указывает `owner` для этой операции.
- **Q8**: Что происходит с `HouseStageHistory`, если стадию меняет `owner` в обход прораба — нужна ли отдельная метка в истории?

---

## US-3.4 — Загрузка планового бюджета (bulk)

**Как** owner или accountant
**Я хочу** загрузить плановый бюджет одним запросом по всем разрезам (проект × статья × стадия × дом)
**Чтобы** иметь в системе исходный план, с которым впоследствии сравниваются фактические затраты

### Критерии приёмки

**AC1 (happy path — bulk-загрузка плана):**
Given: проект, дома и статьи бюджета (`BudgetCategory`) существуют, пользователь с ролью `owner` или `accountant` отправляет `POST /projects/{project_id}/budget-plan/bulk` со списком объектов вида `[{house_id: 1, stage_id: 2, category_id: 3, amount_cents: 500000, note: "..."}, ...]`
When: запрос обработан
Then: все строки сохранены в таблице `BudgetPlan`; ответ `201 Created` с количеством созданных записей; в `audit_log` запись на каждую созданную строку `action=create, entity=budget_plan`

**AC2 (happy path — план на уровне проекта без дома и стадии):**
Given: пользователь отправляет строку с `house_id: null, stage_id: null, category_id: 3, amount_cents: 10000000`
When: запрос обработан
Then: запись создана с `house_id=null`, `stage_id=null` — это допустимый разрез «план на весь проект по статье»

**AC3 (permission-denied — construction_manager):**
Given: пользователь с ролью `construction_manager` отправляет `POST /projects/{project_id}/budget-plan/bulk`
When: запрос обработан
Then: ответ `403 Forbidden`, ни одна строка не создана

**AC4 (validation error — несуществующая статья):**
Given: один из объектов в списке содержит `category_id=9999` (не существует в `BudgetCategory`)
When: запрос обработан
Then: ответ `422 Unprocessable Entity`, **вся транзакция откатывается** (ни одна строка не сохранена), тело содержит индекс ошибочного объекта и `error_code: "budget_category_not_found"`

**AC5 (business-rule — отрицательная сумма):**
Given: один из объектов содержит `amount_cents: -1000`
When: запрос обработан
Then: ответ `422 Unprocessable Entity` с `error_code: "amount_must_be_positive"`, транзакция откатывается

### Скрытые допущения / вопросы

- **Q9**: **Повторная загрузка плана** — это upsert (перезаписать существующие строки) или всегда insert (дублировать)? Если accountant дважды загрузит план по одному разрезу `(project, house, stage, category)`, какое поведение ожидается? **Ключевой вопрос для бизнес-логики. Требует решения Владельца.**
- **Q10**: Нужна ли версионность плана? Например, «Первоначальный план» vs. «Скорректированный план Q2»? Если да — потребуется отдельное поле `version` или отдельная таблица.
- **Q11**: Кто имеет право **удалить или обнулить** плановую строку? Только `owner` или `accountant` тоже?

---

## US-3.5 — Регистрация платежа по договору

**Как** accountant
**Я хочу** зарегистрировать исходящий платёж по действующему договору
**Чтобы** в системе отражался точный факт движения денег с привязкой к конкретному договору и подрядчику

### Критерии приёмки

**AC1 (happy path — создание платежа):**
Given: договор с `id=7` имеет `status=active`, пользователь с ролью `accountant` отправляет `POST /contracts/7/payments` с телом `{amount_cents: 150000, paid_at: "2026-04-15T12:00:00Z", payment_method: "bank_transfer", document_ref: "П/П-0042"}`
When: запрос обработан
Then: запись `Payment` создана с `contract_id=7`, `created_by_user_id=<id accountant>`; ответ `201 Created`; в `audit_log` запись `action=create, entity=payment`

**AC2 (иммутабельность — попытка изменить approved платёж):**
Given: платёж с `id=15` имеет признак `approved` (см. Q12), пользователь с ролью `accountant` или `owner` отправляет `PATCH /payments/15` или `DELETE /payments/15`
When: запрос обработан
Then: ответ `409 Conflict` с `error_code: "payment_is_approved_immutable"`, запись не изменена и не удалена

**AC3 (permission-denied — construction_manager):**
Given: пользователь с ролью `construction_manager` отправляет `POST /contracts/{id}/payments`
When: запрос обработан
Then: ответ `403 Forbidden`, платёж не создан

**AC4 (business-rule — договор не в статусе active):**
Given: договор с `id=8` имеет `status=draft` или `status=cancelled`, пользователь отправляет `POST /contracts/8/payments`
When: запрос обработан
Then: ответ `422 Unprocessable Entity` с `error_code: "contract_not_active"`, платёж не создан

**AC5 (validation — нулевая сумма):**
Given: тело запроса содержит `amount_cents: 0`
When: запрос обработан
Then: ответ `422 Unprocessable Entity` с `error_code: "amount_must_be_positive"`

### Скрытые допущения / вопросы

- **Q12**: **Поле `approved` отсутствует в модели `Payment`**. Скоуп упоминает «иммутабельность после approved», но в модели нет ни поля `is_approved: bool`, ни `status`. Как именно фиксируется признак «утверждён»? Это:
  - (a) отдельное поле `is_approved bool` в таблице `payments`,
  - (b) отдельный статус в enum `PaymentStatus`,
  - (c) отдельная операция `POST /payments/{id}/approve`?
  **Критически важно. Без ответа на Q12 AC2 нельзя реализовать. Требует решения Владельца до начала Батча C.**
- **Q13**: Может ли сумма платежей по договору превысить `Contract.amount_cents`? Нужна ли валидация «сумма всех платежей ≤ сумма договора»? Если да — это бизнес-правило, которое должно войти в отдельный AC.
- **Q14**: Платёж может быть создан только к договору со статусом `active`? Или также `completed`? Например, если закрыли договор, но доплата ещё идёт.

---

## US-3.6 — Регистрация закупки материала

**Как** construction_manager или accountant
**Я хочу** внести запись о закупке материала с привязкой к дому и стадии строительства
**Чтобы** отслеживать фактические материальные затраты в разрезе каждого объекта и этапа

### Критерии приёмки

**AC1 (happy path — регистрация закупки с привязкой к дому и стадии):**
Given: проект `id=1` существует, дом `id=10` существует и принадлежит проекту `id=1`, стадия `id=3` существует, пользователь с ролью `construction_manager` отправляет `POST /projects/1/material-purchases` с телом:
```json
{
  "house_id": 10,
  "stage_id": 3,
  "material_name": "Бетон М300",
  "quantity": 12.5,
  "unit": "м³",
  "unit_price_cents": 800000,
  "total_price_cents": 10000000,
  "supplier": "ООО Бетонстрой",
  "purchased_at": "2026-04-15T09:00:00Z"
}
```
When: запрос обработан
Then: запись `MaterialPurchase` создана с `project_id=1`, `received_by_user_id=<id вызвавшего>`; ответ `201 Created`; в `audit_log` запись `action=create, entity=material_purchase`

**AC2 (happy path — закупка без привязки к конкретному дому):**
Given: пользователь отправляет тело с `house_id: null, stage_id: null` (общепроектная закупка)
When: запрос обработан
Then: запись создана с `house_id=null`, `stage_id=null` — допустимый сценарий для общих материалов проекта

**AC3 (permission-denied — read_only):**
Given: пользователь с ролью `read_only` отправляет `POST /projects/{id}/material-purchases`
When: запрос обработан
Then: ответ `403 Forbidden`, запись не создана

**AC4 (business-rule — несоответствие total_price_cents арифметике):**
Given: в запросе `quantity=10`, `unit_price_cents=100000`, `total_price_cents=50000` (≠ 10 × 100 000 = 1 000 000)
When: запрос обработан
Then: ответ `422 Unprocessable Entity` с `error_code: "total_price_mismatch"`, запись не создана

**AC5 (validation — дом не принадлежит проекту):**
Given: дом `id=55` принадлежит проекту `id=2`, пользователь отправляет запрос к `POST /projects/1/material-purchases` с `house_id=55`
When: запрос обработан
Then: ответ `422 Unprocessable Entity` с `error_code: "house_not_in_project"`, запись не создана

### Скрытые допущения / вопросы

- **Q15**: **Проверка арифметики `total = quantity × unit_price`** — обязательна на уровне API (AC4) или `total_price_cents` просто доверяется клиенту? Если клиент сам несёт ответственность (например, скидка на объём изменяет итог), правило AC4 нужно убрать. **Требует решения Владельца.**
- **Q16**: Нужна ли привязка закупки к **договору** (`contract_id`)? В текущей модели `MaterialPurchase` нет поля `contract_id`. Если материалы закупаются по договорам с поставщиками — это разрыв в модели данных между `Payment` (есть `contract_id`) и `MaterialPurchase` (нет).
- **Q17**: Кто является `received_by_user_id` — тот, кто вносит запись в систему, или тот, кто физически принял материал на объекте? Это разные люди в реальном процессе.

---

## Сводная таблица ролей и операций

| Операция                          | owner | accountant | construction_manager | read_only |
|-----------------------------------|:-----:|:----------:|:--------------------:|:---------:|
| Создать проект                    | ✅    | ❌         | ❌                   | ❌        |
| Bulk-создание домов               | ✅    | ❌         | ❌                   | ❌        |
| Создать дом / привязать опцию     | ✅    | ❌         | ✅                   | ❌        |
| Сменить стадию дома               | ✅*   | ❌         | ✅                   | ❌        |
| Загрузить плановый бюджет         | ✅    | ✅         | ❌                   | ❌        |
| Создать платёж                    | ✅    | ✅         | ❌                   | ❌        |
| Создать закупку материала         | ✅    | ✅         | ✅                   | ❌        |

*Q7: право `owner` менять стадию — требует подтверждения.

---

## Открытые вопросы (сводный список)

| # | Вопрос | Story | Критичность |
|---|--------|-------|-------------|
| Q1 | Bulk-эндпоинт для домов vs. поштучное создание | US-3.1 | Средняя |
| Q2 | «Всё или ничего» vs. частичный успех при bulk | US-3.1, 3.4 | Средняя |
| Q3 | Допустимые значения `Project.status` | US-3.1 | Низкая |
| Q4 | Разрешён ли дубликат опции на одном доме | US-3.2 | Средняя |
| Q5 | `chosen_at` — клиент задаёт или сервер проставляет | US-3.2 | Средняя |
| Q6 | Разрешён ли пропуск стадий | US-3.3 | **Высокая** |
| Q7 | Может ли `owner` менять стадию | US-3.3 | Средняя |
| Q8 | Нужна ли метка в истории при смене owner-ом | US-3.3 | Низкая |
| Q9 | Upsert или insert при повторной загрузке плана | US-3.4 | **Высокая** |
| Q10 | Нужна ли версионность планового бюджета | US-3.4 | Средняя |
| Q11 | Кто может удалить/обнулить плановую строку | US-3.4 | Средняя |
| Q12 | Как реализован признак `approved` у платежа | US-3.5 | **Критическая** |
| Q13 | Валидация «сумма платежей ≤ сумма договора» | US-3.5 | Средняя |
| Q14 | Платёж к договору со статусом `completed` — разрешён? | US-3.5 | Средняя |
| Q15 | Проверка арифметики total = qty × unit_price | US-3.6 | Средняя |
| Q16 | Нужен ли `contract_id` в `MaterialPurchase` | US-3.6 | Средняя |
| Q17 | Кто является `received_by_user_id` — вносящий или принявший | US-3.6 | Низкая |

---

*Документ подготовлен business-analyst (субагент coordinata56). До получения ответов на вопросы с критичностью «Высокая» и «Критическая» (Q6, Q9, Q12) кодинг соответствующих эндпоинтов начинать не рекомендуется.*
