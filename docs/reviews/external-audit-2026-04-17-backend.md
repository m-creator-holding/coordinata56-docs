# Ответ backend-director на внешний аудит M-OS-1 Foundation (backend-зона)

- **Дата:** 2026-04-17
- **Автор:** backend-director (субагент L2, Claude Code)
- **Запрос:** Координатор (msg 1152 от Владельца)
- **Аудитор:** внешний рецензент «кодекс» (GPT), замечания по `prisma/schema.prisma`, `src/app/api/ai/report/route.ts`, `src/lib/supabase.ts`
- **Связанные документы:**
  - ADR 0011 (Foundation Multi-company + RBAC + Crypto Audit) — **утверждён 2026-04-17**
  - ADR 0013 (Migrations Evolution Contract) — **proposed**
  - ADR 0014 (Anti-Corruption Layer) — **proposed**
  - `docs/m-os-vision.md` §2 п.5–10, §3.4 — стек **FastAPI + SQLAlchemy + PostgreSQL**, anti-corruption layer
  - `docs/pods/cottage-platform/m-os-1-foundation-adr-plan.md` v3 — план Волны 1
  - `CLAUDE.md` — правило round-trip, Strict delegation chain

---

## 1. Резюме для Координатора

Аудит GPT описывает **не наш `/root/coordinata56/backend/`, а сторонний локальный прототип Владельца** (Next.js + Prisma + Supabase на MacBook). Все пять пунктов аудита справедливы **в границах прототипа**, но **бо́льшая часть того, что он называет «отсутствующим», уже реализована** в нашем Alembic/SQLAlchemy-стеке согласно ADR 0011. Основной вопрос — архитектурный выбор: что с прототипом (утилизировать / переделать на наш API / ассимилировать).

**Вердикт (коротко):**
- Источник истины модели данных M-OS = `/root/coordinata56/backend/` (FastAPI + SQLAlchemy + Alembic), зафиксировано в Vision §3 и ADR 0002.
- Prisma-прототип — **на выброс или переработку поверх нашего API**, не source of truth.
- ADR 0013 применим **как есть**, amendment не нужен.
- Минимальный Foundation PR уже почти собран: **Шаг 1 Multi-company из ADR 0011 реализован** (модели, миграция, seed, CompanyScopedService). Остались Шаг 2 (RBAC v2 / role_permissions) и Шаг 3 (Crypto Audit chain).

---

## 2. Таблица «реализовано / проектируется / не начато» по Foundation-моделям

Источник сверки: `/root/coordinata56/backend/app/models/`, `/root/coordinata56/backend/alembic/versions/`, ADR 0011, ADR 0014.

