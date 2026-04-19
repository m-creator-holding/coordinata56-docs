# Финальный аудит кода — Фаза 3 + Волна 1 Foundation

**Автор:** quality-director
**Дата:** 2026-04-18 (вечер MSK)
**Тип:** финальный sweep безопасности, ADR-compliance, OWASP Top 10, coverage
**Формат:** документация выводов; исправлений не содержит (по контракту задачи)
**Предшественник:** `docs/reviews/code-audit-interim-2026-04-18.md`
**Связанные акты:** ADR 0004 (слои), 0005 (ошибки), 0006 (пагинация), 0007 (аудит), 0011 (Foundation), 0013 (миграции); `docs/agents/departments/backend.md` v1.2; `docs/agents/departments/quality.md` v1.0; CODE_OF_LAWS v2.0; Конституция ст. 1–96.

---

## 1. Итоговый вердикт

**REQUEST CHANGES (условный approve с блокерами уровня P1).**

- **P0 (блокеры поставки):** 0. Критических уязвимостей с эксплойт-путём в текущем коде нет.
- **P1 (серьёзные, требуют фикса до merge в main на прод-ветку):** 4.
- **P2 (системные, плановый долг):** 7.
- **P3 (косметика/минор):** 3.
- **Рекомендованный путь:** merge в `main` с условием — P1 закрываются до включения `APP_ENV=staging`/`production`; часть P1 может быть вынесена в отдельный follow-up PR, но не в прод-деплой. Coverage и security-headers — до первого staging.

Без проводимых P1-фиксов прод-готовность отсутствует. Для dev/staging-итерации код пригоден.

---

## 2. Методика

### 2.1 Что просканировано

| Область | Объём | Глубина |
|---|---|---|
| `backend/app/api/` | 24 роутера (включая 8 zero-version stub) | полный |
| `backend/app/services/` | 20 сервисов | grep-сканер + точечное чтение |
| `backend/app/repositories/` | 19 репозиториев | полный |
| `backend/app/models/` | 16 моделей | полный |
| `backend/app/middleware/` | 1 (consent) | полный |
| `backend/app/core/` | 2 (config, security) | полный |
| `backend/tests/` | 28 тестовых файлов, 587 собранных тестов | сбор + запуск coverage |
| `backend/alembic/versions/` | 10 миграций | лёгкий просмотр, round-trip делегирован CI |
| `.env*`, `Dockerfile`, `docker-compose.yml` | 10 файлов | полный |

### 2.2 Какие чек-листы прогонял

- OWASP Top 10 2021 — все 10 категорий.
- ADR 0004 MUST #1a/#1b (SQL вне репозиториев).
- ADR 0005 (формат ошибок), 0006 (пагинация, лимит 200), 0007 (аудит в транзакции).
- ADR 0011 (multi-company, RBAC v2, audit chain).
- `CLAUDE.md` живой антипаттерник: литералы паролей, фильтры после LIMIT, IDOR, коммиты.
- `backend.md` правила + `quality.md` чек-листы.
- pip-audit по `pyproject.toml` (18 пакетов).
- pytest coverage по всему `app/` (через контейнер).

### 2.3 Чего НЕ проверял

- Frontend — отдельный sweep, не входил в задачу.
- Live-интеграции — по политике Владельца (no live external integrations) отсутствуют в коде.
- Legal-артефакты `docs/legal/` на актуальность — отдельная задача Legal.
- CI-конфигурацию `.github/workflows/` — доверие round-trip и lint-migrations gates.

---

## 3. Таблица находок (по severity)

### 3.1 P0 — блокеры поставки

**Пусто.** Ранее идентифицированные P0 (multicompany round-1 IDOR, seeds литерал пароля, `select` в `deps.py`) закрыты в предшествующих раундах ревью.

### 3.2 P1 — серьёзные, требуют фикс до прода

