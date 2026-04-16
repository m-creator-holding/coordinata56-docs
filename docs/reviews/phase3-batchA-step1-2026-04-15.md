# Ревью: Фаза 3 Batch A Шаг 1 — PaymentStatus enum + миграция

**Дата**: 2026-04-15  
**Ревьюер**: reviewer (субагент)  
**Файлы**: `backend/app/models/enums.py`, `backend/app/models/contract.py`, `backend/alembic/versions/2026_04_15_1016_48b652e20e99_payment_status_enum.py`  
**ADR-контекст**: phase-3-decisions.md Q12  
**Вердикт**: REQUEST-CHANGES

---

## Замечания

### [BLOCKER] Несоответствие значений Enum в миграции и модели

**Файл**: `backend/alembic/versions/2026_04_15_1016_48b652e20e99_payment_status_enum.py`, строка 23  
**Проблема**: В миграции перечислены имена (`'DRAFT', 'PENDING', 'APPROVED', 'REJECTED'`), тогда как модель использует `native_enum=False`, и в БД хранятся **значения** (`'draft', 'pending', 'approved', 'rejected'`). Сравните с прецедентом: `payment_method` в той же таблице в initial_schema.py строка 262 — там тоже `'BANK_TRANSFER', 'CASH', 'CARD', 'OTHER'` (UPPER_CASE), что соответствует именам enum-членов.

Конкретный конфликт:
- `server_default='draft'` в миграции — строка `'draft'` (lower-case).
- CHECK-constraint, создаваемый SQLAlchemy для `native_enum=False`, будет проверять допустимые значения по списку, переданному в `sa.Enum(...)` при создании колонки — а там `'DRAFT'`, `'PENDING'` и т.д.
- Результат: `server_default='draft'` **не пройдёт** CHECK-constraint при INSERT без явно указанного значения из Python-кода; при использовании raw SQL или при seed-скриптах получим нарушение CHECK и ошибку PostgreSQL.

Это критический функциональный дефект: при `nullable=False` и неверном `server_default` любая вставка строки без явного `status` упадёт на уровне БД.

**Требуемое действие**: привести значения в `sa.Enum(...)` в миграции в соответствие с тем, что реально хранит SQLAlchemy при `native_enum=False`. Модель `PaymentStatus` использует `.value` = `'draft'` и т.д. — значит в миграции должно быть `'draft', 'pending', 'approved', 'rejected'`, а `server_default='draft'` тогда корректен. **Либо** наоборот — значения в `sa.Enum` оставить `'DRAFT'...`, но тогда исправить `server_default='DRAFT'` и привести значения самого Enum к upper-case.