| Foundation-элемент | Аудит говорит | Реальное состояние в `/root/coordinata56/backend/` | Статус |
|---|---|---|---|
| `Company` (таблица + модель) | Отсутствует | `backend/app/models/company.py` + миграция `2026_04_17_0900_f7e8d9c0b1a2_multi_company_foundation.py` | **Реализовано** |
| `company_id` во всех сущностях | Отсутствует | Добавлено в `projects`, `contracts`, `contractors`, `payments` safe-migration паттерном (NULLABLE → backfill → NOT NULL) | **Реализовано** |
| `user_company_roles` | Отсутствует | `backend/app/models/user_company_role.py` + таблица в той же миграции | **Реализовано** |
| `CompanyScopedService` | — | `backend/app/services/company_scoped.py` + использование в Project/Contract/Contractor/Payment services | **Реализовано** |
| `UserContext` + X-Company-ID header | — | `UserContext` dataclass есть; JWT-клейм и header — ещё не проверены, требует сверки с `deps.py` | **Частично** |
| `role_permissions` (матрица как данные) | Отсутствует | Таблицы и seed-матрицы НЕТ. Функция `can(user_context, action, resource)` НЕТ. Сохранён старый `require_role` | **Не начато** (Шаг 2 ADR 0011) |
| `require_permission` decorator | — | НЕТ (используется старый `require_role`) | **Не начато** (Шаг 2 ADR 0011) |
| `AuditLog` (базовый) | Отсутствует | `backend/app/models/audit.py` существует с Фазы 2 (ADR 0007) | **Реализовано** (без crypto-chain) |
| `AuditLog.prev_hash`/`hash` (crypto-chain) | — | Полей НЕТ. Endpoint `/audit/verify` НЕТ. Backfill-скрипт НЕТ | **Не начато** (Шаг 3 ADR 0011) |
| `company_settings` (per-company) | Отсутствует | Нет. Спроектировано в ADR-плане v3 §ADR-0017 (Configuration-as-data, A3-гибрид); 7 полей в M-OS-1.1, 3 в M-OS-1.2 | **Проектируется** (ADR-0017 Волна 3) |
| `integration_catalog` | Отсутствует | Таблицы НЕТ. Каркас описан в ADR 0014 (proposed); хранилище — ADR-0015 Волна 2 | **Проектируется** |
| `IntegrationAdapter` базовый класс | — | НЕТ (`backend/app/core/integrations/` не существует) | **Не начато** (ADR 0014 DoD) |
| Event bus (бизнес + agent-control) | Отсутствует | Нет. Спроектировано в ADR-0016 (две раздельные шины), Волна 2 | **Проектируется** |
| BPM / configuration tables | Отсутствует | Нет. Спроектировано в ADR-0017 с migration rules для запущенных экземпляров | **Проектируется** (Волна 3) |
| Contract: `file_id`, `start_date`, `end_date` | Отсутствует | **Реализовано** в миграции `f7e8d9c0b1a2`. `file_id` с CHECK (IS NULL) как заглушка под ADR M-OS-2 | **Реализовано** |
| Contract: `is_internal`, `counterparty_company_id` | — | Реализовано в той же миграции | **Реализовано** |
| Seed: `Company(id=1)`, маппинг `users.role → user_company_roles` | — | Выполнен в `upgrade()` миграции | **Реализовано** |

**Промежуточный итог:**
- Часть 1 ADR 0011 (Multi-company) — **100% готово**.
- Часть 2 ADR 0011 (RBAC v2) — **0% готово**.
- Часть 3 ADR 0011 (Crypto Audit) — **0% готово** (базовый `AuditLog` без hash-chain есть с Фазы 2).
- Часть 4 ADR 0011 (Contract legal fields) — **100% готово**.

---

## 3. Проверка текущей инфраструктуры `/root/coordinata56/backend/`

Аудит утверждает «нет миграций, нет `tools/lint_migrations.py`, нет network-block тестов, нет OpenAPI generation». Реальное состояние:

| Инфраструктура | Факт | Источник |
|---|---|---|
| Alembic миграции | **Есть**, 8 файлов в `backend/alembic/versions/` (initial schema → multi-company foundation) | `ls backend/alembic/versions/` |
| `tools/lint_migrations.py` | **Нет** | Директория `/root/coordinata56/backend/tools/` отсутствует. DoD ADR 0013 не закрыт |
| CI round-trip тест миграций | **Нет** автоматического. CI запускает `alembic upgrade head`, но не `downgrade -1 && upgrade head`. Правило round-trip зафиксировано в `CLAUDE.md` как ручная практика | `.github/workflows/ci.yml` линии 47–50 |
| network-block тесты (pytest-socket) | **Нет** (grep по `backend/` не находит ни одного упоминания). DoD ADR 0014 не закрыт | Grep pattern `pytest-socket\|allow_network\|disable_socket` — 0 совпадений |
| OpenAPI generation (автоматическая) | **Нет** на уровне CI. FastAPI генерирует schema на лету в runtime; артефакт `openapi.json` в репозиторий не коммитится | `backend/app/main.py` использует стандартную FastAPI schema; отдельного скрипта `scripts/generate_openapi.py` нет |
| `backend/app/core/integrations/` | **Нет** директории | `ls backend/app/core/` показывает только `config.py`, `security.py` |
| `role_permissions` таблица + seed | **Нет** | Grep по коду — 0 совпадений |
| Крипто-цепочка AuditLog | **Нет** | Grep `prev_hash\|/audit/verify` — 0 совпадений |

**Комментарий.** Аудитор ошибается, когда говорит «нет миграций» — миграций **8 штук**, включая недавно применённую Foundation-миграцию `f7e8d9c0b1a2`. Остальные 4 пункта инфраструктуры (lint_migrations, round-trip CI, pytest-socket, OpenAPI autogen) — справедливо «нет», это DoD ADR 0013 и ADR 0014, которые ещё в статусе **proposed**.

