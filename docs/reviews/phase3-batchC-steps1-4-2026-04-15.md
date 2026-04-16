# Ревью Phase 3 Batch C (Steps C.1 + C.4) — 2026-04-15

**Вердикт: `request-changes`**

**P0:** 0 | **P1:** 3 | **P2:** 2 | **P3:** 2

---

## Резюме

Архитектура строго соблюдена: трёхслойка чистая, SQLAlchemy только в репозиториях, бизнес-логика в сервисах, роутеры не знают про ORM. Формат ошибок ADR 0005 везде. Пагинация ADR 0006 корректная — фильтры в SQL WHERE, total считается тем же WHERE. Аудит ADR 0007 присутствует на всех write-операциях в одной транзакции. Секретов в тестах нет — `secrets.token_urlsafe(16)` корректно. Три P1 требуют правки до коммита: `assert` в production-коде Pydantic-валидатора, отсутствие теста IDOR (house/project mismatch), и некорректный docstring в сервисе MP.

---

## Замечания

### P1 — BLOCKER (требуют правки до merge)

---

#### P1-1 | `backend/app/schemas/contractor.py:77` — `assert` в Pydantic field_validator

**Файл:** `backend/app/schemas/contractor.py`, строка 77.

```python
@field_validator("inn")
@classmethod
def validate_inn(cls, v: str) -> str:
    result = _validate_inn(v)
    assert result is not None   # <--- ПРОБЛЕМА
    return result
```

**Почему плохо:** `assert` убивается Python-интерпретатором при запуске с флагом `-O` (optimize, стандартный для production-образов). В результате валидатор молча пропускает `None`, а контракт типа нарушается — `str` вернётся как `None`. Это не гипотетический риск: Docker-образы на основе python:3.12-slim часто собирают с `-O` для уменьшения footprint.

`_validate_inn` с типом `str` (не `str | None`) никогда не вернёт `None` — `assert` избыточен. Исправление: удалить строку с `assert`, вернуть `result` напрямую (или добавить явную проверку через `if result is None: raise ValueError(...)`).

**OWASP A03** — некорректная обработка входных данных.

---

#### P1-2 | `backend/tests/test_material_purchases.py` — нет теста IDOR (HOUSE_PROJECT_MISMATCH)

**Файл:** `backend/tests/test_material_purchases.py`.

Задача ревью явно требовала проверки `house.project_id == project_id`. В сервисе логика реализована правильно (`services/material_purchase.py:188–194`). Однако тест, проверяющий 409 `HOUSE_PROJECT_MISMATCH` при передаче `house_id` из чужого проекта, отсутствует.

**Почему плохо:** Без теста IDOR-защита не верифицирована и может быть случайно сломана при рефакторинге `_validate_create_update`. Поймано в Batch A step 4 как P1 — антипаттерн уже зафиксирован в CLAUDE.md.

**Требуется:** добавить тест `test_create_mp_house_project_mismatch_409` — создать два проекта, один дом, передать `house_id` дома из проекта 1 при `project_id=2`, ожидать 409 `HOUSE_PROJECT_MISMATCH`.

**OWASP A01** — Broken Access Control (IDOR).

---

#### P1-3 | `backend/app/services/material_purchase.py:223–224` — неверный docstring

**Файл:** `backend/app/services/material_purchase.py`, строки 222–224.

```python
Raises:
    ConflictError: несовпадение total_price, HOUSE_PROJECT_MISMATCH.
    ConflictError: purchased_at в будущем (PURCHASED_AT_FUTURE).  # НЕВЕРНО
```

Фактически `PURCHASED_AT_FUTURE` бросается через `DomainValidationError` (строка 183), что даёт HTTP 422, а не 409 ConflictError. Docstring вводит в заблуждение следующего разработчика относительно HTTP-статуса ошибки — он может написать тест на 409 и не понять, почему тест зелёный при ошибке.

Аналогичная (но менее критичная) неточность в `_validate_create_update`:
```
Returns:
    total_price_cents: итоговая цена ..., либо None.
Raises:
    ConflictError: несовпадение total_price_cents или несовпадение house/project.
    ValidationError: purchased_at в будущем.  # тип "ValidationError" нет в проекте
```

**Требуется:** исправить `ConflictError: purchased_at в будущем` → `DomainValidationError: purchased_at в будущем (PURCHASED_AT_FUTURE, HTTP 422)`.

---

### P2 — Major (желательно исправить до merge, не блокеры)

---

