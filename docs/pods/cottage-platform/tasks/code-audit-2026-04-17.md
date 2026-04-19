# Бриф: Полный внутренний аудит кода coordinata56 / M-OS

- **Тип**: задача уровня L (cross-department)
- **Дата выдачи**: 2026-04-17
- **Выдал**: quality-director (L2)
- **Адресат**: review-head (L3), qa-head (L3)
- **Параллельно задействован**: security (Советник L4) — через Координатора, не напрямую
- **Срок**: 5–7 календарных дней
- **Источник поручения**: Владелец (Telegram msg 1226, 2026-04-17), через Координатора
- **Консолидированный выход**: `docs/reviews/code-audit-2026-04-17.md` (составляю я как quality-director, подписываю перед передачей Координатору)

---

## 0. Назначение брифа

Владелец увеличил подписку до 20× Max — ресурсные ограничения сняты. Проводим **полный аудит существующего кода** проекта `coordinata56`. Область — всё, что написано в Фазах 0–3 и в Батче M-OS-0 Reframing. Цель — найти, зафиксировать и приоритизировать все дефекты до начала M-OS-1 Волны 1, чтобы не тащить технический долг в новую фазу.

Этот бриф — **задача двум Начальникам отделов одновременно**. review-head и qa-head работают параллельно по своим блокам; security-советника запрашиваю через Координатора. Я консолидирую результаты и пишу executive summary.

---

## 1. Принципы работы (обязательны к исполнению)

1. **Аудит — только чтение.** Ни один участник аудита не правит код. Все правки — отдельными PR через backend-director / frontend-director после приёмки отчёта. (Статья 22 CODE_OF_LAWS: worker в пределах FILES_ALLOWED; здесь FILES_ALLOWED = пусто на код, только `docs/reviews/**` и `docs/qa/bugs/**`.)
2. **Независимость ревьюеров.** Если ревьюер натыкается на код, который сам писал — помечает «self-review, передаю другому» и возвращает работу Начальнику отдела для переназначения. (Статья 38 CODE_OF_LAWS плюс принцип независимости.)
3. **P0 эскалируется немедленно.** Не копим до конца аудита. Нарушения CODE_OF_LAWS ст. 40 (литерал секрета), ст. 45а (живой вызов), ст. 79 (секрет в коде/логе), ст. 81 (отсутствие MFA для расширенных прав), подтверждённый SQLi, подтверждённая подмена authZ — ко мне немедленно, я эскалирую Координатору. Координатор вызывает Владельца.
4. **Границы ответственности.** review-head ведёт статический анализ кода + ADR-соответствие + code-quality. qa-head ведёт анализ покрытия + недостающие тесты + round-trip миграций + интеграционные разрывы. security (через Координатора) — OWASP + secrets scan + dependency audit + authZ.
5. **Маршрут отчётов.** ревьюер → review-head / qa-head → quality-director → Координатор. Обратно так же.
6. **DoD-чек-лист отдельно на Ваш блок** — см. раздел 6.
7. **Перед началом работы обязательно прочесть** (ст. 20 CODE_OF_LAWS + regulations_addendum_v1.3 §1):
   - `/root/coordinata56/CLAUDE.md`
   - `/root/coordinata56/docs/agents/departments/quality.md`
   - ADR 0001–0007 (MVP-стек), ADR 0011 (Foundation), ADR 0013 (Migrations Contract, proposed), ADR 0014 (ACL, proposed)
   - `docs/CONSTITUTION.md` — разделы «Безопасность и персональные данные» (ст. 77–85), «Данные и источник истины» (ст. 40–48)
   - `docs/agents/CODE_OF_LAWS.md` v2.1 — Книга IV Раздел V (интеграционный шлюз)

---

## 2. Область аудита — чёткие границы

### 2.1. Backend (`/root/coordinata56/backend/`)

**Модели** (`app/models/`, всего 14 Mapped-классов в 10 файлах):

| Файл | Основные модели |
|---|---|
| `user.py` (29 строк) | User |
| `company.py` (38 строк) | Company |
| `user_company_role.py` (64) | UserCompanyRole |
| `project.py` (24) | Project |
| `contract.py` (170) | Contract, Contractor |
| `house.py` (141) | House, HouseType, HouseStageHistory, HouseTypeOptionCompat |
| `stage.py` (24) | Stage |
| `budget.py` (90) | BudgetCategory, BudgetPlan |
| `material.py` (50) | MaterialPurchase, Payment |
| `audit.py` (50) | AuditLog |
| `enums.py` (83) | enums (UserRole, PaymentStatus, ContractStatus, ...) |
| `mixins.py` (36) | SoftDeleteMixin, TimestampMixin |

