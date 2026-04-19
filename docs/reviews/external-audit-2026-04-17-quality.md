# Анализ внешнего аудита (codex/GPT) — зона ответственности Quality (Security)

- **Дата**: 2026-04-17
- **Автор**: quality-director (L2, субагент)
- **Адресат**: Координатор (для сводки Владельцу)
- **Объект аудита**: локальный прототип Владельца `/Users/martinvasilev/Documents/cottage-platform` (Next.js + Prisma + Supabase) + зеркало `coordinata56-docs`
- **Природа прототипа**: не определена (может быть на выброс, может стать каркасом). Анализ ведётся в обе стороны.

---

## 0. Общая оценка аудита

Аудит корректен по сути и критичности. Все 5 находок действительно P0 по нашим стандартам (CODE_OF_LAWS v2.1 + Конституция M-OS + ADR 0011/0014). Ниже — пройдусь по каждой, добавлю attacker-scenario, ссылку на статьи и перечень тестов, которые должны закрывать это в CI M-OS-1.

**Важно**: независимо от того, живёт прототип или нет, эти 5 находок — каталог ошибок, которые мы обязаны исключить в M-OS-1 Волне 1. Аудит де-факто дал нам готовый threat-model, который следует превратить в CI-тесты.

---

## 1. Анализ P0 security-находок

### 1.1 [P0 подтверждён] Hardcoded live AI credential (ст. 45а, 78, 79)

**Файл аудита**: `src/app/api/ai/report/route.ts:9-10` — Anthropic API-ключ в исходнике.

**Attacker scenarios** (реализуемо прямо сейчас):

1. **Утечка через git-history**. Любой, кто получил read-доступ к репозиторию (включая публичное зеркало, форк, случайный push на GitHub), получает рабочий ключ Anthropic. Анализ billing-пайплайна Anthropic: ключ не ротируется автоматически — финансовый урон = остаток по плану Владельца × время до обнаружения.
2. **Утечка через CI-логи**. Если где-то в pipeline печатается env или трассируется ошибка — ключ попадает в неконтролируемые логи (GitHub Actions, Vercel build logs).
3. **Утечка через frontend-bundle**. В Next.js `route.ts` исполняется на сервере, но если по ошибке импорт попал на клиент (через shared util), ключ уедет в браузер — это уже полный compromise.

**Нарушаемые нормы M-OS**:
- **Конституция ст. 79** («секреты не размещаются в коде, комментариях, логах») — прямо нарушено.
- **Конституция ст. 78** (security by design) — нарушено: механизм защиты секретов отсутствует.
- **CODE_OF_LAWS ст. 40** («секреты никогда не литералятся») — прямо нарушено.
- **CODE_OF_LAWS ст. 45а** (запрет живых интеграций до production-gate) — нарушено дважды: (а) живой вызов к внешнему AI-провайдеру без production-gate; (б) живой вызов в обход слоя адаптеров ADR 0014.
- **ADR 0014** — нарушено: нет `IntegrationAdapter` для Anthropic, нет `_mock_transport`, нет записи в `integration_catalog`.

**Что должно стоять в CI M-OS-1**:
- `detect-secrets` или `gitleaks` как pre-commit hook и как обязательный gate в pipeline. Блокирует коммит с высоко-энтропийной строкой.
- Test `test_no_hardcoded_external_urls` (DoD ADR 0014) — grep по `backend/app/` на `http(s)://` вне `_live_transport`.
- Test `test_no_hardcoded_api_keys` — grep по `sk-ant-`, `sk-`, `AKIA`, `ghp_` и аналогам.
- `test_all_adapters_have_mock` и `test_dormant_adapters_make_no_network_calls` из DoD ADR 0014.

### 1.2 [P0 подтверждён] API routes bypass auth proxy (ст. 78, ADR 0011)

**Файл аудита**: `src/proxy.ts:24-32` — matcher защищает страницы, но исключает `/api/*`.

**Attacker scenarios**:

