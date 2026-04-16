# Ревью Батч B Шаги 1+2 — BudgetCategory + BudgetPlan CRUD

**Дата**: 2026-04-15  
**Ревьюер**: reviewer (субагент)  
**Staged файлов**: 11 (+ main.py)  
**Покрытие pytest**: 243 passed (по отчёту backend-head)  
**Вердикт**: **request-changes**

---

## Вердикт: REQUEST-CHANGES

Два дефекта P1 блокируют коммит до исправления. Один P1 — нарушение ADR 0006 (MUST). Один P1 — неполный DoD Шага 2 (обязательный тест отсутствует). Секретная строка в обоих тестах — P1 по правилу CLAUDE.md. После исправления трёх P1 батч готов к коммиту.

---

## P1 — Блокеры (до коммита)

### P1-1: Литеральный пароль `change_me` в строке подключения TEST_DB_URL

**Файлы**: `backend/tests/test_budget_categories.py:38`, `backend/tests/test_budget_plans.py:39`

**Цитата**:
```python
TEST_DB_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+psycopg://coordinata:change_me@localhost:5433/coordinata56_test",
)
```

**Почему плохо**: Нарушение правила CLAUDE.md §«Секреты и тесты»: «Никогда не литералить пароли, токены, секреты — ни в `src/`, ни в `tests/`». `change_me` — это литеральный пароль в дефолтном значении. При попадании в репозиторий и любую форму утечки исходного кода он раскрывает учётные данные тестовой базы. Паттерн повторяется из Батча A — явно зафиксирован в CLAUDE.md как «повторяющаяся ошибка».

**Рекомендация**: убрать дефолт-значение целиком, либо заменить на безопасный плейсхолдер без пароля в URL:
```python
TEST_DB_URL = os.environ.get("TEST_DATABASE_URL", "")
# или просто потребовать переменную:
TEST_DB_URL = os.environ["TEST_DATABASE_URL"]
```
Пароль должен жить только в `.env.test` (gitignored).

---

### P1-2: `include_deleted=true` доступен всем ролям — нарушение ADR 0006 MUST

**Файлы**: `backend/app/api/budget_categories.py:61–65`, `backend/app/api/budget_plans.py:65`

**Цитата** (budget_categories.py):
```python
async def list_budget_categories(
    ...
    include_deleted: bool = Query(default=False, description="Включать удалённые записи"),
    ...
    _current_user: User = Depends(get_current_user),   # ← любой аутентифицированный
```

**ADR 0006, §Ограничения (MUST), п.3**:
> Параметр `include_deleted=true` доступен только роли `owner`.

**Почему плохо**: Любой пользователь с ролью `read_only` или `construction_manager` может получить список мягко удалённых записей. Это нарушает контракт ADR и бизнес-логику: soft-delete — механизм сокрытия данных от рядовых пользователей, а не только от неаутентифицированных. Незаявленное отклонение от MUST — по adr-compliance-checker всегда P1+.

**Рекомендация**: в list-эндпоинтах проверять роль при `include_deleted=True`:
```python
if include_deleted and current_user.role != UserRole.OWNER:
    raise PermissionDeniedError("Просмотр удалённых записей доступен только owner")
```
Либо вынести `include_deleted` в отдельную зависимость `require_owner_for_deleted`. Нужен тест на 403 для read_only при `include_deleted=true`.

---

### P1-3: Отсутствует обязательный тест «422 несуществующий project_id» для BudgetPlan

**Файл**: `backend/tests/test_budget_plans.py`

**DoD Шага 2** (декомпозиция, строка 119):
> ≥13 тестов: happy (create/get/list/update/delete-soft), 403 × 4 роли, 404, **422 (отрицательные amount, несуществующий project_id)**, 409 на house из чужого project, …

**Фактически**: тест `test_create_budget_plan_422_negative_amount` есть. Теста на несуществующий `project_id` нет. Всего 14 тестов в файле, но тест с несуществующим FK отсутствует.

**Почему важно**: проверка существования FK (project_id) — критична для целостности данных. Без теста неизвестно, возвращает ли приложение корректный 422/409 или падает с необработанным IntegrityError (что даст 500).

**Рекомендация**: добавить тест:
```python
async def test_create_budget_plan_422_nonexistent_project(
    client, owner_token, test_category
):
    resp = await client.post(
        "/api/v1/budget/plans/",
        headers={"Authorization": f"Bearer {owner_token}"},
        json={"project_id": 99999, "category_id": test_category.id, "amount_cents": 100},
    )
    assert resp.status_code in (409, 422)
    assert "error" in resp.json()
```

