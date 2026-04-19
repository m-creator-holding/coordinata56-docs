# Триаж 12 test failures — 2026-04-19

**Исполнитель:** backend-head  
**Дата диагностики:** 2026-04-18  
**Команда запуска:**
```
cd /root/coordinata56/backend
pytest tests/test_auth.py tests/test_company_scope.py tests/test_pr2_rbac_integration.py -v
```
**Результат:** 12 failed, 1 error, 30 passed

---

## Распределение по категориям

| Категория | Количество | Файлы |
|---|---|---|
| **env-dependent** | 9 | test_auth (2), test_company_scope (6+1 error), test_pr2_rbac_integration (1) |
| **stale fixture** | 1 | test_company_scope (1 error = payment fixture) |
| **true bug** | 4 | test_pr2_rbac_integration (4) |
| **outdated spec** | 0 | — |

> Примечание: 1 error (test_cross_company_payment_get_by_id_returns_404) классифицирован отдельно как **stale fixture** — фикстура `payment_c1` хардкодит `created_by_user_id=1`, который не существует в изолированной тестовой БД после введения multi-company. Тест даже не доходит до запуска.

---

## Детальная классификация (one-liner)

### test_auth.py

1. `test_me_with_valid_token_returns_user_data`: **env-dependent**: при логине consent-middleware видит `consent_required=True` (нет записи `pd_policies` с `is_current=True` или пользователь не принял), блокирует GET `/auth/me` → 403 вместо 200; тест не устанавливает PD-согласие в фикстуре.

2. `test_me_with_token_for_deactivated_user_returns_401`: **env-dependent**: то же самое — consent-middleware перехватывает запрос раньше, чем проверяется `is_active`; middleware стоит до auth-guard в стеке, возвращает 403 вместо 401.

### test_company_scope.py

3. `test_cross_company_isolation_projects`: **env-dependent**: пользователь company1 после логина получает JWT с `consent_required=True` (нет PD-согласия в фикстуре), middleware блокирует GET `/projects/` → 403 вместо 200.

4. `test_payment_inherits_company_id_from_contract`: **env-dependent**: middleware блокирует POST `/payments/` → 403 (PD_CONSENT_REQUIRED) вместо 201; тест не принимает consent.

5. `test_cross_company_contract_returns_404`: **env-dependent**: пользователь company2 не принял consent, middleware блокирует GET `/contracts/{id}` → 403 вместо 404.

6. `test_cross_company_project_get_by_id_returns_404`: **env-dependent**: аналогично — middleware блокирует GET `/projects/{id}` → 403 вместо 404.

7. `test_cross_company_contractor_get_by_id_returns_404`: **env-dependent**: аналогично — middleware блокирует GET `/contractors/{id}` → 403 вместо 404.

8. `test_cross_company_payment_get_by_id_returns_404` (ERROR): **stale fixture**: фикстура `payment_c1` использует `created_by_user_id=1` (захардкоженный ID), которого нет в изолированной тестовой БД → `ForeignKeyViolation` при `db_session.flush()`. Рефакторинг multi-company (миграция f7e8d9c0b1a2) сделал seed user id=1 ненадёжным в изолированных транзакциях.

### test_pr2_rbac_integration.py

9. `test_accept_consent_correct_version`: **true bug**: POST `/auth/accept-consent` → `audit_service.log()` пытается вставить запись в `audit_log` с полями `prev_hash` и `hash`, которые отсутствуют в тестовой БД (миграция `d3a7f8e21719_audit_crypto_chain_expand` не применена к тестовой схеме) → `UndefinedColumn: column "prev_hash"`.

10. `test_holding_owner_can_create_role`: **true bug**: POST `/roles/` → аудит-лог при создании роли падает на тех же полях `prev_hash`/`hash` → `UndefinedColumn`.

11. `test_create_user_role_creates_assignment_and_audit`: **true bug**: POST user_role → аудит-лог при назначении роли падает аналогично → `UndefinedColumn`.

12. `test_delete_user_role_removes_and_audits`: **true bug**: DELETE user_role → аудит-лог при удалении назначения падает аналогично → `UndefinedColumn`.

13. `test_bulk_replace_permissions_invalidates_cache`: **true bug**: POST bulk_replace → аудит-лог при `BULK_UPSERT` падает аналогично → `UndefinedColumn`.

> Итого: 5 failures в test_pr2_rbac_integration объединяются в один root cause — миграция `d3a7f8e21719` (audit crypto chain expand) не применена к тестовой БД.

---

## Root causes — сводка

### Root Cause A: Миграция `d3a7f8e21719` не применена к тестовой БД (4+1=5 failures)