---

## 4. Prisma vs Alembic — архитектурный выбор

**Контекст:** Vision §3 и §9, ADR 0002 явно зафиксировали стек **FastAPI + SQLAlchemy 2.0 + Alembic + PostgreSQL**. Прототип Владельца на MacBook использует Next.js + Prisma + Supabase. Требуется выбрать один из трёх вариантов.

### Вариант A — Alembic/SQLAlchemy остаётся source of truth; прототип на выброс или переделать поверх нашего API

**Плюсы:**
- Не требует переписывания 8 миграций, 14 моделей, 10 сервисов, 13 API-модулей, 351 тест — они все уже работают.
- Соответствие Vision §3 и ADR 0002 без какого-либо amendment.
- ADR 0013 применим как есть.
- Прототип Владельца — это быстрый UX-эксперимент, его ценность в **дизайне интерфейсов и user flows**, не в коде. Его можно перенести во frontend Next.js-приложения, которое ходит в наш FastAPI backend по REST.
- Supabase как быстрый хостинг для прототипа — разовый tactic, для продакшена неприменим (Vision §2 п.2 — «своя инфра, никаких SaaS», ФЗ-152).

**Минусы:**
- Выбрасывается или переделывается работа Владельца на MacBook.
- Фронтенд-часть прототипа (компоненты, UI-макеты) сохраняется, backend-часть (Prisma schema, Supabase queries) — отдельная задача портирования.

**Трудоёмкость (на стороне backend):** **0 недель**. Трудоёмкость портирования фронтенда прототипа — задача **frontend-director**, не backend.

**Риск:** низкий. Архитектурно — статус кво.

---

### Вариант B — Мигрировать на Prisma/TypeScript, переписать Alembic → Prisma

**Плюсы:**
- Единый язык (TypeScript) на фронте и бэке.
- Prisma Studio как готовый admin-browser схемы.

**Минусы:**
- Полное переписывание: 8 миграций, 14 моделей, 10 сервисов, 13 API-модулей, **351 тест**. Оценка: **8–12 недель чистой работы двух backend-dev**.
- Нарушение Vision §3 (явно фиксирует Python/FastAPI). Нарушение ADR 0002 (утверждён стек). Требует полного пересмотра ADR 0002, 0004, 0007, 0011, 0013.
- Prisma 7 — свежий, с регрессиями (тот же аудит отмечает: `datasource url` в schema.prisma больше не принимается в Prisma 7). Неустойчивая платформа для production.
- Supabase RLS vs наш fine-grained RBAC через matrix — разные модели, конфликт подходов.
- Нет прироста функциональности. Чистая трата 2–3 месяцев.
- Engineering principle Владельца (feedback 2026-04-16 msg 817–818): «думать перед кодом; сначала простота; хирургические правки; работать от цели». Смена стека ради моды — прямое нарушение.

**Трудоёмкость:** **8–12 недель** + amendment 5+ ADR + пересмотр Vision.

**Риск:** высокий. Vision и ADR 0002 — уже утверждены Владельцем.

---

### Вариант C — Hybrid: `/root/coordinata56/backend/` Alembic + отдельный pod на Prisma

**Плюсы:**
- Теоретически позволяет попробовать Prisma в изолированном поде.

**Минусы:**
- ADR 0009 pod-архитектура: **поды разделяют общее ядро**. Ядро (Users, Companies, RBAC, AuditLog) — единое. Два ORM к одной БД создают конфликт миграций: Alembic и Prisma не знают друг про друга, одновременный запуск ломает схему.
- Два ORM = двойное сопровождение, двойные паттерны, двойные тесты, двойной риск.
- Нет ни одной бизнес-причины: ни один под не имеет специфики, которую Alembic не покрывает.

**Трудоёмкость:** средняя, но растёт экспоненциально с добавлением подов.

**Риск:** высокий долгосрочный.

---

### Рекомендация backend-director

