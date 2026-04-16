# Threat Model & Security-by-Design: coordinata56 MVP

**Дата:** 2026-04-14  
**Ревизия:** 1.0  
**Автор:** Security Agent (coordinata56)  
**Статус:** УТВЕРЖДЕНО К ИСПОЛНЕНИЮ  
**Классификация:** INTERNAL — не распространять за пределы проекта

---

## 1. Контекст и границы системы

### Компоненты в периметре

| Компонент | Технология | Данные |
|---|---|---|
| API backend | FastAPI + Python 3.12 | Бизнес-данные, ПДн, финансы |
| База данных | PostgreSQL 16 | Все персистентные данные |
| Фронтенд | React 18 + Vite + Axios | Токены сессий, ввод пользователей |
| Auth-подсистема | JWT (python-jose, HS256) + bcrypt | Учётные данные |
| Файловое хранилище | Не реализовано в фазе 1 | Планируется: договора, акты |
| Audit log | Таблица `audit_log` PostgreSQL | Действия пользователей |
| Среда запуска | Docker Compose (dev), продакшн TBD | Переменные окружения, секреты |

### Роли и уровни доверия

| Роль | Привилегии | Угрозный профиль |
|---|---|---|
| `owner` (Мартин) | Полный доступ ко всему | Компрометация = полный захват |
| `accountant` | Платежи, отчёты, финансы | Финансовое мошенничество |
| `construction_manager` | Материалы, подрядчики, этапы | Фальсификация актов, закупки |
| `read_only` | Только чтение | Утечка ПДн и коммерческой тайны |
| Анонимный | Только `/health`, `/` | Разведка, брутфорс login |

### Категории защищаемых данных

- **ПДн (152-ФЗ):** ФИО сотрудников, ИНН подрядчиков, контакты (`contacts_json` в `contractors`), `full_name` и `email` пользователей
- **Финансовые:** суммы в `budget_items`, `payments`, `contracts` (цены в копейках: `base_price_cents`, `base_cost_cents`)
- **Аутентификационные:** `password_hash`, JWT-токены, `JWT_SECRET_KEY`
- **Конфигурационные:** `DATABASE_URL`, `POSTGRES_PASSWORD`, строки подключения

---

## 2. OWASP Top 10 (2021): применимость и меры

### A01 — Broken Access Control

**Применимость: КРИТИЧЕСКАЯ**

Система имеет 4 роли с разными правами. Backend в фазе 1 содержит только `/health` и `/` без auth. Роуты API (`backend/app/api/`) ещё не реализованы — это риск: первый написанный эндпоинт может выйти без RBAC.

**Конкретные угрозы:**
- `accountant` обращается к `/api/admin/users` и видит хеши паролей
- `construction_manager` изменяет финансовые записи через прямой PUT
- `read_only` через IDOR получает чужие договора: `/api/contracts/42` вместо доступных ему

**Меры:**
1. Каждый роутер FastAPI ОБЯЗАН иметь зависимость `Depends(require_role([UserRole.OWNER]))` или аналог — декларативно, не условием внутри функции
2. Реализовать `get_current_user` + `require_role()` как FastAPI dependencies до первого API-роута
3. Проверять принадлежность объекта пользователю при каждом обращении (IDOR-защита): запрос `SELECT ... WHERE id=? AND owner_id=?`, не только `WHERE id=?`
4. Тесты: для каждого эндпоинта — минимум один тест с неправильной ролью, ожидающий HTTP 403

---

### A02 — Cryptographic Failures

**Применимость: ВЫСОКАЯ**

**Обнаружены текущие риски:**

1. `jwt_algorithm: str = Field(default="HS256")` — HS256 с симметричным ключом: если `JWT_SECRET_KEY` утечёт, злоумышленник подписывает токены от любого пользователя
2. `jwt_expire_minutes: int = Field(default=60)` — без механизма refresh token и revocation: украденный токен живёт 60 минут без возможности инвалидации
3. `seeds.py` содержит `password_hash=_hash_password("change_me_on_first_login")` — дефолтный пароль, попавший в коммит `7755591`
4. `contacts_json` в `contractors` хранится в JSONB открытым текстом — ПДн (152-ФЗ требует контроль доступа и фиксацию обращений)

