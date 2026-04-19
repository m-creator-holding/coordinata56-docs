# Sprint 1 Regression Report — 2026-04-19

commit_under_test: 768fcc9c7958d4cea01402ee032c7f7c5a9687f5
baseline_commit: 856c5cdaef4c466020a53b4844fda96f6abe9167 (docs(diagnostics): 12 pre-existing failures triage)

## Summary

- Total: 757 тестов
- PASSED: 349
- FAILED: 51
- SKIPPED / XFAIL: 13
- ERROR (setup failure): 347
- Duration: 236.49s (3 мин 56 сек)

**Базовая линия Sprint 0 (856c5cd):** 349 PASS.  
**Текущий прогон:** 349 PASS — базовая линия удержана.

---

## Classification of failures

### FAILED (51)

| test_id | class | BUG-id | обоснование |
|---|---|---|---|
| `test_multi_company_isolation::test_list_returns_only_own_company[budget_categories]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 на read budget_category — permission не добавлен US-03 |
| `test_multi_company_isolation::test_list_returns_only_own_company[stages]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 на read stage |
| `test_multi_company_isolation::test_list_returns_only_own_company[house_types]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 на read house_type |
| `test_multi_company_isolation::test_list_returns_only_own_company[houses]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 на read house |
| `test_multi_company_isolation::test_list_returns_only_own_company[material_purchases]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 на read material_purchase |
| `test_multi_company_isolation::test_list_returns_only_own_company[budget_plans]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 на read budget_plan |
| `test_multi_company_isolation::test_list_returns_only_own_company[option_catalog]` | REGRESSION_SPRINT1 | BUG-002 | AttributeError: OptionCategory.FINISH не существует |
| `test_multi_company_isolation::test_get_cross_company_returns_404[budget_categories]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 вместо 404 — не может получить доступ к своим данным |
| `test_multi_company_isolation::test_get_cross_company_returns_404[stages]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 вместо 404 |
| `test_multi_company_isolation::test_get_cross_company_returns_404[house_types]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 вместо 404 |
| `test_multi_company_isolation::test_get_cross_company_returns_404[option_catalog]` | REGRESSION_SPRINT1 | BUG-002 | OptionCategory.FINISH |
| `test_multi_company_isolation::test_get_cross_company_returns_404[houses]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 вместо 404 |
| `test_multi_company_isolation::test_get_cross_company_returns_404[material_purchases]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 вместо 404 |
| `test_multi_company_isolation::test_get_cross_company_returns_404[budget_plans]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 вместо 404 |
| `test_multi_company_isolation::test_list_does_not_contain_cross_company[budget_categories]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 |
| `test_multi_company_isolation::test_list_does_not_contain_cross_company[stages]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 |
| `test_multi_company_isolation::test_list_does_not_contain_cross_company[house_types]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 |
| `test_multi_company_isolation::test_list_does_not_contain_cross_company[option_catalog]` | REGRESSION_SPRINT1 | BUG-002 | OptionCategory.FINISH |
| `test_multi_company_isolation::test_list_does_not_contain_cross_company[houses]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 |
| `test_multi_company_isolation::test_list_does_not_contain_cross_company[material_purchases]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 |
| `test_multi_company_isolation::test_list_does_not_contain_cross_company[budget_plans]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 |
| `test_multi_company_isolation::test_holding_owner_sees_all_companies[option_catalog]` | REGRESSION_SPRINT1 | BUG-002 | OptionCategory.FINISH |
| `test_multi_company_isolation::test_holding_owner_scoped_by_company_id_header[budget_categories]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 |
| `test_multi_company_isolation::test_holding_owner_scoped_by_company_id_header[stages]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 |
| `test_multi_company_isolation::test_holding_owner_scoped_by_company_id_header[house_types]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 |
| `test_multi_company_isolation::test_holding_owner_scoped_by_company_id_header[option_catalog]` | REGRESSION_SPRINT1 | BUG-002 | OptionCategory.FINISH |
| `test_multi_company_isolation::test_holding_owner_scoped_by_company_id_header[houses]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 |
| `test_multi_company_isolation::test_holding_owner_scoped_by_company_id_header[contractors]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 (contractor) |
| `test_multi_company_isolation::test_holding_owner_scoped_by_company_id_header[contracts]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 (contract) |
| `test_multi_company_isolation::test_holding_owner_scoped_by_company_id_header[payments]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 (payment) |
| `test_multi_company_isolation::test_holding_owner_scoped_by_company_id_header[material_purchases]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 |
| `test_multi_company_isolation::test_holding_owner_scoped_by_company_id_header[budget_plans]` | REGRESSION_SPRINT1 | BUG-001 | owner 403 |
| `test_consent_enforcement::test_projects_accessible_after_accept_consent` | REGRESSION_SPRINT1 | BUG-006 | 307 вместо 200 после accept-consent — consent broad fix неполный |
| `test_lint_migrations::TestRealMigrationsSmoke::test_real_migrations_return_zero_errors` | REGRESSION_SPRINT1 | BUG-003 | us01_add_company_id нарушает ADR 0013 (nullable=False без server_default) |
| `test_lint_migrations::TestRealMigrationsSmoke::test_real_migrations_count` | REGRESSION_SPRINT1 | BUG-004 | ожидали 11 миграций, найдено 13 (us01+us03 не учтены в тесте) |
| `test_zero_version_stubs::test_endpoint_returns_501[GET-/api/v1/roles/permissions...]` | PRE_EXISTING | — | существовал в 856c5cd, эндпоинт требует auth (401) до stub-ответа |
| `test_zero_version_stubs::test_endpoint_returns_501[PATCH-/api/v1/roles/permissions]` | PRE_EXISTING | — | аналогично |
| `test_zero_version_stubs::test_endpoint_returns_501[GET-/api/v1/audit/verify]` | PRE_EXISTING | — | аналогично |
| `test_zero_version_stubs::test_endpoint_body_has_not_implemented_code[GET-/api/v1/roles/permissions...]` | PRE_EXISTING | — | следствие 401 вместо 501 |
| `test_zero_version_stubs::test_endpoint_body_has_not_implemented_code[PATCH-/api/v1/roles/permissions]` | PRE_EXISTING | — | аналогично |
| `test_zero_version_stubs::test_endpoint_body_has_not_implemented_code[GET-/api/v1/audit/verify]` | PRE_EXISTING | — | аналогично |
| `test_zero_version_stubs::test_endpoint_body_has_stub_true[GET-/api/v1/roles/permissions...]` | PRE_EXISTING | — | аналогично |
| `test_zero_version_stubs::test_endpoint_body_has_stub_true[PATCH-/api/v1/roles/permissions]` | PRE_EXISTING | — | аналогично |
| `test_zero_version_stubs::test_endpoint_body_has_stub_true[GET-/api/v1/audit/verify]` | PRE_EXISTING | — | аналогично |
| `test_zero_version_stubs::test_endpoint_body_no_stacktrace[GET-/api/v1/roles/permissions...]` | PRE_EXISTING | — | аналогично |
| `test_zero_version_stubs::test_endpoint_body_no_stacktrace[PATCH-/api/v1/roles/permissions]` | PRE_EXISTING | — | аналогично |
| `test_zero_version_stubs::test_endpoint_body_no_stacktrace[GET-/api/v1/audit/verify]` | PRE_EXISTING | — | аналогично |
| `test_zero_version_stubs::test_openapi_contains_all_operation_ids` | PRE_EXISTING | — | openAPI не содержит operationId для roles/permissions + audit/verify |
| `test_zero_version_stubs::test_audit_verify_returns_not_implemented` | PRE_EXISTING | — | 401 вместо 501 |
| `test_zero_version_stubs::test_stub_utils_module_imported_by_all_routers` | PRE_EXISTING | — | roles/ роутер не импортирует stub_utils |
| `test_zero_version_stubs::test_role_permissions_query_param` | PRE_EXISTING | — | 401 вместо 501 |

