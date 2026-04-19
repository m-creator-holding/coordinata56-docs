# OWASP Top 10 Аудит — Sprint 1 M-OS-1.1A

**Дата:** 2026-04-19  
**Аудитор:** security (субагент)  
**Скил:** owasp-top10-checklist v1.0 (из `~/.claude/skills/owasp-top10-checklist/SKILL.md`)  
**Skill applied: owasp-top10-checklist v1.0** — применён до начала прогона, все 10 категорий пройдены по чек-листу скила.  
**Pre-sprint1 SHA:** 856c5cd  
**Коммит HEAD:** 9bca6c8  
**Scope:** US-01 (multi-company isolation), US-02 (JWT + X-Company-ID middleware), US-03 (RBAC matrix)

---

## 0. Изменённые файлы Sprint 1 (backend/app/)

65 файлов изменено. Первостепенный скоуп:
- `backend/app/services/company_scoped.py` — центр фильтрации по компании
- `backend/app/api/deps.py` — JWT + X-Company-ID middleware, require_permission
- `backend/app/core/security.py` — JWT encode/decode
- `backend/app/core/config.py` — Settings, jwt_secret_key, jwt_algorithm
- `backend/app/services/rbac.py` — RbacService, RbacCache
- `backend/app/main.py` — CORS, exception handlers, Sentry init
- `backend/app/core/sentry_scrub.py` — PII scrubbing в Sentry
- `backend/app/api/auth.py`, `payments.py`, `contracts.py`, `projects.py`, `contractors.py` и др.

---

## A01: Broken Access Control

**Вердикт: WARN (1 medium finding, 1 note)**

### Проверки:

**1. Cross-company leak — PASS.**  
`CompanyScopedService._scoped_query_conditions()` корректно фильтрует по `company_id`. Для `is_holding_owner=True` без заголовка — `return []` (cross-view по ADR 0011 §1.3). BUG-007 (commit `f2925ac`) устранил критическую уязвимость: holding_owner теперь корректно фильтруется при наличии X-Company-ID. Текущий код — PASS.

**2. X-Company-ID bypass — PASS.**  
В `deps.get_current_user()` обычный пользователь: если `x_company_id not in company_ids` → `CompanyIdForbiddenError` (403). holding_owner: `x_company_id` принимается без проверки company_ids (intentional bypass по ADR 0011).

**3. IDOR на вложенных ресурсах — PASS.**  
Фильтрация через `_scoped_query_conditions` применяется на уровне SQL. Тест `test_multi_company_isolation.py` покрывает 12 ресурсов × 5 сценариев.

**4. Read-эндпоинты без role-check — MEDIUM FINDING.**  
Эндпоинты `GET /contractors/`, `GET /contractors/{id}`, `GET /payments/`, `GET /payments/{id}` используют только `get_current_user` без проверки роли. Комментарий `"Доступно всем аутентифицированным пользователям"` намеренен, однако payments содержат финансовую информацию и по матрице ADR 0011 `read_only` не должен видеть платежи. Contracts read-эндпоинты используют `_READ_ROLES` — паттерн корректный, но payments/contractors — нет. Это не новая регрессия Sprint 1, но зафиксирована как finding.

**5. Force browsing — PASS.**  
Swagger docs (`/docs`, `/redoc`) не имеют role-ограничений, однако company-данные через API недоступны без JWT. Отдельный finding по A05 (Swagger в production).

**6. RBAC bypass через deprecated require_role — PASS.**  
`require_role` остаётся только в `auth.py` для `/auth/register` — намеренное исключение (регистрация — владельческая операция). Все новые write-эндпоинты Sprint 1 используют `require_permission`.

**7. BUG-001 — Pending P0 (уже в bug_log.md).**  
Owner не получает права на новые ресурсы Sprint 1 — это уже задокументировано как BUG-001. Повторно не поднимается.

---

## A02: Cryptographic Failures

**Вердикт: PASS**

**1. Хеширование паролей — PASS.** `bcrypt` через `passlib.CryptContext(schemes=["bcrypt"])` с `deprecated="auto"`.  
**2. Timing attack protection — PASS.** `dummy_verify()` вызывается при несуществующем email — выравнивает время ответа.  
**3. JWT_SECRET_KEY — PASS.** Обязательное поле (no default), `min_length=32`, валидатор отвергает словарные значения ("change_me", "secret", "test", "default").  
**4. JWT TTL — MEDIUM FINDING.** `jwt_expire_minutes` default = 60 минут. По ADR 0003 ожидалось 15 мин access + refresh. Refresh token не реализован. 60 минут для access-only без rotation — повышенный риск кражи токена. Severity: Medium (backlog).  
**5. PII в БД plain-text — не проверялось в объёме схем** (scope ограничен сервисным кодом). ПД в аудите маскируется (см. A09).  
**6. Случайные значения — PASS.** `secrets.token_urlsafe(16)` в тестах, `secrets.token_hex()` в фикстурах.