**Сервисы** (`app/services/`, всего ~3 200 строк):
- `base.py` (49) — базовый сервис
- `company_scoped.py` (73) — базовый класс CompanyScopedService (новый, из ADR 0011)
- `audit.py` (98) — AuditService
- `project.py` (221), `stage.py` (184), `house_type.py` (248), `house.py` (614), `contractor.py` (228), `contract.py` (352), `payment.py` (458), `budget_category.py` (228), `budget_plan.py` (304), `option_catalog.py` (176), `material_purchase.py` (364)

**API-модули** (`app/api/`, 13 роутеров, ~3 400 строк):
- `auth.py` (222), `deps.py` (220), `health.py` (32)
- `projects.py` (261), `stages.py` (176), `house_types.py` (233), `houses.py` (480), `contractors.py` (280), `contracts.py` (314), `payments.py` (433), `budget_categories.py` (276), `budget_plans.py` (345), `option_catalog.py` (173), `material_purchases.py` (293)

**Миграции Alembic** (`alembic/versions/`, 8 штук):
1. `2026_04_11_1911_...initial_schema.py` (329)
2. `2026_04_15_0737_...seed_initial_owner.py` (117)
3. `2026_04_15_1016_...payment_status_enum.py` (30)
4. `2026_04_15_1200_...budget_soft_delete_and_upsert_indexes.py` (119)
5. `2026_04_15_1400_...payment_approve_reject_audit.py` (102)
6. `2026_04_15_1500_...contractor_inn_partial_unique.py` (50)
7. `2026_04_16_1450_contract_contractor_number_unique_partial.py` (47)
8. `2026_04_17_0900_...multi_company_foundation.py` (337) — **под особым контролем, самая недавняя, самая большая**

**Тесты** (`tests/`, 14 файлов, ~10 000 строк, 351+ тестов):
- `conftest.py` (в корне backend/, фикстуры pytest)
- `test_auth.py` (634), `test_health.py` (60), `test_projects.py` (964), `test_stages.py` (362)
- `test_house_types.py` (418), `test_houses.py` (1289), `test_option_catalog.py` (358)
- `test_contractors.py` (541), `test_contracts.py` (1042), `test_payments.py` (1025)
- `test_budget_categories.py` (676), `test_budget_plans.py` (1104), `test_material_purchases.py` (598)
- `test_batch_a_coverage.py` (1394) — сводное покрытие Батча A
- `test_company_scope.py` (512) — **новый, под особым вниманием QA**

**Ядро** (`app/core/`): `config.py`, `security.py`.

### 2.2. Frontend (`/root/coordinata56/frontend/`)

5 страниц каркаса + конфиги:
- `src/App.tsx`, `src/main.tsx`, `src/routes.tsx`
- `src/pages/` — Dashboard, Houses, Finance, Schedule, NotFound (уточнить список в аудите)
- `src/components/` — shadcn/ui и свои компоненты
- `src/lib/` — утилиты
- `package.json`, `vite.config.ts`, `tsconfig.json`, `tsconfig.node.json`, `tailwind.config.ts`, `postcss.config.js`, `components.json`, `index.html`

### 2.3. Scripts / Tools