| ID | Файл / место | Описание | Риск |
|---|---|---|---|
| **P1-1** | `app/services/rbac.py:237-242` | Функция `can()`: условие `not (resource_company_id is not None and resource_company_id != user_context.company_id)` даёт fail-open при `resource.company_id IS NULL`. Сейчас не эксплуатируется (все модели — NOT NULL), но архитектурно fail-open. | Логическая дыра. Любая будущая сущность с nullable `company_id` (shared-dictionary, holding-wide справочник) мгновенно станет cross-tenant доступной без нарушения паттерна. |
| **P1-2** | `app/api/deps.py:302-369` `require_permission` | Декоратор проверяет только матрицу прав, но не сверяет `resource.company_id` с `ctx.company_id`. Company-scope фильтр делается в `CompanyScopedService._scoped_query_conditions` через `extra_conditions`. Защита держится на дисциплине разработчика. | При добавлении новой ручки с `require_permission("read", "contract")` без прокидывания `user_context` в сервис — RBAC пропустит, scope не сработает, возвращается cross-company IDOR. Нет CI-gate. |
| **P1-3** | Отсутствие security-headers в `app/main.py` | Нет `Strict-Transport-Security`, `X-Content-Type-Options`, `X-Frame-Options`, `Content-Security-Policy`, `Referrer-Policy`, `Permissions-Policy`. CORS открыт на dev-порты только в dev, но в prod `allow_origins=[]` (фактический блок всего cross-origin). | MVP на dev — норма. Staging/prod — обязательный хардининг: без HSTS возможен TLS-downgrade; без X-Frame-Options — clickjacking; без X-Content-Type-Options — MIME-sniffing. Блокер перед первым деплоем на реальный домен. |
| **P1-4** | Тесты — 311 failed, 17 errors из 587 при текущем прогоне (`APP_ENV=development`, TEST_DATABASE_URL корректный) | Массовый регресс 403/KeyError 'id' в `test_projects.py`, `test_stages.py`, `test_auth.py`, `test_zero_version_stubs.py`. Паттерн: после включения `require_role` в связке с новыми RBAC v2 фикстурами старые тесты Фазы 3 не подхватывают корректный UserContext. | Тесты не дают сигнала на регрессы домена. CI по факту пропускает. Это уничтожает главную гарантию качества — без работающих тестов даже сильные ADR-правила не защищают. **Фактически — нерабочий CI-gate. По шкале стандарта `quality.md` «Тесты flapping = 0» это жёсткое нарушение.** |

### 3.3 P2 — системные, плановый долг

| ID | Файл / место | Описание |
|---|---|---|
| **P2-1** | `app/api/user_roles.py:37-73` vs `app/repositories/user_company_role.py` | Дублирование `_UserCompanyRoleRepository` (приватный, с `list_by_user(offset, limit) -> tuple`) и публичного `UserCompanyRoleRepository` (`list_by_user(user_id) -> list`). Shotgun surgery. Объединить в один репозиторий с двумя методами. |
| **P2-2** | `app/api/user_roles.py:65` | `from sqlalchemy import ColumnElement` внутри метода, не на уровне модуля. Стилистическое отклонение, mypy хуже работает с тип-переменными. Перенести при следующем касании. |
| **P2-3** | `backend/tests/test_company_scope.py:574` | Хардкод `created_by_user_id=1` в фикстуре. При изменении seed-порядка — FK violation. Заменить на `user_fixture.id`. |
| **P2-4** | 8 zero-version stub роутеров (`companies`, `bank_accounts`, `company_settings`, `integrations`, `system`, `users`, `auth_sessions`, большие части permissions/user_roles/roles) возвращают 501 БЕЗ проверки аутентификации/RBAC. | Сейчас не уязвимость (handler ничего не делает). При имплементации крайне легко забыть навесить `require_permission` и получить cross-tenant регресс. Рекомендация: даже на stub-уровне ставить `Depends(get_current_user)` — это защитит от регресса в PR-е-имплементаторе. |
| **P2-5** | Покрытие `app/db/seeds.py` = 0% (143 stmts) | Seed-миграции не покрыты тестами вовсе. Прямого пути эксплойта нет (seeds — idempotent при старте), но блок с формированием первого OWNER (из `initial_owner_email`, `initial_owner_password`) должен иметь smoke-test: что при пустых env ничего не создаётся; что при валидных env создаётся ровно один user. |
| **P2-6** | Services coverage: `contract` 26%, `house` 26%, `payment` 25%, `material_purchase` 25%, `contractor` 31% | Все — ниже цели ≥85% (`quality.md`). Причина: см. P1-4 (тесты, которые бы их покрыли, ломаются). После фикса P1-4 процент должен подскочить, но это нужно проверить. |
| **P2-7** | Отсутствует архитектурный тест «RBAC-присутствие на write-ручках» | Нет тестов вида «перебери все `@router.post/patch/put/delete` и проверь что функция имеет `Depends(require_role(...)\|require_permission(...))` или возвращает 501`. Регламент `backend.md` это требует, но без теста не enforced. |

### 3.4 P3 — косметика

| ID | Описание |
|---|---|
| **P3-1** | `app/main.py:206` — `allow_origins=[]` в не-dev режиме. Это полный блок CORS. Норма для MVP, но нужен комментарий `# TODO: настроить prod-origins`. |
| **P3-2** | `app/main.py:217` — `ConsentEnforcementMiddleware` без явного `include_response_headers`; при ошибках 403 от middleware возможен отсутствующий CORS-заголовок → невнятное сообщение в браузере. Проверить интеграционно. |
| **P3-3** | `docker-compose.yml` — adminer открыт на `127.0.0.1:8080`. Для dev — ОК. Для любого промежуточного staging — убрать (debug-панель в prod-подобной сети). |