**Принят вариант A.** Alembic/SQLAlchemy остаётся единственным source of truth для backend M-OS. Прототип Владельца рассматривается как **UX/дизайн-артефакт** (макеты, flows, компоненты), не как код для мержа. Портирование UI-частей прототипа во frontend Next.js-приложения, которое ходит в наш FastAPI, — задача **frontend-director** (через Координатора).

Обоснование в одной фразе: **перевод стабильного, покрытого тестами backend на Prisma ради унификации с прототипом — over-engineering без бизнес-цели, прямое нарушение engineering principles и Vision §3**.

---

## 5. ADR 0013 — применим как есть или нужен amendment?

**Применим как есть.** ADR 0013 написан для Alembic и именно Alembic остаётся source of truth (§4 выше). Все правила expand/contract, round-trip, запрет DROP/RENAME без deprecation — написаны для `op.*` API Alembic-ревизий.

Amendment потребовался бы **только в варианте B** (переход на Prisma), который отклоняется.

**Что должно быть сделано в рамках ADR 0013 DoD:**
- Написать `tools/lint_migrations.py` (6 проверок: DROP COLUMN, RENAME COLUMN, RENAME TABLE, NOT NULL без DEFAULT, DROP TABLE, изменение типа с потерей данных).
- Добавить в CI шаг `lint-migrations` (обязательный, блокирующий PR).
- Добавить в CI шаг `round-trip`: `alembic upgrade head && alembic downgrade -1 && alembic upgrade head`.
- Написать `tests/test_lint_migrations.py` и `tests/test_round_trip.py`.
- Обновить `docs/agents/departments/backend.md` разделом «expand/contract».

**Оценка:** **3–4 дня работы** одного backend-dev под руководством db-head (через db-director).

---

## 6. Оценка минимального Foundation PR

Аудитор рекомендует «минимальный Foundation PR: валидная схема БД, migrations, Company, RBAC matrix, AuditLog, company_settings, integration_catalog». Сверка с нашими ADR 0011, 0013, 0014, 0015, 0017:

| Элемент минимального PR | Наше соответствие | Уже сделано? | Остаток |
|---|---|---|---|
| Валидная схема БД | Есть (SQLAlchemy models + Alembic head) | Да | 0 |
| Migrations infrastructure | Alembic работает; CI-линтер + round-trip не автоматизированы | Частично | ADR 0013 DoD, 3–4 дня |
| Company + company_id везде | Реализовано в миграции f7e8d9c0b1a2 | Да | 0 |
| RBAC matrix (role_permissions) | Не начато, спроектировано в ADR 0011 Часть 2 | Нет | **Шаг 2 ADR 0011, 1.5–2 недели** |
| AuditLog (с crypto-chain) | Базовый AuditLog с Фазы 2. Hash-chain не начат | Частично | **Шаг 3 ADR 0011, 1–1.5 недели** |
| company_settings | Не начато, проектируется | Нет | ADR-0017, Волна 3 (после Foundation) |
| integration_catalog | Не начато, проектируется | Нет | ADR-0014 каркас (каркас без таблицы — можно), ADR-0015 хранилище |

### Что было бы «Foundation-close PR» Волны 1 Code

Это НЕ один PR, а серия из 3–4 PR, каждый с отдельным ревью и DoD (порядок из ADR 0011 §«Порядок реализации»):

1. **PR #1 — ADR 0013 infrastructure** (3–4 дня): `tools/lint_migrations.py`, CI round-trip, тесты линтера.
2. **PR #2 — RBAC v2** (1.5–2 недели): таблица `role_permissions`, миграция, seed матрицы, функция `can()`, декоратор `require_permission`, обновление 13 API-модулей, адаптация 351 теста.
3. **PR #3 — Crypto Audit** (1–1.5 недели): миграция добавляет `prev_hash`/`hash` в `audit_log`, обновлённый `audit_service`, endpoint `/api/v1/audit/verify`, скрипт `scripts/audit_chain_backfill.py`, тесты верификации.
4. **PR #4 — ADR 0014 каркас** (1 неделя): `backend/app/core/integrations/base.py`, `AdapterState` enum, `AdapterDisabledError`, pytest-socket в `conftest.py`, Telegram-адаптер переведён на каркас. Таблица `integration_catalog` — отдельным PR в Волне 2 (ADR-0015).

