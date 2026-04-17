# Ревью: Фаза 3, Батч C, Шаг C.3 — Payment CRUD + approve/reject

- **Дата**: 2026-04-16
- **Ревьюер**: `reviewer` (субагент)
- **Коммит-кандидат**: staged (7 файлов)
- **Эталон стиля**: Шаг C.2 Contract (`3e279ea`)
- **Раундов ревью backend-head**: 3 (P1 на PAYMENT_OVERRUN_LIMIT_PCT, P2 на динамическое сообщение)
- **Вердикт backend-director**: approve-to-commit

---

## Summary

Код технически качественный: слои соблюдены, бизнес-правила реализованы верно, OWASP-нарушений нет. Обнаружено 2 `major` и 2 `minor` замечания, не выявленных в предыдущих раундах. Основная проблема — формат audit meta расходился со спецификацией (незаявленное отклонение), и DoD reject-сценарии были не полностью покрыты тестами.

---

## Файлы

| Файл | Статус | Тип изменения |
|---|---|---|
| `backend/app/api/payments.py` | A | Новый роутер (7 эндпоинтов) |
| `backend/app/core/config.py` | M | Добавлено `payment_overrun_limit_pct` |
| `backend/app/main.py` | M | `import + include_router` (2 строки) |
| `backend/app/repositories/payment.py` | A | Новый репозиторий |
| `backend/app/schemas/payment.py` | A | Новые схемы |
| `backend/app/services/payment.py` | A | Новый сервис |
| `backend/tests/test_payments.py` | A | 27 тестов |

---

## Критерии и результаты (Round 1)

| Критерий | Результат | Примечание |
|---|---|---|
| Scope: ровно 7 файлов, лишнего нет | PASS | `git status --short` чист по staged |
| ADR 0004: SQL только в repositories/ | PASS | Сервис не импортирует `select`, `session.execute` |
| ADR 0004: сервис не знает про FastAPI | PASS | Нет `Request`, `Response`, `status` в services/payment.py |
| ADR 0004: роутер только HTTP-слой | PASS | Бизнес-логика отсутствует в api/payments.py |
| ADR 0004: `_make_service` helper | PASS | Соответствует Amendment 2026-04-15 |
| ADR 0005: формат ошибок | PASS | Все ответы через `error.code`, нет `{"detail":...}` |
| ADR 0005: Swagger responses декларирует 409 для CONTRACT_NOT_PAYABLE | FAIL→FIXED | Исправлено в Round 2: 409 убран, 422 обновлён |
| ADR 0006: envelope (items/total/offset/limit) | PASS | ListEnvelope присутствует |
| ADR 0006: фильтры в SQL, не Python post-filter | PASS | `extra_conditions` в `list_paginated` |
| ADR 0006: limit клиппируется | PASS | Через Pydantic `le=200` в PaginationParams |
| ADR 0007: audit.log() на всех write-операциях | PASS | create, update, delete, approve, reject |
| ADR 0007: в той же транзакции, до `db.commit()` | PASS | `session.flush()` в AuditService, commit в роутере |
| ADR 0007: формат meta в audit | FAIL→FIXED | Исправлено в Round 2: `transition`/`from_status`/`reason` |
| Бизнес-правило: CONTRACT_NOT_PAYABLE → 422 | PASS | `DomainValidationError(code="CONTRACT_NOT_PAYABLE")` |
| Бизнес-правило: PAYMENT_IMMUTABLE (PATCH/DELETE) | PASS | Проверка в сервисе корректна |
| Бизнес-правило: INVALID_STATUS_TRANSITION | PASS | approve/reject из approved|rejected → 409 |
| Бизнес-правило: PAYMENT_EXCEEDS_CONTRACT | PASS | Целочисленная арифметика, порог из конфига |
| Динамическое сообщение ошибки | PASS | `f"...лимит {100 + limit_pct}%..."` |
| PaymentUpdate.status: Literal["draft","pending"] | PASS | approve/reject через PATCH запрещены типом |
| RBAC: approve/reject строго OWNER | PASS | `_ACTION_ROLES = (UserRole.OWNER,)` |
| RBAC: write — owner+accountant | PASS | `_WRITE_ROLES` корректен |
| RBAC: read — все роли | PASS | `_READ_ROLES` включает READ_ONLY |
| Нет `print()` / pdb в staged-файлах | PASS | |
| Нет `# type: ignore` / `# noqa` | PASS | |
| Нет импортов внутри функций | FAIL→FIXED | Исправлено в Round 2: `from datetime import datetime` перенесён на строку 16 |
| Пароли через `secrets.token_urlsafe` | PASS | Фикстура `_make_user` использует `secrets.token_urlsafe(16)` |
| Нет литеральных секретов | PASS | |
| SQL-инъекции: параметризация | PASS | Только ORM-конструкции |
| IDOR: нет вложенных ресурсов без проверки принадлежности | PASS | Payment не вложенный ресурс |
| Swagger: summary/description/response_model/responses | PASS | Все 7 эндпоинтов задокументированы |
| Action endpoints: POST /approve, POST /reject | PASS | Не PATCH status |
| Граничный тест 120% (≤ разрешён, > отклонён) | PASS | `test_approve_within_120_percent_ok` и `test_approve_exceeds_contract_limit_409` |
| `test_approve_creates_audit_log` | PASS | Проверяет audit-запись, user_id, meta |
| Тесты: reject happy path из pending | FAIL→FIXED | `test_reject_pending_payment_ok` добавлен в Round 2 |
| Тесты: reject из approved → 409 | FAIL→FIXED | `test_reject_approved_payment_409` добавлен в Round 2 |
| Тесты: reject из rejected → 409 | FAIL→FIXED | `test_reject_already_rejected_409` добавлен в Round 2 |
| Тесты: DELETE из approved → 409 | MINOR→FIXED | `test_delete_approved_payment_409` добавлен в Round 2 |