**Меры:**
1. Перейти с HS256 на RS256 (асимметричные ключи): приватный — только на backend, публичный — доступен сервисам. При невозможности — `JWT_SECRET_KEY` минимум 64 символа, генерация `secrets.token_urlsafe(48)`
2. Реализовать refresh token + blacklist (Redis или таблица `revoked_tokens` в PG) до деплоя
3. `bcrypt` в seeds — корректно использован. Однако seed-пароль `change_me_on_first_login` нужно немедленно изменить при первом запуске: добавить проверку через скрипт миграции или `FORCE_PASSWORD_CHANGE` флаг
4. ПДн в `contacts_json` — рассмотреть шифрование на уровне приложения через `pgcrypto` или application-level encryption (AES-256-GCM)
5. TLS обязателен на всех соединениях prod: backend↔nginx, nginx↔клиент, backend↔postgres (`sslmode=require` в DATABASE_URL)

---

### A03 — Injection

**Применимость: СРЕДНЯЯ (потенциально высокая)**

**Текущее состояние:** SQLAlchemy ORM используется корректно в моделях. Миграции через Alembic. Прямого сырого SQL не обнаружено.

**Потенциальные риски при разработке API:**
- Соблазн использовать `text()` SQLAlchemy с f-строками для сложных фильтров
- JSONB-поля (`changes_json`, `contacts_json`) принимают произвольные данные — нет схемы валидации
- `entity_type: Mapped[str]` в `audit_log` — строка без enum, потенциально управляемая пользователем

**Меры:**
1. Запрет `text()` с интерполяцией строк — только `text("... :param").bindparams(param=value)`
2. JSONB-поля ОБЯЗАНЫ иметь Pydantic-схему валидации на входе, не просто `dict[str, Any]`
3. `entity_type` в audit_log ограничить enum на уровне приложения, не принимать от пользователя
4. В CI: bandit с проверкой B608 (SQL injection) и B102

---

### A04 — Insecure Design

**Применимость: ВЫСОКАЯ**

Архитектурные решения, требующие корректной закладки до реализации API.

**Меры:**
1. Принцип минимальных привилегий в БД: создать отдельного postgres-пользователя для приложения без прав `CREATE TABLE`, `DROP`, `TRUNCATE` (только DML). Migrations — отдельный пользователь
2. Файловое хранилище (будущее): загрузки только через backend (presigned URL антипаттерн без проверки типа), валидация MIME + magic bytes, хранение вне webroot
3. Audit log (`AuditLog`) должен быть append-only на уровне БД: REVOKE UPDATE, DELETE ON audit_log FROM app_user
4. Rate limiting на `/api/auth/login`: не более 5 попыток за 15 минут с одного IP

---

### A05 — Security Misconfiguration

**Применимость: ВЫСОКАЯ**

**Обнаружено:**

1. `docker-compose.yml` содержит `adminer` (порт 8080) — веб-GUI к БД. В prod это недопустимо
2. `BACKEND_RELOAD=true` в `.env.example` — uvicorn --reload в production открывает файловую систему
3. `echo=False` в `session.py` — правильно, но при `LOG_LEVEL=debug` SQLAlchemy может логировать запросы с данными
4. FastAPI автоматически включает `/docs` и `/redoc` — в production должны быть отключены
5. `CORS` не настроен в `main.py` — FastAPI по умолчанию не ставит CORS-заголовки, но при добавлении middleware риск `allow_origins=["*"]`
6. Нет `Content-Security-Policy`, `X-Frame-Options`, `X-Content-Type-Options` заголовков

