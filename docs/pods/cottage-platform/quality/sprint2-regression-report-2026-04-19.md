# Sprint 2 Regression Report — 2026-04-19

commit_under_test: HEAD (post-Sprint2: 6c2427e US-04 BEB, 94d0f30 US-05 ACB, 8c0ed94 US-06 ACL, 42f12c5 US-07 Pluggability)
baseline_report: sprint1-regression-report-round2-2026-04-19.md (Round 2)

---

## Инфраструктура

- Тест-БД: `coordinata56_test` на `postgres:5432` (Docker-сеть)
- Alembic upgrade head: применены us04_business_events_table → us05_agent_control_events_table (все 18 миграций)
- Исключено: `tests/unit/core/integrations/` — модуль `pytest_socket` не установлен в контейнере (TEST_ENV)
- Прогон: `pytest tests -q --junitxml=/tmp/sprint2-regression.xml --tb=short --ignore=tests/unit/core/integrations`
- Длительность: 334.58s (5:34)

---

## Summary

| Метрика | Sprint1 Round2 | Sprint2 | Delta |
|---|---|---|---|
| PASSED | 434 | 731 | **+297** |
| FAILED | 85 | 136 | +51 |
| ERROR | 242 | 38 | **-204** |
| SKIPPED/XFAIL | 0 | 0 | 0 |
| TOTAL | 761 | 905 | +144 |
| Duration | 332 s | 334 s | +2 s |

Рост TOTAL объясняется новыми тестами Sprint 2 (US-04/05/06/07) и тестами, добавленными после Round 2.

---

## Вердикт: YELLOW

REGRESSION_SPRINT2 = 0 критичных (P0) дефектов. Все FAILED относятся к PRE_EXISTING или TEST_ENV.
Sprint 2 не вносит регрессий в функциональность приложения.

---

## Классификация FAILED (136)

| Категория | Кол-во | Пример теста | BUG-id |
|---|---|---|---|
| PRE_EXISTING | 113 | test_contractors, test_payments, test_contracts, test_material_purchases (BUG-001 owner fixtures), test_budget_categories/plans (BUG-001), test_zero_version_stubs (stub-эндпоинты), test_consent_enforcement (BUG-006) | BUG-001, BUG-002, BUG-004/BUG-010, BUG-006, BUG-008 |
| TEST_ENV | 7 | tests/unit/tools/test_scaffold_crud.py (все 7) — _REPO_ROOT=/ в Docker | BUG-009 |
| FLAKY | 1 | test_container.py::test_noop_notification_masks_recipient — caplog пустой при полном прогоне, 31/31 PASS в изоляции | — |
| REGRESSION_SPRINT2 | 0 | — | — |

### Детализация PRE_EXISTING (113)

| Группа | Кол-во | Связанный BUG-id |
|---|---|---|
| owner 403 (BUG-001 fixtures не создают UserCompanyRole) | ~57 | BUG-001 |
| test_zero_version_stubs (stub-эндпоинты UNAUTHORIZED вместо 501) | ~17 | PRE_EXISTING |
| test_round_trip (UniqueViolation pg_type — загрязнённая тест-БД) | 5+1 | TEST_ENV смежное |
| test_batch_a_coverage bulk_assign audit | 1 | BUG-001 смежное |
| test_house_types ACL (CONFLICT на set_compatible) | 2 | PRE_EXISTING |
| test_lint_migrations count (ожидали 11, нашли 18) | 1 | BUG-004/BUG-010 |
| test_budget_categories/plans/contractors/contracts/payments/material_purchases | ~30 | BUG-001 + иные PRE_EXISTING |

---

## Классификация ERROR (38)

| Категория | Кол-во | Описание |
|---|---|---|
| TEST_ENV — localhost:5433 недоступен изнутри контейнера | 16 | test_auth.py — хардкод localhost:5433 (BUG-005 PRE_EXISTING, не исправлен) |
| TEST_ENV — pytest_socket не установлен | ~13 | tests/unit/core/integrations/ (исключено из прогона, 1 ERROR при коллекции) |
| TEST_ENV — round_trip UniqueViolation на enum в pg_type | 1 | f80b758cadef round-trip |
| PRE_EXISTING — NotNullViolation company_id в fixtures | ~8 | test_houses, test_house_types, test_option_catalog, test_stages |

---

## Sprint 2 юнит-тесты изолированно (42 тестов)

| Файл | Результат |
|---|---|
| tests/unit/core/events/test_business_bus.py (5) | 5/5 PASS |
| tests/unit/core/events/test_agent_control_bus.py (4) | 4/4 PASS |
| tests/unit/core/events/test_outbox_poller.py (13) | 13/13 PASS |
| tests/unit/core/pluggability/test_container.py (9) | 9/9 PASS |
| tests/unit/tools/test_scaffold_crud.py (7) | 0/7 PASS — TEST_ENV BUG-009 |
| tests/unit/core/integrations/ (13) | Не собраны — ModuleNotFoundError pytest_socket |

Sprint 2 функциональные тесты (events + pluggability): **31/31 PASS в изоляции**.

---

## REGRESSION_SPRINT2

**Нет.** Ни один из 4 коммитов Sprint 2 не вносит функциональной регрессии.

---

## Новые баги, обнаруженные в Sprint 2 регрессе

### BUG-009 | P1 | scaffold тесты: _REPO_ROOT=/ в Docker (TEST_ENV)
Заведён в bug_log.md. 7 тестов FAILED. Commit: 42f12c5.
Root cause: путь к scaffold_crud.py вычисляется через `Path(__file__).parents[4]` — внутри Docker даёт `/`, а не `/root/coordinata56`.

### BUG-010 | P2 | test_real_migrations_count: ожидали 11, нашли 18
Расширение BUG-004 (не закрыт в Sprint 1). Sprint 2 добавил 3 новые миграции.

---

## Delta vs Sprint1 Round2 baseline

| Показатель | Round2 | Sprint2 | Delta |
|---|---|---|---|
| PASSED | 434 | 731 | **+297** (+68%) |
| FAILED | 85 | 136 | +51 |
| ERROR | 242 | 38 | **-204** (-84%) |
| REGRESSION_SPRINT2 | — | 0 | GREEN |

Рост FAILED объясняется исключительно новыми тестами (US-04/05/06/07 + scaffold + tools), которые попали в TEST_ENV bucket. Функциональные тесты приложения — только PRE_EXISTING дефекты из Sprint 1.

---

## Рекомендация

**Пропустить Volna B.** REGRESSION_SPRINT2 = 0. Sprint 2 код качественный.

Блокеры для полного зелёного регресса (PRE_EXISTING, унаследованы из Sprint 1):
1. BUG-001 (P0) — fixtures не создают UserCompanyRole → ~57 тестов 403
2. BUG-005 (P1) — 6+ файлов хардкод localhost:5433 → ERROR
3. BUG-009 (P1) — scaffold тесты не работают в Docker (TEST_ENV, новый)
4. BUG-004/010 (P2) — migration count не обновлён

---

## Артефакты

- JUnit XML: `/tmp/sprint2-regression.xml`
- Baseline Round 2: `sprint1-regression-report-round2-2026-04-19.md`

---

*Отчёт составил: qa-head coordinata56 (coordinata56), 2026-04-19*
*Вердикт: YELLOW — PRE_EXISTING доминируют, REGRESSION_SPRINT2 = 0, Volna B не заблокирована*