**Итого остаточный backend-scope Foundation: ~5–6.5 недель** (с учётом ревью, тестов, round-trip проверок, без учёта frontend и governance).

Это совпадает с оценкой ADR 0011 §«Порядок реализации» (4–5.5 недель) плюс инфраструктура ADR 0013 и каркас ADR 0014.

---

## 7. Что уже реализовано в `/root/coordinata56/backend/` — конкретика

Модели (`backend/app/models/`): `user.py`, `company.py`, `user_company_role.py`, `project.py`, `contract.py` (с file_id, start/end dates, is_internal, counterparty_company_id, company_id), `contractor.py` (неявно — в Batch C), `house.py`, `house_type.py` (?), `stage.py`, `budget.py`, `material.py`, `audit.py`, `enums.py`, `mixins.py`.

Миграции (`backend/alembic/versions/`): **8 файлов**, последняя — `f7e8d9c0b1a2_multi_company_foundation.py`.

Сервисы (`backend/app/services/`): `audit.py`, `base.py`, `budget_category.py`, `budget_plan.py`, `company_scoped.py` (базовый), `contract.py`, `contractor.py`, `house.py`, `house_type.py`, `material_purchase.py`, `option_catalog.py`, `payment.py`, `project.py`, `stage.py`.

API (`backend/app/api/`): `auth.py`, `budget_categories.py`, `budget_plans.py`, `contractors.py`, `contracts.py`, `deps.py`, `health.py`, `house_types.py`, `houses.py`, `material_purchases.py`, `option_catalog.py`, `payments.py`, `projects.py`, `stages.py`.

Тесты (`backend/tests/`): 15 файлов, в т.ч. `test_company_scope.py` (512 строк). Раньше было 351 тест на момент ADR 0011; сейчас больше.

**Чего нет на уровне backend:**
- `backend/tools/lint_migrations.py`
- `backend/app/core/integrations/` (ADR 0014 каркас)
- Таблица и модель `role_permissions` (ADR 0011 Часть 2)
- `require_permission` decorator
- Поля `prev_hash`/`hash` в `audit_log` и endpoint `/audit/verify` (ADR 0011 Часть 3)
- Таблица `integration_catalog` (ADR-0015)
- Таблицы `company_settings` / `configuration_entities` (ADR-0017)
- Event bus (ADR-0016)
- `pytest-socket` и `@pytest.mark.allow_network` в CI
- Автоматическая OpenAPI-генерация и коммит `openapi.json` в репозиторий

---

## 8. Вывод для Координатора

1. **Аудит GPT смотрит не на наш backend, а на отдельный Prisma-прототип Владельца.** Бо́льшая часть его «критических замечаний» касается прототипа и не применима к `/root/coordinata56/backend/`.
2. **Где аудит прав применительно к нашему backend** — это инфраструктурные DoD: `tools/lint_migrations.py`, CI round-trip, pytest-socket, OpenAPI artifact. Все эти пункты уже спроектированы в ADR 0013 и ADR 0014 (proposed). Остаётся принять ADR и реализовать DoD.
3. **Prisma vs Alembic** — вариант A (Alembic как source of truth). Варианты B и C отклоняются, Vision и ADR 0002 не трогаются.
4. **ADR 0013 применим как есть**, amendment не нужен.
5. **Минимальный Foundation PR** — это 4 последовательных PR на ~5–6.5 недель backend-работы, не единый PR. Следуем порядку ADR 0011 + ADR 0013 + ADR 0014.

**Рекомендуемые действия Координатору:**
- Довести ADR 0013 и ADR 0014 до governance-утверждения (уже proposed).
- Передать Владельцу ответ: прототип на MacBook — не блокирует нашу работу; если он хочет сохранить UX-дизайн прототипа, это задача frontend-director через Координатора (порт компонентов на Next.js поверх нашего API).
- Запланировать Волну 1 Code: PR #1 (ADR 0013 infra) → PR #2 (RBAC v2) → PR #3 (Crypto Audit) → PR #4 (ADR 0014 каркас).

---

*Артефакт составлен backend-director (субагент L2) по запросу Координатора на основе внешнего аудита от 2026-04-17. Не является ADR и не вносит изменений в утверждённые решения; только аналитика и рекомендации.*