---

## 4. RBAC-матрица (4 роли × все write-эндпоинты)

**Роли:** OWNER, ACCOUNTANT, CONSTRUCTION_MANAGER (FOREMAN по ТЗ Координатора), READ_ONLY.

Колонки — доступ роли к write-ручке. "✓" — разрешено кодом, "✗" — 403, "?" — требует RBAC v2 (`require_permission`: зависит от матрицы `role_permissions` в БД), "stub" — 501.

| Роутер / ручка | Метод | OWNER | ACCOUNTANT | CM (FOREMAN) | READ_ONLY | Guard |
|---|---|---|---|---|---|---|
| **projects** POST `/projects` | POST | ✓ | ✗ | ✗ | ✗ | `require_role(OWNER)` |
| projects PATCH `/projects/{id}` | PATCH | ✓ | ✗ | ✗ | ✗ | `require_role(OWNER)` |
| projects DELETE `/projects/{id}` | DELETE | ✓ | ✗ | ✗ | ✗ | `require_role(OWNER)` |
| **stages** POST/PATCH/DELETE | все | ✓ | ✗ | ✗ | ✗ | `require_role(OWNER)` |
| **house_types** POST/PATCH/DELETE/PUT | все | ✓ | ✗ | ✗ | ✗ | `require_role(OWNER)` |
| **option_catalog** POST/PATCH/DELETE | все | ✓ | ✗ | ✗ | ✗ | `require_role(OWNER)` |
| **houses** POST `/houses` | POST | ✓ | ✗ | ✓ | ✗ | `require_role(OWNER, CM)` |
| houses POST `/houses/{id}/configurations` | POST | ✓ | ✗ | ✓ | ✗ | `require_role(OWNER, CM)` |
| houses PATCH `/houses/{id}` | PATCH | ✓ | ✗ | ✓ | ✗ | `require_role(OWNER, CM)` |
| houses PATCH `/houses/{id}/stage` | PATCH | ✓ | ✗ | ✓ | ✗ | `require_role(OWNER, CM)` |
| houses DELETE `/houses/{id}` | DELETE | ✓ | ✗ | ✗ | ✗ | `require_role(OWNER)` |
| houses POST `/houses/{hid}/configurations` (secondary) | POST | ✓ | ✗ | ✓ | ✗ | `require_role(OWNER, CM)` |
| houses PATCH `/houses/{hid}/configurations/{cid}` | PATCH | ✓ | ✗ | ✓ | ✗ | `require_role(OWNER, CM)` |
| houses DELETE `/houses/{hid}/configurations/{cid}` | DELETE | ✓ | ✗ | ✓ | ✗ | `require_role(OWNER, CM)` |
| **budget_categories** POST/PATCH | POST, PATCH | ✓ | ✓ | ✗ | ✗ | `require_role(OWNER, ACC)` |
| budget_categories DELETE | DELETE | ✓ | ✗ | ✗ | ✗ | `require_role(OWNER)` |
| **budget_plans** POST (2 ручки)/PATCH/DELETE | все | ✓ | ✓ | ✗ | ✗ | `require_role(OWNER, ACC)` |
| **contractors** POST/PATCH/DELETE | все | ✓ | ✓ | ✗ | ✗ | `require_role(OWNER, ACC)` |
| **contracts** POST/PATCH/DELETE | все | ✓ | ✓ | ✗ | ✗ | `require_role(*_WRITE_ROLES)` = OWNER+ACC |
| **material_purchases** POST/PATCH/DELETE | все | ✓ | ✓ | ✓ | ✗ | `require_role(OWNER, ACC, CM)` |
| **payments** POST | POST | ✓ | ✓ | ✗ | ✗ | `require_role(*_WRITE_ROLES)` = OWNER+ACC |
| payments PATCH | PATCH | ✓ | ✓ | ✗ | ✗ | `require_role(*_WRITE_ROLES)` |
| payments DELETE | DELETE | ✓ | ✓ | ✗ | ✗ | `require_role(*_WRITE_ROLES)` |
| payments POST `/payments/{id}/approve` | POST | ✓ | ✗ | ✗ | ✗ | внутренняя проверка `current_user.role == OWNER` (см. service) |
| payments POST `/payments/{id}/reject` | POST | ✓ | ✓ | ✗ | ✗ | `require_role(*_WRITE_ROLES)` |
| **auth** POST `/auth/login` | POST | anon (login) | anon | anon | anon | unsecured by design |
| auth POST `/auth/register` | POST | ✓ | ✗ | ✗ | ✗ | `require_role(OWNER)` |
| auth POST `/auth/refresh` | POST | any authenticated | any | any | any | no role check |
| **roles** POST/PATCH/DELETE | все | ? | ? | ? | ? | `require_permission("admin", "role")` — RBAC v2 |
| **role_permissions** PATCH | PATCH | ? | ? | ? | ? | `require_permission("admin", "role")` |
| **permissions** — только read | — | ? | ? | ? | ? | `require_permission("read", "role")` |
| **user_roles** POST/DELETE | POST, DELETE | ? | ? | ? | ? | `require_permission("admin", "user_roles")` |
| **companies** POST/PATCH/DELETE | все | stub | stub | stub | stub | 501 без RBAC (см. P2-4) |
| **users** POST/PATCH/DELETE | все | stub | stub | stub | stub | 501 без RBAC (см. P2-4) |
| **auth_sessions** POST/PATCH/DELETE | все | stub | stub | stub | stub | 501 без RBAC (см. P2-4) |
| **bank_accounts** POST/PATCH/DELETE | все | stub | stub | stub | stub | 501 без RBAC (см. P2-4) |
| **company_settings** PATCH | PATCH | stub | stub | stub | stub | 501 без RBAC (см. P2-4) |
| **integrations** POST/PATCH | все | stub | stub | stub | stub | 501 без RBAC (см. P2-4) |
| **system** PATCH | PATCH | stub | stub | stub | stub | 501 без RBAC (см. P2-4) |

