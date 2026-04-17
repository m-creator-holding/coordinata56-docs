# Фаза 3, Батч B — Декомпозиция

**Автор:** backend-director
**Дата:** 2026-04-15
**Источник задачи:** Координатор (старт Батча B после закрытия Батча A)
**Утверждающий план:** Координатор
**Срок-ориентир:** 2–3 рабочих дня (из phase-3-scope.md)
**Режим работы:** пилот регламента v1.4 — параллельные backend-dev под backend-head.

---

## Исходные данные

- Модели `BudgetCategory`, `BudgetPlan` — уже есть: `backend/app/models/budget.py`.
- Таблицы созданы в initial migration `2026_04_11_1911_f80b758cadef_initial_schema.py`.
- Базовые компоненты стабильны: `BaseRepository`, `BaseService`, `AuditService`, `ListEnvelope` (ADR 0006), error envelope (ADR 0005), `extra_conditions`-фильтры в SQL.
- Эталон CRUD — `project` (services/repositories/api/schemas/tests).
- Директория роутеров — `backend/app/api/` (ADR 0004 Amendment).
- Ключевое решение Q9: bulk-load — upsert по ключу `(project_id, category_id, stage_id, house_id)`, лимит 200 строк, 1 audit-запись с summary (N created / M updated).

## Блокеры / зависимости db-engineer (ДО шага 3)

**DB-Q1. Уникальный индекс для upsert-ключа `budget_plan`.**
- Модель сейчас не имеет `UniqueConstraint` на `(project_id, category_id, stage_id, house_id)`.
- `house_id` и `stage_id` — nullable. В PostgreSQL обычный UNIQUE **не запрещает** дубликаты, если в ключе есть NULL.
- Без корректного уникального ограничения `INSERT ... ON CONFLICT DO UPDATE` работать не будет, а логика upsert по Q9 станет гонкой.
- **Требуется от db-engineer**: новая Alembic-миграция, добавляющая партиальные уникальные индексы (PostgreSQL-idiom для nullable-ключей):
  - `UNIQUE(project_id, category_id, stage_id, house_id) WHERE stage_id IS NOT NULL AND house_id IS NOT NULL`
  - `UNIQUE(project_id, category_id, stage_id)       WHERE stage_id IS NOT NULL AND house_id IS NULL`
  - `UNIQUE(project_id, category_id, house_id)       WHERE stage_id IS NULL     AND house_id IS NOT NULL`
  - `UNIQUE(project_id, category_id)                 WHERE stage_id IS NULL     AND house_id IS NULL`
- Миграция должна пройти round-trip (CLAUDE.md §Данные и БД).
- Соответствующее обновление модели `BudgetPlan` (Index / UniqueConstraint-декларация в `__table_args__`) чтобы SQLAlchemy знала о constraint и мог использоваться `Insert.on_conflict_do_update(...)` с `index_elements` + `index_where`.
- **Запрос оформляет backend-director → db-director → db-engineer** отдельным промптом одновременно со стартом Шага 1.

**DB-Q2. (подтверждение, не блокер)** `TimestampMixin` уже навешан — ок, миграция для `updated_at` не нужна.

Если db-engineer подтверждает решение и выдаёт миграцию ≤ окончания Шага 2 — Шаг 3 стартует без простоя.

---

## Шаги (один PR = одно ревью)

### Шаг 1. `BudgetCategory` — CRUD (эталон батча)

**Назначение:** первый шаг задаёт стиль Батча B, по нему сверяется Шаг 2. Простой справочник без вложенных связей.

**Исполнитель:** backend-dev-1 (под backend-head).
**Время-ориентир:** 30–45 мин.

**Эндпоинты** (prefix `/api/budget/categories`):
- `GET /` — список, пагинация + фильтры `search` (по name/code, ILIKE), `include_deleted` (bool, default false) — по soft-delete семантике (`SoftDeleteMixin` добавляется db-engineer).
- `GET /{id}` — получить по id (включая soft-deleted? — нет, 404 если `deleted_at IS NOT NULL` и флаг `include_deleted` не передан).
- `POST /` — создать (owner + accountant).
- `PATCH /{id}` — обновить (owner + accountant). Запрет PATCH на soft-deleted (404).
- `DELETE /{id}` — soft-delete (owner only): выставить `deleted_at = now()`. Повторный DELETE на уже soft-deleted → 404. При наличии активных (non-deleted) `BudgetPlan` с этой категорией → 409 `CATEGORY_HAS_PLANS` (FK `ondelete='RESTRICT'` в БД — дополнительная защита на уровне миграции).