Единственный консистентный вариант для проекта — lower-case values (как во всех других enum'ах: `ContractStatus`, `UserRole` и пр.) — то есть миграция должна содержать `'draft', 'pending', 'approved', 'rejected'`.

---

### [MAJOR] Несоответствие паттерну: `Contract.status` не имеет `server_default` в модели

**Файл**: `backend/app/models/contract.py`, строка 63–67  
**Проблема**: `Contract.status` задаёт только `default=ContractStatus.DRAFT` (Python-side), но не `server_default`. `Payment.status` напротив имеет оба. Это не часть текущего diff'а, но следует из добавленного кода — заявленный паттерн «оба default» введён здесь впервые, и его стоит либо закрепить как обязательный в ADR, либо убрать `server_default` из Payment (если паттерн пока не принят). Оставить вполовину — источник путаницы.  
**Требуемое действие**: зафиксировать решение в ADR; либо добавить `server_default` к `Contract.status`, либо явно задокументировать, что `Payment` — особый случай (иммутабельность требует гарантии на уровне БД).

---

### [MINOR] Отсутствует `server_default` в initial_schema для `contracts.status`

**Файл**: `backend/alembic/versions/2026_04_11_1911_f80b758cadef_initial_schema.py`, строка 185  
**Проблема**: `contracts.status` создаётся без `server_default`. Если строка вставляется через raw SQL — поле не имеет дефолта. Не входит в текущий diff, но взаимосвязано с решением по п.2 выше.

---

### [MINOR] downgrade не чистит именованный тип (если бы использовался native_enum)

**Файл**: `backend/alembic/versions/2026_04_15_1016_48b652e20e99_payment_status_enum.py`, строка 28  
**Замечание**: при `native_enum=False` PostgreSQL не создаёт отдельный TYPE, поэтому `op.drop_column` достаточно — это корректно. Замечание информационное, не требует правки.

---

## Чек-лист

| Пункт | Результат |
|---|---|
| Стиль PaymentStatus — UPPER_CASE имена, lower-case values | PASS |
| NOT NULL + default draft | PASS (модель) |
| native_enum=False, length=32 — консистентно с соседями | PASS |
| Enum-значения в миграции совпадают с .value модели | **FAIL** — см. BLOCKER |
| server_default зафиксирован строкой | PASS (строка, не выражение) |
| upgrade/downgrade симметричны | PASS (add_column / drop_column) |
| Не ломает существующие строки | PASS (add_column с server_default) |
| Секреты, токены, хардкоды | PASS — не обнаружены |
| Файлы за рамками scope | PASS — только заявленные 3 файла |
| OWASP A03 Injection | PASS — нет f-string SQL |
| OWASP A05 Misconfiguration | PASS |

---

## Итог

Один BLOCKER препятствует commit'у: несоответствие регистра значений в `sa.Enum(...)` миграции приведёт к нарушению CHECK-constraint при вставке строк без Python-ORM (seeds, raw SQL, тесты через psycopg2). После устранения BLOCKER'а и принятия решения по MAJOR п.2 — approve.

---

## Round 2 — 2026-04-15

**Ревьюер**: reviewer (субагент)  
**Основание**: фикс db-engineer после Round 1 REQUEST-CHANGES

### Статус BLOCKER из Round 1

**ЗАКРЫТ.**

Строка 23 миграции после фикса:

```python
op.add_column('payments', sa.Column('status', sa.Enum('draft', 'pending', 'approved', 'rejected', name='payment_status', native_enum=False, length=32), server_default='draft', nullable=False))
```

`sa.Enum(...)` теперь содержит `'draft', 'pending', 'approved', 'rejected'` — совпадает с `.value` модели `PaymentStatus` (строка 59–62 `enums.py`). `server_default='draft'` консистентен с CHECK-constraint. Конфликт регистра устранён.

### Проверка регрессий

| Проверка | Результат |
|---|---|
| `sa.Enum` значения = `.value` модели | PASS — `'draft'`, `'pending'`, `'approved'`, `'rejected'` |
| `server_default='draft'` попадает в множество допустимых значений | PASS |
| `native_enum=False, length=32` — не изменено | PASS |
| `name='payment_status'` — не изменено | PASS |
| `downgrade` — `op.drop_column` — не изменено, симметрия сохранена | PASS |
| `Payment.status` в модели: `default=PaymentStatus.DRAFT`, `server_default=PaymentStatus.DRAFT.value` → `'draft'` | PASS — оба значения консистентны |
| Новых файлов в diff не появилось | PASS |
| Секреты/хардкоды | PASS — не обнаружены |

### Статус замечаний Round 1

| Замечание | Приоритет | Статус |
|---|---|---|
| Несоответствие регистра в `sa.Enum(...)` | BLOCKER | ЗАКРЫТ |
| `Contract.status` без `server_default` vs `Payment.status` с `server_default` | MAJOR | Открыт — решение не зафиксировано в ADR |
| `contracts.status` без `server_default` в initial_schema | MINOR | Открыт — за рамками текущего diff |
| `downgrade` и native_enum | MINOR (info) | Закрыт — не требовал правки |

### Оценка незакрытого MAJOR

MAJOR из Round 1 (паттерн `server_default` у `Contract.status` vs `Payment.status`) остаётся открытым. Однако он не является блокером для данного коммита по следующей причине: текущий diff добавляет только колонку `payments.status` — и она корректна. `Contract.status` не входит в staged изменения. MAJOR требует отдельного тикета и решения в ADR, но не должен блокировать этот конкретный коммит.

### Новых дефектов не обнаружено.

### Вердикт Round 2: APPROVE

**Резюме (≤60 слов):** BLOCKER устранён: `sa.Enum(...)` приведён к lower-case values — совпадает с `.value` модели и `server_default`. Миграция корректна, round-trip чист. MAJOR по паттерну `server_default` у `Contract.status` остаётся открытым, но не блокирует данный коммит — требует отдельного тикета. Коммит разрешён.