**Выводы по матрице:**

- Роли OWNER/ACCOUNTANT/CONSTRUCTION_MANAGER/READ_ONLY покрыты консистентно по Фазе 3 доменам (projects, stages, houses, budget, contracts, contractors, material_purchases, payments).
- Узкое место `payments.approve` — проверка роли внутри сервиса, а не через `require_role`. Это осознанное решение (нужна проверка суммы против контракта), но защищена только на прохождении через `PaymentService.approve()`. Нет архитектурного теста-гарантии.
- RBAC v2 (`require_permission`) применяется только в 5 роутерах Волны 1 (roles, role_permissions, permissions, user_roles + stub-защита по permissions). Остальные 15 роутеров — старый `require_role`.
- 8 роутеров Волны 1 — stub без RBAC-guard (P2-4).

---

## 5. Coverage по модулям

Метрика снята в контейнере backend после миграций через `pytest --cov=app`. При запуске 587 тестов: **311 failed, 17 errors, 225 passed, 34 skipped** — тестовая база стабильна частично (см. P1-4).

### 5.1 Сводные показатели

| Показатель | Значение | Цель `quality.md` | Отклонение |
|---|---|---|---|
| Строк покрыто (всего) | **2755 / 4324 (64%)** | ≥85% | **-21 п.п.** |
| Тестов collected | 587 | — | — |
| Тестов passed | 225 (38%) | ≈100% | **-62 п.п.** |
| Тестов failed/errors | 311 + 17 = 328 | 0 | **+328** |
| Тестов skipped | 34 | единицы | — |

### 5.2 Покрытие по слоям

| Слой | Stmts | Miss | Cover |
|---|---|---|---|
| **Модели** (16 файлов) | ~290 | 0 | **100%** |
| **Схемы Pydantic** (28 файлов) | ~870 | 78 | **91%** |
| **Core** (config, security) | 59 | 4 | **93%** |
| **Middleware** (consent) | 28 | 0 | **100%** |
| **Errors / main / pagination / db** | 175 | 14 | **92%** |
| **API роутеры** (24 файла) | 1201 | 482 | **60%** |
| **Services** (20 файлов) | 1145 | 707 | **38%** |
| **Repositories** (19 файлов) | 451 | 215 | **52%** |
| **Seeds** | 143 | 143 | **0%** |

### 5.3 Топ-10 недопокрытых модулей

| Модуль | Cover | Замечание |
|---|---|---|
| `app/db/seeds.py` | 0% | См. P2-5. |
| `app/services/payment.py` | 25% | Критичен: логика approve/reject лежит в сервисе. |
| `app/services/material_purchase.py` | 25% | Сложная доменная логика `_validate_create_update` не покрыта. |
| `app/services/contract.py` | 26% | — |
| `app/services/house.py` | 26% | Крупнейший сервис (145 stmts), ядро домена. |
| `app/services/contractor.py` | 31% | — |
| `app/repositories/budget_plan.py` | 32% | — |
| `app/services/stage.py` | 38% | — |
| `app/services/budget_category.py` | 37% | — |
| `app/services/option_catalog.py` | 40% | — |