1. **Прямой вызов AI-эндпоинта без авторизации**. `/api/ai/report` читает бизнес-данные (договоры, платежи) и дёргает Anthropic. Злоумышленник, знающий URL, получает (а) чужие бизнес-данные; (б) управляемую генерацию через нашу квоту Anthropic, что оборачивается prompt-injection атакой через user-controlled payload.
2. **Энумерация**. `/api/*` без auth-gate позволяет прощупать наличие эндпоинтов, определить модели, угадать id, вытянуть данные постранично.
3. **SSRF-плацдарм**. Эндпоинт, который ходит наружу (Anthropic) без авторизации, — классическая точка для SSRF, если параметры запроса влияют на URL/body внешнего вызова.

**Нарушаемые нормы M-OS**:
- **Конституция ст. 78** (security by design).
- **ADR 0011** (Fine-grained RBAC: `require_permission` обязателен на каждом write-эндпоинте; и read-эндпоинт над бизнес-данными — тоже должен проходить проверку прав).
- **CODE_OF_LAWS ст. 39** (отклонения от ADR требуют согласования) — RBAC был пропущен без согласования.

**Что должно стоять в CI M-OS-1**:
- **`test_all_api_routes_require_auth`** — автотест, собирающий все зарегистрированные роуты FastAPI и проверяющий, что без токена каждый возвращает 401 (кроме явного allowlist: `/auth/token`, `/healthz`, `/docs`, `/openapi.json`).
- **`test_rbac_matrix_coverage`** — на каждый write-эндпоинт: 4 роли × 403 для не-допустимых (регламент quality.md п. 8).
- **`test_cross_company_isolation`** — пользователь компании A не получает ресурсы компании B (ADR 0011).
- **`test_no_bulk_enumeration_without_auth`** — любой `GET /api/<list>` без токена → 401, не «пустой список».

### 1.3 [P0 подтверждён] Plaintext demo credentials (ст. 79, ADR 0011)

**Файл аудита**: `src/app/api/auth/[...nextauth]/route.ts:14-17` — in-memory список plaintext-паролей.

**Attacker scenarios**:

1. **Раскрытие паролей через исходник**. Plaintext-пароль в репозитории = скомпрометированный пароль на всех сервисах, где пользователь его переиспользует (это статистически всегда случается).
2. **RBAC bypass**. «Любой залогиненный = admin» — нарушение ADR 0011 multi-company isolation: бухгалтер АЗС видит договоры коттеджей.
3. **Отсутствие audit chain**. Демо-механизм не пишет в AuditLog (ADR 0011 §3) — любое действие под демо-аккаунтом юридически не доказуемо.

**Нарушаемые нормы M-OS**:
- **Конституция ст. 79.2** (секреты не в коде) — прямое нарушение.
- **Конституция ст. 81** (MFA для расширенных прав) — демо-механизм вообще не предусматривает hashing, не говоря о MFA.
- **ADR 0003** (хранение паролей — bcrypt через passlib) — прямое нарушение.
- **ADR 0011** (Fine-grained RBAC, multi-company) — отсутствует.
- **CODE_OF_LAWS ст. 40** — прямое нарушение.

**Что должно стоять в CI M-OS-1**:
- **`test_passwords_are_hashed`** — проверка, что в БД нет plaintext-паролей: после регистрации поле `password_hash` начинается с `$2b$` (bcrypt-PHC) или `$argon2id$`.
- **`test_login_with_wrong_password_returns_401_generic`** — сообщение об ошибке не раскрывает, существует ли пользователь (anti-enumeration, регламент quality.md п. 1).
- **`test_jwt_contains_company_ids_and_role_flags`** — JWT из ADR 0011: `company_ids: list[int]`, `is_holding_owner: bool`.
- **`test_cross_company_write_blocked`** — запись в чужую компанию → 403.
- **`test_fixtures_use_random_passwords`** — grep, чтобы `secrets.token_urlsafe(16)` использовался в фикстурах, не литералы (регламент quality.md п. 2).

### 1.4 [P0 подтверждён] Prisma 7 schema invalid (не прямая security, но DoD-блокер)

