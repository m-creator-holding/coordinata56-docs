# Backend-dev brief — BUG-005 (P1, scope P0) test_db_url password sweep

**Pattern:** 5 (fan-out). Ветка спринт-1 regression block.
**Автор брифа:** backend-head (через backend-director).
**Спавнит:** Координатор (после sign-off Директора).
**Оценка:** 1.5-2 ч (механический sweep 12 файлов + verify pytest-прогоном).
**Зависимости:** НЕТ. Параллельно с BUG-001 и BUG-003 (FILES_ALLOWED не пересекаются).

---

## Контекст проблемы

Коммит `ff209da` (Sprint 1 kick-off) изменил пароль тестовой БД в корневом `backend/conftest.py` с `change_me` на `change_me_please_to_strong_password`. Но 12 тестовых файлов **хардкодят старый литерал** `change_me@localhost:5433/coordinata56_test` как fallback `os.environ.get("TEST_DATABASE_URL", "<хардкод>")`. Когда переменная окружения не задана (CI, dev-машины без `.env`), создаётся engine с неверным паролем — **347 тестов падают в ERROR на setup**, не доходя до запуска.

Классификация — BUG-005 в `sprint1-regression-report-2026-04-19.md`. 347 ERROR = 47% всей сьюты.

## Корневое решение — централизация

Вместо правки 12 литералов по отдельности (хрупко, повторится) — вынести `TEST_DB_URL` в **одно место**: корневой `backend/conftest.py` уже содержит эталонный URL в переменной `_TEST_DATABASE_URL` (строка 43-46). Импорт из тестовых файлов — невозможен (pytest conftest — не модуль для импорта). Правильный паттерн — **session-scope fixture** `test_db_url` в `backend/conftest.py`, которую тесты используют через параметр.

Но это инвазивно: 12 файлов используют `TEST_DB_URL` как module-level константу (строки `_test_engine = create_async_engine(TEST_DB_URL, ...)` на module scope). Поэтому **компромисс**:

**Вариант Б (хирургический, выбранный):** Во всех 12 файлах заменить **только fallback-строку** с `change_me` на `change_me_please_to_strong_password`. Механически, один `sed`-паттерн на файл, ничего больше.

## Файлы (ровно 12, FILES_ALLOWED)

1. `backend/tests/test_round_trip.py` (строка ~37)
2. `backend/tests/test_option_catalog.py` (строка ~30)
3. `backend/tests/test_houses.py` (строка ~40)
4. `backend/tests/test_stages.py` (строка ~35)
5. `backend/tests/test_projects.py` (строка ~43, плюс комментарий на ~38)
6. `backend/tests/test_house_types.py` (строка ~30)
7. `backend/tests/test_batch_a_coverage.py` (строка ~35)
8. `backend/tests/api/test_roles_api.py` (строка ~31)
9. `backend/tests/api/test_permissions_api.py` (строка ~30)
10. `backend/tests/api/test_user_roles_api.py` (строка ~32)
11. `backend/tests/repositories/test_user_repository.py` (строка ~26)
12. `backend/tests/repositories/test_user_company_role_repository.py` (строка ~27)

**Паттерн замены (одинаковый во всех 12 файлах):**

```python
# было
"postgresql+psycopg://coordinata:change_me@localhost:5433/coordinata56_test",
# стало
"postgresql+psycopg://coordinata:change_me_please_to_strong_password@localhost:5433/coordinata56_test",
```

В `test_projects.py` — также актуализировать комментарий «Дефолтный URL не содержит осмысленного пароля...» (строка ~38) на «Дефолтный URL синхронизирован с корневым conftest.py. Пароль `change_me_please_to_strong_password` не является секретом: это dev-dev-БД на localhost:5433, недоступная снаружи. Правило CLAUDE.md §«Секреты и тесты» соблюдено — это не литерал production-пароля.»

## FILES_ALLOWED (12 файлов)

Список выше — ровно 12 файлов, без overlap с BUG-001 и BUG-003.

## FILES_FORBIDDEN

- `backend/conftest.py` (корневой — уже корректный, не трогать)
- `backend/alembic/versions/**` (принадлежит BUG-001/BUG-003)
- `backend/app/**` (код приложения)
- Все остальные test-файлы, **не** вошедшие в список 12

## Acceptance criteria

1. `grep -r "change_me@localhost" backend/tests/` — **0 вхождений** (все 12 заменены).
2. `grep -r "change_me_please_to_strong_password" backend/tests/` — минимум 20 вхождений (было 7, стало ≥19).
3. `pytest backend/tests/ --collect-only 2>&1 | grep -c ERROR` — 0 (коллекция чистая).
4. `pytest backend/tests/ -x --ignore=backend/tests/integration/api/test_multi_company_isolation.py 2>&1 | tail -5` — 0 ERROR на setup (регулярные FAIL допустимы — их чинят BUG-001/003, но 347 ERROR должны исчезнуть).
5. `ruff check backend/tests/` — чисто.

## Обязательно прочесть

1. `/root/coordinata56/CLAUDE.md` — §«Секреты и тесты».
2. `/root/coordinata56/docs/agents/departments/backend.md` — правило 7 «Никаких литералов секретов».
3. Отчёт `docs/pods/cottage-platform/quality/sprint1-regression-report-2026-04-19.md` (раздел BUG-005).

## COMMUNICATION_RULES

- Отчёт ≤200 слов: список 12 изменённых файлов (diff stat LOC), grep-вывод acceptance #1 и #2, pytest collect-only exit code.
- НЕ коммитить.
- НЕ трогать FILES_FORBIDDEN.
- НЕ рефакторить код тестов за пределами замены literal'а пароля (скоуп узкий, строго sweep).
- При overlap-конфликте (видите staged-diff от BUG-001/003) — STOP, не stage'ить, сообщить backend-head.
