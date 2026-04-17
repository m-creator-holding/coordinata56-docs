# Consolidated Code Review — Phase 3 Batch C

**Ревьюер**: reviewer (субагент Quality)
**Дата**: 2026-04-16
**Диапазон коммитов**: `9bf2d95..6cd337e` (4 коммита Батча C)
**Вердикт**: `approve` с одним задокументированным расхождением (P2, non-blocker)

---

## Итоговый вердикт

**APPROVE**

Все P0/P1 пункты consolidated-проверки пройдены. Выявлено одно P2-расхождение по HTTP-статусу `HOUSE_PROJECT_MISMATCH` между двумя сущностями. Расхождение зафиксировано ниже и не блокирует коммит по критериям Батча C (per-step approve уже закрыт, тесты зелёные и закрепляют текущее поведение).

---

## Проверка по 10 пунктам

### Пункт 1 — Единообразие паттерна между 4 сущностями

Проверены: `app/{schemas,repositories,services,api}/{contractor,contract,payment,material_purchase}.py`.

**Результат: соответствует.**

Все 4 сущности следуют единому шаблону:
- Файлы присутствуют в каждой из папок.
- Хелпер `_make_service(db)` реализован в каждом роутере.
- Сигнатуры методов сервисов единообразны: `(self, data, actor_id, ip, user_agent=None)`.
- Именование методов одинаково: `list`, `get`, `create`, `update`, `delete` (+ `approve`/`reject` для Payment).
- `_<entity>_to_dict()` сериализует через Read-схему во всех 4 сервисах.

Отклонений не обнаружено.

---

### Пункт 2 — Drift от эталонов Батчей A+B

Проверены: `app/repositories/base.py`, `app/services/base.py`, `app/services/audit.py`, `app/errors.py`, `app/api/deps.py`.

**Результат: нет модификаций.**

Файлы `BaseRepository`, `BaseService`, `AuditService` не были изменены Батчем C. Код полностью совместим с Батчами A и B. Регрессий нет.

Дополнительно: тест-сюита 351/351 зелёная подтверждает отсутствие регрессий на уровне поведения.

---

### Пункт 3 — Partial UNIQUE constraints

**Результат: соответствует.**

**Contractor.inn:**
- `unique=True` убран из модели (`app/models/contract.py:27` — комментарий с явным объяснением).
- Партиальный индекс `uq_contractors_inn_active WHERE deleted_at IS NULL` создан миграцией `e1f2a3b4c5d6`.
- Простой индекс `ix_contractors_inn` восстановлен неуникальным для быстрого поиска.
- Round-trip: upgrade/downgrade описаны корректно.
- Pre-INSERT проверка в сервисе через `repo.get_by_inn()` — присутствует, фильтрует `deleted_at IS NULL`.

**Contract (contractor_id, number):**
- Партиальный индекс `uq_contracts_contractor_id_number_active WHERE deleted_at IS NULL` создан миграцией `9be2c634d3d9`.
- Явная pre-INSERT проверка через `repo.get_by_number()` — присутствует.
- `ContractRepository.get_by_number()` содержит комментарий о race-condition fallback через глобальный `SAIntegrityError` handler в `main.py` — архитектурно корректно.
- Round-trip описан в заголовке миграции.

---

### Пункт 4 — Action-endpoints `/payments/{id}/approve` и `/reject`

**Результат: соответствует ADR 0004 Amendment.**

- Эндпоинты реализованы через `POST /payments/{id}/approve` и `POST /payments/{id}/reject`.
- `PaymentUpdate.status: Literal["draft", "pending"] | None` — approve/reject через PATCH заблокированы на уровне типа.
- RBAC на action: `_ACTION_ROLES = (UserRole.OWNER,)` — только owner (`app/api/payments.py:45`).
- `approve_payment` и `reject_payment` используют `Depends(require_role(*_ACTION_ROLES))`.

---

### Пункт 5 — Audit.meta каноническая структура

**Результат: соответствует. Регрессия `old_status`/`new_status` отсутствует.**

В `app/services/payment.py`:

**Approve** (`строки 373-379`):
```python
"meta": {
    "transition": "approved",
    "from_status": before["status"],
}
```

**Reject** (`строки 437-443`):
```python
"meta": {
    "transition": "rejected",
    "from_status": before["status"],
    "reason": reason,
}
```

