# Sprint 1 Regression Report Round 2 — 2026-04-19

commit_under_test: HEAD (post-4-fix: BUG-001/003/005/007)
baseline_report: sprint1-regression-report-2026-04-19.md (Round 1)

---

## Summary (delta)

| Метрика | Round 1 | Round 2 | Delta |
|---|---|---|---|
| PASSED | 349 | 434 | **+85** |
| FAILED | 51 | 85 | +34 |
| ERROR | 347 | 242 | **-105** |
| SKIPPED/XFAIL | 13 | 0 | -13 |
| TOTAL | 757 | 761 | +4 |
| Duration | 236 s | 332 s | +96 s |

---

## Вердикт: RED — STOP

Sprint 2 заблокирован. Два P0 остаются активными, два fix'а из четырёх были частичными.

---

## Статус исправлений

| BUG-id | Ожидалось | Факт | Статус |
|---|---|---|---|
| BUG-001 | owner права добавлены (миграция 1200) | Миграция корректна, но тестовые fixtures не создают `user_company_role` для owner → 57 тестов продолжают падать | **PARTIAL FIX — тест-фикстуры сломаны** |
| BUG-003 | migration-exception docstring в US-01 | lint-тест проходит — P1 закрыт | FIXED |
| BUG-005 | 12 файлов password fix | Исправлены 12 из ~18: test_budget_categories, test_budget_plans, test_contracts, test_payments, test_contractors, test_material_purchases (6 файлов) остались с `postgres@localhost/test_coordinata56` (нет пароля) → 139 ERROR | **PARTIAL FIX — 6 файлов пропущены** |
| BUG-007 | 3-line IDOR fix в company_scoped.py | Нет прямой корреляции с новыми ошибками, но 103 ERROR из-за `NotNullViolation company_id` в fixture'ах (test_houses, test_batch_a, test_house_types, test_option_catalog, test_stages) — fixtures не передают company_id при создании объектов | **НЕЯСНО — новые fixture-ошибки** |

---

## Новые баги, обнаруженные в Round 2

### BUG-008 | P1 | PermissionRead schema: action='export' не входит в Literal

- **Тест:** `tests.api.test_permissions_api::test_list_permissions_happy`
- **Root cause:** `app/schemas/permission.py` → `PermissionRead.action: Literal["read", "write", "approve", "delete", "admin"]`. Миграция `us03_rbac_defaults_seed` вставила `project.export` с `action='export'`. При сериализации GET /permissions Pydantic выбрасывает ValidationError.
- **Severity:** P1 — GET /api/v1/permissions полностью сломан для любого пользователя с правом `*.export`.
- **Фикс:** добавить `"export"` и `"reject"` в Literal в `PermissionRead` и `PermissionCreate`.

---

## Классификация 85 FAILED

| Категория | Кол-во | BUG-id |
|---|---|---|
| owner 403 + cascade KeyError (user_company_role не создан в fixtures) | 57 | BUG-001 (partial fix) |
| PRE_EXISTING (test_zero_version_stubs, auth-gate до stub) | 16 | — |
| OptionCategory.FINISH не существует | 5 | BUG-002 (не тронут) |
| NotNullViolation company_id в fixture (INSERT без company_id) | 4 | новый fixture-дефект |
| Consent 307 (accept-consent flow) | 1 | BUG-006 (не тронут) |
| migration count (ожидали 11, нашли 14) | 1 | BUG-004 (не обновлён) |
| Pydantic action=export ValidationError | 1 | BUG-008 NEW |

## Классификация 242 ERROR

| Категория | Кол-во | Файлы |
|---|---|---|
| no password supplied (BUG-005 partial) | 139 | test_budget_categories, test_budget_plans, test_contracts, test_payments, test_contractors, test_material_purchases |
| NotNullViolation company_id в fixture | 103 | test_houses, test_batch_a_coverage, test_house_types, test_option_catalog, test_stages |

---

## Top-5 блокеров для backend-head

1. **BUG-001 (P0):** fixtures в test_projects, test_stages, test_house_types, test_houses, test_option_catalog, test_batch_a не создают `UserCompanyRole` запись для owner → RBAC JOIN возвращает 0 прав → 403. Миграция 1200 правильная. Нужно: добавить `UserCompanyRole(user_id=..., company_id=..., role_template='owner')` во все affected fixtures (или вынести в conftest как `create_user_with_role` pattern).
2. **BUG-005 (P1 scope P0):** 6 файлов пропущены в fix — test_budget_categories, test_budget_plans, test_contracts, test_payments, test_contractors, test_material_purchases используют `postgresql+psycopg://postgres@localhost/test_coordinata56` (нет пароля, нет порта 5433).
3. **NotNullViolation company_id (новый fixture-дефект, P1):** Fixtures в test_houses, test_house_types, test_option_catalog, test_stages создают объекты INSERT без `company_id=...` — нарушение новой NOT NULL constraint из us01_add_company_id. Все affected fixtures должны передавать `company_id`.
4. **BUG-008 (P1):** `PermissionRead.action` Literal не включает `'export'` и возможно `'reject'` — ValidationError на GET /permissions. Фикс: расширить Literal.
5. **BUG-002 (P1):** `OptionCategory.FINISH` не существует в enum — 5 тестов. Не тронут в Round 1 fix-волне. Заменить на `OptionCategory.INTERIOR`.

---

## Артефакты

- JUnit XML: `/tmp/sprint1-regression-round2.xml`
- Round 1 baseline: `sprint1-regression-report-2026-04-19.md`

---

*Отчёт составил: qa-head coordinata56, 2026-04-19*
*Вердикт: RED STOP — BUG-001 + BUG-005 fix'ы частичные, +1 новый баг BUG-008, +1 новая fixture-категория ошибок*
