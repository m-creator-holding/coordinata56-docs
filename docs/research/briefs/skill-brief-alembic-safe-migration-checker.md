# Бриф для ri-analyst — skill `alembic-safe-migration-checker`

**Автор брифа:** ri-director
**Дата:** 2026-04-19
**Бюджет Analyst:** до 4 часов (регламент R&I §«Бюджет внимания»)
**Финальный артефакт:** `~/.claude/skills/alembic-safe-migration-checker/SKILL.md` + эталонный прогон на живой миграции (`versions/20260418_0001_multi_company_foundation.py` или ближайшая US-01 миграция Sprint 1).

---

## Почему этот скил сейчас

Sprint 1 M-OS-1.1A: US-01 (backend-dev-1 + db-engineer) прибивает `company_id` к 12 таблицам через миграцию. ADR-0013 «Expand/contract» запрещает в одном шаге: `DROP COLUMN`, `RENAME COLUMN`, `NOT NULL без DEFAULT`, `ALTER TYPE` сужающий. У нас уже есть `backend/tools/lint_migrations.py` (CI-линтер), но он проверяет сами миграции, а не рассуждения автора. Во время сессии Claude Code (backend-dev) сейчас ничего не подсказывает разработчику *до* запуска CI, что его миграция нарушает ADR-0013 — он узнаёт об этом, только когда CI красный (или когда reviewer ловит). Скил закрывает этот gap: Claude Code при создании/редактировании миграции прогоняет её через чек-лист ADR-0013 прежде, чем вернуть код.

Прямой эффект на Sprint 1: US-01 попадает в PR без раунда «CI сломался на lint-migrations» — экономия 1 раунда reviewer × 12 таблиц.

## Что скил должен делать (scope)

1. **Триггер.** User-invocable=false, auto-invoke при работе в `backend/alembic/versions/*.py` или при генерации новой миграции через `alembic revision`.
2. **Вход.** Путь к файлу миграции (`backend/alembic/versions/<stamp>_<slug>.py`).
3. **Шаги (в SKILL.md).**
   - Шаг 1: распарсить `def upgrade()` и `def downgrade()`. Перечислить все `op.*` вызовы.
   - Шаг 2: сверка с allow/deny-таблицей ADR-0013:
     - DENY (P0): `op.drop_column`, `op.alter_column(... new_column_name=...)`, `op.alter_column(..., nullable=False)` без `server_default`, `op.execute("ALTER TYPE ... DROP VALUE")`.
     - WARN (P1): `op.add_column(..., nullable=False)` без server_default — требует expand/migrate/contract.
     - ALLOW: `op.add_column(nullable=True)`, `op.create_table`, `op.create_index`, `op.add_column` с server_default.
   - Шаг 3: проверка симметрии upgrade/downgrade — каждый `create_*` в upgrade должен иметь `drop_*` в downgrade (ADR-0013 «data-destructive downgrade только для non-production data»).
   - Шаг 4: проверка что новая FK-колонка имеет `index=True` (best practice, не правило ADR — WARN).
   - Шаг 5: вывод: PASS / WARN (список замечаний) / FAIL (список запретов с цитатой строки ADR-0013).
4. **Выход.** Структурированный отчёт (markdown), позволяющий Claude Code либо отредактировать миграцию сразу, либо передать отчёт в комментарий к PR.

## Что скил НЕ делает

- Не запускает сам `alembic upgrade/downgrade` (это CI делает).
- Не валидирует data-layer (это задача `check_sql_layer.py` + отдельный скил B-2).
- Не проверяет соответствие модели ORM и миграции (это `alembic --autogenerate`).
- Не дублирует `backend/tools/lint_migrations.py` — последний запускается в CI на уровне синтаксиса AST. Скил работает на уровне Claude Code-сессии и объясняет *почему* правило.

## Источники для Analyst

- `docs/adr/0013-migrations-evolution-contract.md` (обязательно; раздел «Решение» — источник списка запретов).
- `backend/tools/lint_migrations.py` (эталон правил, не повторять — извлечь semantics).
- `CLAUDE.md` §«Данные и БД» — round-trip правило.
- `backend/alembic/versions/20260418_0001_multi_company_foundation.py` — живой пример для валидации скила.
- `~/.claude/skills/adr-compliance-checker/SKILL.md` и `~/.claude/skills/fz152-pd-checker/SKILL.md` — шаблон структуры SKILL.md в проекте (заголовок, секции «Когда применять», «Шаги», «Выход»).

## Ограничения

- Не менять регламент backend отдела — это governance-director через комиссию.
- Не коммитить — это Координатор.
- Не писать CI-код — только SKILL.md + 1 эталонный прогон для валидации.

## DoD брифа

1. `~/.claude/skills/alembic-safe-migration-checker/SKILL.md` создан в том же стиле что `fz152-pd-checker`.
2. На живой US-01 миграции скил выдаёт корректный PASS/WARN/FAIL (Analyst приложит прогон в отчёт).
3. Отчёт Analyst'а Координатору: ≤500 слов, формат «что сделано / как валидировано / открытые вопросы».

## Метрика успеха после adopt

За 2 недели работы US-01..US-15: 0 CI-раундов на `lint-migrations` по P0-нарушениям ADR-0013 в миграциях, написанных с включённым скилом.
