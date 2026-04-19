# Backend-dev brief — BUG-001 (P0) owner RBAC permissions follow-up seed

**Pattern:** 5 (fan-out). Ветка спринт-1 regression block.
**Автор брифа:** backend-head (через backend-director).
**Спавнит:** Координатор (после sign-off Директора).
**Оценка:** 1-1.5 ч (миграция ~50 строк SQL + round-trip + 1 smoke-тест).
**Зависимости:** НЕТ. Первый в очереди волны (разблокирует 32 из 35 FAILED тестов).

---

## Контекст проблемы

Миграция `backend/alembic/versions/2026_04_19_1000_us03_rbac_defaults_seed.py` (head-3) засеяла `role_permissions` для ролей `admin`, `director`, `accountant`, `foreman` — **owner пропущен**. Роль `owner` создана раньше (в ac27c3e125c8), но ни одной записи в `role_permissions` не получила. Результат: `owner` получает 403 на read собственных ресурсов (house/stage/budget_plan/budget_category/house_type/material_purchase). 32 теста в `tests/integration/api/test_multi_company_isolation.py` FAIL.

Классификация — `REGRESSION_SPRINT1`, BUG-001 в отчёте `docs/pods/cottage-platform/quality/sprint1-regression-report-2026-04-19.md`.

## Почему нельзя править уже применённую миграцию

ADR-0013 immutability: миграция `us03_rbac_defaults_seed` уже применена в dev и уйдёт в боевую БД. Правка её `upgrade()` создаст расхождение hash'а — round-trip тест сломается, `alembic_version` на боевой не совпадёт с файлом. **Решение — follow-up миграция**, добавляющая permissions для owner отдельным шагом.

## Что сделать

Создать новую миграцию:

**Файл:** `backend/alembic/versions/2026_04_19_1200_us03_rbac_owner_seed.py`

- `revision = "us03_rbac_owner_seed"`
- `down_revision = "us01_add_company_id"` (текущий head-1, следующий после US-01)
- `upgrade()`:
  1. `INSERT INTO role_permissions (role_id, permission_id, pod_id) SELECT r.id, p.id, NULL FROM roles r, permissions p WHERE r.code = 'owner' AND NOT EXISTS (SELECT 1 FROM role_permissions rp2 WHERE rp2.role_id = r.id AND rp2.permission_id = p.id AND rp2.pod_id IS NULL)`
  2. Одна строка — owner получает **все** permissions (full-access эквивалент admin). Идемпотентно через NOT EXISTS.
- `downgrade()`: `DELETE FROM role_permissions WHERE role_id = (SELECT id FROM roles WHERE code = 'owner')` — осторожно, удаляет и ранее существовавшие permissions owner'а (их не было, поэтому безопасно; комментарий в docstring пояснить).
- `# migration-exception: op_execute — seed owner full-access permissions US-03 follow-up (ADR 0011 §2.2, BUG-001 fix)`

## FILES_ALLOWED (без overlap)

- `backend/alembic/versions/2026_04_19_1200_us03_rbac_owner_seed.py` (новый файл)

## FILES_FORBIDDEN

- Любые существующие миграции (`2026_04_19_1000_*.py`, `2026_04_19_1100_*.py`)
- Любые файлы в `backend/app/`, `backend/tests/`
- Любые файлы BUG-005 (`backend/tests/**/*.py`)
- Любые файлы BUG-003 (`backend/alembic/versions/2026_04_19_1100_us01_add_company_id.py`)

## Acceptance criteria

1. `cd backend && alembic upgrade head` — проходит.
2. `cd backend && alembic downgrade -1 && alembic upgrade head` — round-trip чистый.
3. `cd backend && python -m tools.lint_migrations alembic/versions/` — 0 ошибок.
4. После миграции — 32 FAILED теста из `test_multi_company_isolation.py` становятся PASS (owner читает свои ресурсы). Проверить руками: `pytest backend/tests/integration/api/test_multi_company_isolation.py -v` — все 32 теста PASS, но возможны 3 остаточных FAIL по BUG-002 (OptionCategory.FINISH) — их не трогаем, это следующая волна.
5. `ruff check backend/alembic/versions/2026_04_19_1200_us03_rbac_owner_seed.py` — чисто.

## Обязательно прочесть

1. `/root/coordinata56/CLAUDE.md` — раздел «Данные и БД», «Секреты и тесты».
2. `/root/coordinata56/docs/agents/departments/backend.md` — §«Правила для авторов миграций», §«§ Fan-out orchestration (Pattern 5)».
3. `/root/coordinata56/docs/adr/0013-migrations-evolution-contract.md` — пункт про immutability и expand/contract.
4. Эталон — существующий `backend/alembic/versions/2026_04_19_1000_us03_rbac_defaults_seed.py` (шаг 4.1 admin — всё по той же схеме, только заменить `'admin'` на `'owner'`).

## COMMUNICATION_RULES

- Отчёт ≤200 слов: что сделал, round-trip ok/fail, pytest на `test_multi_company_isolation.py` (до/после).
- НЕ коммитить.
- НЕ трогать FILES_FORBIDDEN.
- При блокерах — STOP, сообщить backend-head (через Координатора).