**RBAC:**
- Read: все авторизованные роли.
- Create / Update: `owner`, `accountant`.
- Delete: `owner`.

**Аудит:** log на create/update/delete.

**FILES_ALLOWED:**
- `backend/app/schemas/budget_category.py`
- `backend/app/repositories/budget_category.py`
- `backend/app/services/budget_category.py`
- `backend/app/api/budget_categories.py`
- `backend/tests/test_budget_categories.py`
- `backend/app/main.py` (регистрация роутера)

**FILES_FORBIDDEN:** всё остальное, включая модели и миграции.

**DoD шага:**
- ≥11 тестов: happy (create/get/list/update/delete-soft), 403 × 4 роли, 404, 422 на дубликат `code` (UNIQUE), 409 на delete при наличии активного BudgetPlan, повторный DELETE soft-deleted → 404, GET list с `include_deleted=true` возвращает удалённые.
- `ruff check` чисто, pytest зелёный, reviewer approve.

---

### Шаг 2. `BudgetPlan` — CRUD (без bulk)

**Назначение:** одиночные операции CRUD. Bulk-логика — отдельным шагом 3, чтобы не смешивать ревью.

**Исполнитель:** backend-dev-2 (параллельно с Шагом 1; оба шага не пересекаются по файлам).
**Время-ориентир:** 45–60 мин.

**Эндпоинты** (prefix `/api/budget/plans`):
- `GET /` — список с фильтрами: `project_id`, `category_id`, `stage_id`, `house_id` (все опциональны), `include_nulls_stage`, `include_nulls_house` — нет, по умолчанию трактуем nullable как «любое» при отсутствии параметра; при явном `stage_id=0` — **не поддерживать** (валидатор ge=1). Фильтры — через `extra_conditions` (SQL WHERE, не Python).
- `GET /{id}`.
- `POST /` — создать одиночную строку (owner + accountant). Валидация: FK-существование (project, category; stage/house — если переданы).
- `PATCH /{id}` — частичное обновление (owner + accountant).
- `DELETE /{id}` — soft-delete (owner + accountant): выставить `deleted_at = now()`. Повторный DELETE → 404. `SoftDeleteMixin` добавляется db-engineer параллельно.

**Валидация Pydantic:**
- `amount_cents: int, ge=0`.
- `BudgetPlanCreate`: `project_id`, `category_id` — обязательные; `stage_id`, `house_id` — optional.
- Консистентность `house_id → project_id`: если передан `house_id`, сервис проверяет `House.project_id == plan.project_id` → иначе 409 `BUSINESS_RULE_VIOLATION`.

**RBAC:**
- Read: все авторизованные.
- Create / Update / Delete: `owner`, `accountant`.

**Аудит:** log на create/update/delete.

**FILES_ALLOWED:**
- `backend/app/schemas/budget_plan.py`
- `backend/app/repositories/budget_plan.py`
- `backend/app/services/budget_plan.py`
- `backend/app/api/budget_plans.py`
- `backend/tests/test_budget_plans.py`
- `backend/app/main.py` (регистрация роутера)

**FILES_FORBIDDEN:** всё остальное, включая модель `budget.py` и миграции (если потребуется — эскалация Директору).

**Параллельность:** не пересекается по файлам с Шагом 1 (кроме `main.py` — там мёрдж двух однострочников, ответственный — backend-head). Конфликт в `main.py` разрулить на уровне head перед передачей reviewer.

**DoD шага:**
- ≥13 тестов: happy (create/get/list/update/delete-soft), 403 × 4 роли, 404, 422 (отрицательные amount, несуществующий project_id), 409 на house из чужого project, валидация фильтров (total корректен с учётом исключения soft-deleted), повторный DELETE → 404, GET list с `include_deleted=true`.
- Reviewer approve.