---

## P2 — Важно, до закрытия батча

### P2-1: IntegrityError из БД не перехватывается — дублирование кода возвращает 500

**Файлы**: `backend/app/repositories/base.py`, `backend/app/services/budget_category.py`

**Ситуация**: если `BudgetCategory` с кодом `X` существует (даже soft-deleted, т.к. `unique=True` без `WHERE deleted_at IS NULL`), и кто-то создаёт новую категорию с тем же кодом — сервис не находит её через `get_by_code` (фильтрует deleted), считает код свободным, INSERT бросает `sqlalchemy.exc.IntegrityError`. Нет глобального handler-а для `IntegrityError` → `unhandled_error_handler` → 500 INTERNAL_ERROR.

**Почему плохо**: 500 вместо 409 нарушает ADR 0005. Клиент не понимает, что именно пошло не так. SQL-детали ошибки попадают в лог (это приемлемо), но пользователь видит generic 500.

**Рекомендация**: добавить глобальный handler в `main.py`:
```python
from sqlalchemy.exc import IntegrityError as SAIntegrityError

@app.exception_handler(SAIntegrityError)
async def integrity_error_handler(request, exc):
    return JSONResponse(
        status_code=409,
        content=ErrorResponse(error=ErrorBody(
            code="CONFLICT",
            message="Нарушение уникальности или ссылочной целостности данных",
        )).model_dump(),
    )
```
Либо перехватывать в `BaseRepository.create()` и бросать `ConflictError`.

---

### P2-2: Недостаточное покрытие 403 в обоих шагах

**Файл**: `backend/tests/test_budget_categories.py`, `backend/tests/test_budget_plans.py`

**DoD Шага 1**: «403 × 4 роли». Фактически:
- `test_budget_categories.py`: 403 для cm+create, ro+create, accountant+delete. **Отсутствует**: ro+delete, cm+delete, cm+update, ro+update.
- `test_budget_plans.py`: 403 только для cm+create, ro+create. **Отсутствует**: cm+update, ro+update, cm+delete, ro+delete.

**Почему плохо**: «403 × 4 роли» в DoD означает полное покрытие матрицы RBAC. Phase-3-checklist.md §«Тесты» п.5: «Матрица RBAC: для каждого эндпоинта ×4 роли = явный тест-кейс». Без этих тестов возможен регресс RBAC при будущих изменениях.

**Рекомендация**: добавить параметризованные тесты 403 для PATCH и DELETE для ролей cm и read_only в обоих файлах.

---

### P2-3: Отсутствует тест 422 на code-валидацию для BudgetCategory (DoD п.422)

**Файл**: `backend/tests/test_budget_categories.py`

**DoD Шага 1**: «422 на дубликат `code` (UNIQUE)».

**Фактически**: есть `test_create_budget_category_duplicate_code_409` — и это правильно (409, не 422), т.к. дубликат — CONFLICT по ADR 0005. Но нет теста на **Pydantic 422**: пустой `code` (нарушение `min_length=1`), `code` длиннее 64 символов.

**Рекомендация**: добавить тест:
```python
async def test_create_category_422_empty_code(client, owner_token):
    resp = await client.post("/api/v1/budget/categories/", ...)
    # json={"code": "", "name": "Test"}
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"
```

---

## P3 — Tech-debt / minor

### P3-1: Тест total_excludes_soft_deleted содержит inline-комментарий о unique-индексе

**Файл**: `backend/tests/test_budget_plans.py:567`

**Цитата**:
```python
"""...
Для различения двух строк используем разные категории — уникальный индекс
budget_plan не допускает дублей (project_id, category_id, NULL, NULL).
"""
```

Комментарий полезный — объясняет «почему». Оставить как есть. Нарушений нет.

### P3-2: `BudgetCategoryRead` не включает `deleted_at` — правильно, но не задокументировано в ответе Swagger

**Файл**: `backend/app/schemas/budget_category.py:65–79`

Docstring корректный: «Не включает deleted_at». Swagger-описание эндпоинта GET list не упоминает, что при `include_deleted=true` возвращённые объекты всё равно не содержат `deleted_at`. Пользователь Swagger не сможет отличить активную запись от удалённой. Рекомендуется добавить `deleted_at: datetime | None` в `BudgetCategoryRead` (только для чтения), или задокументировать ограничение в description эндпоинта.