Сам по себе не security, но: если `prisma validate` падает, значит и миграции не проходят round-trip. У нас прямое требование **ADR 0013 (migrations evolution contract) + CLAUDE.md «Миграции — обязательный round-trip»**. Невалидная схема ломает механизм эволюции БД, а значит, и откат на любую контрольную точку при инциденте безопасности.

**Нарушаемые нормы**: ADR 0013, CLAUDE.md (раздел «Данные и БД»).

**Тест в CI**: обязательный шаг `alembic upgrade head && alembic downgrade -1 && alembic upgrade head` в pipeline M-OS-1. Если Prisma — тогда `prisma validate && prisma migrate deploy && prisma migrate reset` (в зависимости от судьбы прототипа — см. раздел 4).

### 1.5 [P0 подтверждён] Production build fails (DoD-блокер)

`next build` падает на передаче функции как click-handler с несовпадающей сигнатурой. Сам по себе это качество, не security. Но в нашем DoD: **«код, который не собирается, не может быть задеплоен»** — то есть это блокер релиза.

**Тест в CI**: обязательный шаг `npm run build` (или FastAPI-эквивалент: `ruff check && pytest && mypy`) в pipeline M-OS-1.

---

## 2. Отсутствие тестового контура — план

### 2.1 Что обязано быть в CI M-OS-1 **Волна 1 (минимальный пакет)**

**Security-gates (блокируют merge)**:

1. `detect-secrets` / `gitleaks` pre-commit + pipeline stage.
2. `pytest-socket` в корневом `conftest.py` с `autouse=True` (DoD ADR 0014).
3. `test_no_hardcoded_external_urls` (DoD ADR 0014).
4. `test_all_adapters_have_mock` (DoD ADR 0014).
5. `test_dormant_adapters_make_no_network_calls` (DoD ADR 0014).
6. `test_all_api_routes_require_auth` — покрытие всех зарегистрированных роутов.
7. `test_passwords_are_hashed` — smoke после регистрации.
8. `test_fixtures_use_random_passwords` — ruff custom rule или grep-тест.

**Infrastructure-gates**:

9. `alembic upgrade head && alembic downgrade -1 && alembic upgrade head` (ADR 0013 + CLAUDE.md).
10. `ruff check + ruff format --check` (CODE_OF_LAWS ст. 44).
11. Build-проверка (`next build` или эквивалент).

**RBAC-gates (минимум)**:

12. `test_rbac_matrix_coverage` — параметризованно: 4 роли × все write-эндпоинты → 403 для не-допустимых.
13. `test_cross_company_isolation` — один positive + один negative тест для основного эндпоинта (contracts).
14. Для каждого write-эндпоинта: `test_<entity>_write_produces_audit_log` (ADR 0007 + ADR 0011 crypto chain).

**Error-format gates (ADR 0005)**:

15. По одному тесту на класс ошибок (404/403/422/409) — проверка полного envelope `{error: {code, message, details}}` (регламент quality.md п. 7).

### 2.2 Что откладывается на Волну 2+

- Полный OWASP Top 10 sweep — запланирован раз в фазу (quality.md «Стандарты security-аудита»).
- Нагрузочные тесты `audit_log SELECT FOR UPDATE` (ADR 0011 риск).
- E2E-тесты UI (frontend).
- Contract-тесты OpenAPI vs реализация.
- Fuzz-тесты на эндпоинты (security-phase по ADR 0003).
- MFA-тесты (ст. 81 Конституции — требование, но реализация не входит в Волну 1).

### 2.3 `tools/lint_migrations.py` (упомянут в аудите)

Аудит справедливо отметил отсутствие. В Волну 1 — добавить минимум: (а) проверку, что у каждой миграции есть `downgrade`; (б) проверку, что перечисления Alembic `sa.Enum(..., name='...')` совпадают с Python-`Enum.value` (правило CLAUDE.md, поймано в Phase 3 Batch A step 1).

---

## 3. Security-план для M-OS-1 (независимо от судьбы прототипа)

Чек-лист НОВОЙ реализации — чтобы не повторить ошибки прототипа:

### 3.1 Хранение секретов

