# Security Audit Report — Phase 3 Batch C
## OWASP Top 10 (2021) Sweep

**Дата аудита:** 2026-04-16  
**Аудитор:** Security Agent (coordinata56)  
**Скоуп:** Батч C Фазы 3 — коммиты e08b9b8, 3e279ea, bb1310f, 6cd337e  
**Контекст:** формальный аудит безопасности перед закрытием Фазы 3  

---

## Executive Summary

Батч C прошёл аудит OWASP Top 10 (2021). **Критических (P0) и высоких (P1) уязвимостей не обнаружено.** Найдено 4 замечания уровня P2–P3, которые не блокируют закрытие фазы, но должны быть устранены до выхода в production и/или в первом production-спринте.

**Вердикт Координатору: APPROVE-TO-CLOSE**

Условие: 4 замечания (P2×2, P3×2) передаются в бэклог как технический долг. P0/P1 для перехода к M-OS-0 не требуются.

---

## Результаты по категориям OWASP Top 10

### A01:2021 — Broken Access Control

**Статус: ПРОВЕРЕНО, ЧИСТО (с одним P2-замечанием)**

Проверки выполнены:

- **IDOR на уровне ресурсов.** Все операции над подрядчиками, договорами, платежами и закупками проходят через `get_or_404` в `BaseService`. Несуществующий или soft-deleted объект возвращает 404 — не раскрывает факт существования чужого ресурса. Корректно.
- **Вложенные ресурсы (house.project_id == project_id).** `ContractService._check_house_project_match()` (contract.py:149–170) и `MaterialPurchaseService._validate_create_update()` (material_purchase.py:188–194) явно проверяют принадлежность дома проекту. Нарушение возвращает 422/409 без утечки внутренней информации. Корректно.
- **RBAC-матрица.**
  - Contractors: READ — все authenticated, WRITE — owner+accountant, include_deleted — только owner. Корректно.
  - Contracts: READ — owner+accountant+construction_manager (READ_ONLY исключён намеренно — коммерческая тайна). WRITE — owner+accountant. Корректно.
  - Payments: READ — все роли включая read_only. WRITE — owner+accountant. Approve/Reject — строго owner через `_ACTION_ROLES = (UserRole.OWNER,)`. Корректно.
  - MaterialPurchases: READ — все authenticated, WRITE — owner+accountant+construction_manager. Корректно.
- **require_role обход.** Зависимость `require_role` вызывает `get_current_user` внутри себя — обойти нельзя без валидного JWT. Корректно.
- **CORS в production.** `allow_origins=[]` при `app_env != "development"` (main.py:193). При этом `allow_credentials=True` с пустым списком origins — запросы с credentials будут заблокированы браузером. Технически безопасно. **Однако есть P2-замечание: при добавлении реального домена в production в будущем разработчик должен явно задать список origins — риск случайного `["*"]` с credentials.**

---

**[FIND-01] P2 — CORS production origins не задан явно в конфигурации**

Файл: `backend/app/main.py:193`

`allow_origins=_CORS_ORIGINS_DEV if settings.app_env == "development" else []`

При переходе к production список origins равен `[]`. Это безопасно сейчас (браузер блокирует все кросс-доменные запросы), но означает, что при первом добавлении production-домена нет готового конфигурационного параметра — есть риск поспешно написать `["*"]` с `allow_credentials=True`, что является критической уязвимостью. Рекомендация: добавить `CORS_ORIGINS` в `Settings` и читать его из переменной окружения.

---

### A02:2021 — Cryptographic Failures

**Статус: ПРОВЕРЕНО, ЧИСТО**