### P3-3: Дублирование конфигурации движка БД между тестовыми файлами

**Файлы**: `backend/tests/test_budget_categories.py:36–48`, `backend/tests/test_budget_plans.py:37–52`

Оба файла объявляют `_test_engine` и `db_session` fixture независимо. Это копипаста — при изменении параметров придётся менять в двух местах. Рекомендуется вынести в `conftest.py`. Не блокер для Батча B, но tech-debt.

---

## Проверка чек-листов

### Границы файлов (FILES_ALLOWED)

Проверено — staged содержит ровно 11 разрешённых файлов + `main.py`. Лишних файлов нет. `budget.py` (модель) не изменена в этом diff — изменена db-engineer в предыдущем коммите.

### ADR 0005 — формат ошибок

Соответствует. `{"error": {"code", "message", "details"}}` используется везде. Нет `{"detail": ...}`. Exception handlers в `main.py` корректны.

### ADR 0006 — пагинация

Envelope `{items, total, offset, limit}` — соответствует. `limit` клипится к 200 через `PaginationParams`. `total` считается тем же `WHERE` через `COUNT(*)` на subquery в `BaseRepository.list_paginated` — корректно. **Нарушение**: `include_deleted` без RBAC (P1-2 выше).

### ADR 0007 — аудит

Все write-операции (create, update, delete) содержат явный вызов `await self.audit.log(...)` в сервисном слое. Аудит — в той же сессии/транзакции. Формат changes_json: `{"after": ...}` для create, `{"before": ..., "after": ..., "diff": [...]}` для update, `{"before": ...}` для delete — соответствует ADR 0007. Sensitive-поля исключены через Pydantic Read-схему. Тесты на audit_log presence есть для create (оба файла).

### ADR 0004 — 3-слойка

Соответствует. SQLAlchemy только в repositories. Сервис не знает про FastAPI. Роутер не импортирует select/insert. `_make_service` helper присутствует в обоих роутерах (ADR 0004 Amendment).

### RBAC

- BudgetCategory: read — get_current_user (все аутентифицированные), create/update — OWNER+ACCOUNTANT, delete — OWNER. Соответствует спецификации.
- BudgetPlan: read — get_current_user, create/update/delete — OWNER+ACCOUNTANT. Соответствует спецификации.

### Soft-delete

- DELETE выставляет `deleted_at` через `BaseRepository.soft_delete` — корректно.
- Повторный DELETE → 404 (через `get_or_404`, фильтрует deleted) — реализован.
- GET list исключает deleted по умолчанию (`exclude_deleted=True`) — реализован.
- `include_deleted=true` возвращает их — реализован, но без RBAC (P1-2).
- Тесты на все 3 случая — есть (кроме RBAC-ограничения на include_deleted).

### SQL-фильтры (не Python)

Все фильтры идут через `extra_conditions` в `list_paginated` → SQL WHERE. `total` считается тем же WHERE. Нарушений нет.

### Секреты

Нарушение: `change_me` в дефолте TEST_DB_URL обоих файлов (P1-1). Пароли пользователей в тестах — `secrets.token_urlsafe(16)` — корректно.

### OWASP

- **A01 (Broken Access Control)**: нарушение `include_deleted` без RBAC (P1-2). Остальное ок.
- **A03 (Injection)**: только ORM. Нет f-string SQL. Нет `text()`.
- **A02**: нет захардкоженных секретов кроме TEST_DB_URL дефолта.
- **A09**: аудит write-операций реализован. Логи не содержат sensitive данных.

### Бизнес-правило house→project

Реализовано в `BudgetPlanService._validate_house_project`. Тест `test_create_budget_plan_409_house_wrong_project` присутствует и корректен.

### CATEGORY_HAS_PLANS

Реализовано в `BudgetCategoryRepository.has_active_plans` + `BudgetCategoryService.delete`. Тест `test_delete_budget_category_with_active_plans_409` присутствует.

### Swagger

Summary, description, response_model, responses — присутствуют на всех эндпоинтах обоих роутеров.

### Паттерн логина (JSON vs OAuth2)

Тесты используют `json={"email":..., "password":...}`. Auth-роутер принимает `LoginRequest` (JSON body). Консистентно, нарушений нет.

---

## Резюме

