# Backend-dev brief — BUG-003 (P1) us01 migration ADR-0013 marker

**Pattern:** 5 (fan-out). Ветка спринт-1 regression block.
**Автор брифа:** backend-head (через backend-director).
**Спавнит:** Координатор (после sign-off Директора).
**Оценка:** 30-45 мин (хирургическая правка docstring + 2-3 строки комментария).
**Зависимости:** НЕТ. Параллельно с BUG-001 и BUG-005 (FILES_ALLOWED не пересекаются).

---

## Контекст проблемы

Миграция `backend/alembic/versions/2026_04_19_1100_us01_add_company_id.py` (строка 96):

```python
for tbl in _TABLES:
    op.alter_column(tbl, "company_id", nullable=False)
```

Линтер `tools/lint_migrations` (ADR-0013 правило 4) расценивает это как «`alter_column(nullable=False)` без `server_default`» и роняет CI-job `lint-migrations` + тест `test_real_migrations_return_zero_errors`.

**Фактически** миграция **безопасна** — она соответствует safe-migration паттерну ADR-0013 §«Expand → Backfill → Contract»:
- Шаг 1 (строки 69-79): `ADD COLUMN company_id NULL` + FK + индекс.
- Шаг 2 (строки 87-88): `UPDATE SET company_id=1 WHERE company_id IS NULL` — backfill всех существующих строк.
- Шаг 3 (строки 95-96): `ALTER NOT NULL` — безопасно, потому что все строки уже заполнены в шаге 2.

Проблема в том, что линтер статический — он видит `alter_column(nullable=False)` и не различает «голый NOT NULL» от «NOT NULL после backfill в той же миграции». Документированный выход — **`migration-exception` marker** (см. `departments/backend.md` §«Правила для авторов миграций»).

Классификация — BUG-003 в `sprint1-regression-report-2026-04-19.md`.

## Что сделать

Добавить в docstring миграции строку-маркер и короткий комментарий в коде перед циклом ALTER.

**Правка 1: docstring (в конце docstring-блока, после существующей `migration-exception: op_execute` на строке 29).**

Добавить строку:

```
migration-exception: not_null_without_default — ALTER NOT NULL применяется после backfill
  в той же миграции (шаг 2 выше). ADR 0013 safe-migration pattern Expand→Backfill→Contract
  соблюдён: шаг 3 безопасен на любой БД, так как после шага 2 ни одной NULL-строки не остаётся.
  Дефолт 1 (первая компания) не указывается, потому что для новых INSERT'ов значение
  company_id обязательно приходит от middleware (US-02), а не от дефолта БД.
```

**Правка 2: комментарий перед циклом `alter_column(nullable=False)` (строка 95).**

Заменить существующий комментарий:

```python
# ------------------------------------------------------------------
# Шаг 3. Contract — устанавливаем NOT NULL
# ADR 0013: ALTER COLUMN NOT NULL допускается только после backfill
# всех существующих записей.
# ------------------------------------------------------------------
```

на:

```python
# ------------------------------------------------------------------
# Шаг 3. Contract — устанавливаем NOT NULL
# migration-exception: not_null_without_default — см. docstring.
# ADR 0013 safe-migration: шаг 2 (backfill) выше гарантирует 0 NULL-строк.
# server_default не указываем: для новых INSERT company_id приходит от middleware (US-02).
# ------------------------------------------------------------------
```

## FILES_ALLOWED (1 файл)

- `backend/alembic/versions/2026_04_19_1100_us01_add_company_id.py`

## FILES_FORBIDDEN

- Любые другие миграции (включая BUG-001 новую `2026_04_19_1200_us03_rbac_owner_seed.py`)
- Все файлы из BUG-005 (`backend/tests/**`)
- Все файлы в `backend/app/`, `backend/tools/`, `docs/`, CI

## Acceptance criteria

1. `cd backend && python -m tools.lint_migrations alembic/versions/` — 0 ошибок для `2026_04_19_1100_us01_add_company_id.py` (раньше была 1 ошибка «not_null_without_default»).
2. `pytest backend/tests/test_lint_migrations.py::TestRealMigrationsSmoke::test_real_migrations_return_zero_errors -v` — PASS.
3. `cd backend && alembic upgrade head && alembic downgrade -1 && alembic upgrade head` — round-trip ok (логически не должен измениться — правки чисто в комментариях).
4. `ruff check backend/alembic/versions/2026_04_19_1100_us01_add_company_id.py` — чисто.
5. Код функций `upgrade()` / `downgrade()` **не трогается** — только docstring и комментарий.

## Обязательно прочесть

1. `/root/coordinata56/CLAUDE.md` — §«Данные и БД».
2. `/root/coordinata56/docs/agents/departments/backend.md` — §«Правила для авторов миграций», строка про `not_null_without_default` и `<rule>` список.
3. `/root/coordinata56/docs/adr/0013-migrations-evolution-contract.md` — раздел safe-migration pattern.
4. Сам файл миграции `backend/alembic/versions/2026_04_19_1100_us01_add_company_id.py` — особенно docstring (строка 29 — уже есть один `migration-exception: op_execute`, новый добавляется рядом тем же форматом).

## COMMUNICATION_RULES

- Отчёт ≤150 слов: diff docstring + diff комментария, вывод `lint_migrations` до/после, статус `test_lint_migrations.py`.
- НЕ коммитить.
- НЕ трогать FILES_FORBIDDEN.
- НЕ менять логику `upgrade()` / `downgrade()` — только docstring/комментарии.
- При желании ввести `server_default=1` — STOP, не делать без эскалации: это архитектурный выбор (см. в брифе аргумент про middleware US-02), требует согласования Директора.