**Меры:**
1. `adminer` — только в dev-compose, исключить из prod
2. В prod: `BACKEND_RELOAD=false`, `app_env=production`, FastAPI `docs_url=None, redoc_url=None`
3. CORS: `CORSMiddleware` с явным whitelist origins, `allow_credentials=True` только если нужно, `allow_methods` — только используемые методы
4. Security headers middleware: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Strict-Transport-Security: max-age=31536000`, `Referrer-Policy: strict-origin`
5. CSP (Content-Security-Policy) на фронтенде: `default-src 'self'; script-src 'self'; connect-src 'self' <api-domain>`

---

### A06 — Vulnerable and Outdated Components

**Применимость: СРЕДНЯЯ**

**Зависимости backend (pyproject.toml):**
- `python-jose[cryptography]>=3.3.0` — **РИСК**: python-jose имеет CVE-2022-29217 (алгоритм confusion), не обновлялся с 2021 года. Рекомендуется замена на `python-jwt` или `authlib`
- `bcrypt>=4.0,<5.0` — корректно
- `fastapi>=0.115.0`, `sqlalchemy>=2.0.35` — актуальные major версии

**Зависимости frontend (package.json):**
- `axios ^1.7.3` — проверить CVE (исторически были XSS через ответы с data URL)
- `vite ^5.3.4` — убедиться, что установлена >= 5.3.5 (CVE-2024-23331 в старых версиях)
- `@tanstack/react-query ^5.51.1` — актуально

**Меры:**
1. CI: `pip-audit` на каждый PR и push в main (backend)
2. CI: `npm audit --audit-level=high` на каждый PR (frontend)
3. Dependabot или Renovate: еженедельные PR на обновление зависимостей
4. **Приоритет**: заменить `python-jose` на `authlib` (`pip install authlib`) до реализации auth
5. CVE-feed: еженедельный просмотр nvd.nist.gov по ключевым словам: fastapi, sqlalchemy, python-jose, axios, vite

---

### A07 — Identification and Authentication Failures

**Применимость: КРИТИЧЕСКАЯ**

**Обнаружено:**

1. JWT-алгоритм HS256 с дефолтным секретом `change_me_to_random_32_char_secret` в коде (config.py, попал в коммит)
2. Нет механизма блокировки после N неудачных попыток входа
3. Нет многофакторной аутентификации (для роли `owner` — критично)
4. `last_login_at` поле есть в модели, но обновление не реализовано
5. Refresh token не предусмотрен — при rotate необходим полный перелогин

**Меры:**
1. `JWT_SECRET_KEY` в production: минимум 64 символа, генерация `python -c "import secrets; print(secrets.token_urlsafe(48))"`, хранение в Vault или как env var на сервере (не в файле)
2. Счётчик неудачных попыток входа: поле `failed_login_count` + `locked_until` в модели `User` или Redis
3. MFA для роли `owner`: TOTP (pyotp) — обязательно до production
4. Refresh token: отдельная таблица `refresh_tokens (jti, user_id, expires_at, revoked)`
5. `last_login_at` обновлять атомарно при каждом успешном login

---

### A08 — Software and Data Integrity Failures

**Применимость: СРЕДНЯЯ**

**Меры:**
1. CI: проверять хеши зависимостей (`pip install --require-hashes` + `pip-compile --generate-hashes`)
2. Docker images: использовать конкретные digest вместо тегов (`postgres:16-alpine@sha256:...`)
3. Alembic-миграции: не изменять уже примененные версии в production, только forward migrations
4. `audit_log.changes_json` — не допускать запись туда данных из пользовательского ввода без валидации

---

### A09 — Security Logging and Monitoring Failures

**Применимость: ВЫСОКАЯ**

**Текущее состояние:** Модель `AuditLog` правильно спроектирована (append-only, IP, user_agent, action enum). Но записи в нее пока не производятся (auth не реализован).

**Меры:**
- Подробный перечень — в разделе 5 (Логирование)

---

### A10 — Server-Side Request Forgery (SSRF)

**Применимость: НИЗКАЯ (MVP)**

В MVP нет функций загрузки внешних URL, webhook'ов или интеграций с внешними сервисами.

**Меры:**
1. При добавлении интеграций (банк, SMS, геосервисы): валидировать URL по whitelist доменов
2. Не передавать пользовательский ввод в `httpx.get(url)` без проверки

---

## 3. STRIDE по компонентам

### 3.1 API (FastAPI backend)

| Угроза | Конкретный вектор | Риск | Мера |
|---|---|---|---|
| **S**poofing | Подделка JWT (смена `alg` на `none` или `HS256→RS256`) | HIGH | Жёстко фиксировать алгоритм при верификации; заменить python-jose |
| **T**ampering | Изменение `role` в JWT payload | HIGH | JWT подписан — но при слабом секрете брутфорсится. RS256 устраняет |
| **R**epudiation | Пользователь отрицает действие (удаление записи) | MEDIUM | audit_log с IP + user_agent; soft delete везде (deleted_at уже есть) |
| **I**nformation Disclosure | Трассировки стека в ответах API (FastAPI по умолчанию возвращает detail) | HIGH | В production: `app_env=production` → только generic errors; exception handler |
| **D**enial of Service | Брутфорс `/api/auth/login`, тяжёлые запросы без pagination | HIGH | Rate limiting (slowapi), обязательный LIMIT в запросах к БД |
| **E**levation of Privilege | Отсутствие RBAC на первых API-эндпоинтах | CRITICAL | Dependency `require_role()` на каждый роутер до мержа |

### 3.2 База данных (PostgreSQL 16)

| Угроза | Конкретный вектор | Риск | Мера |
|---|---|---|---|
| **S**poofing | Подключение от имени app-пользователя к БД напрямую | MEDIUM | Postgres bind только на `127.0.0.1` / внутренняя docker-сеть; сильный пароль |
| **T**ampering | Прямое UPDATE/DELETE записей в audit_log | HIGH | REVOKE UPDATE, DELETE ON audit_log; Row Security Policy |
| **R**epudiation | Удаление записей БД без следа | MEDIUM | Soft delete (`deleted_at`) уже реализован во всех моделях — корректно |
| **I**nformation Disclosure | Ошибки PG в ответе API (DATABASE_URL в трассировке) | HIGH | Перехватывать `DBAPIError`, возвращать generic 500 |
| **D**enial of Service | Неограниченные запросы, отсутствие connection pool limits | MEDIUM | `pool_size=5, max_overflow=10` уже настроено — корректно |
| **E**levation of Privilege | App-пользователь с правами суперпользователя | HIGH | Отдельная роль `coordinata_app` без DDL-прав |

### 3.3 Фронтенд (React)

| Угроза | Конкретный вектор | Риск | Мера |
|---|---|---|---|
| **S**poofing | XSS для кражи токена из localStorage | CRITICAL | JWT в httpOnly cookie (не в localStorage); CSP |
| **T**ampering | CSRF: вредоносный сайт делает мутирующий запрос от имени пользователя | HIGH | CSRF-токен для всех POST/PUT/DELETE/PATCH; SameSite=Strict на cookie |
| **R**epudiation | Пользователь отрицает отправку формы | LOW | Логировать на backend с IP |
| **I**nformation Disclosure | React DevTools, `console.log` с данными в prod | MEDIUM | В build: убирать console.log (ESLint rule `no-console`); source maps — приватно |
| **D**enial of Service | Рекурсивные re-render, Memory leak | LOW | Актуально для качества, не для безопасности |
| **E**levation of Privilege | Фронт скрывает UI-элементы по роли, но API не проверяет | CRITICAL | Проверка роли ТОЛЬКО на backend; фронт — только UI-hint |

### 3.4 Auth-подсистема (JWT + bcrypt)

| Угроза | Конкретный вектор | Риск | Мера |
|---|---|---|---|
| **S**poofing | Подбор JWT_SECRET_KEY (дефолт 32 символа) | CRITICAL | 64+ символа; RS256 |
| **T**ampering | Algorithm confusion attack (none/HS256) | HIGH | Заменить python-jose на authlib |
| **R**epudiation | Украденный refresh token используется после logout | MEDIUM | Blacklist refresh tokens в Redis |
| **I**nformation Disclosure | Timing attack на сравнение паролей | LOW | bcrypt корректно использован (постоянное время) |
| **D**enial of Service | bcrypt с cost=12+ на каждый логин под нагрузкой | LOW | MVP — малая нагрузка; при масштабировании — argon2id |
| **E**levation of Privilege | Forgery access token с повышенной ролью | CRITICAL | RS256 + строгая верификация claims (`sub`, `role`, `exp`, `iat`) |

### 3.5 Файловое хранилище (будущая фаза)

| Угроза | Конкретный вектор | Риск | Мера |
|---|---|---|---|
| **S**poofing | Загрузка .php/.py файла под видом PDF | HIGH | Валидация magic bytes (не только расширения); хранение вне webroot |
| **T**ampering | Перезапись чужого файла через предсказуемое имя | HIGH | UUID как имя файла; проверка владельца |
| **I**nformation Disclosure | Прямой URL к файлу без проверки авторизации | HIGH | Presigned URL с TTL или проксирование через backend |
| **D**enial of Service | Загрузка 10 ГБ файла | MEDIUM | Лимит размера (`MAX_UPLOAD_SIZE`), streaming с проверкой |

---

## 4. Чеклист Security-by-Design

### 4.1 Backend-разработчик ОБЯЗАН

#### Пароли и хеширование

- [ ] Хеширование только через `bcrypt` (уже используется) или `argon2id` (`argon2-cffi`)
- [ ] Минимум `bcrypt.gensalt(rounds=12)` — не менее 12 раундов
- [ ] Сравнение паролей только через `bcrypt.checkpw()` — без самодельного `==`
- [ ] Никогда не логировать исходный пароль, не возвращать `password_hash` в API-ответах

#### JWT

- [ ] JWT хранить в httpOnly, Secure, SameSite=Strict cookie — не в теле ответа (не в localStorage на фронте)
- [ ] Жёстко указывать `algorithms=["HS256"]` (или RS256) при декодировании — защита от algorithm confusion
- [ ] Claims обязательно содержат: `sub` (user_id), `role`, `exp`, `iat`, `jti` (для revocation)
- [ ] Заменить `python-jose` на `authlib` до реализации auth (см. CVE-2022-29217)
- [ ] Refresh token: отдельная таблица, хранить hash (не сам токен), TTL 30 дней, one-time use

#### SQL и ORM

- [ ] Только SQLAlchemy ORM или `text().bindparams()` — никаких f-строк в SQL
- [ ] Запросы к объектам — всегда с фильтром по владельцу/проекту (анти-IDOR)
- [ ] JSONB-поля принимают только валидированные Pydantic-схемы, не сырой `dict`

#### Валидация входных данных

- [ ] Все входные данные — через Pydantic v2 schemas (`BaseModel`) с явными типами и ограничениями
- [ ] Строки: `max_length` всегда указан; email — `EmailStr`; числа — `ge=0` где применимо
- [ ] Paginination обязательна: `limit: int = Field(default=20, le=100)`, `offset: int = 0`

#### Rate Limiting

- [ ] Подключить `slowapi` (или аналог) для FastAPI
- [ ] `/api/auth/login`: 5 попыток / 15 минут / IP
- [ ] `/api/auth/refresh`: 10 попыток / 15 минут / IP
- [ ] Все API: 100 запросов / минуту / authenticated user

#### CORS

- [ ] `CORSMiddleware` с явным `allow_origins=["https://app.coordinata56.ru"]` — никогда `"*"` в production
- [ ] `allow_credentials=True` только при необходимости (если JWT в cookie)
- [ ] `allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH"]` — не `["*"]`