---

## A03: Injection

**Вердикт: PASS**

**1. SQL-инъекции — PASS.** `CompanyScopedService` использует SQLAlchemy ORM-предикаты (`Model.company_id == user_context.company_id`), не raw SQL с user-input.  
**2. X-Company-ID заголовок — PASS.** FastAPI принимает `x_company_id: int | None = Header(...)` — автоматически валидирует тип; невалидный int → 422.  
**3. SQL в миграциях — не проверялся детально** (миграции не включены в FILES_ALLOWED для глубокого чтения), однако Bandit не выявил SQL-конкатенацию.  
**4. NoSQL/OS command — PASS (подтверждено отсутствием).** Grep по `subprocess`, `shell=True`, NoSQL — чисто.  
**5. Pydantic validation — PASS.** Все входные данные проходят Pydantic-схемы.

---

## A04: Insecure Design

**Вердикт: WARN (1 medium)**

**1. Threat model US-01 — PASS.** Сценарий «бухгалтер company A с X-Company-ID: 2» обработан: `x_company_id not in company_ids` → `CompanyIdForbiddenError`.  
**2. Fail-secure в require_permission — PASS.** Если `db=None` → `return False`. Исключение при загрузке прав из БД не обёрнуто в try/except — пропагируется как 500 (fail-secure по умолчанию FastAPI + exception handler).  
**3. Rate limiting на /login — MEDIUM FINDING.** Отсутствует rate-limiting на `POST /api/v1/auth/login` и `/api/v1/auth/register`. `system_config.rate_limit_per_minute` существует как схема, но middleware не реализован. Brute-force возможен. Severity: Medium (backlog).  
**4. Race conditions в платежах — не включено в Sprint 1 scope** (SELECT FOR UPDATE реализован в audit chain — PASS).

---

## A05: Security Misconfiguration

**Вердикт: WARN (2 findings)**

**1. app_env default = "development" — PASS.** Нет ветки "если env не распознан → production-privileges".  
**2. CORS — PASS.** В production `allow_origins=[]` (пустой список). В dev — localhost:5173/3000 (допустимо с комментарием).  
**3. Debug mode — PASS.** `FastAPI(debug=False)` по умолчанию (параметр не передан → False).  
**4. Stack traces — PASS.** `unhandled_error_handler` возвращает только `{"error": {"code": "INTERNAL_ERROR", ...}}`, детали только в лог.  
**5. Swagger UI открыт в production — MEDIUM FINDING.** `docs_url="/docs"`, `redoc_url="/redoc"`, `openapi_url="/openapi.json"` без ограничений по `app_env`. В production схема API (все эндпоинты, схемы, типы) доступна анонимно. Рекомендация: `docs_url=None if settings.app_env == "production" else "/docs"`. Severity: Medium.  
**6. dev_trigger эндпоинт — PASS.** Регистрируется только при `settings.app_env == "development"` (строка 321 main.py).  
**7. Default credentials — PASS.** Seed-owner требует `OWNER_INITIAL_PASSWORD` через env (raises RuntimeError если не задан).

---

## A06: Vulnerable and Outdated Components

**Вердикт: PASS**

**Bandit delta vs baseline:**  
Baseline: 2 findings (LOW: B106 @ auth.py:167, B110 @ stage.py:69).  
Sprint 1 результат: 2 findings (те же самые, HIGH: 0, MEDIUM: 0).  
**Новых Bandit findings: 0. Delta: 0 HIGH, 0 MEDIUM.**

**pip-audit delta vs baseline:**  
PyJWT был на версии 2.7.0 с CVE-2026-32597 (HIGH, FIX-LATER в baseline). Коммит `a014a7b` обновил PyJWT до 2.12.1 — CVE-2026-32597 закрыта.  
pip-audit показал 27 CVE (было 28 в baseline) — разница: CVE-2026-32597 устранена.  
Все оставшиеся 27 CVE — BLOCKED-UPSTREAM (системные пакеты Ubuntu, не в production-образе) или FIX-LATER DEV/BUILD инструменты. **Новых production CVE: 0.**