---

### Шаг 3. `BudgetPlan` — bulk upsert

**Назначение:** bulk-endpoint, единственный нестандартный сценарий батча.

**Зависимости:** миграция от db-engineer (DB-Q1) применена; партиальные unique-индексы присутствуют. **Шаг стартует только после подтверждения миграции**.
**Исполнитель:** backend-dev-3 (или backend-dev-2, если освободился).
**Время-ориентир:** 60–90 мин.

**Эндпоинт:**
- `POST /api/budget/plans/bulk` — принимает список строк BudgetPlanBulkItem.

**Контракт запроса:**
```
{
  "items": [
    {"project_id": 1, "category_id": 3, "stage_id": 2, "house_id": null, "amount_cents": 1500000, "note": "..."},
    ...
  ]
}
```
- `items`: `min_length=1, max_length=200` (лимит из Q9 / ADR 0006).
- Все строки должны принадлежать одному `project_id` — иначе 422.
- FK-существование всех category/stage/house проверяется перед записью одним батч-запросом (IN), не построчно.

**Контракт ответа:**
```
{
  "project_id": 1,
  "created": 42,
  "updated": 158,
  "total": 200
}
```

**Логика:**
- Operation — atomic (CLAUDE.md / departments/backend.md §10): одна транзакция, всё или ничего. При любой ошибке — rollback.
- Upsert через `postgresql.insert(...).on_conflict_do_update(...)` с `index_elements` или `index_where`, ссылающимися на 4 партиальные unique-индекса DB-Q1. Репозиторий содержит 4 ветки upsert в зависимости от nullability `stage_id`/`house_id`, либо один общий `INSERT ... ON CONFLICT` с `index_where` по маске — **финальное решение оставляем за backend-head + архитектором** при первом ревью.
- Возвращаемые `created`/`updated` считаются через `RETURNING xmax = 0` (PostgreSQL-идиома: `xmax=0` ⇒ вставка, иначе ⇒ обновление).

**Аудит:**
- **Одна** запись audit_log на всю bulk-операцию. `action = "bulk_upsert"`, `entity = "BudgetPlan"`, `entity_id = null` (операция не на одной сущности). `meta` = `{"project_id", "created", "updated", "total"}`.
- Поэлементный diff before/after **не пишем** (Q9 в decisions.md упоминает diff, но это несовместимо с требованием Координатора «одна запись с summary»; решение Координатора приоритетно — фиксируется как уточнение Q9).

**RBAC:**
- `owner`, `accountant`.

**FILES_ALLOWED:**
- `backend/app/schemas/budget_plan.py` (дополнения: `BudgetPlanBulkItem`, `BudgetPlanBulkRequest`, `BudgetPlanBulkResult`)
- `backend/app/repositories/budget_plan.py` (метод `bulk_upsert`)
- `backend/app/services/budget_plan.py` (метод `bulk_upsert`)
- `backend/app/api/budget_plans.py` (эндпоинт `/bulk`)
- `backend/tests/test_budget_plans_bulk.py` — отдельный файл тестов.

**FILES_FORBIDDEN:** модели, миграции, тесты других сущностей.

**DoD шага:**
- ≥8 тестов:
  1. Happy pure-insert (все new).
  2. Happy pure-update (все уже существуют).
  3. Смешанный insert+update, корректный counter.
  4. Atomic rollback: одна строка с несуществующим `category_id` — вся операция откатывается, в БД ничего не создаётся.
  5. 403 для ролей read_only/construction_manager.
  6. 422 на `items=[]`, `items.length > 200`.
  7. 422 на смешанные project_id внутри batch.
  8. Аудит: ровно 1 запись с правильным summary (проверить COUNT(*) audit_log до/после).
- `EXPLAIN ANALYZE` на list-эндпоинте с фильтром `project_id` — не регрессирует (индекс есть с initial migration).
- Reviewer approve.

---

### Шаг 4. Замыкание батча

**Назначение:** sanity-check всего батча и подготовка к коммиту в main.

**Исполнитель:** backend-head.
**Время-ориентир:** 20–30 мин.