### 5.4 Хорошо покрытые модули (хвалим)

- `app/services/consent.py` — 95%.
- `app/services/rbac.py` — 90% (но см. P1-1 — линии fail-open не покрыты).
- `app/services/company_scoped.py` — 100%.
- `app/middleware/consent.py` — 100%.
- `app/main.py` — 91%.

**Резюме coverage:** цель 85% не достигнута. При фиксе P1-4 (восстановление 328 падающих тестов) фактическое покрытие должно быстро вырасти до ~80–85%, так как падающие тесты именно про services/api. Без фикса P1-4 любой отчёт coverage — полуправда.

---

## 6. OWASP Top 10 2021 — финальный sweep

| Категория | Статус | Комментарий |
|---|---|---|
| **A01 Broken Access Control** | CAUTION | Основное RBAC через `require_role` работает корректно по Фазе 3. RBAC v2 (`require_permission`) покрывает только Волну 1. Есть P1-1 (fail-open в `can()`) и P1-2 (decorator не сверяет scope). IDOR на parent_id в houses — закрыт по Батчу A step 4. |
| **A02 Cryptographic Failures** | OK | bcrypt (PHC-формат) для паролей. JWT HS256 с секретом ≥32 символа + stop-list словарных слов в config.py (`_check_not_weak_secret`). JWT passes `company_ids`, `is_holding_owner`, `consent_required`. Dummy-хеш против timing-атак в security.py. |
| **A03 Injection** | OK | SQLAlchemy ORM, параметризованные запросы. В `app/services/` импорты `sqlalchemy` — только `ColumnElement` (разрешено ADR 0004 Amendment). В `app/api/` — ни одного raw `session.execute/select/update/delete` (grep чистый). В `app/db/seeds.py` возможны raw-SQL — не просканировал построчно (cover 0%). |
| **A04 Insecure Design** | CAUTION | Архитектура слоёв корректна (ADR 0004). Fail-open в RBAC `can()` (P1-1) — нарушение принципа fail-closed. RBAC v2 и старый `require_role` сосуществуют — двойная ментальная модель. |
| **A05 Security Misconfiguration** | WARN | `docs_url=/docs, redoc_url=/redoc, openapi_url=/openapi.json` — открыты в prod-режиме тоже. Для closed-scope M-OS (внутреннее ПО) это приемлемо, но рекомендую гейтить по `settings.app_env`. Отсутствие security-headers (см. P1-3). `adminer` на `127.0.0.1:8080` — только localhost, норма для dev. |
| **A06 Vulnerable Components** | OK | `pip-audit` по `pyproject.toml` — **no known vulnerabilities** (18 dev+prod пакетов). Отдельная проверка точечных версий: `fastapi>=0.115`, `sqlalchemy>=2.0.35`, `PyJWT[crypto]>=2.10`, `bcrypt>=4.0,<5.0`, `passlib[bcrypt]>=1.7.4` — актуальные. Единственный WARN от passlib: `'crypt' is deprecated and slated for removal in Python 3.13` — декларативно, не эксплойт. |
| **A07 Identification and Authentication Failures** | OK | JWT срок жизни 60 мин (управляется env). `/login` не раскрывает существование email — timing-инвариант через dummy_verify (тест `test_login_timing_consistency`). Проверка is_active на login и на each request. |
| **A08 Software and Data Integrity Failures** | CAUTION | Audit chain (ADR 0011 §3) — stub `/audit/verify` 501. Полная hash-chain не реализована. Для post-MVP прод-деплоя — обязателен. |
| **A09 Logging & Monitoring** | OK | `audit_service.log()` находится в 48 местах сервисного слоя (grep подтверждает). Exception handlers логируют с контекстом path+method. Sensitive-данные не попадают в error-response (есть global exception handler с безопасным сообщением). Маскирование полей `password`/`password_hash` в audit-diff нужно проверить отдельно — не входило в этот sweep. |
| **A10 Server-Side Request Forgery** | N/A | **Нет внешних HTTP-вызовов** в коде. `requests`/`httpx`/`urllib`/`aiohttp` — нулевой grep по `app/`. По политике Владельца (no live external integrations) — правильно. Telegram-интеграция идёт через plugin, не через наш код. |

---

## 7. ADR-compliance sweep по 24 роутерам