- **Пароли.** bcrypt через passlib.CryptContext (security.py:22). Соль автоматическая. PHC-формат. Корректно.
- **JWT_SECRET.** Поле `jwt_secret_key` обязательное (`...`), без дефолта, минимум 32 символа (config.py:46–53). Валидатор `_check_not_weak_secret` запрещает словарные подстроки: "change_me", "secret", "test", "default" (config.py:67). Приложение не стартует без корректного секрета. Корректно.
- **Тестовые пароли.** Все 4 тестовых файла используют `secrets.token_urlsafe(16)` для генерации паролей фикстур — словарных паролей нет. Корректно.
- **JWT-декодирование.** Алгоритм явно указан в `algorithms=[settings.jwt_algorithm]` (security.py:140) — algorithm confusion атака закрыта. Корректно.
- **PII в БД.** В скоупе Батча C нет хранения PII (имена, телефоны физлиц). Суммы договоров — бизнес-данные, не персональные.
- **Случайные токены.** `secrets.token_urlsafe` везде. Корректно.
- **TLS.** Конфигурация TLS не входит в скоуп бэкенда (решается на уровне reverse proxy). Отмечено для следующей фазы.

---

### A03:2021 — Injection

**Статус: ПРОВЕРЕНО, ЧИСТО**

- **SQL Injection.** Весь слой репозиториев строит запросы через SQLAlchemy ORM (`select(Model).where(Model.field == value)`) — параметризация на уровне драйвера. Поиск по f-string-сборке SQL через grep дал нулевой результат по всему `app/repositories/` и `app/services/`. Корректно.
- **ILIKE-параметры.** Паттерн для ILIKE строится как `f"%{search}%"` и передаётся в `.ilike(pattern)` — SQLAlchemy параметризует его через `LIKE $1`, не конкатенирует в SQL-строку. Wildcards `%` и `_` в пользовательском вводе будут экранированы драйвером. Корректно.
- **Миграция (raw text).** `postgresql_where=sa.text('deleted_at IS NULL')` в migration 9be2c634d3d9 — это статическая строка, не пользовательский ввод. Безопасно.
- **datetime.fromisoformat.** `payments.py:102–106` парсит строковые параметры `paid_at_from` / `paid_at_to` через `datetime.fromisoformat()`. Значение затем передаётся в SQLAlchemy-условие как объект datetime — SQL injection исключён. При некорректном формате Python бросает `ValueError`, который будет перехвачен глобальным `validation_error_handler` → 422. Корректно.
- **Command injection.** Исходящих subprocess-вызовов в скоупе нет.
- **Pydantic-валидация.** Все входные данные проходят через Pydantic-схемы на границе HTTP. Корректно.

---

### A04:2021 — Insecure Design

**Статус: ПРОВЕРЕНО, ЧИСТО (с одним P3-замечанием)**

- **Иммутабельность Payment после approved/rejected.** Проверка `payment.status in _IMMUTABLE_STATUSES` реализована в `PaymentService.update()` (payment.py:220) и `PaymentService.delete()` (payment.py:274). Оба метода вызываются из соответствующих PATCH и DELETE эндпоинтов. Approve и Reject проходят через отдельный код с собственными проверками. Покрытие полное.
- **Лимит 120% суммы договора.** Реализован через `get_settings().payment_overrun_limit_pct` (payment.py:343). Значение по умолчанию 20, читается из `PAYMENT_OVERRUN_LIMIT_PCT`. Целочисленная арифметика без float (payment.py:344–346) исключает ошибки округления. Корректно.
- **Race condition на лимите 120%.** Между `sum_approved_amount_for_contract()` и `repo.update()` в `approve()` нет транзакционной блокировки строки договора. Два одновременных approve одного платежа технически могут пройти оба. Закрыто частично: UNIQUE INDEX на (contractor_id, number) закрыл race для дубликатов договоров. Для суммы платежей аналогичной гарантии нет. Это MVP/skeleton, критичность низкая при текущей нагрузке. Отмечено как P3 для production-спринта.
- **Race condition на UNIQUE (contractor_id, number).** Закрыт партиальным UNIQUE INDEX `uq_contracts_contractor_id_number_active` в миграции 9be2c634d3d9. IntegrityError-handler в main.py возвращает корректный 409. Корректно.
- **Статусные переходы договора.** `_ALLOWED_TRANSITIONS` (contract.py:32–37) явно описывает граф. Обратные переходы (completed→active) заблокированы. Корректно.