#### P2-1 | `backend/app/models/contract.py:24` — уникальный индекс ИНН не учитывает soft-delete

**Файл:** `backend/app/models/contract.py`, строка 24.

```python
inn: Mapped[str] = mapped_column(String(12), unique=True, nullable=False, index=True)
```

Ограничение `unique=True` — глобальное, без учёта `deleted_at`. Сценарий: подрядчик мягко удалён (`deleted_at IS NOT NULL`), создаётся новый с тем же ИНН — `IntegrityError` от PostgreSQL. Сервис `contractor.py` проверяет дубль только среди не-удалённых (`get_by_inn` фильтрует `deleted_at.is_(None)`), но уникальный индекс сработает на уровне БД.

**Почему P2, не P1:** обработчик `SAIntegrityError` в `main.py` перехватит и вернёт 409 CONFLICT с безопасным сообщением. Данные не утекут, но сообщение будет непрозрачным для клиента (нет кода `CONTRACTOR_INN_DUPLICATE`).

**Рекомендация:** заменить `unique=True` на частичный уникальный индекс PostgreSQL в миграции: `CREATE UNIQUE INDEX uq_contractors_inn_active ON contractors (inn) WHERE deleted_at IS NULL`. Это изменение модели и миграции — выходит за скоуп staged файлов, поэтому P2.

---

#### P2-2 | `backend/app/schemas/material_purchase.py` — `purchased_at` не валидируется в схеме

**Файл:** `backend/app/schemas/material_purchase.py`.

`MaterialPurchaseCreate.purchased_at` — поле типа `datetime`, валидация «не в будущем» сделана в сервисном методе `_validate_create_update`. Это архитектурно правильно по ADR 0004 (бизнес-правила — в сервисе), но класс `DomainValidationError` бросается из сервиса, а код в `_validate_create_update` возвращает `int | None` — это смешение «вычисления total» и «валидации дат» в одном методе.

**Конкретный риск:** если метод `_validate_create_update` вызывается из `update` без `purchased_at` (строка 301: `purchased_at=new_purchased_at` где `new_purchased_at` может быть `None`), проверка даты пропускается. Это корректно намеренно, но не документировано — разработчик может не понять, почему для update можно не передавать `purchased_at`.

**Рекомендация:** добавить комментарий на строке 301 в update-ветке с явным указанием: «purchased_at не обновляется — дата не проверяется».

---

### P3 — Minor / Nit

---

#### P3-1 | `backend/app/schemas/contractor.py` — `ContractorUpdate` не блокирует изменение ИНН, но это не документировано в API

**Файл:** `backend/app/schemas/contractor.py`, класс `ContractorUpdate`.

`inn` не входит в `ContractorUpdate` — правильное бизнес-решение (ИНН нельзя менять после создания). Однако в Swagger для `PATCH /contractors/{id}` нигде не сказано, что ИНН иммутабелен и что передача `inn` в теле игнорируется. Если фронтенд попробует передать `inn` — поле молча проигнорируется (Pydantic просто не увидит его).

**Рекомендация:** добавить в description эндпоинта или в docstring схемы явную фразу: «ИНН изменить нельзя — он фиксируется при создании».

---

#### P3-2 | `backend/tests/test_contractors.py:233` — ИНН `"770708389301"` (12 цифр) является корректным ИП-ИНН по формату, но тест неявно использует его как «12-цифровой ИНН ИП»

**Файл:** `backend/tests/test_contractors.py`, строка 234.

Незначительно: тесты используют реальные форматы ИНН (7707083893 — фактически ИНН Сбербанка). Это не секрет и не PII, но при code-review может смутить. Рекомендуется использовать заведомо несуществующие ИНН вроде `0000000001` для 10-значных и `000000000001` для 12-значных — или взять из официального набора тест-данных ФНС.

Не блокер, просто гигиена.

---

## Чек-лист ADR