Модель `AuditLog` в коде содержит поля `prev_hash` и `hash` (добавлены миграцией `2026_04_18_1600_d3a7f8e21719_audit_crypto_chain_expand`). Тестовая БД не прогнала эту миграцию — колонки физически отсутствуют. Любой write-эндпоинт, вызывающий `audit_service.log()`, падает с `ProgrammingError: column "prev_hash" does not exist`.

**Категория: true bug** (точнее: код опережает схему БД; при корректном apply миграции тесты пройдут, но это состояние тестовой среды — сигнал о реальной проблеме: новая миграция не включена в CI setup тестовой БД).

### Root Cause B: Отсутствие PD-consent в тестовых фикстурах (7 failures)

Consent-middleware (`app/middleware/consent.py`) блокирует ВСЕ запросы пользователей, у которых `consent_required=True` в JWT. После введения ФЗ-152 flow (миграция `ac27c3e125c8_rbac_v2_pd_consent`) каждый логин проверяет `pd_policies.is_current=True` и сравнивает с `user.pd_consent_version`. Тесты из `test_auth.py` и `test_company_scope.py` создавали пользователей и логинились, не принимая consent → логин выдаёт JWT с `consent_required=True` → middleware блокирует все последующие запросы 403.

**Категория: env-dependent** — тесты написаны до введения consent middleware. Фикстуры нужно либо принимать consent явно, либо создавать пользователей с уже проставленным `pd_consent_version` равным текущей версии политики.

### Root Cause C: Хардкод `created_by_user_id=1` в фикстуре (1 error)

Фикстура `payment_c1` в `test_company_scope.py` использует `created_by_user_id=1` — предположительно seed-пользователь холдинга. В транзакционно изолированной тестовой сессии этот пользователь не существует → FK violation при `flush()`.

**Категория: stale fixture** — после введения multi-company и изоляции тестовых транзакций seed id=1 ненадёжен. Фикстура должна создавать пользователя сама или ссылаться на одну из fixture-переменных.

---

## Remediation Plan

### Приоритет 1 — Root Cause A: применить миграцию к тестовой БД (блокирует 5 тестов)
**Действие:** `alembic upgrade head` на тестовой БД. Если CI использует `alembic upgrade head` в setup — проверить, что `d3a7f8e21719` включена в цепочку ревизий и не имеет конфликтующих down_revision.  
**Оценка:** 30 минут (1 команда + проверка chain). Если миграция не стыкуется — 1-2 часа на диагностику цепочки.  
**Исполнитель:** backend-dev-1 (уже в контексте задачи).

### Приоритет 2 — Root Cause B: consent в тестовых фикстурах (блокирует 7 тестов)
**Действие:** Добавить в тестовые фикстуры `create_user_with_role` (или отдельную вспомогательную функцию `create_user_with_consent`) простановку `pd_consent_version` равным версии `pd_policies.is_current=True`, либо bypass через параметр. Затронутые тесты: `test_auth.py` (2), `test_company_scope.py` (5).  
**Оценка:** 2-3 часа (правка conftest + фикстуры + прогон).  
**Исполнитель:** backend-dev-2 (параллельно с приоритетом 1).

### Приоритет 3 — Root Cause C: stale fixture payment_c1 (1 error)
**Действие:** Заменить `created_by_user_id=1` на динамически созданного пользователя через фикстуру `company1_user` или аналог. Проверить все другие фикстуры в `test_company_scope.py` на аналогичные хардкоды.  
**Оценка:** 30-60 минут.  
**Исполнитель:** backend-dev-2 (в рамках того же PR что и приоритет 2).

---

## Общая оценка полной починки

| Категория | Failures | Оценка |
|---|---|---|
| true bug (миграция) | 5 | ~1 час |
| env-dependent (consent) | 7 | ~3 часа |
| stale fixture | 1 | ~1 час |
| **Итого** | **13 (12+1 error)** | **~4-5 часов** (параллельно: ~3 часа) |

При параллельном распределении (dev-1 = миграция, dev-2 = consent + fixture) — закрытие за **3 рабочих часа**.

---

## Флаги для Директора

- **Повторяющийся паттерн:** тесты не обновляются синхронно с введением новых middleware/миграций. Это уже второй раз (первый — фильтры пагинации в Батче A). Рекомендую добавить в `departments/backend.md` правило: «при добавлении нового middleware — обязателен прогон полного test suite и обновление фикстур».
- **CI gap:** тестовая БД не получила миграцию `d3a7f8e21719`. Если CI прогоняет `alembic upgrade head` перед тестами — это цепочка ревизий сломана. Требует проверки `alembic history` на тестовой БД.
- **Хардкод id=1 в фикстуре** — нарушение правила 7 `departments/backend.md` (нет секретов/литералов), расширенно: литеральные ID в фикстурах создают хрупкость. Это второй случай после IDOR-инцидента в Батче A.