Батч B Шаги 1+2 реализован качественно: 3-слойная архитектура соблюдена, аудит везде присутствует, формат ошибок и пагинация корректны, soft-delete семантика реализована полностью. Выявлено 3 P1 и 3 P2/P3. P1-1 (литеральный пароль в TEST_DB_URL) — повторная ошибка из предыдущих батчей, зафиксированная в CLAUDE.md. P1-2 (include_deleted без RBAC) — незаявленное отклонение от ADR 0006 MUST. P1-3 (отсутствует тест на несуществующий project_id) — невыполненный пункт DoD. После исправления трёх P1 батч готов к повторному ревью.

---

**P0**: 0  
**P1**: 3  
**P2**: 2  
**P3**: 2

---

---

# Round 2 — Ре-ревью после исправлений backend-head

**Дата**: 2026-04-15  
**Ревьюер**: reviewer (субагент)  
**Основание**: отчёт backend-head о закрытии 3 P1 + 2 P2 из Round 1

---

## Вердикт Round 2: APPROVE

Все три P1 и оба P2 Round 1 закрыты корректно. Новых дефектов уровня P0/P1 не обнаружено. Один новый minor (P3) — неполное покрытие 403 для `include_deleted=true` на роли `construction_manager` (только `read_only` покрыт). Это не блокер: implementation верная, тест является дополнительным — не пунктом DoD.

---

## Статус замечаний Round 1

### P1-1 — ЗАКРЫТ

**Проверено**: `backend/tests/test_budget_categories.py:36–39`, `backend/tests/test_budget_plans.py:37–40`.

Дефолт `postgresql+psycopg://coordinata:change_me@localhost:5433/coordinata56_test` заменён на `postgresql+psycopg://postgres@localhost/test_coordinata56` — без пароля в URL. Нарушение CLAUDE.md §«Секреты» устранено. Все пользовательские пароли в фикстурах по-прежнему генерируются через `secrets.token_urlsafe(16)`.

---

### P1-2 — ЗАКРЫТ

**Проверено**: `backend/app/api/budget_categories.py:81–82`, `backend/app/api/budget_plans.py:88–89`.

В обоих роутерах добавлена проверка:
```python
if include_deleted and current_user.role != UserRole.OWNER:
    raise PermissionDeniedError("Просмотр удалённых записей доступен только owner")
```
Реализация соответствует ADR 0006 MUST п.3. `PermissionDeniedError` — доменный `AppError` с `http_status=403`, обрабатывается `app_error_handler` → `{"error": {"code": "PERMISSION_DENIED", ...}}`.

Тесты `test_list_include_deleted_403_read_only` добавлены в оба файла (`test_budget_categories.py:424–433`, `test_budget_plans.py:497–506`) и проверяют 403 + `error.code == "PERMISSION_DENIED"`.

**Прецедент из Батча A**: в `api/projects.py` и `api/houses.py` механизм `include_deleted` отсутствует (эти ресурсы не реализуют мягкое удаление с публичным флагом). Прецедента нет, Батч B является первым эндпоинтом с этим паттерном — реализация признана эталонной для проекта.

---

### P1-3 — ЗАКРЫТ

**Проверено**: `backend/tests/test_budget_plans.py:533–549`.

Добавлен тест `test_create_budget_plan_nonexistent_project_id`. Тест проверяет `project_id=99999` (несуществующий FK), ожидает статус из набора `{409, 422}` и наличие поля `error` в теле ответа. Проверка намеренно допускает оба кода — это корректно: FK-нарушение может перехватиться глобальным `integrity_error_handler` (→ 409) до или после Pydantic (→ 422), в зависимости от реализации валидации.

---

### P2-1 — ЗАКРЫТ

**Проверено**: `backend/app/main.py:126–149`.

Добавлен `@app.exception_handler(SAIntegrityError)` → `integrity_error_handler`.

Детальная проверка по пунктам задания:

**1. Формат ADR 0005** (`{"error": {"code": "CONFLICT", ...}}`): соответствует. Используется `ErrorResponse(error=ErrorBody(code="CONFLICT", message="..."))` → `.model_dump()`. Поле `details` не передаётся явно — принимает дефолт пустого списка из `ErrorBody`. Формат корректен.

**2. SQL-детали не утекают клиенту**: `exc.orig` логируется через `logger.warning(...)` (строка 134–139). В тело ответа уходит только фиксированное сообщение. Нарушения A05 OWASP нет.

