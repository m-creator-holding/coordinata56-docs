# Бриф для backend-head: B-1 — генератор `make scaffold-crud ENTITY=<name>`

- **Дата:** 2026-04-18
- **Автор:** backend-director
- **Получатель:** backend-head
- **Исполнитель (рекомендуемый):** backend-dev-2 (свежий, без контекста H-2/audit)
- **Приоритет:** P2 (Top-5 quick-win RFC-008)
- **Оценка:** 1 день

---

## Контекст

В M-OS-1 прогнозируется ~8 новых CRUD-сущностей (companies, users, roles, permissions, houses, house_types, house_configurations, audit уже заложены — остаются permits_packages, manufacturing_orders, notifications_settings и пр.). Текущий ручной путь по чек-листу `departments/backend.md §«Шаблон промпта для backend-dev (CRUD-сущность)»` занимает 15–20 минут на шаблонную часть (5 файлов + регистрация + миграция). Генератор экономит 2+ часа на фазу M-OS-1 и гарантирует единообразие структуры.

---

## Что конкретно сделать

1. **Написать генератор** `backend/tools/scaffold_crud.py` и таргет `scaffold-crud` в `Makefile` (или `backend/Makefile`, уточнить с backend-head, где живёт make-логика).
2. **Вход:** `make scaffold-crud ENTITY=permit_package` → имя в snake_case. Генератор сам выводит PascalCase (`PermitPackage`), plural (`permit_packages`) и camelCase для клиент-схем при необходимости. Если plural не по правилу (например, company→companies) — параметр `PLURAL=companies`.
3. **Выход — создать файлы по эталону Project (`backend/app/services/project.py`):**
   - `backend/app/models/<entity>.py` — SQLAlchemy-модель с `id`, `created_at`, `updated_at`, `SoftDeleteMixin`-плейсхолдером (закомментированным, чтобы было просто раскомментировать), placeholder-поле `name: Mapped[str]`.
   - `backend/app/schemas/<entity>.py` — `<Entity>Create`, `<Entity>Update`, `<Entity>Read` (Pydantic v2, `ConfigDict(from_attributes=True)`).
   - `backend/app/repositories/<entity>.py` — `<Entity>Repository(BaseRepository[<Entity>])` с пустым переопределением `list(extra_conditions=...)` (заглушка из BaseRepository).
   - `backend/app/services/<entity>.py` — `<Entity>Service` (наследование `CompanyScopedService` **только** если ENTITY — company-scoped; флаг `--scoped`/`SCOPED=1`).
   - `backend/app/api/<entities>.py` — 5 эндпоинтов (GET list, GET by id, POST, PATCH, DELETE). RBAC через `require_permission` с placeholder-разрешениями (`<entity>.read`, `<entity>.write`), **закомментировать с TODO-note** «заполнить реальные permission-codes перед merge, см. ADR 0011 §2.3».
   - `backend/tests/unit/services/test_<entity>_service.py` — скелет на 4 теста (create, get, update, delete) с `pytest.mark.skip("scaffold stub — заполнить бизнес-правилами")`.
   - `backend/tests/integration/api/test_<entities>.py` — скелет на 5 тестов (happy + 404 + 403 + 422 + аудит) с `pytest.mark.skip("scaffold stub")`.
   - `backend/alembic/versions/<timestamp>_add_<entity>.py` — миграция-шаблон с `op.create_table(...)` по модели; **никаких drop/alter/rename** (ADR 0013).
4. **Регистрация роутера:** автоматически добавить `from app.api.<entities> import router as <entity>_router` + `app.include_router(<entity>_router)` в `backend/app/main.py`. Если импорт уже есть — не дублировать.
5. **Идемпотентность:** повторный запуск для существующего ENTITY → exit 1 с сообщением «already exists, use `--force` to overwrite» (а `--force` — не реализовывать; защита от ног-в-спусковом-крючке).
6. **Самопроверка:** после scaffold `ruff check backend/app` — 0 ошибок; `pytest backend/tests` — зелёно (скелеты skip'нуты, не падают).
7. **Юнит-тест генератора:** `backend/tests/unit/tools/test_scaffold_crud.py` — 3 теста: (а) генерит файлы в нужных местах на фейковом ENTITY `_fixture_entity`; (б) повторный запуск exit 1; (в) snake→PascalCase конверсия корректна. После теста фикстурные файлы удаляются.

---

## Критерии приёмки (DoD)

- [ ] `make scaffold-crud ENTITY=fixture_entity` создаёт все 8 файлов и правит `main.py`.
- [ ] `ruff check backend/app` + `ruff check backend/tests` — 0 ошибок после scaffold.
- [ ] `pytest backend/tests/unit/tools/test_scaffold_crud.py` — зелёно.
- [ ] Повторный запуск → exit 1 с понятным сообщением.
- [ ] Регистрация роутера в `main.py` идемпотентна.
- [ ] README в `backend/tools/README.md` (или новый) с примером использования и списком полей шаблона.
- [ ] Запрещённые операции ADR 0013 не появляются в сгенерированной миграции — проверка локально `python -m tools.lint_migrations alembic/versions/` зелёно.

---

## FILES_ALLOWED

- `backend/tools/scaffold_crud.py`
- `backend/tools/README.md`
- `Makefile` (корень репо) или `backend/Makefile` (уточнить с head).
- `backend/tools/templates/*.j2` (если выбран Jinja2; альтернатива — строковые шаблоны в Python).
- `backend/tests/unit/tools/test_scaffold_crud.py`
- `backend/tests/unit/tools/__init__.py` (если нужен)

## FILES_FORBIDDEN

- `backend/app/**` — генератор **правит** `main.py`, но по готовому паттерну (patch через анкер-комментарий `# <scaffold-crud routers>`). Сам генератор НЕ содержит хардкода бизнес-моделей.
- `scripts/hooks/**` (это задача A)
- `.github/workflows/**` (это задача C)
- `docs/adr/**`, `docs/agents/**`

## COMMUNICATION_RULES

- Не коммитить.
- Если шаблон модели требует решения по полям, которых нет в эталоне Project (например, какие индексы по умолчанию) — эскалировать backend-head, не изобретать.
- Не добавлять в шаблон `require_role` (deprecated по v1.3 чек-листа A.3) — только `require_permission`-плейсхолдер.
- Отчёт ≤200 слов: что сгенерировал, тесты, какие решения принял по шаблонам.

## Обязательно к прочтению

- `/root/coordinata56/CLAUDE.md`
- `/root/coordinata56/docs/agents/departments/backend.md` — §Правила 1–11, §Шаблон промпта CRUD, чек-лист
- `/root/coordinata56/docs/adr/0004-backend-layering.md`, `0005-error-format.md`, `0006-pagination.md`, `0007-audit-trail.md`, `0011-rbac-v2.md`, `0013-migrations-evolution-contract.md`
- `backend/app/services/project.py` — эталон-Service
- `backend/app/api/projects.py` (если есть) — эталон-Router
- `backend/app/repositories/base.py` — BaseRepository

Scope-vs-ADR: verified (ADR 0004 layering, 0011 RBAC, 0013 migrations); gaps: none.