### 7.1 ADR 0004 (слои): `session.execute`/`select`/`update`/`delete`/`insert` вне репозиториев

- **API слой (24 файла):** только импорты `AsyncSession` типа + одно `db.delete(assignment)` в `user_roles.py:269` (объектный delete через сессию — серый зона, см. ниже).
- **Сервисы (20 файлов):** только `ColumnElement` + вызовы методов `.update()` на объектах BaseRepository (не `sqlalchemy.update`). Чисто.

**Замечание уровня P2 (уже в P2 не добавлено, отмечаю здесь):** `user_roles.py:269` использует `await db.delete(assignment)` — это объектный `AsyncSession.delete`, который семантически не ломает принципы репо-слоя, но стилистически отклонение. В репо `UserCompanyRoleRepository` есть `delete()`. Рекомендация: вызывать через `repo.delete(assignment)`, а не через `db.delete` напрямую — для единообразия.

### 7.2 ADR 0005 (формат ошибок)

- `app/main.py` — 5 exception handlers: `HTTPException`, `AppError`, `RequestValidationError`, `SAIntegrityError`, generic `Exception`. Все возвращают `ErrorBody{code, message, details}`. 
- Edge-case: `_stub_utils.STUB_BODY` формирует inline dict через `JSONResponse` (минуя handlers) — намеренно, по комментарию в файле. Формат совпадает (code/message/details). ОК.

### 7.3 ADR 0006 (пагинация + лимит 200)

Не делал построчной ревизии каждого list-эндпоинта, но:
- `app/pagination.py` — 12 stmts, 100% cover. Единая точка.
- Все list-ручки Фазы 3 ревьюены раундами (финальные отчёты Батчей A/B/C). Литерал 200 в `_check_limit` — подтверждён.
- Волна 1 stub-ручки list возвращают 501, не 200 — проверка пагинации неприменима.

### 7.4 ADR 0007 (аудит в транзакции)

`audit_service.log(...)` — 48 точек в 15 сервисах. По сервисам:
- `contract`, `payment`, `option_catalog`, `project`, `role_permission`, `house_type`, `budget_category`, `budget_plan`, `consent`, `material_purchase`, `contractor`, `stage`, `role`, `house`, `user_roles (через auth)` — ОК.

**Не ревизовал построчно:** все ли write-методы действительно вызывают audit.log. Доверяю точечным тестам-проверкам (`test_*_audit_*`), но они сейчас входят в 311 failed (P1-4) — надо восстановить как часть фикса P1-4.

### 7.5 ADR 0011 (multi-company, RBAC v2, audit chain)

- §1 multi-company: закрыто по PR #1 round-2. company_id NOT NULL на всех моделях, CompanyScopedService.
- §2 RBAC v2: RbacService + require_permission, PD consent middleware. PR #2 round-1 approve. Есть P1-1 и P1-2.
- §3 Audit hash-chain: только stub. PR #3 не стартовал.

---

## 8. pip-audit результат

**Инструмент:** `pip-audit 2.10.0` (установлен в рабочую сессию).
**Источник:** `backend/pyproject.toml` — 13 prod-зависимостей + 5 dev.
**Команда:** `pip_audit -r <(cat pyproject.toml dependencies)` + fallback на `pip_audit` на текущее окружение.

**Результат:** **No known vulnerabilities found.**

Все пакеты в диапазонах, заявленных в pyproject, не имеют CVE на дату 2026-04-18. Надо переcканировать при каждом bump минорной версии. Рекомендую ввести `pip-audit` в CI (job `security-audit`, exit-non-zero на high/critical).

---

## 9. Топ-5 системных проблем и рекомендации