#### Security Headers

- [ ] Middleware добавляет заголовки к каждому ответу:
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Strict-Transport-Security: max-age=31536000; includeSubDomains`
  - `Referrer-Policy: strict-origin-when-cross-origin`
  - `Cache-Control: no-store` для API-ответов с данными

#### RBAC

- [ ] Каждый роутер имеет `dependencies=[Depends(require_role([...]))]`
- [ ] Функция `require_role()` реализована как FastAPI dependency (не условие внутри endpoint)
- [ ] Тест с неправильной ролью для каждого эндпоинта — ожидает HTTP 403

#### Production-конфигурация

- [ ] `docs_url=None, redoc_url=None` при `app_env=production`
- [ ] `BACKEND_RELOAD=false` в production
- [ ] Generic exception handler скрывает трассировки стека от клиента
- [ ] PostgreSQL `sslmode=require` в DATABASE_URL (production)

### 4.2 Frontend-разработчик ОБЯЗАН

#### Хранение токенов

- [ ] JWT access token — только в httpOnly cookie (backend устанавливает через `Set-Cookie`)
- [ ] Никакого `localStorage.setItem("token", ...)` и `sessionStorage`
- [ ] Если SPA требует знать роль — только декодированные non-sensitive claims (не хранить raw token в JS)

#### CSRF

- [ ] Для всех мутирующих запросов (POST, PUT, PATCH, DELETE) — CSRF-токен в заголовке `X-CSRF-Token`
- [ ] Backend валидирует `X-CSRF-Token` — Double Submit Cookie pattern или Synchronizer Token
- [ ] Cookie с JWT: `SameSite=Strict` (или `Lax` с CSRF-токеном)

#### Content Security Policy

- [ ] CSP через meta-тег или заголовок nginx:
  ```
  default-src 'self';
  script-src 'self';
  style-src 'self' 'unsafe-inline';
  connect-src 'self' https://api.coordinata56.ru;
  img-src 'self' data:;
  font-src 'self';
  frame-ancestors 'none';
  ```
- [ ] Никакого `eval()`, `innerHTML`, `dangerouslySetInnerHTML` без крайней необходимости

#### Обработка ошибок

- [ ] Не выводить технические детали ошибок пользователю (stack traces, SQL errors)
- [ ] `console.log` — запрещен в production build (ESLint: `"no-console": "error"`)
- [ ] Source maps в production — только для Sentry/мониторинга, не публичные

#### Зависимости

- [ ] `npm audit --audit-level=high` — 0 high/critical уязвимостей перед каждым деплоем
- [ ] `@tanstack/react-query-devtools` — только в dev (`process.env.NODE_ENV === 'development'`)

---

## 5. Управление секретами

### Что и где хранить

| Секрет | Dev | Staging | Production |
|---|---|---|---|
| `POSTGRES_PASSWORD` | `.env.dev` (в .gitignore) | Env var CI/CD | HashiCorp Vault или env var сервера |
| `JWT_SECRET_KEY` | `.env.dev` | CI secret | Vault / systemd EnvironmentFile (chmod 600) |
| `DATABASE_URL` | `.env.dev` | CI secret | Vault / systemd EnvironmentFile |

### Текущая проблема: дефолты в коде

**Уровень: HIGH**

В коммите `7755591` (HEAD) в `backend/app/core/config.py` зафиксированы дефолтные значения:
```
default="postgresql+psycopg://coordinata:change_me_please_to_strong_password@..."
default="change_me_to_random_32_char_secret"
```

Это не секреты в git-истории (это дефолты, не реальные значения), но создаёт риск: если developer забудет установить переменные окружения, приложение запустится с известными дефолтными значениями.

**Рекомендация:** Убрать дефолтные значения для критических секретов, заменить на `...` (Pydantic required field):
```python
jwt_secret_key: str = Field(description="...")  # без default — запуск без переменной = ошибка старта
```

### Rotation Policy (политика ротации)

| Секрет | Плановая ротация | Внеплановая (при инциденте) |
|---|---|---|
| `JWT_SECRET_KEY` | Каждые 90 дней | Немедленно + инвалидация всех сессий |
| `POSTGRES_PASSWORD` | Каждые 180 дней | Немедленно + смена в Vault + рестарт backend |
| Пароли пользователей | По требованию (нет автоматики в MVP) | Принудительный сброс |
| Refresh tokens | TTL 30 дней (автоматически) | Flush всей таблицы `refresh_tokens` |

### Инструменты для production

**Рекомендуется (в порядке приоритета):**

1. **Системные переменные + EnvironmentFile** — минимальный вариант для старта: `systemd` unit с `EnvironmentFile=/etc/coordinata56/secrets.env` (chmod 600, root only). Не требует доп. инфраструктуры.

2. **SOPS + age/GPG** — секреты зашифрованы в git-репозитории (`infra/secrets.enc.yaml`), расшифровываются при деплое. Подходит при наличии CI/CD (GitHub Actions, GitLab CI).

3. **HashiCorp Vault** — полноценное управление секретами: dynamic credentials, lease, audit trail. Рекомендуется при масштабировании за MVP.

**Запрещено в любой среде:**
- `.env` файл в git-репозитории (даже в private)
- Секреты в `docker-compose.yml` как hardcode
- Секреты в переменных окружения Docker image (layer истории)
- Передача секретов через Telegram/мессенджеры

---

## 6. Логирование: что и как

### 6.1 Что ОБЯЗАТЕЛЬНО логировать (в `audit_log`)

| Событие | action | entity_type | Поля |
|---|---|---|---|
| Успешный вход | `LOGIN` | `user` | user_id, ip_address, user_agent, timestamp |
| Неудачный вход (wrong password) | `LOGIN_FAILED` | `user` | email (хеш или masked), ip_address, timestamp |
| Выход | `LOGOUT` | `user` | user_id, ip_address, timestamp |
| Отказ в доступе (403) | `ACCESS_DENIED` | endpoint | user_id, endpoint, method, ip_address |
| Создание записи | `CREATE` | тип сущности | user_id, entity_id, краткий diff |
| Изменение записи | `UPDATE` | тип сущности | user_id, entity_id, `changes_json` с before/after |
| Удаление (soft) | `DELETE` | тип сущности | user_id, entity_id, timestamp |
| Доступ к ПДн | `ACCESS` | `user`/`contractor` | кто обратился, к чьим данным, зачем (152-ФЗ) |
| Смена пароля | `UPDATE` | `user` | user_id, ip_address (не логировать сам пароль) |
| Смена роли | `UPDATE` | `user` | actor_id, target_user_id, old_role, new_role |

**Добавить в `AuditAction` enum:** `LOGIN_FAILED`, `ACCESS` (доступ к ПДн для 152-ФЗ)

### 6.2 Что КАТЕГОРИЧЕСКИ ЗАПРЕЩЕНО логировать

- Пароли в любом виде (открытый текст, частично маскированный)
- JWT токены (access и refresh) — даже фрагменты
- Полные ПДн в `changes_json`: ФИО, номера телефонов, email пользователей — только ID + маска
- `DATABASE_URL` и другие строки подключения в application logs
- Тела HTTP-запросов целиком (могут содержать пароли при login)
- `HTTP Authorization` заголовок

### 6.3 Срок хранения (152-ФЗ + практика)

| Тип логов | Срок | Основание |
|---|---|---|
| `audit_log` (действия с ПДн) | Минимум 3 года | Ст. 19 152-ФЗ, операторские обязательства |
| `audit_log` (прочие действия) | Минимум 1 год | Внутренний регламент |
| Системные логи (nginx, uvicorn) | 90 дней | Operational need |
| Логи неудачных auth | 1 год | Расследование инцидентов |

**Реализация:** Партиционирование таблицы `audit_log` по месяцам (`PARTITION BY RANGE (timestamp)`) для эффективного удаления истёкших данных без `DELETE`.

### 6.4 Технические требования к логированию

- Формат: JSON structured logging (не plain text) — `structlog` или `logging` с JSON formatter
- Уровни: `INFO` для audit events, `WARNING` для security events, `ERROR` для исключений
- Не писать audit в stdout (теряется при рестарте контейнера) — только в БД
- Application logs (stdout) — через Docker log driver в централизованное хранилище (будущая фаза)

---

## 7. Зависимости и CI

### 7.1 Backend: pip-audit

```yaml
# .github/workflows/security.yml (пример)
- name: pip-audit
  run: |
    pip install pip-audit
    pip-audit --requirement requirements.txt --strict