Структура соответствует канону `{"transition": "<new>", "from_status": "<old>"[, "reason": "..."]}`.
Ключи `old_status`/`new_status` (P2-2 из Round 1 C.3) отсутствуют — регрессия закрыта.

---

### Пункт 6 — RBAC-матрица (4 сущности × 4 роли × 5 операций)

**Результат: соответствует.**

| Операция | Contractor | Contract | MaterialPurchase | Payment |
|---|---|---|---|---|
| list | все auth | owner/acct/cm | все auth | все auth |
| read | все auth | owner/acct/cm | все auth | все auth |
| create | owner/acct | owner/acct | owner/acct/cm | owner/acct |
| update | owner/acct | owner/acct | owner/acct/cm | owner/acct |
| delete | owner/acct | owner/acct | owner/acct/cm | owner/acct |
| approve/reject | — | — | — | **owner only** |

Ключевые точки:
- Contract list/read: `read_only` **заблокирован** — `_READ_ROLES = (OWNER, ACCOUNTANT, CONSTRUCTION_MANAGER)`. Обоснование зафиксировано в docstring роутера.
- Contractor/MaterialPurchase: `read_only` разрешён через `get_current_user`.
- Payment approve/reject: `_ACTION_ROLES = (UserRole.OWNER,)` — строго только owner.

---

### Пункт 7 — IDOR-защита

**Результат: соответствует.**

- **Contract**: `_check_house_project_match()` проверяет `house.project_id == project_id`, при несовпадении — `DomainValidationError(code="HOUSE_PROJECT_MISMATCH")` → HTTP 422. Покрыто тестом `test_contracts.py:546` (ожидает 422).
- **MaterialPurchase**: `_validate_create_update()` проверяет `house.project_id == project_id`, при несовпадении — `ConflictError(code="HOUSE_PROJECT_MISMATCH")` → HTTP 409. Покрыто тестом `test_material_purchases.py:550` (ожидает 409).
- **Payment**: `get_contract_amount_and_status()` фильтрует `deleted_at IS NULL`, проверяет `contract_status in PAYABLE_CONTRACT_STATUSES` → `DomainValidationError(code="CONTRACT_NOT_PAYABLE")` → HTTP 422.

**Замечание P2**: `HOUSE_PROJECT_MISMATCH` возвращает HTTP 422 для Contract и HTTP 409 для MaterialPurchase. Это семантическая несогласованность — один error-code, два разных статуса. Технически обе ветки блокируют IDOR. Тесты закрепляют текущее поведение. Фронтенд должен обрабатывать оба варианта для одного кода. Рекомендуется унифицировать в Фазе 5: либо оба 422, либо оба 409, предпочтительно 422 (не является нарушением уникальности, является нарушением бизнес-валидации принадлежности). **Не блокирует Батч C.**

---

### Пункт 8 — Бизнес-правила

**Результат: соответствует.**

**Contract:**
- Whitelist переходов: `_ALLOWED_TRANSITIONS` (`services/contract.py:32-37`): `draft→active`, `draft→cancelled`, `active→completed`, `active→cancelled`. Терминальные статусы `completed`/`cancelled` — пустое множество.
- Запрет удаления при наличии Payment: `repo.has_payments()`.
- Проверка активности подрядчика: `_check_contractor_active()`.

**Payment:**
- Иммутабельность после approved/rejected: `_IMMUTABLE_STATUSES = {APPROVED, REJECTED}` — проверяется в `update()` и `delete()`.
- Лимит 120%: целочисленная арифметика `(approved_total + payment.amount_cents) * 100 > contract_amount * (100 + limit_pct)` — без float, корректно.
- Действие approve/reject — через отдельные эндпоинты.
- Hard delete только из DRAFT.

**MaterialPurchase:**
- `total_price_cents` = `round(quantity × unit_price_cents)` — вычисляется автоматически.
- Допустимая погрешность: ±1 копейка (`_validate_total`).
- `purchased_at` не в будущем — проверяется.

---

### Пункт 9 — Pre-existing tech-debt

**Результат: зафиксировано корректно, не блокирует.**

