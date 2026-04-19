# Bug Log — cottage-platform pod

Формат: BUG-NNN | severity | title | test_id | обнаружен | статус

---

## BUG-001 | P0 | US-03 migration не добавляет read-права для роли `owner` на новые ресурсы

**Обнаружен:** 2026-04-19, sprint1-regression-report  
**Статус:** OPEN — возврат backend-head  
**Тест:** `test_multi_company_isolation::test_list_returns_only_own_company[stages|house_types|houses|material_purchases|budget_plans|budget_categories]`, `test_get_cross_company_returns_404[...]`, `test_list_does_not_contain_cross_company[...]`  
**Root cause:** Миграция `us03_rbac_defaults_seed` добавляет permissions для house, stage, material_purchase, budget_plan, house_type, option_catalog, budget_category, НО не добавляет эти права роли `owner` в `role_permissions`. Миграция `ac27c3e125c8` (rbac_v2) вставила `owner` → SELECT * WHERE r.code='owner', но на момент выполнения этих permissions не существовало. US-03 добавляет их только для admin/director/accountant/foreman.  
**Эффект:** Пользователи с ролью `owner` получают PERMISSION_DENIED (403) при попытке читать дома, стадии, закупки и т.д. — P0 (утечка прав в обратную сторону: владелец не видит свои данные).  
**Фикс:** В `us03_rbac_defaults_seed.upgrade()` добавить INSERT role_permissions для роли `owner` на все новые permissions (аналогично INSERT SELECT WHERE r.code='admin').

---

## BUG-002 | P1 | `OptionCategory.FINISH` не существует в enum — stale fixture в test_multi_company_isolation

**Обнаружен:** 2026-04-19, sprint1-regression-report  
**Статус:** OPEN — возврат backend-head / qa  
**Тест:** `test_multi_company_isolation::test_list_returns_only_own_company[option_catalog]`, `test_get_cross_company_returns_404[option_catalog]`, `test_list_does_not_contain_cross_company[option_catalog]`, `test_holding_owner_sees_all_companies[option_catalog]`, `test_holding_owner_scoped_by_company_id_header[option_catalog]` (часть)  
**Root cause:** Тест использует `OptionCategory.FINISH` (строка 220), но enum `OptionCategory` в `app/models/enums.py` содержит значения: CANOPY, INTERIOR, WELLNESS, LANDSCAPE, UTILITY, OTHER — без FINISH.  
**Фикс:** Заменить `OptionCategory.FINISH` на существующее значение, например `OptionCategory.INTERIOR`.

---

## BUG-003 | P1 | US-01 migration нарушает ADR 0013 — `op.alter_column(nullable=False)` без `server_default`

**Обнаружен:** 2026-04-19, sprint1-regression-report  
**Статус:** OPEN — возврат backend-head  
**Тест:** `test_lint_migrations::TestRealMigrationsSmoke::test_real_migrations_return_zero_errors`  
**Root cause:** Файл `2026_04_19_1100_us01_add_company_id.py`, строка 96 — `op.alter_column(nullable=False)` без `server_default=` нарушает правило ADR 0013. Безопасный паттерн требует: сначала add nullable → backfill → NOT NULL.  
**Фикс:** Добавить `migration-exception` в docstring миграции (если паттерн был выполнен, только не задокументирован) или исправить порядок шагов.

---

## BUG-004 | P2 | test_lint_migrations ожидает 11 миграций, найдено 13

**Обнаружен:** 2026-04-19, sprint1-regression-report  
**Статус:** OPEN — возврат backend-head/qa  
**Тест:** `test_lint_migrations::TestRealMigrationsSmoke::test_real_migrations_count`  
**Root cause:** Sprint 1 добавил 2 новые миграции (us01_add_company_id, us03_rbac_defaults_seed), тест не обновлён (`assert len == 11`).  
**Фикс:** Обновить expected count с 11 до 13 в тесте.

---

## BUG-005 | P1 | Несогласованный пароль тестовой БД в файлах Sprint 1 — 347 тестов ERROR

**Обнаружен:** 2026-04-19, sprint1-regression-report  
**Статус:** OPEN — возврат backend-head  
**Тест:** Все тесты в: `tests/api/`, `tests/repositories/`, `tests/test_batch_a_coverage.py`, `tests/test_stages.py`, `tests/test_projects.py`, `tests/test_houses.py`, `tests/test_house_types.py`, `tests/test_option_catalog.py`, `tests/test_material_purchases.py`, `tests/test_payments.py`, `tests/test_round_trip.py`, `tests/test_batch_a_coverage.py` — 347 ERROR  
**Root cause:** Коммит `ff209da` (Sprint 1 kick-off) изменил пароль тестовой БД в `conftest.py` на `change_me_please_to_strong_password`, но многочисленные тестовые файлы (test_projects.py, test_stages.py, etc.) содержат хардкод `change_me` в локальном `TEST_DB_URL`. При попытке подключения к port 5433 — `password authentication failed`.  
**Эффект:** 347 тестов не запускаются вообще — ни PASS, ни FAIL — только ERROR при setup.  
**Фикс:** В каждом файле заменить `"coordinata:change_me@localhost:5433"` на `"coordinata:change_me_please_to_strong_password@127.0.0.1:5433"` или, лучше, вынести `TEST_DB_URL` в общий conftest и убрать дублирование.

