# Бриф security-auditor: OWASP Top 10 аудит Sprint 1 (M-OS-1.1A)

**Дата:** 2026-04-19
**От:** quality-director → review-head → security-auditor
**Кому:** security-auditor (через review-head)
**Приоритет:** P0 — security-аудит обязателен раз в фазу (quality.md §«Стандарты security-аудита»)
**Оценка:** 1 рабочий день (OWASP Top 10 прогон + отчёт с классификацией severity)
**Триггер:** закрытие Sprint 1 M-OS-1.1A (US-01 multi-company isolation, US-02 JWT middleware, US-03 RBAC matrix)
**Коммит:** НЕ коммитить — передать артефакты Координатору

---

## Цель

Зафиксировать статус безопасности Sprint 1 кода против чек-листа OWASP Top 10 (2021 edition). Sprint 1 затрагивает три чувствительные зоны: изоляция данных между юрлицами холдинга (US-01), механизм аутентификации с многокомпаний­ной привязкой (US-02), матрица авторизации (US-03). Дефект в любой из них — прямая утечка данных или эскалация прав, то есть P0 для M-OS-1.1A exit-gate.

**Exit criterion:** полный OWASP Top 10 отчёт с классификацией по severity (Critical/High/Medium/Low/Info), нулевое количество **новых** Critical/High findings (по сравнению с baseline M-OS-0); все finding'и имеют либо конкретный file:line, либо reproducible scenario.

## Автотриггер скила

Этот бриф должен автоматически триггерить скил `owasp-top10-checklist` у security-auditor. Если скил не сработал — Координатор указывает на это в эскалации, security-auditor перечитывает скил из `~/.claude/skills/` и повторяет прогон. Без скила аудит не валиден.

## Обязательно прочесть

1. `/root/coordinata56/CLAUDE.md` (все разделы, особенно «Данные / ПД», «Секреты и тесты», «API»)
2. `/root/coordinata56/docs/agents/departments/quality.md` v1.3 §«Стандарты security-аудита» и §«Security scanning»
3. `/root/coordinata56/docs/CONSTITUTION.md` — статьи о PD и multi-company изоляции (если применимо)
4. `/root/coordinata56/docs/agents/CODE_OF_LAWS.md` — ст. 45а/45б (запрет live integrations)
5. ADR 0005 (формат ошибок), ADR 0006 (пагинация), ADR 0007 (аудит), ADR 0011 (RBAC + multi-company), ADR 0013 (safe-migration)
6. Дев-брифы Sprint 1 (см. qa-head-brief-sprint1-regression-2026-04-19.md)
7. Документ `docs/reviews/bandit-baseline-2026-04-18.md` и `docs/reviews/pip-audit-baseline-2026-04-18.md` — известные accepted-findings (не поднимать повторно)

## Скоуп работ

### 1. Идентификация изменённых файлов Sprint 1

```bash
cd /root/coordinata56
git diff --name-only <pre-sprint1-sha>..HEAD | grep -E '^backend/app/' | sort > /tmp/sprint1-changed.txt
```

Sprint 1 затрагивает ориентировочно:
- `backend/app/models/*.py` — новая колонка `company_id` на 12 таблицах
- `backend/app/services/company_scoped.py` — центр фильтрации по компании
- `backend/app/core/auth/jwt.py` (или аналог) — JWT + X-Company-ID middleware
- `backend/app/core/auth/permissions.py` — `require_permission` + deprecation `require_role`
- `backend/alembic/versions/2026_04_19_*` — safe-migration three-step
- `backend/app/api/contracts.py` — consent broad fix
- `backend/conftest.py` — `get_current_policy_version` helper + фикстуры

Эти файлы — первостепенный скоуп аудита. Остальной код — сравнение с baseline.

### 2. Прогон OWASP Top 10 (2021) чек-листа

Для каждой категории — **конкретные проверки Sprint 1 кода**.

#### A01: Broken Access Control

Это главная зона риска Sprint 1 (US-01 + US-03).

**Проверки:**
1. **Cross-company leak via direct object reference.** Для каждого эндпоинта `/<resource>/{id}` — убедиться, что сервис фильтрует по `company_id` user'а (через `CompanyScopedService._scoped_query_conditions`). Проверка через grep: `grep -r "db.query\|session.execute" backend/app/services/ | grep -v "company_scoped\|_scoped"` — любой service-метод, делающий запрос в обход scoped-query, — suspicious.
2. **IDOR на вложенных ресурсах.** `/projects/{pid}/houses/{hid}` — `house.project_id == pid` обязательно. Несовпадение → 404, не 403 (CLAUDE.md §API).
3. **Holding-owner bypass.** Проверить, что bypass реализован явно (через отдельный branch в `require_permission`), а не случайным отсутствием фильтра. Не должен работать по default.
4. **Force browsing.** Попытка GET `/companies/2/users` из токена company_id=1 — 403 или 404 (никогда не 200 с чужими данными).
5. **RBAC bypass через `require_role` deprecation.** Если где-то остался старый `require_role` — не игнорирует ли он новую матрицу? Любой endpoint с `require_role` вместо `require_permission` — finding.
6. **Missing function-level access control.** Grep: `@router\.(post|put|patch|delete)` без `Depends(require_permission(...))` — finding.