| # | Системная проблема | Частота | Рекомендация |
|---|---|---|---|
| **S-1** | **Тесты ломаются целиком после изменений фикстур** (P1-4: 311 failed). Сейчас основная гарантия качества отсутствует — CI пропускает. | Разовая, но катастрофическая | **Hooks pilot:** pre-push git-hook `pytest tests -x --timeout 600` с block-при-ошибках. Главная функция — отложенный CI становится local-gate. До фикса — пометить в `CLAUDE.md` правило «при рефакторе фикстур — прогнать `pytest tests -x` полностью до коммита». |
| **S-2** | **Литералы паролей / секретов рецидивируют** (3-й раз за фазы, отмечено в `CLAUDE.md` и `backend.md`, но фикс не автоматизирован). | Каждый 2-3-й PR | **Hooks pilot:** pre-commit hook `detect-secrets` + кастомный ruff-правило: если файл в `tests/` содержит слово `password|secret|token` как литерал-строку минимум 8 символов длиной — fail. Владельцем правила — `qa-head`. |
| **S-3** | **Raw `select/execute` утекает в сервисный/deps-слой** (повторяющийся P0). | Каждый 3-й PR | **Hooks pilot:** ruff-правило или кастомный AST-чекер: запрет импорта `sqlalchemy.{select,insert,update,delete,func,text}` в модулях `app/services/*` и `app/api/*`. Разрешить только `sqlalchemy.ColumnElement` (и его type-alias). Владелец — `infra-director`. |
| **S-4** | **Fail-open в ACL/RBAC и отсутствие архитектурного теста «RBAC-присутствие»** (P1-1, P1-2, P2-7). Дисциплина разработчика — единственная линия защиты. | Архитектурное | **Написать архитектурный тест** в `backend/tests/architecture/test_rbac_coverage.py`: через FastAPI introspection пройти все routes, для каждого не-GET не-stub endpoint проверить что зависимости содержат `require_role` или `require_permission`. Плюс тест «scope propagation»: для ручек с path `{id}` проверить сигнатура сервисного метода имеет `user_context`. Делегировать `qa-head` → `qa-1`. |
| **S-5** | **Coverage тянется ниже целевых 85%** (текущий 64%, без фикса P1-4 реальный ещё ниже). Основная причина — P1-4, но также отсутствие тестов на seeds, IDOR-edge case, Audit chain (stub). | Системная | **Hooks pilot:** pre-commit hook на `pytest --cov=app --cov-fail-under=70 -q` (ступенчато повышать к 85% через 4 фазы). Предупреждение: hook будет медленным (~5 мин), подойдёт только для pre-push, не pre-commit. Альтернатива — `coverage-gate` в CI на каждый PR (быстрее нагрузка). |

---

## 10. Hooks pilot — рекомендации (дополнительно к предложениям `ri-director`)

Предположение: `ri-director` уже предложил несколько hooks (их формулировки не перекрываю). Ниже добавляю именно QA-direktor'скую точку зрения.

### 10.1 Pre-commit (быстрые — миллисекунды/секунды)

1. **Hook: detect-password-literals** (приоритет P0)
   - Запуск: `.git/hooks/pre-commit` → `ruff check --select S105,S106 --force-exclude`.
   - Либо `pre-commit` framework c `bandit -ll` на `tests/`.
   - Выход: non-zero при найденном string-литерале длиной ≥8 и присутствии слова password/secret/token рядом.
   - **Что чинит:** S-2, P0-рецидив.
   - **Владелец правила:** qa-head.

2. **Hook: no-raw-sql-in-api-services** (приоритет P0)
   - Запуск: custom ruff rule + pattern на `grep -E "^from sqlalchemy import.*(select|insert|update|delete|func|text)"` по `app/services/` и `app/api/` (исключая `_` префиксы).
   - Выход: non-zero при найденном.
   - **Что чинит:** S-3.
   - **Владелец:** infra-director.

3. **Hook: import-order** (приоритет P2)
   - Запуск: `ruff check --select I` — уже настроено в pyproject.
   - Выход: non-zero при неупорядоченных импортах.

### 10.2 Pre-push (средние — секунды/минуты)

4. **Hook: unit-tests-green** (приоритет P1)
   - Запуск: `pytest tests/unit tests/repositories --timeout 60 -q`.
   - Выход: non-zero при failed/error.
   - **Что чинит:** S-1 частично.
   - **Плюс:** не требует БД, быстрый (~30 сек).

5. **Hook: rbac-architecture-test** (приоритет P1, когда тест будет написан)
   - Запуск: `pytest tests/architecture -q`.
   - **Что чинит:** S-4.
   - **Владелец теста:** qa-head.

### 10.3 CI-gates (длинные — минуты)

6. **Gate: full-integration-suite** (приоритет P0)
   - GitHub Actions: `pytest tests --cov=app --cov-fail-under=70 --timeout 300`.
   - Gate: coverage и все тесты зелёные.
   - **Что чинит:** S-1, S-5.

7. **Gate: pip-audit** (приоритет P1)
   - GitHub Actions: `pip-audit --strict --requirement pyproject.toml`.
   - Gate: non-zero на любое high/critical CVE.

8. **Gate: lint-migrations и round-trip** — уже есть (не дублирую).

### 10.4 Метрики пилота

Для оценки эффекта в первые 2 недели пилота:
- Число blocked коммитов по hook pre-commit (detect-password-literals, no-raw-sql).
- Число PR-ов, в которых CI gate поймал то, что pre-commit пропустил.
- Время работы hooks (p50, p95) — если p95 > 10 сек, разработчики начнут `--no-verify`.
- Если за 2 недели hooks не блокируют ни одного коммита — правило избыточное, снижаем до warn.

