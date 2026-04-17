# Ревью Phase 3 Batch C Step C.2 (Contract CRUD) — Round 2 — 2026-04-16

**Вердикт: `approve`**

**P0:** 0 | **P1:** 0 | **P2:** 0 | **P3:** 0

---

## Закрытие пяти замечаний Round 1

### P1-1 — SQL в сервисе (ADR 0004 MUST-1)

**Статус: ЗАКРЫТО**

- `from sqlalchemy import select` — отсутствует в `services/contract.py` (импорты: строки 15–28).
- `from sqlalchemy.ext.asyncio import AsyncSession` — отсутствует в `services/contract.py`.
- `__init__` принимает `contractor_repo: ContractorRepository`, `house_repo: HouseRepository`, `stage_repo: StageRepository`; параметра `session` нет (строки 61–73).
- `_check_contractor_active` вызывает `self.contractor_repo.get_active_by_id(contractor_id)` (строка 142).
- `_check_house_project_match` вызывает `self.house_repo.get_active_by_id(house_id)` (строка 163).
- `_check_stage_exists` вызывает `self.stage_repo.get_by_id(stage_id)` (строка 181) — метод унаследован из `BaseRepository`.
- `ContractorRepository.get_active_by_id` добавлен с фильтром `deleted_at IS NULL` (строки 42–54 в `contractor.py`).
- `HouseRepository.get_active_by_id` добавлен с фильтром `deleted_at IS NULL` (строки 27–39 в `house.py`).
- `_make_service` в `api/contracts.py` передаёт все три репозитория: `contractor_repo=ContractorRepository(db)`, `house_repo=HouseRepository(db)`, `stage_repo=StageRepository(db)` (строки 42–53).

Замечание полностью устранено.

---

### P1-2 — RBAC-тесты для PATCH/DELETE

**Статус: ЗАКРЫТО**

Три новых теста добавлены в `tests/test_contracts.py` (строки 848–919):

| Тест | Роль | Эндпоинт | Проверки |
|---|---|---|---|
| `test_403_construction_manager_cannot_update` | CONSTRUCTION_MANAGER | PATCH | `status_code == 403`, `error.code == "PERMISSION_DENIED"` |
| `test_403_read_only_cannot_update` | READ_ONLY | PATCH | `status_code == 403`, `error.code == "PERMISSION_DENIED"` |
| `test_403_read_only_cannot_delete` | READ_ONLY | DELETE | `status_code == 403`, `error.code == "PERMISSION_DENIED"` |

Каждый тест: (1) создаёт договор через owner, (2) пытается изменить/удалить от имени ограниченной роли, (3) проверяет оба утверждения. Покрытие RBAC-матрицы полное.

---

### P2-1 — Docstring с несуществующим индексом

**Статус: ЗАКРЫТО**

`repositories/contract.py:30` — docstring метода `get_by_number` переписан честно: упоминание несуществующего индекса `uq_contracts_contractor_id_number_active` убрано, явно указан риск race condition, зафиксировано что задача на миграцию передана db-engineer до Шага C.5.

---

### P2-2 — Мёртвый код `effective_project_id`

**Статус: ЗАКРЫТО**

В методе `update` (строки 279–285 `services/contract.py`) переменная `effective_project_id` отсутствует. Вызов использует `contract.project_id` напрямую:

```python
if "house_id" in update_data and update_data["house_id"] is not None:
    await self._check_house_project_match(
        update_data["house_id"], contract.project_id,
    )
```

Ложный комментарий «Если project_id меняется вместе — берём новый» убран. Мёртвый код устранён.

---

### P3-1 — Docstring `Raises` в `_check_house_project_match`

**Статус: ЗАКРЫТО**

Docstring метода `_check_house_project_match` (строки 149–170) содержит явное описание обоих случаев:

```
Raises:
    NotFoundError: дом с house_id не найден или soft-deleted (→ HTTP 404).
    DomainValidationError: дом найден, но принадлежит другому проекту
        (код HOUSE_PROJECT_MISMATCH, → HTTP 422).
```

---

## Проверка регрессий

- Логика бизнес-методов не изменилась: `_check_stage_exists` использует `BaseRepository.get_by_id`, который корректно работает для Stage (Stage не имеет SoftDeleteMixin — фильтр по `deleted_at` не применяется, что соответствует поведению Round 1).
- API-контракт (коды ошибок, форма ответа) не изменился.
- Схемы, модели, миграции не тронуты.
- Итоговое количество тестов: 26 (было 23 + 3 новых RBAC).

---

## Чек-лист ADR (дополнение к Round 1)

| Требование | Статус |
|---|---|
| ADR 0004: SQLAlchemy только в repositories/ | ✅ Устранено |
| ADR 0004: сервис не знает про HTTP | ✅ |
| Три новых метода в репозиториях с правильными фильтрами | ✅ |
| RBAC-матрица покрыта тестами (все 4 роли × write) | ✅ |

---

## Итог

Все пять замечаний Round 1 закрыты полностью и корректно. Новых замечаний не обнаружено. Код соответствует ADR 0004, ADR 0005, ADR 0006, ADR 0007. Коммит разрешён.
