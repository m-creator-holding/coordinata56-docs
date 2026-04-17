# Ревью Phase 3 Batch C Step C.2 (Contract CRUD) — 2026-04-16

**Вердикт: `request-changes`**

**P0:** 0 | **P1:** 2 | **P2:** 2 | **P3:** 1

---

## Резюме

Архитектура в целом качественная: формат ошибок ADR 0005 соблюдён, пагинация ADR 0006 реализована корректно (фильтры в SQL WHERE, total через тот же WHERE без постобработки), аудит ADR 0007 есть на всех трёх write-операциях (create/update/delete) в одной транзакции. Секретов в тестах нет. Whitelist переходов `_ALLOWED_TRANSITIONS` реализован правильно — COMPLETED и CANCELLED — терминальные состояния.

Два P1 блокируют коммит: нарушение ADR 0004 (SQLAlchemy-запросы в сервисном слое) и неполное тестовое покрытие RBAC для PATCH. Два P2 требуют правки после коммита до начала C.3.

---

## Решения по наблюдениям backend-director

### R1 — Docstring о партиальном индексе `uq_contracts_contractor_id_number_active`

**Вердикт: P2 — расхождение документации и реальности.**

Индекс упомянут в `backend/app/repositories/contract.py:30` в docstring метода `get_by_number`. Проверка всех 6 файлов миграций (`f80b758cadef` через `e1f2a3b4c5d6`) подтвердила: партиального уникального индекса на `(contractor_id, number) WHERE deleted_at IS NULL` в БД нет. В initial schema — только неуникальный `ix_contracts_number` по одному полю `number`.

Последствия для продакшена: защита от дублирования держится исключительно на явной проверке в сервисе (`get_by_number` + `ConflictError`). При параллельных запросах (два одновременных POST с одинаковым номером) race condition приведёт к тому, что оба пройдут проверку до вставки и в таблице окажутся два договора с одинаковой парой `(contractor_id, number)`. Индекс в БД убрал бы этот риск полностью.

**Требуемые действия (P2):** (1) убрать из docstring упоминание несуществующего индекса немедленно, чтобы не вводить в заблуждение; (2) создать миграцию с партиальным уникальным индексом `CREATE UNIQUE INDEX uq_contracts_contractor_id_number_active ON contracts(contractor_id, number) WHERE deleted_at IS NULL` — это задача db-engineer, оформить как отдельный шаг до C.5.

### R2 — `_check_house_project_match`: 404 при несуществующем house vs 422 при mismatch

**Вердикт: норм, расхождение с DoD приемлемо, но требует документирования.**

DoD формулирует «→ 422 HOUSE_PROJECT_MISMATCH» без разбора двух подслучаев. Поведение сервиса семантически корректно:
- `house_id` не найден в БД → 404 NOT_FOUND (ресурс не существует — клиент передал невалидную ссылку).
- `house.project_id != project_id` → 422 HOUSE_PROJECT_MISMATCH (ресурс существует, но нарушена связность — это именно доменная ошибка валидации).

Однако клиент получает разные коды для обоих случаев, что может потребовать дополнительной логики на фронтенде. Выбор не задокументирован в спецификации.

**Требуемые действия (P3/nit):** добавить в docstring метода `_check_house_project_match` явную формулировку о двух разных HTTP-кодах ответа с объяснением, чтобы разработчик C.3 понимал паттерн. Менять поведение не нужно.

---

## Замечания по коду

### P1-1 | `backend/app/services/contract.py:19–20, 138–191` — SQLAlchemy `select` в сервисном слое (нарушение ADR 0004 MUST-1)

**Файл:** `backend/app/services/contract.py`, строки 19–20, 138–191.

```python
from sqlalchemy import select          # строка 19
from sqlalchemy.ext.asyncio import AsyncSession  # строка 20
...
result = await self.session.execute(
    select(Contractor).where(...)      # строка 139
)
...
result = await self.session.execute(
    select(House).where(...)           # строка 163
)
...
result = await self.session.execute(
    select(Stage).where(Stage.id == stage_id)  # строка 187
)
```

ADR 0004 MUST-1: «SQLAlchemy-запросы пишутся **только** в `repositories/`. Ни роутер, ни сервис не импортируют `select`, `insert`, `update`.»

