# Code Review — Phase 3 Batch B Step 3 — bulk_upsert BudgetPlan

- **Дата**: 2026-04-15
- **Ревьюер**: `reviewer` (субагент)
- **Коммит**: staged (до коммита)
- **Предыдущий коммит**: 286a5c3 (Шаги 1+2 — APPROVE)
- **Вердикт**: **APPROVE**

---

## P-счётчики

| Уровень | Кол-во |
|---------|--------|
| P0 (blocker) | 0 |
| P1 (major) | 0 |
| P2 (minor) | 2 |
| P3 (nit) | 2 |

---

## Резюме (≤200 слов)

Реализация bulk_upsert BudgetPlan соответствует всем критическим требованиям. ADR 0007 (аудит в одной транзакции) — соблюдён: AuditService.log() вызывает flush() без commit(), а db.commit() в роутере коммитит bulk INSERT и audit_log атомарно. ADR 0006 (лимит 200 строк) — соблюдён через min_length=1/max_length=200 в Pydantic-схеме. ADR 0005 (формат ошибок) — соблюдён. RBAC: owner+accountant разрешён, construction_manager и read_only получают 403, тесты есть. AuditAction.BULK_UPSERT хранится как VARCHAR (native_enum=False) — миграция не нужна, P0 отсутствует. SQL-инъекций нет: index_where_sql — строковая константа, не интерполяция пользовательского ввода; все данные идут через bind-params SQLAlchemy. xmax::text::bigint — корректный обходной путь для PG 16. Тест на soft-deleted ключ присутствует. Тест на idempotency (повторный запрос) отсутствует — P2. Документ роутера содержит docstring «Шаг 2» в заголовке файла — нит, не обновлён после добавления bulk-эндпоинта в Шаге 3.

---

## Замечания

### P2-1 — Нет теста на idempotency

**Файл**: `backend/tests/test_budget_plans.py`  
**Критичность**: minor

**Проблема**: В чек-листе задачи явно указан пункт «повторный запрос с тем же телом даёт такой же результат (updated растёт, created не удваивается)». Такого теста нет. Без него нельзя гарантировать, что ON CONFLICT действительно работает как upsert, а не создаёт дубли при повторе.

**Требуемое действие**: Добавить тест `test_bulk_upsert_idempotent` — два одинаковых запроса подряд; второй ответ должен содержать created=0, updated=N, items совпадают с первым по составу.

---

### P2-2 — Валидация house_id выполняется N отдельными SELECT-ами до bulk_upsert

**Файл**: `backend/app/services/budget_plan.py`, строки 268–275  
**Критичность**: minor

**Проблема**: Для каждой строки с house_id выполняется отдельный `session.get(House, house_id)`. При batch из 200 строк с house_id это 200 последовательных SELECT в цикле перед самим INSERT. Для MVP с малым объёмом не критично, но это O(N) round-trips — известный антипаттерн «N+1».

**Требуемое действие**: В данном MVP-контексте допустимо оставить как есть, но зафиксировать технический долг: добавить комментарий `# TODO: заменить на один SELECT WHERE id IN (...) при росте нагрузки`. Без фиксации — нарушение правила CLAUDE.md «долг без записи».

---

### P3-1 — Docstring заголовка файла роутера не обновлён

**Файл**: `backend/app/api/budget_plans.py`, строка 1–12  
**Критичность**: nit

**Проблема**: Строка `"""Роутер для сущности BudgetPlan (ADR 0004, Фаза 3, Батч B — Шаг 2)."""` и раздел «Эндпоинты» не содержит `/bulk` — добавленного в Шаге 3. Читатель по docstring не увидит bulk-эндпоинт.

**Требуемое действие**: Обновить модульный docstring: указать «Шаг 3» и добавить `POST /budget/plans/bulk` в список эндпоинтов.

---

### P3-2 — Отсутствует пример в Swagger для BudgetPlanBulkRequest

**Файл**: `backend/app/schemas/budget_plan.py`, строки 134–150  
**Критичность**: nit

**Проблема**: `BudgetPlanBulkRequest` не имеет `model_config` с `json_schema_extra` (пример тела). В Swagger для `/bulk` кнопка «Try it out» покажет пустую форму. ADR требует Swagger с примером для новых эндпоинтов (проверяется по чек-листу задачи).

**Требуемое действие**: Добавить `model_config = {"json_schema_extra": {"example": {...}}}` в `BudgetPlanBulkRequest` и `BudgetPlanBulkResponse`.

---

## Сверка по критичным пунктам задачи

| Пункт | Статус |
|-------|--------|
| ADR 0007: аудит в той же транзакции | PASS — audit.log() → flush(), commit() в роутере после bulk |
| ADR 0006: max_length=200, 201 строка → 422 | PASS — Pydantic + тест |
| ADR 0005: формат ошибок | PASS — ConflictError, PermissionDeniedError используют AppError |
| Один project_id на batch | PASS — project_id на уровне BudgetPlanBulkRequest |
| house_id принадлежит project_id | PASS — проверка в сервисе, тест есть |
| Пустой список → 422 | PASS — min_length=1 + тест |
| Soft-delete: bulk не падает на удалённый ключ | PASS — индекс WHERE deleted_at IS NULL, тест есть |
| RBAC: owner+accountant ok; cm, read_only → 403 | PASS — тесты есть |
| Swagger: summary, description, responses | PASS — описания есть, примера нет (P3) |
| SQL-инъекции | PASS — index_where_sql константа, данные через bind-params |
| AuditAction.BULK_UPSERT: нужна миграция? | PASS — native_enum=False, VARCHAR, миграция не нужна |
| Idempotency-тест | FAIL — тест отсутствует (P2-1) |

---

## OWASP Top 10 — релевантные пункты

- **A01 Broken Access Control**: require_role(OWNER, ACCOUNTANT) на bulk-эндпоинте — PASS.
- **A03 Injection**: SQL строится через SQLAlchemy insert() + bind-params. index_where_sql — строковая константа из кода, не из пользовательского ввода — PASS.
- **A09 Logging**: одна запись BULK_UPSERT на операцию, в той же транзакции — PASS. Лог не содержит секретов — PASS (changes_json содержит только project_id, created, updated, total).

---

## ADR-compliance (сводка)

Все три релевантных ADR (0005, 0006, 0007) соблюдены. Незаявленных отклонений не обнаружено. Amendment не требуется.