**Проверки:**
- `pytest backend/tests` зелёный целиком (не только новые файлы).
- `ruff check backend/app` чисто.
- Swagger: `/docs` открывается, все новые эндпоинты имеют summary/description/response_model/example.
- Alembic round-trip: `alembic downgrade -1 && alembic upgrade head` чисто (после db-engineer).
- Обновление `docs/pods/cottage-platform/phases/phase-3-checklist.md` — пункты по Батчу B.
- Ретро-заметки Батча B начаты (краткий draft 5–7 строк: что сработало / что нет).
- Формальная передача reviewer для финального approve перед коммитом.

**FILES_ALLOWED:** только docs/pods/cottage-platform/phases/phase-3-checklist.md, docs/knowledge/retros/phase_3_batch_b_notes.md (draft).

---

## Граф зависимостей

```
       ┌── Шаг 1 BudgetCategory ──┐
старт ─┤                          ├─> Шаг 3 BudgetPlan bulk ─> Шаг 4 замыкание
       └── Шаг 2 BudgetPlan CRUD ─┘
       │
       └── DB-Q1 миграция unique-indexes (db-engineer) ──> gate для Шага 3
```

Шаги 1 и 2 — параллельно. Шаг 3 ждёт и DB-Q1, и мёрдж Шагов 1+2 в main (или promotion-ветку).

---

## Коммуникационный регламент батча (departments/backend.md §в работе)

- Промпты backend-dev — всегда включают: ссылку на CLAUDE.md, `departments/backend.md`, ADR 0004/0005/0006/0007, эталон Project. См. шаблон промпта в `departments/backend.md` §«Шаблон промпта для backend-dev».
- Каждый dev **обязан** прогнать чек-лист самопроверки до сдачи head (departments/backend.md §«Чек-лист»).
- Reviewer — ДО `git commit` (CLAUDE.md).
- `git add -A` запрещён (CLAUDE.md) — явный список файлов.
- Секреты — `secrets.token_urlsafe(16)` в тестах (CLAUDE.md §Секреты).
- Фильтры — в SQL WHERE (CLAUDE.md §Данные и БД).

## Риски Батча B

| # | Риск | Митигация |
|---|---|---|
| B-R1 | Повтор ошибок Батча A (пароли литералом, фильтр в Python, IDOR) | Явная ссылка на CLAUDE.md-правила в каждом промпте + чек-лист. |
| B-R2 | DB-Q1 задержит Шаг 3 | Запрос db-engineer отправляется одновременно со стартом Шага 1. |
| B-R3 | Конфликт в `main.py` между Шагами 1 и 2 | Мёрдж делает backend-head, а не dev. |
| B-R4 | Upsert с nullable-ключом реализован неверно (silently вставляет дубликаты) | Тест 2 (pure-update) проверит: повторный bulk на тех же данных даёт `updated=N, created=0`. |
| B-R5 | Bulk — неатомарный (PR-дефект Батча A по Payment) | Тест 4 (rollback при FK-ошибке) обязателен. |

## Решения Владельца (закрыто 2026-04-15, Telegram msg #572)

1. **Q9-уточнение — аудит bulk**: ✅ **одна запись** `audit_service.log()` на всю bulk-операцию с summary `{project_id, created, updated, total}`, НЕ построчно. Поэлементный diff before/after отменён. Зафиксировано в `docs/pods/cottage-platform/phases/phase-3-decisions.md` §Q9.
2. **SoftDelete для BudgetCategory / BudgetPlan**: ✅ **добавляется `SoftDeleteMixin`** для обеих моделей. Миграция — в зоне db-engineer (параллельно Шагам 1 и 2). Шаги 1 и 2 **не трогают** `backend/app/models/budget.py` и миграции.
   - DELETE выставляет `deleted_at`, GET list по умолчанию исключает удалённые, повторный DELETE на soft-deleted → 404 (departments/backend.md §6).
   - Это меняет DoD Шага 1 и Шага 2: тесты должны покрыть soft-delete семантику, а не hard-delete.
   - 409 `CATEGORY_HAS_PLANS` на DELETE `BudgetCategory` при наличии активных (non-deleted) `BudgetPlan` — остаётся в силе.