| ADR | Требование | Статус |
|---|---|---|
| 0004 | SQL только в repositories/ | PASS |
| 0004 | Router не знает про SQLAlchemy | PASS |
| 0004 | Service не знает про FastAPI | PASS |
| 0004 | Ошибки через собственные исключения (NotFoundError / ConflictError) | PASS |
| 0004 | `audit_service.log()` в сервисном слое | PASS |
| 0004 | `_make_service()` helper (Amendment) | PASS |
| 0005 | Формат `{"error":{"code","message","details"}}` | PASS |
| 0005 | Exception handlers зарегистрированы в main.py | PASS |
| 0005 | 5xx не раскрывают traceback/SQL | PASS |
| 0006 | Envelope `{items, total, offset, limit}` | PASS |
| 0006 | limit клиппируется к 200 (в PaginationParams через BaseModel) | PASS |
| 0006 | Фильтры в SQL WHERE, не постобработка | PASS |
| 0006 | COUNT() с теми же WHERE-условиями | PASS |
| 0007 | audit.log() на create/update/delete | PASS |
| 0007 | Аудит в той же транзакции (flush, не commit) | PASS |
| 0007 | changes_json через Read-схему (без секретных полей) | PASS |
| Contractor RBAC | owner+accountant на write | PASS |
| Contractor RBAC | все аутентифицированные на read | PASS |
| Contractor | ИНН/КПП Pydantic validator | PASS |
| Contractor | 409 CONTRACTOR_HAS_CONTRACTS на delete | PASS |
| Contractor | soft-delete семантика | PASS |
| MaterialPurchase RBAC | owner+accountant+construction_manager на write | PASS |
| MaterialPurchase | hard delete (нет SoftDeleteMixin) | PASS |
| MaterialPurchase | total_price_cents автовычисление/валидация | PASS |
| MaterialPurchase | purchased_at в будущем → 422 | PASS |
| MaterialPurchase | IDOR: house.project_id == project_id в сервисе | PASS |
| MaterialPurchase | IDOR: тест покрывает HOUSE_PROJECT_MISMATCH | FAIL → P1-2 |
| Secrets в тестах | secrets.token_urlsafe(16), не литералы | PASS |
| Swagger | summary, description, responses | PASS |

---

## OWASP Top 10 Snapshot

| Пункт | Статус | Примечание |
|---|---|---|
| A01 Broken Access Control | PARTIAL | IDOR-защита в коде есть, тест отсутствует → P1-2 |
| A02 Cryptographic Failures | PASS | Пароли через bcrypt, нет секретов в коде |
| A03 Injection | PASS | Параметризованные запросы через SQLAlchemy ORM |
| A04 Insecure Design | PASS | Аудит, RBAC, rate-limit вне скоупа ревью |
| A05 Security Misconfiguration | PASS | Stack traces не уходят клиенту (unhandled_error_handler) |
| A07 Auth Failures | PASS | require_role через Depends |
| A09 Logging | PASS | IntegrityError логируется, секреты не в логах |

---

## Что хорошо (не требует правок)

- Чёткое разделение слоёв — ни одного `select()` вне `repositories/`.
- `_compute_total` / `_validate_total` корректно используют `Decimal` для точности дробных значений.
- Аудит для hard-delete записывается **до** физического удаления — snapshot `before` не потеряется.
- `CORS allow_credentials=True` с непустым `allow_origins` только в dev — правильно.
- `secrets.token_urlsafe(16)` во всех фикстурах обоих тестовых файлов — антипаттерн из Batch A не повторяется.
- `DomainValidationError` vs `ConflictError` семантически корректно разделены по HTTP-кодам (422 vs 409).

---

---

## Round 2 — Re-review 2026-04-15

**Вердикт Round 2: `approve`**

**P0:** 0 | **P1:** 0 | **P2:** 0 | **P3:** 0

### Статус закрытия замечаний Round 1

#### P1-1 — CLOSED

Файл: `/root/coordinata56/backend/app/schemas/contractor.py`, строки 75–81.

`assert result is not None` заменён на явную проверку:

```python
if result is None:
    raise ValueError("ИНН не может быть пустым")
return result
```

Комментарий на строке 78 поясняет причину явной проверки (`Python -O вырезает assert`). Исправление корректно. Сканирование всех файлов `backend/app/schemas/` через grep подтвердило: других `assert` в Pydantic-валидаторах нет — единственное вхождение слова `assert` в схемах является частью этого же комментария, не инструкцией.

#### P1-2 — CLOSED

Файл: `/root/coordinata56/backend/tests/test_material_purchases.py`, строки 544–597.

Тест `test_create_mp_house_project_mismatch_409` добавлен. Сценарий корректный:
- Создаются два проекта (`project_a`, `project_b`) и дом в `project_a`.
- POST на `/api/v1/material-purchases/` с `project_id=project_b.id` и `house_id=house_in_a.id`.
- Ожидается 409 с `error.code == "HOUSE_PROJECT_MISMATCH"`.