- Все секреты — `os.environ.get(...)` без дефолтов для production-значений. Для dev — дефолт-заглушка, которая **физически не работает** (например, `JWT_SECRET_KEY=devonly-not-secret`, и login-эндпоинт в production падает, если увидит эту строку).
- `.env` в `.gitignore` (проверка в CI: `test_env_not_tracked`).
- `.env.example` — без настоящих значений, только имена переменных.
- Для production — секреты только через secrets manager (на M-OS-1 допустим systemd-env-файл с правами `0600` у владельца сервиса; полноценный secrets manager — M-OS-2).
- AI-ключи (Anthropic и т.п.) **не хранятся в M-OS-1** — вызов AI через ACL-адаптер в состоянии `written` или `enabled_mock` до production-gate (ADR 0014 + ст. 45а).

### 3.2 Pre-commit hooks (блокируют локальный коммит)

- `detect-secrets` или `gitleaks` — на высокоэнтропийные строки.
- `ruff check` + `ruff format --check`.
- `mypy --strict` на `backend/app/`.
- `pytest -m fast` — быстрый smoke-набор (опционально; полный pytest — в pipeline).

Настраивается в `.pre-commit-config.yaml` + `pre-commit install` при онбординге.

### 3.3 Auth guard на все `/api/*`

- Default-deny: глобальный dependency `require_authenticated` на `app.router`. Каждый публичный endpoint явно исключается через `dependencies_override` или декоратор `@public_endpoint` — это explicit opt-out, не opt-in.
- Проверочный тест `test_all_api_routes_require_auth` — итерирует `app.routes` и assert-ит 401 без токена.
- На каждый endpoint, требующий прав (write, read бизнес-данных) — `require_permission(action, resource_type)` из ADR 0011.

### 3.4 Password hashing

- **bcrypt через passlib[bcrypt]** — как принято в ADR 0003.
- В backlog security-фазы: миграция на **argon2id** с re-hash on login (ADR 0003 §2 Примечание, ст. 79 Конституции).
- Политика сложности пароля — минимум 12 символов (достаточно для MVP; полная политика — security-фаза).
- Smoke-тест: `test_password_stored_is_bcrypt_hash` (регулярка `^\$2[aby]\$\d{2}\$`).

### 3.5 RBAC alignment с ADR 0011

- Все эндпоинты — через `require_permission(action, resource_type)`, не `require_role`.
- Все сервисы бизнес-логики — наследники `CompanyScopedService` из ADR 0011 §1.3.
- JWT содержит `company_ids: list[int]` и `is_holding_owner: bool`.
- Заголовок `X-Company-ID` — обязателен, если у пользователя несколько компаний.
- Тесты: (а) matrix 4 роли × 5 actions × 3 resource_types; (б) holding-owner bypass; (в) cross-company block; (г) pod-scoped access.

### 3.6 AuditLog crypto chain

- `prev_hash` + `hash` (SHA-256) на каждой записи (ADR 0011 §3).
- `SELECT ... FOR UPDATE` на последней записи при INSERT — закрывает race condition.
- Endpoint `/api/v1/audit/verify` — только `is_holding_owner`.
- Тест: `test_audit_chain_verifies_clean_after_100_writes`, `test_audit_chain_detects_broken_link`.

### 3.7 ACL по ADR 0014 (обязательно)

- Ни один `httpx.get/post`, `requests.*`, `fetch(...)` вне класса, наследующего `IntegrationAdapter._live_transport`.
- Ни один live-адаптер в M-OS-1, кроме Telegram. Anthropic/OpenAI — в состоянии `enabled_mock` (если вообще нужны) либо `written` (если пока не нужны).
- Egress iptables — отдельная заявка через Координатора к infra-director (открытый вопрос ADR 0014).

---

## 4. Порядок действий — согласие и дополнения к плану аудитора

Аудитор предложил:
1. Ротировать Anthropic-ключ (это делает Владелец).
2. Закрыть `/api/*` auth guard.
3. Минимальный Foundation PR.

**Согласен с порядком. Дополняю и уточняю**:

### 4.0 Немедленные действия (owner-only, сегодня)