#### A02: Cryptographic Failures

**Проверки:**
1. JWT подписывается **только** асимметричным ключом (RS256/EdDSA) или stable-HS256 с секретом в env. Никаких литералов ключей в коде.
2. Секрет JWT — через `settings.JWT_SECRET` или аналог, не литерал в middleware.
3. TTL JWT — ограничен (по ADR — обычно 15 мин access + refresh). Unlimited-lifetime JWT — finding.
4. Хеширование паролей — `bcrypt`/`argon2`, не MD5/SHA1 без соли.
5. Хранение `pd_consent_version` и согласий — проверить, что нет ПД (паспорт, телефон) в clear-text в логах/аудите (CLAUDE.md §Данные/ПД: маскирование ВСЕГДА).

#### A03: Injection

**Проверки:**
1. SQL-инъекции в новых миграциях US-01 backfill — использован ли параметризованный `op.execute(sa.text("..."))` с bind-params, или конкатенация? Конкатенация — P0.
2. Все `CompanyScopedService` методы используют SQLAlchemy ORM, не raw SQL с user-input (`f"WHERE company_id = {user_company_id}"` — finding).
3. NoSQL/LDAP/OS command — в скоупе нет, **подтвердить** отсутствием.
4. Проверить headers (`X-Company-ID`) на валидацию: middleware **должен** парсить `int(header)` с обработкой ValueError → 400, не падать 500.

#### A04: Insecure Design

**Проверки:**
1. **Threat model US-01** — зафиксирован ли он в ADR 0011 / декомпозиции? Есть ли сценарий «бухгалтер компании A вводит `X-Company-ID: 2`»? В middleware должна быть проверка: user **принадлежит** указанной компании через `user_company_roles`. Если нет — 403 `COMPANY_ACCESS_DENIED`.
2. **Rate limiting** на login и refresh JWT — есть ли? Если нет — в backlog, finding severity=Medium.
3. **Fail-secure vs fail-open.** Если `require_permission` не смог загрузить матрицу из БД — он **должен** возвращать 500/503, не пропускать (fail-secure). Проверить логику.

#### A05: Security Misconfiguration

**Проверки:**
1. `APP_ENV` default — `dev`, не `production`. Проверить, что нет ветки «если env не распознан → production-privileges».
2. CORS middleware — не `allow_origins=['*']` в production. В dev можно, но с комментарием.
3. `debug=True` в FastAPI в тестах/staging — допустимо; в production — finding.
4. Стек-трейсы в 500-ответах — не утекают наружу в production (ADR 0005 формат ошибок перехватывает).
5. Default-credentials — seed-юзер `owner@example.com` с известным паролем — только в `conftest.py`, не в prod-seed.

#### A06: Vulnerable and Outdated Components

**Проверки:**
1. `pip-audit` прогон по текущему `pyproject.toml`:
   ```bash
   cd backend && pip-audit --desc
   ```
   Сравнить с `docs/reviews/pip-audit-baseline-2026-04-18.md`. Новые Critical/High CVE — finding.
2. Отдельно проверить `pyjwt` (US-02 использует): версия ≥ 2.9.0 (известная уязвимость в <2.8.0 касательно алгоритма confusion).

#### A07: Identification and Authentication Failures

Прямо затрагивает US-02.

**Проверки:**
1. JWT без подписи (`alg=none`) — отвергается middleware? Тест `test_jwt_alg_none_rejected` должен быть.
2. JWT с чужим алгоритмом (HS256 с публичным RSA-ключом) — атака key-confusion. Middleware должен явно указывать `algorithms=['RS256']` (не `['HS256','RS256']`).
3. Refresh token rotation — реализован или backlog? Если нет — finding Medium.
4. Session fixation — после login выдаётся новый JWT, старый инвалидируется (или JWT stateless и проверяется `iat`).
5. Credential stuffing mitigation — backlog, finding Low.
6. **X-Company-ID без JWT** — middleware должен требовать JWT первым, X-Company-ID — вторым. Иначе можно обойти auth через подмену header.

#### A08: Software and Data Integrity Failures

**Проверки:**
1. Миграции US-01 — round-trip и dry-run проведены (ADR 0013)? Есть ли артефакт `docs/pods/cottage-platform/quality/dry_run_us_01_*.md`?
2. Seed `company_id=1` для backfill — идемпотентен? Повторный прогон не создаёт дубликатов.
3. Аудит-лог — append-only? Проверить, что нет DELETE / UPDATE на `audit_log` в сервисах (ADR 0007).

#### A09: Security Logging and Monitoring Failures