Тест проверяет именно бизнес-ветку в `_validate_create_update` строки 188–194, которая защищает от IDOR. Фикстуры используют `db_session` с откатом транзакции — изоляция обеспечена. OWASP A01 закрыт.

#### P1-3 — CLOSED

Файл: `/root/coordinata56/backend/app/services/material_purchase.py`.

Docstring метода `create` (строки 222–224) исправлен: `ConflictError: purchased_at в будущем` заменён на `DomainValidationError: purchased_at в будущем (PURCHASED_AT_FUTURE, HTTP 422)`. Docstring метода `_validate_create_update` (строка 174) также корректен: `DomainValidationError: purchased_at в будущем (PURCHASED_AT_FUTURE, HTTP 422)`. Введения в заблуждение нет.

#### P2-1 — CLOSED

Миграция: `/root/coordinata56/backend/alembic/versions/2026_04_15_1500_e1f2a3b4c5d6_contractor_inn_partial_unique.py`.

Проверены три критерия:

1. **`down_revision` корректен.** Значение `'d1e2f3a4b5c6'` — ссылка на предыдущую миграцию `payment_approve_reject_audit`. Файл `2026_04_15_1400_d1e2f3a4b5c6_payment_approve_reject_audit.py` существует. Цепочка ревизий непрерывна.

2. **Партиальный UNIQUE работает правильно.** `upgrade()`:
   - Сначала снимает глобальный `ix_contractors_inn` (уникальный).
   - Создаёт `uq_contractors_inn_active` с `unique=True` и `postgresql_where=sa.text('deleted_at IS NULL')` — партиальный индекс только по активным записям.
   - Восстанавливает `ix_contractors_inn` как обычный (неуникальный) для быстрого поиска.

3. **Round-trip чистый.** `downgrade()`:
   - Удаляет `ix_contractors_inn` (неуникальный).
   - Удаляет `uq_contractors_inn_active`.
   - Пересоздаёт `ix_contractors_inn` как `unique=True`.
   Порядок drop/create зеркален upgrade — конфликтов имён нет.

Сервис `contractor.py` проверяет дубль только среди активных через `get_by_inn` (фильтр `deleted_at.is_(None)`) — теперь это соответствует поведению индекса. Мягко удалённый подрядчик с тем же ИНН больше не блокирует создание нового.

#### P2-2 — CLOSED

Файл: `/root/coordinata56/backend/app/services/material_purchase.py`, строки 300–302.

Комментарий добавлен в ветку `elif "house_id" in update_data or "purchased_at" in update_data`:

```python
# purchased_at проверяется только если явно передан в update_data;
# если не передан — new_purchased_at=None и проверка даты намеренно пропускается
```

Намерение задокументировано. P2-2 закрыт.

#### P3-1 — CLOSED

Файл: `/root/coordinata56/backend/app/schemas/contractor.py`, строки 89–94.

Docstring класса `ContractorUpdate` дополнен явным указанием на иммутабельность ИНН и поведение Pydantic при передаче поля `inn` в теле запроса.

#### P3-2 — CLOSED

Файл: `/root/coordinata56/backend/tests/test_contractors.py`.

Реальные ИНН заменены на тестовые заглушки вида `0000000001`–`0000000009` (10-значные) и `000000000101`–`000000000901` (12-значные). Grep по файлу тестов подтвердил: ни одного ИНН, совпадающего с реальными юрлицами, не осталось.

### Новых дефектов не обнаружено

Проверены при re-review:
- Схемы `schemas/contractor.py`, `schemas/material_purchase.py` — без регрессий.
- Сервис `services/material_purchase.py` — без регрессий, комментарий добавлен в нужную ветку.
- Миграция `e1f2a3b4c5d6` — технически корректна, round-trip чистый.
- Тест `test_create_mp_house_project_mismatch_409` — корректен, изоляция через транзакцию обеспечена, секреты не введены.

### Резюме Round 2

Все 3 блокера (P1) и 2 мажорных замечания (P2) закрыты полностью. Тест IDOR добавлен корректно — охватывает именно бизнес-ветку защиты от подмены `house_id`. Миграция `e1f2a3b4c5d6` технически выверена: `down_revision=d1e2f3a4b5c6` верный, партиальный UNIQUE `WHERE deleted_at IS NULL` создан правильно, downgrade зеркален. Оба P3 закрыты: docstring ContractorUpdate дополнен, тестовые ИНН заменены на заглушки. Новых дефектов не внесено. Код готов к коммиту.