---

## Замечания Round 1

### P2-1 (major) — Неверный HTTP-код в Swagger-документации для CONTRACT_NOT_PAYABLE

**Файл**: `backend/app/api/payments.py`, строка 177
**Описание**: В `responses` POST `/payments/` задекларирован `409` для `CONTRACT_NOT_PAYABLE`. Фактически `DomainValidationError` возвращает HTTP `422`. Swagger показывает неверный статус — потребитель API (фронтенд, интеграция) будет ловить `409`, а приходит `422`.
**Ожидается**: заменить `409` на `422` в `responses`, убрать из `409: {"description": "Договор в недопустимом статусе (CONTRACT_NOT_PAYABLE)"}` и добавить в `422`.

---

### P2-2 (major) — Формат audit meta расходился со спецификацией (незаявленное отклонение ADR)

**Файл**: `backend/app/services/payment.py`, строки 373-378 (approve) и 429-445 (reject)
**Описание**: Спецификация §C.3 (строки 435, 440) определяет формат:
```
approve audit meta: {"transition": "approved", "from_status": "<old>"}
reject  audit meta: {"transition": "rejected", "from_status": "<old>", "reason": "..."}
```
Реализация использовала:
```python
"meta": {"old_status": before["status"], "new_status": after["status"]}
```
Ключи `"transition"` и `"from_status"` отсутствовали. Тест `test_approve_creates_audit_log` проверял несоответствующий формат (`"new_status"`), что маскировало расхождение.

---

### P3-1 (major) — Отсутствовали тесты reject из pending и из терминальных статусов

**Файл**: `backend/tests/test_payments.py`
**Описание**: DoD §C.3 (строка 193): «Reject: аналогично [approve]». Approve покрывает: happy(draft), happy(pending), 409(approved), 409(rejected). Reject покрывал только: happy(draft), 422(короткий reason). Три сценария отсутствовали.

---

### P4-1 (minor) — Импорт `datetime` внутри тела функции

**Файл**: `backend/app/api/payments.py`, строка 100 (до исправления)
**Описание**: `from datetime import datetime` выполнялся при каждом вызове `list_payments`. Нарушение правила CLAUDE.md «Импорты в верхней части файла, не внутри функций».

---

### P4-2 (minor) — Тест DELETE покрывал pending вместо approved/rejected

**Файл**: `backend/tests/test_payments.py`, строки 526-553
**Описание**: `test_delete_non_draft_payment_409` тестировал DELETE из `pending`. DoD (строка 427) перечислял: «DELETE /payments/{id} при status in (approved, rejected) → 409 PAYMENT_IMMUTABLE». Требовался тест с `approved`.

---

## Round 2 — после исправлений (2026-04-16)

### Проверка каждого пункта

**P2-1** — `backend/app/api/payments.py` строки 173–182.
Ключ `409` удалён из `responses`. Блок `422` содержит объединённое описание: валидационные ошибки и `CONTRACT_NOT_PAYABLE`. Соответствует фактическому HTTP-коду. PASS.

**P2-2** — `backend/app/services/payment.py` строки 370–380 (approve) и 429–445 (reject).
Approve meta: `{"transition": "approved", "from_status": before["status"]}` — точное соответствие спецификации §C.3.
Reject meta: `{"transition": "rejected", "from_status": before["status"], "reason": reason}` — точное соответствие спецификации §C.3.
Тест `test_approve_creates_audit_log` проверяет `log.changes_json["meta"]["transition"] == "approved"` и `log.changes_json["meta"]["from_status"] == PaymentStatus.DRAFT.value`. PASS.

**P3-1** — три новых теста подтверждены:
- `test_reject_pending_payment_ok` (строка 736): draft → pending (PATCH) → reject; проверяет status, rejected_at, rejected_by_user_id, rejection_reason. PASS.
- `test_reject_already_rejected_409` (строка 772): reject → reject; проверяет 409 + `INVALID_STATUS_TRANSITION`. PASS.
- `test_reject_approved_payment_409` (строка 803): approve → reject; проверяет 409 + `INVALID_STATUS_TRANSITION`. PASS.

**P4-1** — `from datetime import datetime` на строке 16 файла `backend/app/api/payments.py`. Импорт на уровне модуля. PASS.

**P4-2** — `test_delete_approved_payment_409` (строка 557): draft → approve → DELETE; проверяет 409 + `PAYMENT_IMMUTABLE`. PASS.

### Итоговая сводка по suite

Координатор подтвердил прогон: 27 passed (было 23 + 4 новых), ruff clean, полный suite 351 passed.

### Новых замечаний не выявлено

Повторный просмотр всех исправленных мест не выявил регрессий или побочных эффектов:
- `test_reject_pending_payment_ok` корректно передаёт заголовок авторизации в промежуточном PATCH.
- Reject-сценарии проверяют и поле `error.code`, соответствуя ADR 0005.
- Формат meta в audit не содержит лишних ключей (`new_status` удалён), что снижает вероятность ошибочных ожиданий у будущих потребителей.

---

## Вердикт

**APPROVE**

Все 5 замечаний Round 1 (P2-1, P2-2, P3-1, P4-1, P4-2) устранены. Код соответствует ADR 0004, 0005, 0006, 0007, спецификации §C.3 и DoD Батча C. Тестовое покрытие полное по заявленным сценариям. Разрешено к коммиту.