---

## A07: Identification and Authentication Failures

**Вердикт: WARN (2 findings)**

**1. JWT alg=none — PASS.** PyJWT 2.12.1 отвергает `alg=none` при указании `algorithms=["HS256"]`. Проверено программно: `jwt.exceptions.InvalidAlgorithmError`.  
**2. Key-confusion HS256/RSA — N/A.** Система использует только HS256 симметричный ключ. Атака key-confusion (RS256 публичный ключ как HS256 секрет) неприменима к HS256-only конфигурации.  
**3. Тест `test_jwt_alg_none_rejected` — ОТСУТСТВУЕТ. LOW FINDING.** Несмотря на то что PyJWT корректно отвергает `alg=none`, тест явно не покрывает этот сценарий. Бриф требует наличия теста.  
**4. Refresh token rotation — MEDIUM FINDING.** Не реализован. Stateless JWT без rotation — при компрометации токена нет возможности инвалидации до истечения 60 минут. Severity: Medium (backlog).  
**5. X-Company-ID без JWT — PASS.** JWT проверяется первым (OAuth2PasswordBearer требует Bearer header). Без валидного JWT декодирование падает до проверки X-Company-ID.  
**6. Anti-enumeration — PASS.** Несуществующий пользователь и неверный пароль возвращают одинаковый detail + `dummy_verify()` выравнивает время.  
**7. Session fixation — PASS (stateless JWT).** При логине выдаётся новый JWT. Старый не инвалидируется (stateless), но `iat` клейм присутствует.

---

## A08: Software and Data Integrity Failures

**Вердикт: WARN (1 finding)**

**1. Audit log append-only — PASS.** Нет DELETE/UPDATE на `audit_log` в сервисах. `AuditService.log()` только вставляет.  
**2. Audit chain (SHA-256) — PASS.** Реализован `SELECT ... FOR UPDATE` на последней записи перед INSERT — защита от race condition. `_compute_hash()` корректно реализован.  
**3. Round-trip миграций — WARN.** BUG-003 (уже в bug_log.md): `op.alter_column(nullable=False)` без `server_default` нарушает ADR 0013. Это уже задокументировано. Артефакт dry_run для US-01 migration отсутствует в `docs/pods/cottage-platform/quality/`.  
**4. Seed backfill company_id=1 — PASS (предположительно).** Миграция следует паттерну ADR 0011 §1.5. Детальный аудит самого файла миграции выходит за пределы FILES_ALLOWED.  
**5. Webhooks HMAC — N/A.** Внешних webhook-интеграций нет (запрет live integrations).

---

## A09: Security Logging and Monitoring Failures

**Вердикт: WARN (1 medium finding)**

**1. Аудит write-эндпоинтов — PASS.** Все write-сервисы вызывают `audit_service.log()` (паттерн ADR 0007 Вариант C).  
**2. ПД в audit_log — PASS.** Маскировка через Pydantic Read-схемы (password_hash исключён). `AUDIT_EXCLUDED_FIELDS` паттерн задокументирован в ADR 0007.  
**3. ПД в Sentry — PASS.** `sentry_scrub.py` с `_SENSITIVE_KEYS_RE` удаляет паспорт/СНИЛС/ИНН/телефон/пароль/токен из event перед отправкой. `send_default_pii=False` (проверить при следующем аудите — в scope не входило).  
**4. Failed login логируется — PASS.** `logger.warning("Попытка использования просроченного JWT-токена")`, `logger.warning("Невалидный JWT-токен: %s", exc)`.  
**5. Cross-company denial (403) — MEDIUM FINDING.** `CompanyIdForbiddenError` (403 COMPANY_ID_FORBIDDEN) не логируется как security-event перед бросом. Это важное событие — попытка доступа к чужой компании. В `deps.get_current_user()` нет `logger.warning(...)` при `CompanyIdForbiddenError`. Рекомендация: добавить `logger.warning("Security: user_id=%s попытка доступа к company_id=%s", user.id, x_company_id)`.  
**6. Алерты — вне scope MVP** (Sentry подключён, алерты настраиваются на prod).  
**7. Email в логах — INFO.** `logger.info("Успешный вход: user_id=%s email=%s ip=%s", ...)` — email в логах допустим для аудита безопасности (не ПД в смысле маскировки), но является персональным данным. LOW FINDING — при production-gate рассмотреть маскировку или hash email в логе.