### ERROR (347)

| группа файлов | class | BUG-id | обоснование |
|---|---|---|---|
| `tests/api/test_permissions_api.py`, `test_roles_api.py`, `test_user_roles_api.py` | REGRESSION_SPRINT1 | BUG-005 | пароль `change_me` вместо `change_me_please_to_strong_password` |
| `tests/repositories/test_user_repository.py`, `test_user_company_role_repository.py` | REGRESSION_SPRINT1 | BUG-005 | аналогично |
| `tests/test_batch_a_coverage.py` | REGRESSION_SPRINT1 | BUG-005 | аналогично |
| `tests/test_stages.py`, `test_projects.py`, `test_houses.py`, `test_house_types.py` | REGRESSION_SPRINT1 | BUG-005 | аналогично |
| `tests/test_option_catalog.py`, `test_material_purchases.py`, `test_payments.py` | REGRESSION_SPRINT1 | BUG-005 | аналогично |
| `tests/test_round_trip.py` | REGRESSION_SPRINT1 | BUG-005 | аналогично |

---

## Coverage critical paths

Coverage НЕ измерен — 347 ERROR в основных тестах делают coverage-прогон бессмысленным (он будет показывать ложно низкие значения). После устранения BUG-005 (пароль) необходим повторный прогон с `--cov`.