```

Запускать: на каждый PR + еженедельно по расписанию.

### 7.2 Frontend: npm audit

```yaml
- name: npm audit
  working-directory: frontend
  run: npm audit --audit-level=high
```

Запускать: на каждый PR + еженедельно.

### 7.3 SAST: bandit (backend)

```yaml
- name: bandit SAST
  run: |
    pip install bandit
    bandit -r backend/app/ -ll -x backend/app/tests/
```

Проверки: B608 (SQL injection), B105/B106/B107 (hardcoded passwords), B501/B502 (weak TLS).

### 7.4 SAST: semgrep (backend + frontend)

```yaml
- name: semgrep
  run: semgrep --config=p/owasp-top-ten --config=p/python --config=p/typescript .
```

### 7.5 Gitleaks: сканирование секретов в истории

```bash
# Разовый запуск для проверки текущей истории:
gitleaks detect --source /root/coordinata56 --verbose
```

Запускать: при каждом push (pre-receive hook или CI).

### 7.6 Dependabot (GitHub)

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: pip
    directory: /backend
    schedule:
      interval: weekly
  - package-ecosystem: npm
    directory: /frontend
    schedule:
      interval: weekly
```

---

## 8. Требования 152-ФЗ (технические)

Система обрабатывает ПДн сотрудников и контрагентов (ИНН, ФИО, контакты). Категория — **иные ПДн** (не специальные), уровень защищённости УЗ-3 (при числе субъектов до 100 тыс. и отсутствии спецкатегорий).