- **P3-NEW-1** (`seeds.py` ruff): Батч C не трогал `seeds.py`. Происхождение — Фаза 1. Не блокирует.
- **P3-NEW-2** (`conftest.py` без `alembic upgrade`): зафиксировано в `docs/pods/cottage-platform/phases/phase-3-tech-debt.md`. Не блокирует MVP.
- **P3-NEW-3** (`Payment.amount_cents` без верхнего лимита): зафиксировано. Фаза 5.

Все три пункта присутствуют в `phase-3-tech-debt.md`. Долг документирован — принимается.

---

### Пункт 10 — Регрессии Батчей A+B

**Результат: регрессий нет.**

- Кросс-срезовые компоненты (`app/core/*`, `app/errors.py`, `app/api/auth.py`, `BaseRepository`, `BaseService`) не модифицированы Батчем C.
- 351/351 тестов зелёных (включая 263 теста Батчей A+B).
- `app/main.py`: добавлены только новые роутеры (contractors, contracts, material_purchases, payments). Exception handlers, CORS, существующие роутеры — не тронуты.

---

## OWASP Top 10 — чек-лист по Батчу C

| Пункт | Статус | Детали |
|---|---|---|
| A01 Broken Access Control | Прошло | RBAC на каждом эндпоинте; IDOR-защита реализована; approve/reject только owner |
| A02 Cryptographic Failures | N/A | Криптография не затронута Батчем C |
| A03 Injection | Прошло | Только параметризованные ORM-запросы; `select` не импортируется в сервисах |
| A04 Insecure Design | Прошло | Аудит в транзакции; IDOR-проверки перед записью |
| A05 Security Misconfiguration | Прошло | Stack traces не утекают (unhandled_error_handler); IntegrityError — безопасный ответ |
| A06 Vulnerable Components | N/A | Зависимости не менялись |
| A07 Auth Failures | Прошло | require_role/get_current_user — без изменений |
| A08 Data Integrity | Прошло | Нет pickle/unsafe deserialization |
| A09 Logging | Прошло | audit_log на каждом write; secrets не утекают в changes_json (sanitize) |
| A10 SSRF | N/A | Нет исходящих HTTP-запросов |

---

## ADR-соответствие

| ADR | Требование | Статус |
|---|---|---|
| ADR 0004 | Router→Service→Repository | Соответствует |
| ADR 0004 | `_make_service` helper | Соответствует |
| ADR 0004 | SQLAlchemy только в repositories/ | Соответствует |
| ADR 0004 | Аудит в сервисном слое | Соответствует |
| ADR 0005 | Формат ошибок `{"error": {"code", "message"}}` | Соответствует |
| ADR 0005 | SAIntegrityError → 409 handler | Соответствует |
| ADR 0006 | Pagination envelope + SQL WHERE | Соответствует |
| ADR 0007 | `audit.log()` после каждого write | Соответствует |
| ADR 0007 | `changes_json` формат (before/after/meta) | Соответствует |
| ADR 0007 | Secrets не в changes_json | Соответствует (через Read-схемы + `_sanitize`) |

---

## Реестр замечаний

### P2 — Несогласованный HTTP-статус для `HOUSE_PROJECT_MISMATCH`

**Приоритет**: P2 (major, non-blocker)
**Файлы**:
- `/root/coordinata56/backend/app/services/material_purchase.py:191` — `ConflictError` → 409
- `/root/coordinata56/backend/app/services/contract.py:167` — `DomainValidationError` → 422

**Проблема**: один и тот же error-code `HOUSE_PROJECT_MISMATCH` возвращает HTTP 409 для MaterialPurchase и HTTP 422 для Contract. Фронтенд обязан обрабатывать оба варианта для одного кода, что нарушает принцип единообразия ADR 0005. Семантически это ошибка бизнес-валидации принадлежности (не нарушение уникальности), поэтому правильный статус — 422.

**Рекомендация**: в Фазе 5 заменить `ConflictError` на `DomainValidationError` в `material_purchase.py` (унифицировать под 422). Одновременно обновить тест `test_material_purchases.py:596` с `assert resp.status_code == 409` на 422.

**Не блокирует**: IDOR-защита функционирует на обоих путях; тесты прошли; per-step approve уже выдан.

---

## Итог

Все 10 пунктов consolidated-проверки пройдены. Единственное замечание — P2 по HTTP-статусу — является задокументированным техдолгом, не нарушением безопасности. Тесты зелёные (351/351). ADR 0004/0005/0006/0007 соблюдены. Батч C готов к коммиту в main.