---

**[FIND-02] P3 — Race condition при двойном approve одного платежа**

Файл: `backend/app/services/payment.py:331–362`

`sum_approved_amount_for_contract()` и последующий `repo.update()` не атомарны. При конкурентных запросах approve двух разных платежей одного договора возможно превышение лимита 120%. Для MVP/skeleton с одним пользователем-owner риск пренебрежимо мал. В production-спринте: использовать `SELECT ... FOR UPDATE` на строку договора или advisory lock на contract_id при approve.

---

### A05:2021 — Security Misconfiguration

**Статус: ПРОВЕРЕНО, ЕСТЬ P2-ЗАМЕЧАНИЕ**

- **CORS.** Рассмотрено в A01. P2 зафиксирован как FIND-01.
- **Трассировки ошибок клиенту.** `unhandled_error_handler` (main.py:156–177) логирует traceback через `logger.exception()` и возвращает клиенту только `{"error": {"code": "INTERNAL_ERROR", "message": "Внутренняя ошибка сервера"}}`. `SAIntegrityError` handler (main.py:130–153) логирует `exc.orig` только в лог, клиенту — только безопасное сообщение. Корректно.
- **Формат ошибок ADR 0005.** Все исключения перехватываются и приводятся к единому формату. Нет утечки stacktrace или SQL-деталей клиенту. Корректно.
- **Default credentials в .env.example.** `JWT_SECRET_KEY=__GENERATE_VIA_secrets.token_urlsafe(32)__` — явная инструкция-заглушка, не рабочий секрет. `DATABASE_URL` содержит `change_me` в пароле — это дефолт для dev, валидатор `_check_not_weak_secret` не пустит `change_me` в JWT_SECRET_KEY, но не проверяет DATABASE_URL. При этом `.env` добавлен в `.gitignore`. Принято.
- **Swagger/OpenAPI в production.** `docs_url="/docs"`, `redoc_url="/redoc"`, `openapi_url="/openapi.json"` задан без условия окружения (main.py:48–51). В production `/docs` будет доступен публично.

---

**[FIND-03] P2 — Swagger UI и OpenAPI schema доступны в production без ограничений**

Файл: `backend/app/main.py:41–51`

```python
app = FastAPI(
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)
```

Нет проверки `app_env`. В production-деплое `/docs`, `/redoc`, `/openapi.json` будут доступны любому без аутентификации. Это раскрывает полную структуру API, все эндпоинты, схемы запросов/ответов и коды ошибок — исходные данные для целенаправленной атаки.

Рекомендация: передавать `docs_url=None, redoc_url=None, openapi_url=None` при `app_env == "production"`. Либо закрыть маршруты через `require_role` на уровне middleware.

- **Security headers.** `X-Content-Type-Options`, `X-Frame-Options`, `Content-Security-Policy` не устанавливаются. Для API-бэкенда (не SSR-фронтенд) критичность средняя — браузерный контекст минимальный. Отмечено для production-спринта.

---

### A06:2021 — Vulnerable and Outdated Components

**Статус: ПРОВЕРЕНО, ЕСТЬ P2-ЗАМЕЧАНИЕ**

Установленные версии (pip show):
- fastapi: 0.135.3 (актуальна на дату аудита)
- SQLAlchemy: 2.0.49 (актуальна)
- bcrypt: 4.3.0 (актуальна, в скоупе `>=4.0,<5.0`)
- python-jose: 3.5.0 (последняя доступная версия)

---

**[FIND-04] P2 — python-jose не поддерживается, рекомендована миграция на PyJWT**

Файл: `backend/pyproject.toml:14`

`python-jose` последний раз обновлялась в 2023 году. Проект фактически unmaintained. Зафиксированы CVE:
- **CVE-2024-33664** (Medium) — алгоритмическая confusion атака при использовании EC-ключей. В текущем коде используется только HS256 с строковым секретом — CVE не эксплуатируется в данной конфигурации.
- **CVE-2024-33663** (Medium) — проблема с None-алгоритмом при определённых условиях.

