# Бриф для ri-analyst — skill `api-contract-checker`

**Автор брифа:** ri-director
**Дата:** 2026-04-19
**Бюджет Analyst:** до 4 часов (регламент R&I §«Бюджет внимания»)
**Финальный артефакт:** `~/.claude/skills/api-contract-checker/SKILL.md` + эталонный прогон на живом роутере (`backend/app/api/houses.py` или ближайший Sprint 1 роутер).

---

## Почему этот скил сейчас

В CLAUDE.md 4 строки (54-58) описывают API-контракт M-OS:
- Формат ошибок ADR-0005 (`{"error": {"code", "message", "details"}}`).
- Envelope пагинации ADR-0006 (`{items, total, offset, limit}`, limit ≤200).
- Audit в той же транзакции на write-эндпоинтах (ADR-0007).
- Проверка принадлежности во вложенных ресурсах (IDOR, 404 не 403).

Все 4 правила ловятся **только в ревью** (review-head) — Claude Code, пишущий роутер, не получает подсказки на месте. В Phase 3 Batch A step 4 поймана IDOR-уязвимость в HouseConfiguration — это не единичный случай, это паттерн. С началом Sprint 1 M-OS-1.1A (US-01..US-15: 12 таблиц, новые CRUD-роутеры per-company) нагрузка на review-head удвоится. Скил закрывает 80% типовых ошибок до PR.

## Что скил должен делать (scope)

1. **Триггер.** user-invocable=false, auto-invoke при редактировании файлов в `backend/app/api/**/*.py` или при появлении в diff'е новых FastAPI `@router.{get|post|put|patch|delete}`.
2. **Вход.** Путь к файлу роутера.
3. **Шаги SKILL.md.**
   - **Шаг 1: инвентаризация эндпоинтов.** Grep `@router\.` + `def ` → список handler'ов.
   - **Шаг 2: формат ошибок (ADR-0005).** Для каждого handler'а проверить: использует ли `HTTPException` корректно? Не возвращает ли голый `{"detail": ...}`? Global handler'ы уже приводят `HTTPException` к формату — но кастомные `JSONResponse(status_code=400, content={"detail": ...})` **запрещены**. FAIL если найден прямой `JSONResponse` с `detail`.
   - **Шаг 3: envelope пагинации (ADR-0006).** Любой handler, возвращающий список (имя содержит `list`, `search`, `find`, или `response_model=List[...]`) → обязан возвращать `PaginatedResponse[T]` с `items/total/offset/limit`. Голый `return items` — FAIL. `limit > 200` без клиппинга — WARN.
   - **Шаг 4: audit на write (ADR-0007).** Handler'ы POST/PUT/PATCH/DELETE должны содержать вызов `audit_service.log(...)` в том же `async with db.begin():` (или `db.commit()` после log). Отсутствие — P0 FAIL.
   - **Шаг 5: IDOR в nested routes.** Пути вида `/parents/{pid}/children/{cid}` или любой handler с ≥2 path-params, где один FK на другой → проверить `child.parent_id == pid`. Отсутствие проверки + возврат объекта = P0 (404 required, не 403).
   - **Шаг 6: вывод.** PASS / WARN[список] / FAIL[список с цитатой ADR и номером строки].
4. **Выход.** Markdown-отчёт с таблицей handler × правило × статус.

## Что скил НЕ делает

- Не проверяет OpenAPI-схемы (pydantic сам).
- Не валидирует RBAC/permissions (это отдельный skill `rbac-permission-wiring-checker`, бриф уже есть).
- Не дублирует ruff/mypy — это семантическая сверка, не синтаксис.
- Не проверяет сами модели данных (это `fz152-pd-checker` + ADR-0013 для миграций).

## Источники для Analyst

- `docs/adr/0005-api-error-format.md` (обязательно, extract MUST-требования).
- `docs/adr/0006-pagination-envelope.md` (обязательно).
- `docs/adr/0007-audit-same-transaction.md` (обязательно).
- `backend/app/exceptions.py` (эталон global handler'а — что он делает, чтобы не дублировать).
- `backend/app/api/houses.py` или другой live-роутер Sprint 1 — validation target.
- `~/.claude/skills/adr-compliance-checker/SKILL.md` и `~/.claude/skills/fz152-pd-checker/SKILL.md` — эталон стиля SKILL.md (секции «Когда применять», «Шаги», «Антипаттерны», «Чек-лист отчёта», «Источники»).
- Phase 3 Batch A step 4 P1-1 (IDOR HouseConfiguration) — живой кейс для раздела «Ловушки».

## Ограничения

- Не менять backend регламент — governance-director через комиссию.
- Не коммитить — Координатор.
- Не писать CI-код — только SKILL.md + 1 прогон на live-роутере для валидации.

## DoD брифа

1. `~/.claude/skills/api-contract-checker/SKILL.md` создан в стиле `fz152-pd-checker` (размер 120-150 строк).
2. Прогон на 1 живом роутере (Sprint 1) — отчёт PASS/WARN/FAIL приложен в итоговый отчёт Analyst'а.
3. Отчёт Analyst'а ≤500 слов: «что сделано / как валидировано / какие разделы CLAUDE.md можно удалить после adopt».

## Метрика успеха после adopt

За 2 недели Sprint 1 M-OS-1.1A: 0 ревью-замечаний от review-head по категориям ADR-0005/0006/0007 и IDOR в роутерах, написанных с включённым скилом. Сейчас baseline — 2-3 таких замечания на батч.