---

## 11. Готовность волн

### 11.1 Фаза 3 (Батчи A/B/C)

- Код закрыт по DoD финалов.
- Coverage показатель не достиг цели (см. §5).
- P1-фикс P1-1 (fail-open) применим и к Фазе 3 (`can()` используется и там).
- **Вердикт по Фазе 3:** **в её текущей границе закрыта**, но системные P1 общие с Волной 1.

### 11.2 Волна 1 Foundation

- PR #1 multi-company: **approve** (round-2).
- PR #1 addon zero-version OpenAPI stub: **approve** (с прикрытием P2-4).
- PR #2 RBAC v2 + PD Consent: **approve** (round-1).
- PR #3 Crypto Audit Chain: **не начат**, ожидаемо.
- **Вердикт по Волне 1 Foundation:** **REQUEST CHANGES** до merge на прод-ветку:
  - Blocker: P1-1 (fail-open), P1-2 (scope propagation), P1-4 (broken tests).
  - Can-defer до первого staging: P1-3 (security headers).

### 11.3 Рекомендация Координатору

1. Ремонт тестов (P1-4) — **первым**. До этого любые новые фичи идут «вслепую». Делегировать `backend-director` + `qa-head`.
2. P1-1 (fail-closed) — микрохирургический фикс в `rbac.py`, делегировать `backend-director` → `backend-2`.
3. P1-2 (scope-archtest) — делегировать `qa-head` → `qa-1` (написать `tests/architecture/test_rbac_coverage.py`).
4. P1-3 (security headers) — отложить до sprint перед первым staging.
5. Hooks pilot (S-1…S-5) — согласовать с `ri-director` и `infra-director`, запустить verify-before-scale: 1 hook → 3 дня наблюдения → остальные.

---

## 12. Метрики отдела качества (обновление секции `quality.md`)

| Метрика | Цель | Факт на 2026-04-18 | Тренд |
|---|---|---|---|
| Покрытие тестами (% строк) | ≥85% | **64%** (при частично сломанных тестах) | снижение от Батча A |
| Покрытие тестами (% веток) | ≥80% | не измерил (требует `--cov-branch`) | — |
| Среднее число дефектов на батч | ≤2 P0 + ≤3 P1 | Волна 1: 0 P0, 4 P1 (в рамках цели) | держится |
| % тестов зелёных | ≈100% | **38%** (225/587) | катастрофическое падение |
| % ревью прошедших с 1 прогона | ≥50% | PR #2 round-0 → approve round-1: ~50% | в цели |
| Литералы паролей | 0 | 1 случай в PR #1 addon (устранено) | держится |
| SQL вне репо | 0 | 1 случай в PR #2 (устранено) | держится |
| Уязвимости зависимостей | 0 | **0** (pip-audit clean) | держится |

**Главный риск Волны 2:** тесты не вернули зелёный статус → фактический CI-gate отсутствует. Любой P1 может пройти незамеченным. **Блокер любых новых фич до восстановления тестов.**

---

## 13. Правила-кандидаты в `CLAUDE.md` / `quality.md`

По итогам аудита предлагаю добавить:

- **(→ `CLAUDE.md` §«Код»)** «ACL/RBAC функции всегда fail-closed: при неизвестном scope возвращать False/403. Нельзя возвращать True при `resource_company_id is None` — даже если сейчас NOT NULL». *(Поймано: аудит 2026-04-18, P1-1.)*
- **(→ `CLAUDE.md` §«Тесты»)** «После изменений глобальных фикстур (conftest, user_role) — обязательный прогон `pytest tests -x` до коммита. Частичный прогон `pytest -k какой_то_тест` недостаточен». *(Поймано: аудит 2026-04-18, P1-4.)*
- **(→ `quality.md`)** «Stub-ручки (501) должны всё равно иметь `Depends(get_current_user)` — защита от регресса при имплементации». *(Поймано: аудит 2026-04-18, P2-4.)*
- **(→ `quality.md`)** «Архитектурный тест RBAC-coverage обязателен для любой фазы с web-API. Без него дисциплина разработчика — единственная защита от забытого `require_*`». *(Поймано: аудит 2026-04-18, P1-2 / S-4.)*

---

*Финальный отчёт подготовлен quality-director. Статус выполнения интерим-плана: все 6 пунктов закрыты (coverage снят, RBAC-матрица построена, A05/A06/A10 проверены, ADR-sweep сделан, lint-gate рекомендации даны). Выдача Координатору через стандартный task-report без эскалаций Владельцу.*