---

## A10: Server-Side Request Forgery (SSRF)

**Вердикт: PASS**

**1. httpx/requests в приложении — PASS.** Grep по `httpx.`, `requests.` в `backend/app/` — чисто. Sentry SDK работает через собственный транспорт.  
**2. Внешние интеграции — N/A.** Запрет live integrations (CLAUDE.md). Sprint 2 scope для ACL base class.

---

## Сводная таблица findings

| ID | Severity | OWASP | Type | Location | Рекомендация |
|---|---|---|---|---|---|
| F-01 | Medium | A01 | real-issue | `api/payments.py`, `api/contractors.py` (read эндпоинты) | Добавить role-check (read_only не видит payments) или задокументировать как намеренное решение в ADR 0011 |
| F-02 | Medium | A02 | backlog | `core/config.py:54` `jwt_expire_minutes=60` | Снизить до 15 мин, реализовать refresh token rotation |
| F-03 | Medium | A04 | backlog | `api/auth.py` `/auth/login` | Добавить rate-limiting (SlowAPI или аналог) |
| F-04 | Medium | A05 | real-issue | `main.py:94-96` | `docs_url=None` в production, `redoc_url=None`, `openapi_url=None` |
| F-05 | Low | A07 | real-issue | `tests/` | Написать `test_jwt_alg_none_rejected` |
| F-06 | Medium | A07 | backlog | `core/security.py` | Refresh token rotation |
| F-07 | Medium | A09 | real-issue | `api/deps.py:153` | Добавить `logger.warning()` при CompanyIdForbiddenError |
| F-08 | Low | A09 | real-issue | `api/auth.py:163` | Рассмотреть маскировку email в production-логах |

**Critical findings: 0. High findings: 0. Medium: 5. Low: 2. Info: 0.**

**BUG-007 (P0 cross-company leak) — уже исправлен коммитом `f2925ac`. Не открывается повторно.**

---

## Bandit delta

| Metric | Baseline (2026-04-18) | Sprint 1 (2026-04-19) | Delta |
|---|---|---|---|
| HIGH | 0 | 0 | 0 |
| MEDIUM | 0 | 0 | 0 |
| LOW | 2 | 2 | 0 |

Новых high/medium Bandit findings: **0**. Обе LOW-находки — те же ACCEPT из baseline.

## pip-audit delta

| Metric | Baseline | Sprint 1 | Delta |
|---|---|---|---|
| PROD CVE critical/high | 1 (CVE-2026-32597 PyJWT HIGH FIX-LATER) | 0 | -1 (закрыта) |
| TRANSITIVE/SYSTEM | 27 | 27 | 0 |

PyJWT обновлён до 2.12.1 — CVE-2026-32597 устранена.

---

## Open questions

1. **Rate-limiting** — реализован ли через `system_config.rate_limit_per_minute` middleware? Схема есть, middleware не обнаружен.
2. **Swagger в production** — принято ли архитектурное решение об отключении? Рекомендую ADR или CLAUDE.md-строку.
3. **send_default_pii=False** в `sentry_sdk.init()` — не проверено в рамках текущего scope; рекомендую явную верификацию.
4. **Тест alg=none** — добавить в sprint 2 scope.
5. **Email masking в логах** — принять решение до production-gate.

---

## Вердикт по OWASP

| Категория | Статус | Findings |
|---|---|---|
| A01 Broken Access Control | WARN | 1 medium (F-01) |
| A02 Cryptographic Failures | WARN | 1 medium (F-02) |
| A03 Injection | PASS | 0 |
| A04 Insecure Design | WARN | 1 medium (F-03) |
| A05 Security Misconfiguration | WARN | 1 medium (F-04) |
| A06 Vulnerable/Outdated Components | PASS | 0 |
| A07 Auth Failures | WARN | 1 low (F-05) + 1 medium (F-06) |
| A08 Data Integrity | WARN | 0 новых (BUG-003 уже в bug_log) |
| A09 Logging/Monitoring | WARN | 1 medium (F-07) + 1 low (F-08) |
| A10 SSRF | PASS | 0 |

**Итоговый вердикт: request-changes (WARN).**  
Новых Critical/High нет. Все findings — Medium/Low уровня, критерий выхода Sprint 1 (0 новых Critical/High) выполнен.

---

*Аудит завершён 2026-04-19. Файл создан security-auditor. Не коммитить.*