Три метода сервиса (`_check_contractor_active`, `_check_house_project_match`, `_check_stage_exists`) выполняют сырые SQLAlchemy-запросы напрямую через `self.session.execute(select(...))`. Это именно то, что ADR 0004 запрещает: бизнес-логика и доступ к данным смешаны в одном слое.

**Почему плохо, кроме нарушения ADR:** методы нельзя протестировать без реальной БД (нет мок-репозитория); при добавлении кеширования или логирования на слое данных эти три запроса выпадут из-под него; Contractor- и House-репозитории уже существуют — смысловое дублирование.

**Требуемое исправление:** вынести три проверки в `ContractorRepository` (метод `get_active_by_id`), `HouseRepository` (метод `get_by_id`) и `StageRepository` (метод `get_by_id`), либо использовать уже существующие методы этих репозиториев. `ContractService` должен принимать их через конструктор и вызывать методы репозиториев, не `self.session.execute`. Параметр `session` из конструктора `ContractService` убрать, он нужен только для обхода ADR.

**Приоритет: P1 — блокер коммита.** Это незаявленное отклонение от MUST-требования ADR 0004, которое создаёт прецедент для C.3–C.4 субагентов.

---

### P1-2 | `backend/tests/test_contracts.py` — отсутствие RBAC-теста для PATCH от `construction_manager` и `read_only`

**Файл:** `backend/tests/test_contracts.py`.

DoD §C.2: «Тесты ≥14: ... RBAC (все 4 роли × create/update/delete/read)». В наличии:

| Роль | GET list | GET by id | POST | PATCH | DELETE |
|---|---|---|---|---|---|
| read_only | ✅ 403 | ✅ 403 | ✅ 403 | ❌ нет теста | ❌ нет теста |
| construction_manager | ✅ 200 | ✅ 200 | ✅ 403 | ❌ нет теста | ✅ 403 |
| accountant | ✅ (через include_deleted) | — | — | — | — |

Отсутствуют тесты:
1. `construction_manager` + PATCH → ожидается 403.
2. `read_only` + PATCH → ожидается 403.
3. `read_only` + DELETE → ожидается 403.

**Почему блокер:** это не косметика — без этих тестов нельзя гарантировать, что PATCH-эндпоинт действительно блокирует `construction_manager`. В частности, если кто-то ошибётся при рефакторинге ролей — регрессия не будет поймана. DoD явно требует покрытия всех 4 ролей × все write-операции.

**Требуемое исправление:** добавить минимум 3 теста: `test_403_construction_manager_cannot_update`, `test_403_read_only_cannot_update`, `test_403_read_only_cannot_delete`.

**Приоритет: P1 — блокер коммита.** DoD §C.2 нарушен: тестов меньше требуемого по матрице RBAC.

---

### P2-1 | `backend/app/repositories/contract.py:30` — docstring упоминает несуществующий индекс

(см. решение по R1 выше)

**Файл:** `backend/app/repositories/contract.py`, строка 30.

Docstring метода `get_by_number` утверждает: «партиальный индекс `uq_contracts_contractor_id_number_active` покрывает этот сценарий». Индекс отсутствует во всех миграциях. Это вводящий в заблуждение комментарий.

**Требуемые действия:** (1) немедленно исправить docstring, убрав упоминание несуществующего индекса; (2) завести задачу на миграцию для db-engineer.

**Приоритет: P2** — не блокирует работу кода, но создаёт риск race condition и обманывает будущих разработчиков.

---

### P2-2 | `backend/app/services/contract.py:288–292` — мёртвый код в `update()` (project_id в ContractUpdate)

**Файл:** `backend/app/services/contract.py`, строки 288–292.

```python
if "house_id" in update_data and update_data["house_id"] is not None:
    # Если project_id меняется вместе — берём новый, иначе текущий.
    effective_project_id = update_data.get("project_id", contract.project_id)  # строка 290
    await self._check_house_project_match(
        update_data["house_id"], effective_project_id
    )
```

Схема `ContractUpdate` не содержит поля `project_id`, поэтому `update_data.get("project_id", ...)` никогда не вернёт переданное значение — только `contract.project_id`. Комментарий «Если project_id меняется вместе — берём новый» документирует несуществующий случай.