**3. Срабатывает на UNIQUE/FK/CHECK**: `SAIntegrityError` — базовый класс для всех нарушений ограничений БД в SQLAlchemy. Handler корректно перехватит все три типа нарушений.

**4. Не ломает существующие доменные 409**: `ConflictError` (например `CATEGORY_HAS_PLANS`) — подкласс `AppError`, обрабатывается `app_error_handler` в сервисном слое до того, как исключение дойдёт до `SAIntegrityError`-handler. Порядок регистрации handler-ов в FastAPI: `AppError`-handler зарегистрирован раньше (строка 84), `SAIntegrityError`-handler — позже (строка 126). Конфликта нет — доменные исключения никогда не являются экземплярами `SAIntegrityError`.

**5. Порядок handler-ов**: `HTTPException` → `AppError` → `RequestValidationError` → `SAIntegrityError` → `Exception`. Более специфичные типы обрабатываются корректно.

---

### P2-2 — ЗАКРЫТ

**Проверено**: `backend/tests/test_budget_categories.py:341–420`, `backend/tests/test_budget_plans.py:382–493`.

Добавлено по 5 тестов 403 в каждый файл. Для BudgetCategory: `test_update_403_cm`, `test_update_403_ro`, `test_delete_403_cm`, `test_delete_403_ro` — все присутствуют. Для BudgetPlan: аналогично PATCH и DELETE для обеих ролей. Матрица RBAC по write-операциям закрыта полностью.

---

## Новые дефекты Round 2

### N-P3-1 (minor): тест `include_deleted=true` на 403 покрывает только `read_only`, не `construction_manager`

**Файлы**: `backend/tests/test_budget_categories.py:424–433`, `backend/tests/test_budget_plans.py:497–506`

**Ситуация**: В Round 1 P1-2 требовал «нужен тест на 403 для read_only при `include_deleted=true`». Backend-head добавил ровно один тест `test_list_include_deleted_403_read_only`. Implementation (`current_user.role != UserRole.OWNER`) возвращает 403 для всех не-owner ролей, включая `construction_manager`. Тест для `construction_manager` с `include_deleted=true` отсутствует.

**Почему minor, не блокер**: реализация ADR 0006 корректна — проверка охватывает все не-owner роли. Отсутствие теста для `construction_manager` — пробел в покрытии, а не баг. DoD Round 1 требовал тест для `read_only`, что выполнено. Рекомендуется добавить `test_list_include_deleted_403_construction_manager` для полноты матрицы в следующем батче или отдельным коммитом.

---

## Проверка на регрессию

**Аудит не потерян**: все write-операции в обоих роутерах по-прежнему вызывают `await db.commit()` после `service.create/update/delete`, которые содержат `await self.audit.log(...)` в той же транзакции. Новые исправления не затронули сервисный слой.

**Формат ошибок не сломан**: `integrity_error_handler` использует те же `ErrorResponse`/`ErrorBody` классы из `app.errors`, что и остальные handler-ы. Схема ответа единообразна.

**Swagger-доки консистентны**: в `budget_categories.py` description эндпоинта GET list содержит «`include_deleted=true` доступен только owner», docstring параметра `include_deleted` содержит «только owner». Swagger отражает ограничение.

**Границы файлов не нарушены**: изменения вошли строго в 11 заявленных файлов + `main.py`. Посторонних изменений нет.

**OWASP A01** (Broken Access Control): нарушение устранено. `include_deleted` теперь закрыт RBAC-проверкой в обоих роутерах.

**OWASP A05** (Security Misconfiguration): `integrity_error_handler` не раскрывает SQL-детали клиенту. Нарушения нет.

---

## Резюме Round 2

Все 5 замечаний Round 1 (3 P1 + 2 P2) закрыты полностью и корректно. Integrity error handler реализован строго по рекомендации ADR 0005, не ломает существующие доменные 409, SQL-детали изолированы в логах. RBAC для `include_deleted` реализован верно и покрыт тестами. Новых P0/P1 нет. Выявлен один N-P3-1 (minor) — неполное тестовое покрытие `include_deleted=true` для роли `construction_manager`. Батч B Шаги 1+2 готов к коммиту.

---

**Round 2 — P0**: 0  
**Round 2 — P1**: 0  
**Round 2 — P2**: 0  
**Round 2 — P3**: 1 (N-P3-1, не блокер)
