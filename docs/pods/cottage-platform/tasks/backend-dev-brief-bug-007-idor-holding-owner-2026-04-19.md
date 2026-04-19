# Дев-бриф: BUG-007 P0 SECURITY — IDOR в CompanyScopedService для holding_owner

**Роль:** backend-dev
**Приоритет:** P0 SECURITY (cross-company data leak)
**Оценка:** 2–3 часа
**Дата:** 2026-04-19
**Источник:** найдено при верификации BUG-001 fix; 9 тестов `test_holding_owner_scoped_by_company_id_header` FAIL в `backend/tests/integration/api/test_multi_company_isolation.py`.

---

## ultrathink

## Обязательно прочитать перед стартом

1. `/root/coordinata56/CLAUDE.md`
2. `/root/coordinata56/docs/agents/departments/backend.md` — правила отдела, ADR-gate A.1–A.5 в чек-листе самопроверки
3. `/root/coordinata56/docs/adr/0011-rbac-v2.md` §1.3 (company scoping для holding_owner)
4. `backend/app/services/company_scoped.py` — источник бага
5. `backend/app/api/deps.py` — `get_current_user` (как формируется `UserContext.company_id` для holding_owner)
6. `backend/tests/integration/api/test_multi_company_isolation.py` строки 500–628 — два релевантных сценария:
   - test_holding_owner_sees_all_companies (без header → видит всё — **должен продолжать PASS**)
   - test_holding_owner_scoped_by_company_id_header (с header → видит только выбранную — **9 тестов FAIL, нужно починить**)

## Симптом

holding_owner (`is_holding_owner=True`) делает запрос с заголовком `X-Company-ID: 2`. Ожидание: сервис фильтрует по `company_id=2`. Факт: сервис игнорирует фильтр и возвращает записи ВСЕХ компаний. 9 параметризованных тестов FAIL.

## Root-cause (подтверждён Директором)

Файл: `backend/app/services/company_scoped.py`, метод `_scoped_query_conditions`, строки 72–73:

```python
if user_context.is_holding_owner:
    return []
```

Безусловный bypass фильтра для holding_owner независимо от `user_context.company_id`. При этом `deps.py:144-146` корректно записывает `x_company_id` в `active_company_id`:

```python
if is_holding_owner:
    active_company_id = x_company_id  # правильно
```

То есть `company_id` в контексте есть, но сервис его не использует. Это и есть IDOR: trivial request без header даёт утечку всех компаний. С header — должен фильтровать, но не фильтрует.

## Fix — требуемая логика

В `_scoped_query_conditions`:

1. **holding_owner + `company_id` задан** (header передан) → `[model.company_id == user_context.company_id]` (фильтровать по указанной компании).
2. **holding_owner + `company_id is None`** (header не передан) → `[]` (bypass, смотрит всё; сохраняем сценарий 4 из test_multi_company_isolation).
3. **обычный user** → прежнее поведение: `[model.company_id == user_context.company_id]`.

**Важно.** holding_owner — тот, кто может поставить в header **любое** company_id (включая не из `company_ids`), и это разрешено. Проверка на принадлежность company_ids для holding_owner НЕ применяется (уже так в `deps.py` — это корректно, не менять). Если в БД таких записей нет — вернётся пустой список (это корректно, не 403/404 со стороны сервиса; FastAPI вернёт 200 с `items:[]`).

## FILES_ALLOWED

- `backend/app/services/company_scoped.py` (основной fix, ~5 LOC)

## FILES_FORBIDDEN

- `backend/app/api/deps.py` — логика формирования `active_company_id` для holding_owner уже корректна, не трогать.
- `backend/tests/integration/api/test_multi_company_isolation.py` — тесты эталонные, не править; они — acceptance criteria.
- Любые middleware, роутеры, другие сервисы. Если возникает искушение править где-то ещё — STOP, эскалация Head.
- Миграции БД — не требуются.

## COMMUNICATION_RULES

- Не вызывать других субагентов; только self-check и отчёт Head.
- Не коммитить.
- `git add` только `backend/app/services/company_scoped.py`.
- Отчёт Head ≤ 200 слов: diff (строки), результат pytest (target suite), ruff clean, подтверждение ADR-gate A.1–A.5.

## Acceptance criteria

1. `pytest backend/tests/integration/api/test_multi_company_isolation.py::test_holding_owner_scoped_by_company_id_header -v` — 9/9 PASS.
2. `pytest backend/tests/integration/api/test_multi_company_isolation.py::test_holding_owner_sees_all_companies -v` — 9/9 PASS (регрессия сценария 4 недопустима).
3. `pytest backend/tests/integration/api/test_multi_company_isolation.py -v` — весь файл PASS.
4. `pytest backend/tests/test_company_scope.py backend/tests/test_jwt_company_middleware.py backend/tests/test_pr2_rbac_integration.py -v` — PASS (смежные suite, проверка на отсутствие регрессий).
5. `ruff check backend/app/services/company_scoped.py` — 0 ошибок.
6. `python -m tools.check_sql_layer app/services` — layer-check PASS (не добавляй select/execute в сервис; только `ColumnElement[bool]`).

## Negative-test (добавлять НЕ нужно — только verify существующих)

Сценарии 400 (holding_owner без header при multi-company в company_ids) и 404 (несуществующий ресурс) уже покрыты в других тестах isolation suite. Твоя задача — **не ломать** их. Если при reg-прогоне что-то из негативных сценариев упало — эскалация Head, не чини наугад.

## Скилы / паттерны

- Minimal-diff хирургия: один `if`, три строки кода.
- Не рефакторить метод, не добавлять параметров в сигнатуру.
- Не менять публичный API `UserContext` или `CompanyScopedService`.

## ADR-gate (A.1–A.5) — self-check

- A.1 — нет литералов секретов (не применимо, only сервис-логика).
- A.2 — SQL только в репозиториях. Fix возвращает `ColumnElement[bool]` — это предикат, не запрос. OK.
- A.3 — RBAC: не трогаем.
- A.4 — формат ошибок/пагинации: не трогаем.
- A.5 — audit: write-операций в этом fix нет.

## Если возникает неоднозначность

- Намёки на редизайн `UserContext` / нужен новый атрибут → STOP, эскалация backend-head → backend-director.
- Падение negative-тестов из соседних сценариев → STOP, эскалация.
- Сомнение «может, baseline fix в deps.py?» → НЕТ. deps.py правильно формирует `company_id`; баг строго в `company_scoped.py`.

## Definition of Done

- Acceptance criteria 1–6 PASS.
- Diff ≤ 10 LOC в `backend/app/services/company_scoped.py`.
- Отчёт Head отправлен.
- `git status` показывает ровно один изменённый файл.