| Требование | Статья/Приказ | Мера в системе |
|---|---|---|
| Учёт доступа к ПДн | Приказ ФСТЭК 21, п.9 | audit_log с action=`ACCESS` для таблиц users, contractors |
| Идентификация и аутентификация | Приказ ФСТЭК 21, ИА | JWT + RBAC; MFA для owner |
| Управление доступом | Приказ ФСТЭК 21, УПД | Роли: owner/accountant/construction_manager/read_only |
| Регистрация событий безопасности | Приказ ФСТЭК 21, РСБ | audit_log; хранение 3 года |
| Защита каналов передачи | Приказ ФСТЭК 21, ЗИС | TLS 1.2+ обязательно; HSTS |
| Целостность ПО | Приказ ФСТЭК 21, ЦС | pip-audit, npm audit, хеши зависимостей |
| Антивирусная защита | Приказ ФСТЭК 21, АВЗ | На уровне сервера (вне scope backend-разработки) |

**Специфика для MVP:** Данные покупателей домов (ФИО, контакты в `contacts_json`) — если появятся в системе, необходимо Согласие на обработку ПДн и политика конфиденциальности до первого ввода данных реального клиента.

---

## 9. Найденные проблемы: сводная таблица

| ID | Уровень | Компонент | Описание | Мера | Срок |
|---|---|---|---|---|---|
| SEC-001 | CRITICAL | Auth | JWT_SECRET_KEY с дефолтом в коде; python-jose с CVE | Заменить на authlib; убрать дефолт из Field | До первого auth-коммита |
| SEC-002 | CRITICAL | Auth | Нет RBAC на API-роутерах (api/ пустой сейчас) | `require_role()` dependency — первое, что реализуется | До первого API-роута |
| SEC-003 | CRITICAL | Frontend | JWT в localStorage (риск) — паттерн ещё не задан | Закрепить httpOnly cookie как единственный паттерн | До первого auth на фронте |
| SEC-004 | HIGH | Auth | Нет rate limiting на /auth/login | slowapi — до первого деплоя | До деплоя |
| SEC-005 | HIGH | Auth | Нет refresh token / revocation | Таблица refresh_tokens — до production | До production |
| SEC-006 | HIGH | Config | Дефолтный пароль `change_me_on_first_login` в seeds.py (в коммите) | Принудительная смена при первом входе | До первого пользователя |
| SEC-007 | HIGH | Config | adminer в docker-compose без ограничений (port 8080) | Только в dev-compose; в prod — не запускать | До prod |
| SEC-008 | HIGH | Backend | Нет security headers (CSP, HSTS, X-Frame-Options) | Middleware в main.py | До деплоя |
| SEC-009 | HIGH | Backend | FastAPI /docs /redoc открыты в любой среде | Отключить при app_env=production | До деплоя |
| SEC-010 | HIGH | Deps | python-jose CVE-2022-29217 (algorithm confusion) | Замена на authlib | До auth-реализации |
| SEC-011 | MEDIUM | DB | App-пользователь PostgreSQL не ограничен в DDL | Создать роль без CREATE/DROP прав | До prod |
| SEC-012 | MEDIUM | DB | audit_log доступен для UPDATE/DELETE app-пользователем | REVOKE на уровне PG | До prod |
| SEC-013 | MEDIUM | Logging | AuditAction enum не содержит LOGIN_FAILED, ACCESS | Добавить в enum | До auth-реализации |
| SEC-014 | MEDIUM | Deps | Нет pip-audit / npm audit в CI | Добавить в CI pipeline | До первого деплоя |
| SEC-015 | LOW | Backend | bcrypt rounds не зафиксирован явно в коде | Добавить константу BCRYPT_ROUNDS=12 | При реализации auth |