- **Ротация Anthropic-ключа** (делает Владелец) — до любых иных действий. Старый ключ — в revoked, в Anthropic dashboard включить alert на аномальное использование старого ключа (если платформа позволяет).
- **Убрать ключ из git-history прототипа** (если прототип живёт). BFG Repo-Cleaner или `git filter-repo` — это делает Владелец или его подрядчик по прототипу. Без этого факта ротации недостаточно: старый ключ остаётся в истории.

### 4.1 Решение о судьбе прототипа (блокирует следующие шаги)

**Рекомендация quality-director**: **не тянуть код прототипа в M-OS-1**. Основания:

- Стек прототипа (Next.js + Prisma + Supabase) не соответствует утверждённому стеку M-OS (FastAPI + PostgreSQL + Alembic, ADR 0002). Перенос потребует рефакторинга всей data layer.
- В коде прототипа нарушены сразу 5 P0 — такой код проще переписать по ADR 0011/0014, чем чинить.
- Наш процесс (reviewer-до-commit, phase-checklist, CODE_OF_LAWS) с прототипом не совмещался — история коммитов не доверена.

Прототип полезен как **функциональный референс UX** (user flows, wireframes, feature list), но не как исходный код.

**Если Владелец принимает решение «прототип — на выброс»**: идём напрямую в M-OS-1 Волна 1 по утверждённому плану.

**Если Владелец хочет сохранить прототип как рабочий код**: требуется отдельная governance-заявка (вне моей компетенции) на amendment ADR 0002 (стек). До тех пор — прототип помечается как `quarantine/` и не считается частью M-OS.

### 4.2 Скорректированный порядок (независимо от судьбы прототипа)

1. **Ротация ключа** — немедленно.
2. **Заморозить разработку в прототипе**: никаких новых коммитов, пока не принято решение о судьбе. Иначе мы накапливаем долг.
3. **M-OS-1 Волна 1 Foundation PR** — минимальный скелет с фичами (в порядке приоритета):
   - `.gitignore` + `.env.example` + pre-commit hooks (`gitleaks`/`detect-secrets`, `ruff`, `mypy`).
   - Pipeline-каркас (`.github/workflows/ci.yml` или эквивалент): lint → migrations round-trip → pytest → build.
   - Каркас ADR 0014: `IntegrationAdapter`, `AdapterDisabledError`, `pytest-socket` в `conftest.py`.
   - Миграция Foundation (ADR 0011): `companies`, `user_company_roles`, `role_permissions`, `company_id` во всех бизнес-таблицах, crypto-chain на `audit_log`.
   - `require_permission` + глобальный `require_authenticated` на `/api/*`.
   - Базовые security-тесты из раздела 2.1 (15 тестов — минимум).
4. **Вторая волна** — OpenAPI-генерация, `tools/lint_migrations.py`, расширение RBAC-матрицы, MFA-задел.

### 4.3 Что добавить сверх плана аудитора

- **Решение о судьбе прототипа** — пункт 4.1, критический вопрос к Владельцу.
- **Удаление ключа из git-history**, не только ротация.
- **Заморозка прототипа** на время принятия решения.
- **Глобальный default-deny auth guard**, не просто исправление matcher-а proxy. Matcher-подход даёт ложное чувство безопасности: при добавлении нового роута разработчик может забыть обновить matcher.
- **CI-gate на коммит** (не только на merge), чтобы секреты не попадали даже в feature-branch.

---

## 5. Дополнительные находки quality-director (сверх аудита)

В процессе анализа заметил следующее, что аудитор не подсветил, но это наши собственные риски:

### 5.1 Наличие ключа AI в прототипе = инцидент безопасности по CODE_OF_LAWS

По ст. 45б любое предложение живой интеграции идёт через Владельца. Ключ Anthropic в прототипе означает, что интеграция с Anthropic уже де-факто произошла без процедуры 45б. Это инцидент. **Должен быть задокументирован в `docs/governance/incidents/` как кейс для извлечения уроков** — не для наказания, а чтобы процедура 45б была реализована в M-OS-1 как обязательный шаг.

### 5.2 Публичное зеркало `coordinata56-docs`