Предварительная оценка по тестам, которые ПРОШЛИ (349):
- `backend/app/core/security.py` — частичное покрытие (auth-тесты работают)
- `backend/app/middleware/user_context.py` — частичное (US-02 тесты в test_jwt_company_middleware.py входили в 349 PASS)
- `backend/app/services/rbac.py` — частичное

Точные цифры coverage недоступны без устранения BUG-005.

---

## RBAC matrix check

Файл `tests/test_rbac_matrix_completeness.py` — new в Sprint 1. Не запускался (ERROR из-за BUG-005). Требует фикса.

По имеющимся данным из `test_zero_version_stubs` и `test_pr2_rbac_integration.py`:
- Роли owner/accountant/construction_manager/read_only покрыты в `test_pr2_rbac_integration.py` (входил в 349 PASS базовой линии).
- Полная матрица US-03 (4 роли × все write-эндпоинты) — в `test_rbac_matrix_completeness.py`, не запускался.

---

## Consent gate sanity

- Коллекционных NameError на `contracts.py`: не обнаружено в прогоне (тесты contracts прошли в категории 349 PASS).
- Намеренно-негативные тесты consent: `test_pr2_rbac_integration.py` строки ~230-231, ~278 — НЕ упали случайно (они в PASS-категории 349 с ожидаемым xfail/fail), consent-gate НЕ отключён.
- ОДНАКО: `test_projects_accessible_after_accept_consent` = 307 (BUG-006) — вероятно partial fix: consent middleware блокирует правильно, но accept-consent endpoint не завершает flow корректно.

---

## Итоговый счёт регрессий Sprint 1

| Категория | Количество тестов |
|---|---|
| REGRESSION_SPRINT1 FAILED | 35 |
| REGRESSION_SPRINT1 ERROR | 347 |
| PRE_EXISTING FAILED | 16 |
| PASSED | 349 |
| SKIPPED/XFAIL | 13 |

---

## Gate recommendation

- [ ] ~~APPROVE~~
- [ ] ~~REQUEST-CHANGES~~
- [x] **BLOCK** — критические регрессии Sprint 1

### Блокирующие причины:

**BUG-001 (P0):** Роль `owner` лишена read-прав на все ресурсы US-03 (house, stage, material_purchase, budget_plan, house_type, option_catalog, budget_category). Это прямое нарушение US-01 цели (multi-company isolation должна работать для всех ролей, включая owner). Владелец компании не может читать собственные данные.

**BUG-005 (P1 масштаб P0):** 347 тестов не запускаются вообще из-за несогласованного пароля тестовой БД. Это означает, что 47% тестовой сьюты фактически не выполнялось на Sprint 1 — включая критические тесты stages, projects, houses, payment flows. Реальное состояние кода неизвестно.

**BUG-003 (P1):** ADR 0013 violation в продуктовой миграции us01_add_company_id — небезопасный NOT NULL без server_default. Блокирует применение миграции на непустую БД.

### Возврат backend-head через Координатора:
- BUG-001: добавить `owner` в role_permissions для всех US-03 permissions
- BUG-002: заменить `OptionCategory.FINISH` на валидное значение
- BUG-003: добавить migration-exception или исправить us01 safe-migration паттерн
- BUG-004: обновить счётчик миграций в тесте 11 → 13
- BUG-005: унифицировать TEST_DB_URL во всех тестовых файлах
- BUG-006: исследовать 307 в accept-consent flow

---

## Артефакты

- JUnit XML: `/tmp/sprint1-junit.xml`
- pytest log: `/tmp/sprint1-pytest.log`
- Coverage HTML: не сгенерирован (BUG-005 блокирует)

---

*Отчёт составил: qa-head coordinata56, 2026-04-19*
*Вердикт: BLOCK — 6 новых регрессий (BUG-001 — BUG-006), из которых BUG-001 — P0 (owner без read-прав)*