- `scripts/` — в частности dashboard-сервер (http://81.31.244.71:8765/) — прочесть и оценить security posture (не слушает ли 0.0.0.0 без auth, нет ли path traversal).
- `.claude/hooks/` если присутствуют — пройтись на исполнение произвольного кода, shell-injection.

### 2.4. Инфраструктура

- `docker-compose.yml`, `Dockerfile` (root и backend) — secrets, latest-tags, non-root user, healthchecks
- `.github/workflows/ci.yml` и `docs-validation.yml` — secrets в workflow, permissions, версии actions
- `Makefile` — shell-injection, env-leaks
- `.env`, `.env.example`, `.env.dev.example`, `backend/.env`, `backend/.env.example` — проверить что **никакие реальные секреты не коммичены**; проверить `.gitignore`
- `alembic.ini`, `pyproject.toml` (backend), `lychee.toml`, `managed_agents/`

### 2.5. Что НЕ входит в аудит

- Содержимое `docs/` — кроме чтения ADR и регламентов для проверки соответствия.
- Сессионные `__pycache__/`, `node_modules/`, `.egg-info/`.
- Memory files (`~/.claude/...`).

---

## 3. Разделение работы между Начальниками

### 3.1. Блок review-head (ревьюеры L4)

**Ответственный**: review-head.
**Исполнители**: reviewer-1, reviewer-2 (могут быть дополнительно up-shift-нуты до Opus на время аудита — согласовать с Координатором).

#### Задача R-1. Соответствие ADR (построчный аудит реализации к решениям)

Для каждого ADR — ответ «реализовано корректно / частично / не реализовано / отклонение без amendment». Привязка к файлам с номерами строк.

| ADR | Что проверять (ключевые места) |
|---|---|
| **0001** — data model v1 | 14 моделей vs описание ADR; типы полей, nullable, индексы, FK cascade-политика, naming conventions; `mixins.py` (SoftDelete, Timestamp); `enums.py` — совпадают ли `.value` Python-enum с CHECK-constraint в миграциях (ловим паттерн из CLAUDE.md §«Данные и БД») |
| **0002** — tech stack | Версии: Python 3.12, FastAPI, SQLAlchemy 2.0 (не 1.x-паттерны), Pydantic v2 (не v1), Alembic, passlib+bcrypt. Никаких неутверждённых зависимостей в `pyproject.toml` |
| **0003** — auth MVP | `api/auth.py`, `core/security.py`. Bcrypt через passlib, JWT, время жизни токена, refresh-mechanism (если есть), поведение при смене пароля, rate-limit на login (или его отсутствие как дефект). **Отдельно**: заменён ли `require_role` на `require_permission` (ADR 0011 §2.3) — или остался deprecated alias, и на каких эндпоинтах |
| **0004** (+ Amendment 2026-04-15) | Роутеры в `backend/app/api/` (не `routers/`). Слои: api → service → model. Нет утечек SQLAlchemy-объектов в Pydantic-схемы (read-schemas без sensitive полей) |
| **0005** — error envelope | Во всех API-роутерах: `HTTPException` приводится к `{"error": {"code", "message", "details"}}` через глобальные handlers. Grep по `{"detail":` должен быть пустым (или обоснованным). Проверить `RequestValidationError` handler |
| **0006** — пагинация | Везде где есть list — envelope `{items, total, offset, limit}`. `limit` клиппится к 200 и отклоняет 201 → 422. `offset < 0` → 422. **Критично**: фильтрация коллекций — только в SQL WHERE, никакого post-filter в Python после LIMIT (CLAUDE.md §«Данные и БД», ловим Phase 3 Batch A P0-1) |
| **0007** — audit log | Каждая write-операция создаёт `AuditLog` в той же транзакции. Grep по `db.commit()` без предшествующего `audit_service.log(...)` — потенциальный дефект. Для soft-delete тоже нужна запись |
| **0011** — Foundation | `company.py`, `user_company_role.py`, `company_scoped.py`. `company_id` везде где требует ADR (projects, contracts, contractors, payments). Partial unique index на `companies.inn` (WHERE is_active AND inn IS NOT NULL). `UserCompanyRole` UNIQUE на (user_id, company_id, role_template, pod_id). Seed Company(id=1). Маппинг существующих `users.role` в `user_company_roles`. JWT-клеймы `company_ids`, `is_holding_owner`. `X-Company-ID` header. `require_permission` декоратор — или пока только `require_role` |
| **0013** — migrations contract (proposed) | Даже в proposed-статусе — проверить: все 8 миграций имеют `downgrade()`, имеют docstring с revision/revises, именование, отсутствие DDL без round-trip проверки. Фиксируем gap между proposed и реальным состоянием |
| **0014** — ACL (proposed) | Нет ли hardcoded http(s)://-URL-ов вне адаптеров; есть ли `IntegrationAdapter`-база. Если ещё не реализовано — зафиксировать список мест, куда его надо внедрить при активации ADR |

**Выход R-1**: `docs/reviews/code-audit/R-1-adr-compliance.md` — таблица «ADR × findings» с severity.

#### Задача R-2. Соответствие CODE_OF_LAWS v2.0/v2.1 и Конституции

Особое внимание (каждая статья — отдельный sweep по репо):

| Статья | Что делать |
|---|---|
| **ст. 23 Конституции** + **ст. 40 CODE_OF_LAWS** | `grep -rE "(password\s*=\s*['\"])` по всему `backend/`, `tests/`, `frontend/`, `scripts/`. Любой литерал пароля, токена, API-ключа — P0. Включая `conftest.py` (повторяющийся дефект, CLAUDE.md §«Секреты и тесты»). Альтернатива: все пароли через `secrets.token_urlsafe(16)` |
| **ст. 79 Конституции** | Логирование: не выводится ли секрет/пароль в logger/print. Проверить middleware логов. Проверить что JWT-payload не попадает в логи as-is |
| **ст. 81 Конституции** | MFA для owner/accountant — ADR 0003 extension. Реализовано? Если нет — зафиксировать как P1 блокер production-gate |
| **ст. 45а CODE_OF_LAWS** | grep на `requests.`, `httpx.`, `urllib`, `aiohttp.`, `socket.` по `backend/app/`. Любой живой исходящий вызов вне `_live_transport` адаптера — P0. Разрешено только Telegram, и только в его выделенном модуле |
| **ст. 44 CODE_OF_LAWS** | Запустить `ruff check backend/` и `ruff format --check backend/` — сколько нарушений, каких правил. Запустить `mypy --strict` (если настроено) — сколько ошибок. `eslint` / `tsc --noEmit` на frontend |
| **ст. 46 CODE_OF_LAWS** | Коммит через Координатора — проверить в git-log Phase 3, что все коммиты идут через одного автора (Координатор), нет «человеческих» коммитов мимо маршрута |
| **ст. 47 (commit messages)** | Формат commit-сообщений, Co-Authored-By, подписи. Скан последних 50 коммитов |

**Выход R-2**: `docs/reviews/code-audit/R-2-code-of-laws.md` — список нарушений с привязкой к статье и файлу.

#### Задача R-3. Соответствие CLAUDE.md (живой антипаттерник)

Пройти по каждому пункту секций «Данные и БД», «Секреты и тесты», «API», «Код», «Git». Для каждого — статус «соблюдается / нарушено / не применимо». Особенно:
- фильтры после LIMIT (P0-паттерн);
- enum value vs CHECK-constraint совпадение;
- round-trip миграций — закрывается Вашим блоком qa-head (M-1), но если встретите — фиксируйте;
- IDOR на вложенных ресурсах (например, `/houses/{house_id}/configurations/{cfg_id}` — проверка `cfg.house_id == house_id`);
- `# type: ignore` / `# noqa` без обоснования — P2;
- комментарии «что» вместо «почему» — P3.

**Выход R-3**: `docs/reviews/code-audit/R-3-claude-md.md`.

#### Задача R-4. Python / SQLAlchemy 2.0 / FastAPI / Pydantic best practices

Что ищем:
- **SQLAlchemy 2.0 паттерны**: только `select()` и `db.scalars(...).all()` / `db.execute(...).scalar_one()`. Запрещено `db.query(Model).filter(...)` — legacy 1.x. Любое `db.query(` — P1 (code smell, со временем ломается).
- **Mapped-типизация**: все модели используют `Mapped[...]` + `mapped_column(...)`. Старые Column без Mapped — P2.
- **N+1 queries**: список, в котором в цикле подтягивается child — `selectinload` / `joinedload`. Без него — P1.
- **Transaction boundaries**: `async with db.begin():` или явный `db.commit()` + `db.rollback()` на error. Смешение — P1.
- **FastAPI DI**: `Depends(...)` для `db`, `current_user`, `company_context`. Никаких глобальных переменных или scope-утечек.
- **Pydantic v2**: `BaseModel` v2 (не v1). `ConfigDict(from_attributes=True)`, не `class Config: orm_mode=True`. `Field(...)` с правильными валидаторами. `model_validate` вместо `from_orm`.
- **Response models**: на каждом эндпоинте `response_model=` со схемой, из которой **исключены** sensitive поля (password_hash, tokens).
- **Exception handling**: никаких голых `except:`; никаких `except Exception:` без логирования; бизнес-ошибки через `HTTPException` с правильным `error.code`, не 500.
- **Concurrency**: `SELECT FOR UPDATE` там, где ADR 0011 требует (payment.approve, audit_log insert). Race conditions на approve/reject, на уникальные constraints.
- **Idempotency**: POST-эндпоинты, которые создают сущности с внешним ID — как защищаемся от дублей (unique constraints, idempotency keys, `ON CONFLICT DO NOTHING`).

**Выход R-4**: `docs/reviews/code-audit/R-4-python-backend-quality.md`.

#### Задача R-5. Frontend quality

- **TypeScript strict mode**: `strict: true`, `noImplicitAny`, `strictNullChecks` в `tsconfig.json`. Наличие `any` в коде — P2.
- **React 18 patterns**: только hooks, нет class-components. `useEffect` без зависимостей, вызывающий sideeffect при каждом рендере — P1. `useState` без initial — P2.
- **shadcn/ui**: компоненты используются через `components.json` CLI, не копипастой. `cn()` утилита для merge классов.
- **A11y basics**: `<button>` без text/aria-label, `<img>` без alt, форма без label-for — P2.
- **Routing**: React Router v6 (не v5). Защищённые маршруты — проверка токена. Нет ли хардкода URL бэкенда в коде (должно быть из env).
- **State**: локальный (`useState`) vs глобальный (Context / Zustand / Redux). Токен — где хранится? localStorage vs httpOnly cookie (если есть backend для этого) — security-влияние.
- **Bundle health**: `npm audit` на `package.json` — CVE. Размер бандла, treeshaking.
- **Env leaks**: `import.meta.env.VITE_*` — ничего кроме публичных констант. **Никаких** `VITE_SECRET_*`.

**Выход R-5**: `docs/reviews/code-audit/R-5-frontend-quality.md`.

### 3.2. Блок qa-head (тестировщики L4)

**Ответственный**: qa-head.
**Исполнители**: qa-1, qa-2.

#### Задача Q-1. Coverage analysis (анализ, не написание)

Запустить `pytest --cov=backend/app --cov-report=term-missing --cov-branch` и зафиксировать:
- текущий % покрытия строк и веток в целом и по модулям;
- топ-20 непокрытых участков (файл:строки, тип — happy/error-handling/edge-case);
- цель quality.md — ≥85% строк, ≥80% веток. Где мы сейчас? Где провалы?

**Особое внимание**:
- `test_company_scope.py` (512 строк) — что покрывает, что пропускает. ADR 0011 требует явных тестов cross-company isolation, holding_owner bypass, `X-Company-ID` обработки (missing / mismatched / valid). Проверить, что для каждого из 13 API-модулей есть минимум один cross-company тест.
- RBAC-матрица: 4 роли × 13 API-модулей × 3 action (read/write/delete) = **156 ожидаемых комбинаций**. Сколько из них реально покрыто параметризованными тестами? Построить матрицу-таблицу (зелёный/жёлтый/красный).

**Выход Q-1**: `docs/reviews/code-audit/Q-1-coverage.md` с таблицами и backlog-ом тестов, которые надо написать в рамках отдельной задачи (не в этом аудите).

#### Задача Q-2. Edge-cases валидации (проверяется по коду, без написания)

Пройти по моделям и сервисам, зафиксировать отсутствие / наличие валидаций:
- **ИНН** — 10/12 цифр, checksum по алгоритму ФНС. Тесты на битый ИНН — есть? (см. `test_contractors.py`, модель `contractor.py`.)
- **КПП** — 9 цифр, код региона валиден. Тесты?
- **ОГРН / ОГРНИП** — 13/15 цифр, checksum. Упоминается в ADR 0011? Проверяется?
- **Суммы денег** — только в копейках (`amount_cents: int`), не Float, не Decimal. Тесты на отрицательные значения, на 0, на overflow.
- **Даты** — `start_date <= end_date` для `Contract`. Тесты?
- **Email** — формат, максимальная длина, уникальность.
- **Unicode в именах** — поддерживается ли корректно, нет ли проблем с нормализацией.

**Выход Q-2**: `docs/reviews/code-audit/Q-2-validation-gaps.md`.

#### Задача Q-3. IDOR / cross-company access tests (анализ)

Для каждого из 13 API-модулей построить таблицу:
- есть ли тест «user компании A не видит GET список компании B»;
- есть ли тест «user компании A не может POST в company_id=B через payload»;
- есть ли тест «user компании A не может GET /entity/{id} где entity.company_id=B → 404, не 403»;
- есть ли тест на вложенные ресурсы `/parents/{pid}/children/{cid}` — проверка принадлежности (CLAUDE.md §«API»).

**Выход Q-3**: `docs/reviews/code-audit/Q-3-idor-matrix.md`.

#### Задача Q-4. Concurrency / race condition tests

- `payment.approve()` — требует `SELECT FOR UPDATE` на contract (ADR 0011 §4 + FIND-02 OWASP sweep). Есть ли тест на параллельный approve двумя разными accountant → один успех, один 409?
- `audit_log.insert` — требует `SELECT ... FOR UPDATE LIMIT 1` на последнюю запись (ADR 0011 §3.1). Есть ли тест на параллельные инсерты → цепочка не рвётся, нет gap в prev_hash?
- Unique constraints (contractor.inn partial, contract.number partial) — есть ли тест на параллельную вставку с одинаковым ключом → один успех, один 409.

**Выход Q-4**: `docs/reviews/code-audit/Q-4-concurrency.md`.

#### Задача Q-5. Round-trip миграций

**Критичная задача** — CLAUDE.md §«Данные и БД»: без round-trip миграция не считается готовой.

Для каждой из 8 миграций — прогнать в dev-БД:

```
alembic upgrade head
alembic downgrade -1
alembic upgrade head
```

И зафиксировать:
- какие миграции ломаются при `downgrade -1` (ошибка Alembic / integrity error);
- какие оставляют grep-артефакты (orphan-constraints, orphan-indexes);
- для `f7e8d9c0b1a2_multi_company_foundation.py` особо — downgrade должен удалить `companies`, `user_company_roles`, `role_permissions` (когда добавится), `company_id` в 4 таблицах; `users.role` не трогается (ADR 0011 §1.5);
- какие миграции содержат `op.execute(raw SQL)` — риск для round-trip.

Отдельно: между миграциями должна быть корректная цепочка `down_revision` — нет висящих веток, нет duplicate revision id.

**Выход Q-5**: `docs/reviews/code-audit/Q-5-migrations-round-trip.md` + подробный лог.

#### Задача Q-6. Integration / end-to-end business scenarios

Пройти по главному бизнес-сценарию и проверить, что он покрыт хотя бы одним integration-тестом через httpx AsyncClient:

1. Создать company (owner)
2. Создать project под company
3. Создать house_type, house внутри project
4. Создать contractor (company_id)
5. Создать contract (project_id, house_id, contractor_id, сумма, start/end_date)
6. Создать payment (contract_id, amount)
7. Approve payment (accountant) — проверить что approved_at/approved_by заполнены
8. Проверить, что в audit_log каждая write-операция записана с правильным entity_type/action/user_id
9. Проверить, что для user_B другой company все эти объекты недоступны

**Если такого теста нет** — это пробел в integration coverage, зафиксировать как P1.

**Выход Q-6**: `docs/reviews/code-audit/Q-6-integration-gaps.md`.

#### Задача Q-7. Error envelope тесты

Для каждого класса ошибок (400, 401, 403, 404, 409, 422, 500) — минимум один тест, проверяющий **полный** envelope `{"error": {"code", "message", "details"}}`. Не просто `assert status_code == 404`, а `assert body["error"]["code"] == "not_found"` (правило quality.md п. 1 + п. 7).

Зафиксировать по каждому API-модулю, какие классы ошибок не проверены через error.code.

**Выход Q-7**: `docs/reviews/code-audit/Q-7-error-envelope.md`.

### 3.3. Блок security (через Координатора)

**Маршрут**: я как quality-director не могу общаться с security напрямую (он Советник L4, вне моей вертикали, но и не у меня в подчинении). Запрашиваю через Координатора: «security-советник нужен на 5–7 дней на задачи S-1..S-4, бриф — см. раздел 3.3 брифа аудита». Координатор принимает решение о делегировании.

#### Задача S-1. OWASP Top 10 2021 — полный sweep

Для каждой категории (A01–A10) — пройтись по репо и дать список находок с severity:
- **A01 Broken Access Control** — ADR 0011 RBAC + multi-tenancy + IDOR на вложенных.
- **A02 Cryptographic Failures** — bcrypt rounds (≥12), JWT secret length, crypto audit chain (SHA-256 генезис, не коллизии).
- **A03 Injection** — SQL injection (весь ли код через ORM, нет ли `text()` с f-string), command injection в scripts/, log injection.
- **A04 Insecure Design** — flow approve/reject платежей, отсутствие rate-limit на login, отсутствие MFA (ст. 81).
- **A05 Security Misconfiguration** — `debug=True`, `allow_origins=["*"]`, `echo=True` на engine, секреты в docker-compose как `environment:` не через secrets.
- **A06 Vulnerable Components** — `pip-audit` и `npm audit`, HIGH+.
- **A07 Authentication Failures** — поведение при неверном пароле (timing-safe сравнение через passlib), lockout, reuse refresh, logout mechanism.
- **A08 Software and Data Integrity** — crypto audit chain работает, dependencies signed/pinned, `requirements.txt` с hash.
- **A09 Logging Failures** — пишется audit_log на каждый важный event, нет утечки secrets в логи, формат логов структурированный.
- **A10 SSRF** — нет user-controlled URL в исходящих запросах (связано с ADR 0014).

**Выход S-1**: `docs/reviews/code-audit/S-1-owasp-top10.md`.

#### Задача S-2. Secrets scan

- Запустить `gitleaks detect --source /root/coordinata56 --no-git` и `gitleaks detect --source /root/coordinata56` (с git-историей).
- Запустить `detect-secrets scan` альтернативно.
- Каждая находка — проверить вручную: это реальный секрет или false positive (baseline).
- Особое внимание: `.env`-файлы в репе (не `.env.example`). Если закоммичен `.env` с реальным значением — **P0 немедленная эскалация**, ротация секрета.

**Выход S-2**: `docs/reviews/code-audit/S-2-secrets.md` + при находках реальных секретов — немедленный эскалейт мне, я эскалирую Координатору, Координатор вызывает Владельца, Владелец ротирует.

#### Задача S-3. Dependency audit

- `pip-audit -r backend/pyproject.toml` (или `backend/requirements.txt`, если есть). Зафиксировать CVE severity HIGH+ с CVSS и fix-versions.
- `npm audit --prefix frontend` + `npm audit --json` для парсинга. HIGH+.
- Проверить, что версии pinned (не `^` и `~` без верхней границы там, где критично). Lockfiles есть (`package-lock.json` / `poetry.lock` / `pip.lock`)?

**Выход S-3**: `docs/reviews/code-audit/S-3-dependencies.md`.

#### Задача S-4. AuthZ / AuthN deep audit

- **JWT verification**: где проверяется подпись, какой алгоритм, есть ли проверка `exp`, `iss`, `aud`. Алгоритм `HS256` с секретом — секрет достаточной длины? Если `RS256` — где публичный ключ?
- **require_role / require_permission coverage**: найти все FastAPI-эндпоинты (via `app.routes` или grep `@router.` / `@app.`), для каждого — проверить наличие декоратора авторизации. Список эндпоинтов **без** авторизации должен совпадать с allowlist: `/auth/login`, `/auth/register` (если есть, и разрешён ли), `/healthz`, `/docs`, `/openapi.json`, `/redoc`.
- **Multi-tenancy scope leaks**: в каждом сервисе, наследующем `CompanyScopedService`, — проверить, что `_scoped_query` реально применяется в каждом методе. Прямые `select(Model)` без scope — leak.
- **Password policy**: минимальная длина, запрет из словаря, сложность. Хотя бы basic.
- **Session / token revocation**: есть ли механизм logout/invalidate? Или токен живёт до `exp`?
- **MFA**: есть ли хоть какая-то инфраструктура (TOTP, WebAuthn, email-code)? Или в полном ноле? Критично для ст. 81 Конституции.

**Выход S-4**: `docs/reviews/code-audit/S-4-authz-authn.md`.

---

## 4. Формат консолидированного отчёта

Я как quality-director консолидирую выходы R-1..R-5, Q-1..Q-7, S-1..S-4 в единый документ:

**Путь**: `/root/coordinata56/docs/reviews/code-audit-2026-04-17.md`

**Структура**:

```
1. Executive Summary
   - Топ-10 проблем по severity × business impact
   - Блокеры production-gate (отдельный список)
   - Метрики: coverage, дефектов на kLoC, % нарушений ADR, % нарушений CODE_OF_LAWS

2. Подробности по областям
   2.1. Backend — ADR compliance (свод R-1)
   2.2. Backend — CODE_OF_LAWS compliance (свод R-2)
   2.3. Backend — Python / SQLAlchemy / FastAPI quality (свод R-3, R-4)
   2.4. Frontend quality (свод R-5)
   2.5. Test coverage gaps (свод Q-1)
   2.6. Validation gaps (свод Q-2)
   2.7. IDOR / cross-company matrix (свод Q-3)
   2.8. Concurrency tests (свод Q-4)
   2.9. Migration round-trip (свод Q-5)
   2.10. Integration gaps (свод Q-6)
   2.11. Error envelope coverage (свод Q-7)
   2.12. OWASP Top 10 findings (свод S-1)
   2.13. Secrets scan (свод S-2)
   2.14. Dependency audit (свод S-3)
   2.15. AuthZ / AuthN (свод S-4)

3. Сводный Backlog (все находки в одной таблице)
   Поля: ID, severity (P0/P1/P2/P3), area, file:line, ADR/CODE ref, описание,
         recommendation, effort (часы), owner-department

4. Что делаем прямо сейчас
   - P0 — PR в течение недели (по каждому конкретные файлы, ответственный директор)
   - P1 — в ближайший sprint (M-OS-1 Волна 1)
   - P2+ — в общий backlog

5. Что блокирует production-gate (отдельный список для Координатора)
   - Юридический столп: какие находки блокируют?
   - Security столп: какие?
   - Staging столп: какие интеграции нужны в симуляциях?

6. Подписи
   - quality-director (я)
   - review-head
   - qa-head
   - security (через Координатора)
   - architect (Советник) — review executive summary на архитектурные заблуждения
```

**Приложения** — отдельные файлы `R-1..R-5`, `Q-1..Q-7`, `S-1..S-4` остаются в `docs/reviews/code-audit/` как первичные артефакты.

---

## 5. Severity матрица (обязательна к единой применимости)

| Severity | Определение | SLA на исправление |
|---|---|---|
| **P0 (BLOCKER)** | Уязвимость безопасности; нарушение CODE_OF_LAWS ст. 40, 45а, 79, 81; нарушение ст. 23 Конституции; сломанный round-trip на последней миграции; подтверждённый IDOR с чтением данных; SQLi; hardcoded production-секрет | Эскалация немедленная; PR в течение **3 рабочих дней** |
| **P1 (MAJOR)** | Нарушение ADR без amendment; N+1 в горячих путях; отсутствие RBAC-теста на write-эндпоинте; legacy SQLAlchemy 1.x; отсутствие error envelope в ответе; CVE HIGH в зависимости; отсутствие MFA (ст. 81) | В ближайший sprint (M-OS-1 Волна 1) |
| **P2 (MINOR)** | Code smell, `any` в TS, устаревшие паттерны Pydantic v1, `# type: ignore` без обоснования, отсутствие a11y-атрибутов, missing edge-case test | В backlog на M-OS-1 Волна 2+ |
| **P3 (NIT)** | Стилистика, комментарии «что» вместо «почему», naming inconsistency | По мере касания кода |

---

## 6. DoD на Ваш блок (обязательно выполнить до сдачи мне)

### DoD для review-head

- [ ] Все 5 задач R-1..R-5 закрыты отдельными файлами в `docs/reviews/code-audit/`
- [ ] Каждая находка имеет: ID (например `AUDIT-R1-007`), severity, file:line, ADR/CODE ref, описание, рекомендация, effort (часы)
- [ ] Никаких правок в код (FILES_ALLOWED = `docs/reviews/**` на всё время аудита)
- [ ] Если ревьюер встретил собственный код — передал Начальнику на переназначение, пометил
- [ ] P0 эскалированы мне **в момент обнаружения**, не в конце
- [ ] Самопроверка ревьюера по чек-листу `departments/quality.md` «Чек-лист reviewer (CRUD-эндпоинт)»
- [ ] Отчёт review-head мне ≤300 слов + ссылки на R-1..R-5

### DoD для qa-head

- [ ] Все 7 задач Q-1..Q-7 закрыты отдельными файлами в `docs/reviews/code-audit/`
- [ ] Q-5 (round-trip) — прогон в реальной dev-БД, лог сохранён
- [ ] Q-1 — отчёт `pytest --cov` приложен как артефакт (coverage.xml + term-missing)
- [ ] Никаких новых тестов не написано (только анализ) — FILES_ALLOWED = `docs/**` + `docs/qa/bugs/**` для фиксации багов
- [ ] Каждая находка имеет severity и ссылку на правило из quality.md / ADR
- [ ] P0 эскалированы мне в момент обнаружения
- [ ] Отчёт qa-head мне ≤300 слов + ссылки на Q-1..Q-7

### DoD для security (через Координатора)

- [ ] Задачи S-1..S-4 закрыты отдельными файлами в `docs/reviews/code-audit/`
- [ ] S-2 при находке реального секрета — **немедленный** эскалейт через Координатора (не ждать конца)
- [ ] S-3 сохранены raw-отчёты `pip-audit.json`, `npm-audit.json` в `docs/reviews/code-audit/artifacts/`
- [ ] Отчёт security Координатору + копия мне для включения в консолидацию

### DoD на мой блок (quality-director)

- [ ] Консолидированный отчёт `docs/reviews/code-audit-2026-04-17.md` собран
- [ ] Executive summary ≤500 слов, топ-10 проблем с конкретными действиями
- [ ] Backlog таблица отсортирована по severity
- [ ] Раздел «блокеры production-gate» готов отдельно для Координатора
- [ ] architect (Советник) прочитал executive summary и дал вердикт «нет архитектурных заблуждений»
- [ ] Передаю Координатору одним сообщением с чётким списком следующих действий

---

## 7. Сроки

| День | Активность |
|---|---|
| **День 1** | review-head и qa-head раздают задачи исполнителям; security получает задачи S-1..S-4 через Координатора; все читают обязательные документы (раздел 1 п. 7) |
| **День 2–4** | Параллельное исполнение R-1..R-5, Q-1..Q-7, S-1..S-4. P0-эскалации — в режиме реального времени |
| **День 5** | review-head и qa-head собирают свои блоки, делают первичную приёмку, отправляют мне |
| **День 6** | Я консолидирую, пишу executive summary, отправляю architect на review |
| **День 7** | Финальный отчёт Координатору |

---

## 8. Что делать при находке критической уязвимости

Если кто-то из участников видит:
- hardcoded production-секрет в текущем HEAD репозитория;
- подтверждённый SQL injection (не гипотетический);
- authZ bypass (рабочий curl-сценарий, не теория);
- backdoor / logic bomb;

то:
1. **Не продолжает аудит этой области**.
2. Немедленно сообщает своему Начальнику отдела: короткое сообщение «P0 security finding, тип=..., файл=...».
3. Начальник отдела в течение ≤15 минут эскалирует мне.
4. Я в течение ≤15 минут эскалирую Координатору с просьбой «срочный вызов Владельца».
5. Никто ничего не коммитит и не публикует до решения Владельца.
6. Находка фиксируется в `docs/reviews/code-audit/CRITICAL-<timestamp>-<short>.md`.

---

## 9. Финальное слово

У нас 351+ тест и чистое CI по состоянию на 2026-04-17. Но мы только что вылетели из Фазы 3 в M-OS-0 Reframing + Foundation-миграцию, которая меняет модель данных и RBAC. Это точка, где технический долг проще всего выловить и дешевле всего починить — до того, как на эту базу ляжет M-OS-1 с pod'ами, BPM, Telegram-ботом и реальным UI.

Аудит не про «найти виноватого». Аудит — про построение карты, которую мы передаём backend-director / frontend-director / infra-director для планомерной починки в PR.

Работаем спокойно и тщательно. 5–7 дней хватит.

— quality-director, 2026-04-17