---

## 10. Резюме: Top-5 угроз MVP и что сделать до первого деплоя

**Top-5 угроз для coordinata56 MVP:**

1. **Слабая auth-подсистема (SEC-001, SEC-010):** Дефолтный JWT_SECRET_KEY в коде + библиотека python-jose с CVE на algorithm confusion — злоумышленник может подделать токен с ролью `owner` и получить полный доступ к финансовым данным проекта.

2. **Отсутствие RBAC на API (SEC-002):** Первые реализованные эндпоинты могут выйти без проверки роли. В системе с финансовыми данными и ПДн это означает, что `read_only` пользователь сможет изменить бюджет или получить данные всех подрядчиков.

3. **Хранение JWT в небезопасном месте на фронте (SEC-003):** Если паттерн не закреплён сейчас, разработчик по умолчанию положит токен в localStorage — любой XSS (в т.ч. через уязвимость в npm-зависимости) немедленно даёт атакующему полный доступ к сессии.

4. **Нет rate limiting на login (SEC-004):** При отсутствии блокировки перебора — брутфорс пароля `owner` реален за разумное время. Единственная учётная запись с полным доступом к холдинговым данным.

5. **Дефолтный seed-пароль и adminer без ограничений (SEC-006, SEC-007):** Seed создаёт владельца с паролем `change_me_on_first_login`, а adminer с портом 8080 открыт — в prod-среде это прямой доступ к БД через браузер без дополнительной защиты.

**Что ОБЯЗАТЕЛЬНО сделать до первого деплоя (в порядке приоритета):**

1. Заменить `python-jose` на `authlib`; убрать дефолты `jwt_secret_key` и `database_url` из `Field(default=...)` — запуск без env vars должен падать с ошибкой, не продолжаться с небезопасными дефолтами
2. Реализовать `require_role()` dependency и httpOnly cookie для JWT — до написания первого API-роута
3. Добавить `slowapi` rate limiting на `/auth/login` (5 попыток / 15 мин / IP)
4. Добавить security headers middleware в `main.py` и отключить `/docs`/`/redoc` при `app_env=production`
5. Добавить `pip-audit` и `npm audit --audit-level=high` в CI — нулевая толерантность к high/critical уязвимостям в зависимостях перед деплоем