**Почему P2:** код работает корректно (fallback на `contract.project_id` правильный), но комментарий создаёт ложное ощущение, что через PATCH можно изменить `project_id`. Если в C.3 субагент добавит `project_id` в `ContractUpdate` без review, это создаст логическую ошибку — договор сменит проект в обход бизнес-правил.

**Требуемое исправление:** убрать ветку `update_data.get("project_id", ...)` — использовать только `contract.project_id`. Обновить комментарий.

---

### P3-1 | `backend/app/services/contract.py` — docstring `_check_house_project_match` некорректен (см. R2)

**Файл:** `backend/app/services/contract.py`, строки 151–156.

Docstring метода написан «Raises: ValidationError: дом не принадлежит проекту» — без упоминания, что при отсутствии дома бросается `NotFoundError` (404). Неполная документация.

**Требуемое исправление:** в блоке `Raises` добавить оба случая: `NotFoundError → 404: дом с house_id не найден` и `DomainValidationError → 422 HOUSE_PROJECT_MISMATCH: дом найден, но принадлежит другому проекту`.

---

## Чек-лист ADR

| Требование | Статус | Примечание |
|---|---|---|
| ADR 0004: SQLAlchemy только в repositories/ | ❌ НАРУШЕНО | P1-1: `select` в `services/contract.py` |
| ADR 0004: сервис не знает про HTTP | ✅ | |
| ADR 0004: `_make_service` helper в роутере | ✅ | |
| ADR 0005: `{"error": {"code", "message", "details"}}` | ✅ | Все 5 эндпоинтов |
| ADR 0005: нет `{"detail": "..."}` | ✅ | |
| ADR 0006: envelope `{items, total, offset, limit}` | ✅ | |
| ADR 0006: фильтры через SQL WHERE (не постобработка) | ✅ | `extra_conditions` в BaseRepository |
| ADR 0006: total через тот же WHERE | ✅ | `count_stmt` с subquery |
| ADR 0006: limit max 200 | ✅ | В PaginationParams |
| ADR 0007: audit.log() на каждой write-операции | ✅ | create/update/delete |
| ADR 0007: аудит в одной транзакции | ✅ | flush без commit в AuditService |
| ADR 0007: changes_json не содержит секретов | ✅ | Через ContractRead.model_dump() |
| RBAC: read_only блокирован на чтение | ✅ | |
| RBAC: construction_manager read-only | частично ✅ | GET ok, PATCH/DELETE: нет теста (P1-2) |
| RBAC: include_deleted только owner | ✅ | Проверка в роутере |
| Soft-delete: deleted_at выставляется | ✅ | Через BaseRepository.soft_delete() |
| Soft-delete: 409 при наличии Payments | ✅ | CONTRACT_HAS_PAYMENTS |
| Статусные переходы: whitelist | ✅ | `_ALLOWED_TRANSITIONS` |
| Статусные переходы: 409 при нарушении | ✅ | BUSINESS_RULE_VIOLATION |
| IDOR: house_id → project_id check | ✅ | `_check_house_project_match` |
| IDOR: contractor проверяется на активность | ✅ | `_check_contractor_active` |
| Нет литеральных паролей в тестах | ✅ | `secrets.token_urlsafe(16)` |
| Нет `assert` в validators | ✅ | Используется `raise ValueError` |
| Нет `# type: ignore` без причины | ✅ | |
| DoD: ≥14 тестов | ❌ | 23 теста, но RBAC-матрица неполная (P1-2) |

---

## OWASP Top 10

| Категория | Статус |
|---|---|
| A01 Broken Access Control / IDOR | ✅ IDOR-защита есть; RBAC-тест неполный (P1-2) |
| A03 Injection | ✅ Параметризованные запросы через SQLAlchemy ORM |
| A08 assert-patterns | ✅ `raise ValueError`, не `assert` |

---

## Итог

Два P1 блокируют коммит:

1. Вынести SQLAlchemy-запросы из трёх методов сервиса в репозиториии (ADR 0004 MUST-1).
2. Добавить 3 RBAC-теста для PATCH-эндпоинта (`construction_manager`, `read_only`) и DELETE (`read_only`).

После правки P1 — re-review. P2 и P3 можно исправить в том же коммите или отдельно до старта C.3.