---

## BUG-008 | P1 | PermissionRead schema: action='export' не входит в Literal — ValidationError на GET /permissions

**Обнаружен:** 2026-04-19, sprint1-regression-round2  
**Статус:** OPEN — возврат backend-head  
**Тест:** `tests.api.test_permissions_api::test_list_permissions_happy`  
**Root cause:** `app/schemas/permission.py` → `PermissionRead.action: Literal["read", "write", "approve", "delete", "admin"]`. Миграция `us03_rbac_defaults_seed` вставила `project.export` с `action='export'`. При сериализации GET /permissions Pydantic 2 выбрасывает `ValidationError: Input should be 'read', 'write', 'approve', 'delete' or 'admin'`.  
**Фикс:** добавить `"export"` и `"reject"` (если используется) в Literal в `PermissionRead.action` и `PermissionCreate.action`.

---

## BUG-006 | P1 | Consent middleware: accept-consent возвращает 307 вместо 200

**Обнаружен:** 2026-04-19, sprint1-regression-report  
**Статус:** OPEN — возврат backend-head  
**Тест:** `test_consent_enforcement::test_projects_accessible_after_accept_consent`  
**Root cause:** После `POST /api/v1/auth/accept-consent` при запросе `GET /api/v1/projects/` возвращается 307 Temporary Redirect вместо 200. Возможно trailing slash или middleware redirect перехватывает запрос.  
**Фикс:** Исследовать путь redirect — либо убрать trailing slash в тесте (`/api/v1/projects` вместо `/api/v1/projects/`), либо включить `follow_redirects=True` в AsyncClient, либо исправить middleware.

---

## BUG-OWASP-SPRINT1-001 | Medium | A01 — Read-эндпоинты payments/contractors без role-check

**Обнаружен:** 2026-04-19, owasp-sprint1-2026-04-19  
**Статус:** OPEN — передать backend-head  
**Location:** `backend/app/api/payments.py` list+get, `backend/app/api/contractors.py` list+get  
**Scenario:** Пользователь с ролью `read_only` может читать список платежей (`GET /payments/`) — финансовые данные без role-restriction. Payments по матрице ADR 0011 §2.2 доступны read_only только с `payment.read=+`.  
**Recommendation:** Либо добавить `require_permission("read", "payment")` на GET-эндпоинты, либо явно задокументировать в ADR 0011 что read_only видит payments. Проверить матрицу role_permissions — если `read_only.payment.read=False`, то эндпоинт должен быть защищён.

---

## BUG-OWASP-SPRINT1-002 | Medium | A05 — Swagger UI открыт в production

**Обнаружен:** 2026-04-19, owasp-sprint1-2026-04-19  
**Статус:** OPEN — передать backend-head  
**Location:** `backend/app/main.py:94-96`  
**Scenario:** `docs_url="/docs"`, `redoc_url="/redoc"`, `openapi_url="/openapi.json"` доступны без аутентификации в любом `app_env`, включая production. Схема API (все эндпоинты, схемы, типы) раскрывается анонимно.  
**Recommendation:** `docs_url=None if settings.app_env == "production" else "/docs"` (аналогично для redoc_url, openapi_url).

---

## BUG-009 | P1 | test_scaffold_crud.py: _REPO_ROOT разрешается в `/` внутри Docker — 7 тестов FAILED

**Обнаружен:** 2026-04-19, sprint2-regression  
**Статус:** OPEN — возврат backend-head  
**Тест:** `tests/unit/tools/test_scaffold_crud.py::test_scaffold_creates_all_files`, `::test_scaffold_idempotency_exits_1`, `::test_name_conversion[*]` (7 тестов)  
**Root cause:** `_REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent.parent` внутри Docker-контейнера разрешается в `/` (5 уровней вверх от `/app/tests/unit/tools/`), а не в `/root/coordinata56`. Путь к скрипту становится `/backend/tools/scaffold_crud.py` вместо `/app/tools/scaffold_crud.py`. Тест задуман для запуска вне контейнера.  
**Commit:** 42f12c5 (US-07 Pluggability) — scaffold тест добавлен в Sprint 2  
**Фикс:** Использовать `Path(__file__).resolve().parents[3]` чтобы попасть в `/app` (то есть в `backend/` внутри контейнера), или добавить маркер `pytest.mark.skipif` при работе внутри Docker (`os.getenv('DOCKER_CONTAINER')`), или пересмотреть логику определения `_REPO_ROOT` через переменную окружения `APP_ROOT`.

---

## BUG-010 | P2 | test_real_migrations_count ожидает 11, нашли 18 — Sprint 2 добавил US-04/US-05/US-08 миграции

**Обнаружен:** 2026-04-19, sprint2-regression (обновление BUG-004)  
**Статус:** OPEN — возврат backend-head/qa  
**Тест:** `tests/test_lint_migrations.py::TestRealMigrationsSmoke::test_real_migrations_count`  
**Root cause:** BUG-004 не закрыт; Sprint 2 добавил ещё 3 новые миграции (us04_business_events_table, us05_agent_control_events_table, us08_outbox_published_at). Счётчик нужно обновить с 11 до 18.  
**Фикс:** Обновить expected count с 11 до 18 в тесте.
