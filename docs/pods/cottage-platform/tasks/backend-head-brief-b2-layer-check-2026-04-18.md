# Бриф для backend-head: B-2 — CI-job `layer-check` (SQL только в репозиториях)

- **Дата:** 2026-04-18
- **Автор:** backend-director
- **Получатель:** backend-head
- **Исполнитель (рекомендуемый):** backend-dev-3 (свежий, без контекста H-2/audit/scaffold)
- **Приоритет:** P2 (Top-5 quick-win RFC-008)
- **Оценка:** 0.5 дня

---

## Контекст

ADR 0004 (layering) + Amendment 2026-04-18 фиксирует: SQL-вызовы (`db.execute(select(…))`, `session.get`, `COUNT`, `offset/limit`, raw SQL) разрешены **только** в `backend/app/repositories/`. Сервисы могут передавать типизированные предикаты `ColumnElement[bool]` через `extra_conditions=`, но не делать сами запросы.

Повторяющийся дефект Батча A (P0-1 step 4 round 1): сервис делал `select(...)` напрямую. Ручное ревью не всегда ловит. Нужен CI-gate, блокирующий merge при нарушении.

---

## Что конкретно сделать

1. **Написать скрипт** `backend/tools/check_sql_layer.py`:
   - Проходит по всем `.py` файлам в `backend/app/services/`, `backend/app/api/`, `backend/tests/unit/services/`, `backend/tests/unit/api/`, `backend/tests/integration/api/`.
   - Парсит AST (модуль `ast`, не regex — regex ловит в комментариях и строках).
   - **Запрещённые паттерны:**
     - Вызовы `select(...)`, `insert(...)`, `update(...)`, `delete(...)` из `sqlalchemy`.
     - Вызовы `session.execute(...)`, `session.get(...)`, `session.scalar(...)`, `session.scalars(...)`, `db.execute(...)`, `db.get(...)`, `db.scalar(...)`, `db.scalars(...)`.
     - Вызовы `.subquery()`, `exists()` при явном импорте из `sqlalchemy`.
     - Импорты `from sqlalchemy import select/insert/update/delete` в `services/`, `api/`.
   - **Разрешено в сервисах:** типизированные предикаты — выражения `ColumnElement[bool]` вида `Model.field == value`, `Model.field.in_(...)`. Эти не ловим (это не вызовы select/execute — это boolean-выражения).
   - **Разрешено в тестах (unit services/api):** моки репозиториев с `AsyncMock`/`MagicMock` — не содержат SQL-вызовов. Если тест использует реальную сессию (fixture `db_session`) — это разрешено, но проверяется отдельно: вызовы db.execute в тестах сервисов — допустимы только внутри фикстур `conftest.py`. Проще правило: тесты проверяем **только** на импорт `select/insert/update/delete` из sqlalchemy (если нужен — значит, тест дублирует репо-логику, это запах). Если head/dev решит что тесты исключить полностью — согласовать с director.
2. **Вывод:** для каждого нарушения — `<file>:<line>: <message> (<rule-code>)`. Exit 0 если нарушений 0, exit 1 иначе. Формат понятный для CI-лог-парсера.
3. **Исключения (белый список):** поддержать файл `backend/tools/layer_check_allowlist.txt` с glob-паттернами и кодом правила. Пример: `app/services/migration_runner.py:raw_sql_execute`. Пустой по умолчанию — сейчас ни один файл не должен попадать в allowlist. Добавления — через явное согласование директора (как сейчас `migration-exception` в Alembic).
4. **Юнит-тесты скрипта** `backend/tests/unit/tools/test_check_sql_layer.py`:
   - Фикстура «плохой» файл сервиса с `db.execute(select(...))` → exit 1, нарушение в выводе.
   - Фикстура «хороший» файл сервиса с `extra_conditions=(Model.status == "x",)` → exit 0.
   - Фикстура репозиторий с `select(...)` → exit 0 (репозиториям разрешено).
   - Фикстура файл в allowlist → exit 0.
   - ≥5 тестов, покрытие ≥85%.
5. **CI-job** в `.github/workflows/ci.yml`:
   - Имя: `layer-check`.
   - Триггер: `push` и `pull_request` на `main` + любые.
   - Стартует после lint, параллельно с существующими `lint-migrations`/`round-trip`.
   - Команда: `cd backend && python -m tools.check_sql_layer app/services app/api tests/unit/services tests/unit/api tests/integration/api`.
   - Fail job на exit != 0. Job required для merge в main (согласовать с infra-director/governance отдельной задачей — в этом бриф не входит).
6. **Документация:** добавить в `docs/agents/departments/backend.md` §«Правила работы» ссылку на новый CI-job (пункт «layer-check CI job блокирует merge при SQL-вызовах вне repositories»).

---

## Критерии приёмки (DoD)

- [ ] `python -m tools.check_sql_layer app/services app/api tests/unit/services tests/unit/api tests/integration/api` на текущем коде — exit 0. Если нет — зафиксировать существующие нарушения и **эскалировать** (починка не в этом бриф).
- [ ] Юнит-тесты пройдены (`pytest backend/tests/unit/tools/test_check_sql_layer.py`), покрытие ≥85%.
- [ ] CI-job `layer-check` виден в GitHub Actions, стартует на PR.
- [ ] Создан «плохой» PR (синтетический) — job fail. Создан «хороший» PR — job pass. Артефакт — ссылки на два прогона в отчёте.
- [ ] `departments/backend.md` обновлён (добавить пункт в §Правила работы, обновить §История версий).
- [ ] `ruff check backend/tools/check_sql_layer.py backend/tests/unit/tools/test_check_sql_layer.py` — 0 ошибок.

---

## FILES_ALLOWED

- `backend/tools/check_sql_layer.py`
- `backend/tools/layer_check_allowlist.txt` (пустой, с комментарием)
- `backend/tests/unit/tools/test_check_sql_layer.py`
- `backend/tests/unit/tools/__init__.py`
- `.github/workflows/ci.yml` — добавить job, не менять существующие
- `docs/agents/departments/backend.md` — обновление §Правила работы + §История версий

## FILES_FORBIDDEN

- `backend/app/services/**`, `backend/app/api/**`, `backend/app/repositories/**` — если проверка обнаружила нарушения, починка отдельной задачей. В этом бриф **только** построение gate.
- `scripts/hooks/**` (задача A)
- `backend/tools/scaffold_crud.py` (задача B)

## COMMUNICATION_RULES

- Не коммитить.
- Если на текущем коде есть >0 нарушений — **остановиться и эскалировать** backend-head перед включением CI-job (иначе сломаем main).
- В шаблоне фикстур test_check_sql_layer.py не литералить пароли — `secrets.token_urlsafe(16)` при необходимости, хотя для layer-check проверки на SQL пароли не нужны вообще.
- Отчёт ≤200 слов: сколько файлов проверено, сколько нарушений найдено (ожидание: 0), ссылки на прогоны CI.

## Обязательно к прочтению

- `/root/coordinata56/CLAUDE.md` — §Данные и БД, §Код
- `/root/coordinata56/docs/agents/departments/backend.md` v1.3 — §Правила работы п.1, §Правила для авторов миграций (как пример stylistic для другого линтера)
- `/root/coordinata56/docs/adr/0004-backend-layering.md` + Amendment 2026-04-18
- `backend/tools/lint_migrations.py` — эталон аналогичного CI-линтера (структура CLI, allowlist, формат вывода)
- `.github/workflows/ci.yml` — существующие jobs `lint-migrations`, `round-trip`

Scope-vs-ADR: verified (ADR 0004 + Amendment 2026-04-18); gaps: none.