Если аудитор имеет доступ к зеркалу — вероятно, зеркало публично или полупублично. Необходимо убедиться, что в зеркало не попадают (и не попадут в будущем):
- никакие `.env`, `secrets/`, `credentials/`, `*.key`, `*.pem`;
- скриншоты админ-панели с реальными id/email;
- ADR с ссылками на внутренние эндпоинты.

**Рекомендация**: добавить в процесс публикации зеркала отдельный `gitleaks`-gate и `.mirrorignore` с исключениями.

### 5.3 Отсутствие Content Security Policy и security-headers

Next.js-прототип по умолчанию не ставит CSP, HSTS, X-Frame-Options, Referrer-Policy. Это не P0, но P1 — должно быть в backlog security-фазы, не откладываться до выхода в production.

### 5.4 `tools/lint_migrations.py` должен проверять также partial indexes

По ADR 0011 есть партиальный индекс `WHERE is_active=TRUE` на `companies.inn`. Линтер миграций должен проверять совместимость партиальных индексов с Alembic autogenerate (известная проблема — autogenerate их игнорирует).

### 5.5 Отсутствие threat model для AI-эндпоинта

`/api/ai/report` — это интересный класс эндпоинта: он читает бизнес-данные и шлёт их внешнему LLM. Это **exfiltration surface**: пользователь-злоумышленник может через prompt-injection вытянуть больше данных, чем ему положено по RBAC. Нужен отдельный под-раздел threat model «AI-эндпоинты»:
- Что можно отправлять во внешний LLM (принцип минимизации, ст. 85 Конституции).
- Как логируется промпт и ответ.
- Как обеспечивается, что LLM-ответ не вытаскивает данные других компаний (cross-company leak через общий контекст).

Это — задача на ADR-следующего уровня, когда AI-функциональность вернётся в план. Пока AI-эндпоинтов в M-OS-1 нет (по решению «прототип на выброс» или после ротации ключа), этот пункт в backlog.

---

## 6. Сводка: что обязательно, что отложено

| Зона | Волна 1 M-OS-1 | Позже |
|---|---|---|
| Ротация ключа Anthropic | **Сегодня** (Владелец) | — |
| Удаление ключа из git-history прототипа | **Сегодня** (если прототип живёт) | — |
| Решение о судьбе прототипа | **До старта Волны 1** (Владелец) | — |
| pre-commit hooks + gitleaks | Волна 1 | — |
| `pytest-socket autouse` | Волна 1 | — |
| ADR 0014 каркас адаптеров | Волна 1 | — |
| ADR 0011 multi-company + RBAC + crypto audit | Волна 1 | — |
| Default-deny auth guard на `/api/*` | Волна 1 | — |
| Pipeline CI (lint + migrations round-trip + pytest + build) | Волна 1 | — |
| `tools/lint_migrations.py` минимум | Волна 1 | Расширение на partial indexes — Волна 2 |
| OpenAPI генерация | Волна 2 | — |
| MFA для owner | Security-фаза | — |
| argon2id миграция | Security-фаза | — |
| Egress iptables | Требует infra-director — Волна 2+ | — |
| Full OWASP Top 10 sweep | Раз в фазу | — |
| Threat model для AI-эндпоинтов | Когда AI вернётся в план | — |
| Инцидент по ст. 45б оформить | В Governance (отдельно) | — |

---

## 7. Что требует решения Координатора (эскалация)

1. **Решение «судьба прототипа»** — нужно спросить Владельца. Без этого следующие шаги не стартуют.
2. **Активация infra-director** (для egress iptables) — открытый вопрос из ADR 0014.
3. **Оформление инцидента по ст. 45б** (Anthropic-ключ) — через governance-director, не через меня. Это не наказание, а фиксация прецедента для процедурного извлечения урока.
4. **Публичное зеркало `coordinata56-docs`** — убедиться, что в зеркало не утекают секреты; добавить `gitleaks` в процесс публикации.

---

*Подготовлено quality-director (L2). Передаётся Координатору для сводки Владельцу. Код прототипа не правился (не в нашем репозитории), заявок в Governance не подано (только анализ).*