Текущий код использует явный `algorithms=[settings.jwt_algorithm]` при decode (security.py:140) — прямой эксплуатации нет. Тем не менее, библиотека не получает патчи безопасности.

Рекомендация для production-спринта: заменить `python-jose` на `PyJWT>=2.8.0` (активно поддерживается, тот же API для HS256). Миграция — замена импорта и незначительная правка security.py.

Python 3.12 — актуальна, входит в extended support до 2028.

---

### A07:2021 — Identification and Authentication Failures

**Статус: ПРОВЕРЕНО, ЧИСТО (с известным ограничением MVP)**

- **Хеширование паролей.** bcrypt, PHC-формат, автоматическая соль. Корректно.
- **Timing attack на /login.** `dummy_verify()` вызывается когда пользователь не найден в БД (security.py:45–58). Занимает то же время, что полноценный bcrypt. Единое сообщение 401 для всех ошибок аутентификации — anti-enumeration. Корректно.
- **Brute-force защита.** Отсутствует. Нет rate-limiting на `/auth/login`, нет счётчика неудачных попыток, нет lockout. Это известное ограничение MVP/skeleton-фазы. Для production-спринта: добавить `slowapi` или аналог.
- **JWT invalidation при logout.** Эндпоинт `/logout` отсутствует. JWT — stateless, токен действует до истечения `exp` (60 минут по умолчанию). При компрометации токена нет механизма отзыва. Известное ограничение MVP. Для production: token blacklist или refresh token flow.
- **Сессии.** JWT без refresh token — 60 минут. Приемлемо для внутренней системы.

Оба пункта (brute-force, JWT revocation) известны и задокументированы в рамках skeleton-подхода. P0/P1 не назначены — это сознательное архитектурное решение для MVP.

---

### A08:2021 — Software and Data Integrity Failures

**Статус: ПРОВЕРЕНО, ЧИСТО**

- **IntegrityError handler.** `SAIntegrityError` перехватывается глобальным хендлером (main.py:130–153). SQL-детали `exc.orig` логируются только на сервере, клиент получает безопасный 409 CONFLICT. Корректно.
- **Аудит в одной транзакции с write-операцией.** Все сервисы Батча C вызывают `AuditService.log()` с `session.flush()` — без `commit()`. `db.commit()` вызывается в роутере после возврата сервиса. Аудитная запись и основное изменение атомарны (ADR 0007). Корректно.
- **AuditService._sanitize().** Удаляет поля `password_hash`, `password`, `token`, `secret`, `key`, `jwt` перед записью в `changes_json` (audit.py:25–34). Сериализация через Pydantic ReadSchema (`_contractor_to_dict`, `_payment_to_dict` и т.д.) добавляет второй уровень защиты — схемы не содержат этих полей по определению. Двойная защита. Корректно.
- **Десериализация.** Нет `pickle.loads` или аналогов. Все данные — через Pydantic.
- **CI/CD подписи артефактов.** Вне скоупа текущей фазы.

---

### A09:2021 — Security Logging and Monitoring Failures

**Статус: ПРОВЕРЕНО, ЧИСТО (с известным архитектурным ограничением)**

- **Полнота AuditLog.** Каждая write-операция Батча C логирует: `user_id`, `action`, `entity_type`, `entity_id`, `changes_json` (before/after/diff), `ip_address`, `user_agent`, `timestamp` (серверный UTC). Покрытие: create/update/delete для Contractor, Contract, Payment, MaterialPurchase, включая approve/reject с meta-полями (from_status, reason). Полное покрытие.
- **IP и User-Agent.** Передаются из `request.client.host` и `request.headers.get("user-agent")` через все write-эндпоинты Батча C. Корректно.
- **Чувствительные данные в логах.** `_sanitize()` в AuditService исключает секретные поля. Корректно.
- **Иммутабельность audit_log.** Таблица не имеет `updated_at`/`deleted_at`, регламент запрещает физическое удаление (v1.2 C1). На уровне БД нет row-level security или append-only триггера — это известное ограничение: нет крипто-цепочки хешей. Приемлемо для MVP, отмечено для production-спринта (152-ФЗ требует защиту от подмены журнала при хранении ПДн).
- **Алерты на подозрительные паттерны.** Отсутствуют (всплеск 401, аномальные IP для owner). Известное ограничение MVP.