**Проверки:**
1. Каждый write-эндпоинт Sprint 1 пишет в audit_log **в той же транзакции** (CLAUDE.md §API).
2. В audit_log маскируются ПД (паспорт, телефон): `****1234` (CLAUDE.md §Данные/ПД).
3. Failed-login attempts логируются с уровнем WARN, но **без** пароля и **без** полного JWT в логе.
4. Cross-company access denial (403 от middleware) — логируется как security-event.

#### A10: Server-Side Request Forgery (SSRF)

В скоупе Sprint 1 — нет внешних integrations (CLAUDE.md запрет live integrations), поэтому SSRF-риск минимален. Но проверить:
1. Нет ли `httpx.get(url)` / `requests.get(url)` в новом коде US-01/02/03? Grep: `grep -rE "httpx\.|requests\." backend/app/` — вне `_live_transport` и `settings.py` — finding.
2. ACL base class (из Sprint 2) ещё не в main — SSRF-тесты только в Sprint 2 scope.

### 3. Автоматические проверки (Bandit, pip-audit)

Прогнать и сверить с baseline:
```bash
cd backend
bandit -r app/ -f json -o /tmp/sprint1-bandit.json
pip-audit --desc > /tmp/sprint1-pip-audit.log 2>&1
```

Новые high-severity Bandit findings (не в baseline) — перечислить. Новые critical CVE — перечислить.

### 4. Классификация findings

Каждый finding:
- **Severity:** Critical / High / Medium / Low / Info
- **OWASP category:** A01..A10
- **Type:** false-positive / real-issue / backlog
- **Location:** file:line или reproducible scenario
- **Recommendation:** конкретный фикс или ссылка на ADR/backlog

## Ограничения

- **Не чинить код.** Security-auditor находит и документирует, фиксит backend-dev через Координатора.
- **Не запускать live-атаки.** Аудит — статический + unit-тестовый. Никаких HTTP-запросов к production (которого и нет).
- **ПД в отчёте — маскировать.** Если в findings всплыл реальный паспорт в логе — в отчёте показать `****1234`, не полный номер.
- **Не коммитить.** Артефакты `/tmp/sprint1-owasp-*` передать Координатору.
- `FILES_ALLOWED`:
  - `docs/reviews/owasp-sprint1-2026-04-19.md` (новый отчёт)
  - `docs/pods/cottage-platform/quality/bug_log.md` (append-only для Critical/High findings)
- `FILES_FORBIDDEN`: `backend/app/**`, `backend/tests/**` (security-auditor — read-only в отношении кода).

## Критерии приёмки (DoD)

- [ ] Скил `owasp-top10-checklist` автотриггернулся и применён (подтверждение в отчёте)
- [ ] Все 10 категорий OWASP 2021 пройдены, каждая имеет subsection в отчёте (даже если «no finding»)
- [ ] Изменённые файлы Sprint 1 перечислены, каждый имеет секцию «проверено на X»
- [ ] Для US-01: явно проверен cross-company leak через force-browsing + IDOR
- [ ] Для US-02: явно проверен alg=none, key-confusion, X-Company-ID bypass
- [ ] Для US-03: явно проверена RBAC-матрица на эскалацию
- [ ] Bandit delta vs baseline зафиксирована
- [ ] pip-audit delta vs baseline зафиксирована
- [ ] Все findings классифицированы по severity и OWASP-категории
- [ ] 0 новых Critical/High (или — точный список с BUG-id для возврата backend-head)
- [ ] Отчёт `docs/reviews/owasp-sprint1-2026-04-19.md` создан (НЕ коммитить)
- [ ] Сводка security-auditor → review-head → quality-director ≤ 300 слов

## Эскалация

Немедленная остановка gate + эскалация Координатору (не ждать конца прогона):
- Найдена cross-company leak (A01) — P0
- Найдена эскалация прав через bypass `require_permission` (A01) — P0
- Найден `alg=none` accept или key-confusion (A07) — P0
- Найден хардкод секрета/ключа в коде (A02) — P0
- ПД в логах без маскирования (A09) — P0

---

*Бриф составил quality-director 2026-04-19. Маршрут: quality-director → Координатор (транспорт) → review-head → security-auditor. Возврат — обратным маршрутом. Pattern 5 fan-out не применяется (1 аудитор, 1 скоуп).*

---

## Instruction для Координатора при спавне security-auditor

- security-auditor — Opus-агент (CLAUDE.md §«Процесс», Extended Thinking list). При `Agent`-вызове **обязательно** вставить ключевое слово `ultrathink` в начало промпта. Без этого скил `owasp-top10-checklist` триггернётся, но без extended-reasoning аудит потеряет глубину на A01/A07 (кросс-файловые сценарии эскалации и key-confusion).
- Промпт Координатора security-auditor'у ссылается на **этот файл** (`docs/pods/cottage-platform/tasks/security-auditor-brief-sprint1-owasp-2026-04-19.md`) как на бриф; не переписывать содержимое в промпт.

---

## review-head sign-off: APPROVED review-head 2026-04-19 + ready-for-spawn: yes