---

### A10:2021 — Server-Side Request Forgery

**Статус: НЕ ПРИМЕНИМО**

В скоупе Батча C нет исходящих HTTP-запросов к пользовательским URL. Никаких fetch/httpx/requests по user-controlled адресам. При добавлении интеграций в следующих фазах — обязательный allowlist и запрет private CIDR (`169.254.x.x`, `10.x.x.x`, `127.x.x.x`).

---

## Реестр находок

| ID | Приоритет | Категория | Файл:строка | Описание |
|----|-----------|-----------|-------------|----------|
| FIND-01 | P2 | A01/A05 — CORS | main.py:193 | Production origins не задан через конфиг — риск случайного `["*"]` при добавлении домена |
| FIND-02 | P3 | A04 — Race Condition | services/payment.py:331–362 | Двойной approve без блокировки строки договора — потенциальное превышение лимита 120% |
| FIND-03 | P2 | A05 — Misconfiguration | main.py:41–51 | Swagger/OpenAPI (`/docs`, `/redoc`, `/openapi.json`) доступны в production без аутентификации |
| FIND-04 | P2 | A06 — Components | pyproject.toml:14 | `python-jose` unmaintained, CVE-2024-33664/33663; текущая конфигурация HS256+explicit algorithm не эксплуатируема, но требует миграции на PyJWT |

**Итого: P0 — 0, P1 — 0, P2 — 3, P3 — 1**

---

## Рекомендации

### Немедленно (блокеры production, не блокеры закрытия фазы)

1. **FIND-03 (P2):** Отключить Swagger/Redoc в production. В `main.py` при `app_env == "production"` передавать `docs_url=None, redoc_url=None, openapi_url=None`.

2. **FIND-04 (P2):** Заменить `python-jose` на `PyJWT>=2.8.0`. Правка затрагивает только `security.py` (импорт и вызовы) и `pyproject.toml`. Тесты покроют регрессию автоматически.

3. **FIND-01 (P2):** Вынести список CORS origins в `Settings.cors_origins: list[str]` (читается из `CORS_ORIGINS` env-var). В production задавать реальный домен явно.

### В первом production-спринте

4. **FIND-02 (P3):** При approve добавить `SELECT payment.contract_id ... FOR UPDATE` или advisory lock на `contract_id`, чтобы гарантировать атомарность проверки лимита.

5. **Brute-force на /login:** Добавить rate-limiting (`slowapi` или middleware). Счётчик по IP + по email.

6. **JWT revocation:** Реализовать либо refresh token flow, либо server-side blacklist (Redis) для logout. Актуально при появлении реальных пользователей.

7. **Security headers:** Добавить middleware для `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, минимальный CSP для API-ответов.

8. **Audit integrity:** Рассмотреть append-only роль PostgreSQL для `audit_log` (separate DB user без UPDATE/DELETE на таблицу). Требование 152-ФЗ при хранении ПДн.

---

## Конфигурация аудита

- Инструменты: статический анализ кода (ручной), grep-поиск по паттернам инъекций, проверка версий зависимостей
- pip-audit / safety: недоступны в среде выполнения (не установлены)
- Проверка CVE выполнена вручную по NVD для python-jose и fastapi
- Тесты на наличие захардкоженных секретов: grep по `password`, `secret`, `token_urlsafe` в tests/
- SQL injection: grep `f".*SELECT`, `f".*WHERE`, `text(f`, `shell=True` — совпадений не найдено

---

*Отчёт сгенерирован Security Agent coordinata56, 2026-04-16.*  
*Следующий плановый аудит: через 2 недели или перед деплоем production.*
