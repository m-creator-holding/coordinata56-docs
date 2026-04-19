# M-OS — внутренняя AI-native платформа холдинга

**cottage-platform** — первый пилотный pod (посёлок «Координата 56», 85 домов бизнес-класса, 4 типовых проекта с опциями, полный цикл под ключ).

Стек: Python 3.12 + FastAPI + SQLAlchemy 2.0 + PostgreSQL 16 + React + TypeScript + Vite + shadcn/ui + Docker.

---

## Что система умеет сейчас

По состоянию на Sprint 2 Volna A (2026-04-19) система охватывает **полный учётный цикл** строительства посёлка с многокомпанийной изоляцией, ролевым управлением правами, административной панелью, событийными шинами и интеграционным слоем.

**Многокомпанийная архитектура (Sprint 1, US-01):**
- Данные каждого юрлица изолированы — бухгалтер одной компании физически не может видеть данные другой.
- Фильтрация по компании встроена в базовый сервисный слой (`CompanyScopedService`), а не разбросана по коду.
- Суперадмин (holding owner) имеет доступ ко всем компаниям сразу.

**Авторизация и токены (Sprint 1, US-02):**
- JWT-токен содержит список компаний пользователя и признак суперадмина.
- При работе с несколькими компаниями клиент указывает активную через заголовок `X-Company-ID`.

**Тонкая настройка прав доступа — RBAC v2 (Sprint 1, US-03):**
- Права определяются тройкой: роль + действие + тип ресурса (например, бухгалтер может читать договоры, но не удалять).
- Матрица прав хранится в базе данных — добавить новое право можно без деплоя кода.
- Все write-эндпоинты API переведены на `require_permission`.

**Событийные шины (Sprint 2 Volna A, US-04 + US-05):**
- `BusinessEventBus` — шина деловых событий: платёж одобрен, договор подписан, стадия дома изменена. Подписчики регистрируются декоратором, ядро их не знает напрямую.
- `AgentControlBus` — шина управления ИИ-субагентами: сигналы запуска и остановки проходят через единую точку контроля.

**Интеграционный слой (Sprint 2 Volna A, US-06 + US-07):**
- ACL IntegrationAdapter: входящие данные из внешних систем (1С, банки) преобразуются во внутренние модели на границе. Внутренний код никогда не видит чужие форматы.
- Pluggability container: новый адаптер или интеграция регистрируется в одном месте и подключается/отключается без правки ядра.

**Административная панель (Wave 11):**
- `/admin/permissions` — визуальная матрица прав: кто что может делать.
- `/admin/companies` — реестр компаний: создание, редактирование, вкладка с 7 параметрами настроек.
- `/admin/users` — реестр пользователей: назначение ролей прямо в строке таблицы (inline).
- `/admin/rules` — бизнес-правила в трёх категориях: Финансы, Кадры, Процессы.

**Каталог и объекты:**
- Реестр из 85 домов с типами, опциями и историей смены стадий строительства.
- 11 стадий от «земля» до «сервис», переходы строго в одну сторону.

**Плановый бюджет:**
- Статьи бюджета и плановые суммы в разрезе проект × статья × стадия × дом.
- Массовая загрузка (bulk upsert) планового бюджета.

**Факт — подрядчики и договоры:**
- Реестр подрядчиков с уникальным ИНН; мягкое удаление не блокирует создание нового подрядчика с тем же ИНН.
- Договоры с жёсткими переходами статусов: черновик → действующий → завершён / отменён.

**Факт — платежи:**
- Платёж создаётся в статусе «черновик»; переводится в «согласован» или «отклонён» только Владельцем через отдельные действия (не через обычное редактирование).
- Согласованный или отклонённый платёж нельзя изменить или удалить — финансовая история защищена.
- Лимит перерасхода: сумма одобренных платежей не может превысить 120% суммы договора.

**Факт — закупки материалов:**
- Запись о закупке привязана к дому и стадии; итоговая сумма рассчитывается автоматически.

**Сквозные возможности:**
- Все изменения фиксируются в криптографически связанном журнале аудита (SHA-256 цепочка) с указанием роли, IP и содержимого изменения.
- 14 полей персональных данных маскируются автоматически на всех средах (включая email).
- WAL-архив в Yandex Object Storage — непрерывная защита данных между дампами.

**Текущий охват:**
- 14 сущностей в базе данных
- 57 эндпоинтов API
- 4 страницы Admin UI
- 2 событийные шины (BusinessEventBus + AgentControlBus)
- 1С adapter skeleton: 60 тестов, на полке до production-gate

---

## Текущий статус

| Фаза | Содержание | Статус |
|------|-----------|--------|
| 0 | Инфраструктура (Docker, CI, Makefile) | закрыта |
| 1 | Аутентификация, пользователи, роли | закрыта |
| 2 | Базовые справочники | закрыта |
| 3 | Каталог объектов + финансы план/факт | закрыта технически (ожидает OWASP + legal) |
| M-OS-0 | Реструктуризация в pod-архитектуру | закрыта (`06baf07`, ADR 0008–0010) |
| M-OS-1 Sprint 1 | Multi-company, JWT, RBAC v2 | закрыт (US-01, US-02, US-03) |
| M-OS-1 Wave 11 | Admin UI: 4 страницы + регрессия Round 4 | закрыт |
| M-OS-1 Sprint 2 Volna A | Event Bus, ACL Adapter, Pluggability | закрыт (US-04–US-07) |
| M-OS-1 Sprint 2 Volna B | Operations UI + оставшиеся US | в работе |
| M-OS-2 | 1С интеграция + Voice AI | в очереди |
| M-OS-4 | CV-модуль (видеоаналитика) | в планировании |

---

## Архитектура (схема)

```
┌─────────────────────────────────────────────────────┐
│                  Admin UI (React)                   │
│  /admin/permissions  /admin/companies               │
│  /admin/users        /admin/rules                   │
└────────────────────────┬────────────────────────────┘
                         │ HTTP REST + JWT
┌────────────────────────▼────────────────────────────┐
│              FastAPI (Python 3.12)                  │
│  UserContextMiddleware  →  CompanyScopedService     │
│  require_permission()   →  role_permissions (БД)   │
│  audit_service.log()    →  crypto audit chain       │
│  BusinessEventBus       →  подписчики-обработчики  │
│  AgentControlBus        →  ИИ-субагенты             │
│  ACL IntegrationAdapter →  внешние системы          │
└────────────────────────┬────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────┐
│              PostgreSQL 16                          │
│  companies  user_company_roles  role_permissions    │
│  projects  contracts  payments  materials  ...      │
│  WAL-архив → Yandex Object Storage (непрерывно)    │
└─────────────────────────────────────────────────────┘
```

**Принцип многокомпанийной изоляции:**

```
Запрос пользователя
  → JWT декодируется: company_ids, is_holding_owner
  → Заголовок X-Company-ID → активная компания
  → UserContextMiddleware кладёт UserContext в ContextVar
  → Все сервисы читают UserContext → фильтруют по company_id
  → В БД уходит SELECT ... WHERE company_id = ? (не постобработка!)
```

---

## Быстрый старт для разработки

### Требования

- Docker Desktop (или Docker Engine + Docker Compose v2)
- GNU Make (входит в macOS Xcode CLI Tools; на Windows — через WSL2)

### Первый запуск

```bash
# 1. Клонировать репозиторий (если ещё не сделано)
git clone <repo-url> coordinata56
cd coordinata56

# 2. Создать файл переменных окружения
cp .env.dev.example .env.dev
# Откройте .env.dev и смените пароли (POSTGRES_PASSWORD, JWT_SECRET_KEY)

# 3. Установить pre-commit хуки (один раз после клонирования)
bash scripts/install-hooks.sh

# 4. Поднять все сервисы (PostgreSQL, backend, frontend, Adminer)
make up
```

После успешного запуска доступны:

| Сервис    | Адрес                      | Описание                        |
|-----------|----------------------------|---------------------------------|
| Backend   | http://127.0.0.1:8000      | FastAPI REST API                |
| Swagger   | http://127.0.0.1:8000/docs | Интерактивная документация API  |
| Frontend  | http://127.0.0.1:5173      | React + Vite (hot-reload)       |
| Admin UI  | http://127.0.0.1:5173/admin | Административная панель        |
| Adminer   | http://127.0.0.1:8080      | Веб-интерфейс PostgreSQL        |
| PostgreSQL| 127.0.0.1:5433             | Прямое подключение (порт 5433)  |

### Повседневные команды

```bash
make logs        # логи всех сервисов в реальном времени
make logs-back   # только backend
make psql        # psql-консоль PostgreSQL
make migrate     # применить Alembic-миграции (alembic upgrade head)
make migration MSG="добавить таблицу lots"  # создать новую миграцию
make shell-back  # bash внутри backend-контейнера
make down        # остановить сервисы (данные сохраняются)
make reset-db    # ОСТОРОЖНО: удалить все данные БД и начать заново
make build       # пересобрать образы после изменений в Dockerfile
```

### Как работает hot-reload

- **Backend**: uvicorn запускается с флагом `--reload`. Любое изменение `.py`-файла в `backend/` вызывает перезагрузку сервера автоматически.
- **Frontend**: Vite HMR (hot module replacement). Изменения в `frontend/src/` отражаются в браузере без перезагрузки страницы.
- Исходники обоих сервисов монтируются как volume — код не копируется в образ при запуске, только при сборке.

### Структура окружения

```
docker-compose.yml       # описывает 4 сервиса + сеть + тома
.env.dev.example         # шаблон (коммитится в git)
.env.dev                 # реальные значения (НЕ коммитится, в .gitignore)
backend/Dockerfile       # multi-stage: deps → development → production
frontend/Dockerfile      # multi-stage: deps → development → production (nginx)
Makefile                 # удобные команды для разработчика
```

---

## Структура проекта

```
coordinata56/
├── backend/           # FastAPI + SQLAlchemy (Python 3.12)
│   ├── app/           # Код приложения
│   │   ├── core/      # Ядро M-OS: master_data, integrations, auth, events
│   │   │   ├── master_data/    # Company, UserCompanyRole
│   │   │   ├── integrations/   # IntegrationAdapter (ADR 0014), 1С adapter
│   │   │   └── events/         # BusinessEventBus, AgentControlBus (ADR 0016)
│   │   └── api/       # FastAPI-роутеры
│   └── tests/         # Юнит и интеграционные тесты
├── frontend/          # React + TypeScript + Vite + shadcn/ui
│   └── src/
│       ├── pages/admin/       # Admin UI: permissions, companies, users, rules
│       └── shared/api/        # API-клиенты (TanStack Query)
├── migrations/        # Alembic миграции
├── tests/             # Сквозные (E2E) тесты
├── docs/              # Документация, ADR, регламент субагентов
│   ├── adr/           # Architecture Decision Records
│   ├── agents/        # Регламент 17 ИИ-субагентов (v1.0–v1.3)
│   ├── design/        # Design System
│   ├── knowledge/     # База знаний: уроки, решения, глоссарий, онбординг
│   ├── onboarding/    # Онбординг для разработчика и оператора системы
│   ├── qa/            # QA-отчёты и тест-планы
│   ├── security/      # Security-отчёты и аудиты
│   └── pods/          # Спецификации pod-архитектуры
├── infra/             # Инфраструктурные файлы
├── scripts/
│   └── hooks/         # Pre-commit хуки H-1..H-5
├── CHANGELOG.md       # История изменений по Keep a Changelog
├── docker-compose.yml # Локальное окружение: postgres + backend + frontend
├── .env.dev.example   # Шаблон переменных окружения для разработки
└── Makefile           # Команды разработки (up, down, logs, psql, migrate…)
```

---

## Принципы разработки

1. **Skeleton-first для compliance.** Всё, что касается персональных данных (ПД) — строим структуры и маски сразу, а юридические флоу (согласия, уведомления регулятору) — отдельным треком перед выходом в production.
2. **ИИ делает рутину, человек одобряет важное.** Ни одно финансово или юридически значимое действие не происходит без подтверждения человека.
3. **Pluggability.** Любая интеграция, модуль, модель ИИ — подключается и отключается без правки ядра.
4. **Всё записывается.** Каждое действие — в неизменяемом криптографически связанном аудит-журнале.
5. **Данные изолированы по компании.** Фильтр по `company_id` — на уровне SQL, не постобработкой.
6. **Тройная защита данных.** WAL-архив (непрерывно) + SQL-дамп (ежедневно) + том Docker (локально).

---

## Ключевые документы (навигация)

**Онбординг**
- [Быстрый старт разработчика](docs/onboarding/developer-quickstart.md)
- [Обзор Admin UI для оператора](docs/onboarding/admin-panel-overview.md)
- [Онбординг разработчика (полный)](docs/knowledge/onboarding/developer.md)

**Стратегия и цели**
- [Дорожная карта (10 фаз)](ROADMAP.md)
- [Видение M-OS](docs/m-os-vision.md)
- [История изменений](CHANGELOG.md)
- [Статус cottage-platform pod](docs/pods/cottage-platform/status.md)

**Регламенты и процесс**
- [Регламент субагентов v1.0 (17 ролей)](docs/agents/regulations_draft_v1.md)
- [v1.1 — скилы и источники знаний](docs/agents/regulations_addendum_v1.1.md)
- [v1.2 — регламент Координатора, RACI, DoD](docs/agents/regulations_addendum_v1.2.md)
- [v1.3 — уроки Фазы 2](docs/agents/regulations_addendum_v1.3.md)
- [Definition of Done — общий чек-лист](docs/agents/phase-checklist.md)
- [CLAUDE.md — живой антипаттерник](CLAUDE.md)

**Архитектура (ADR)**
- [ADR 0011 — Foundation: multi-company, RBAC v2, crypto audit](docs/adr/0011-foundation-multi-company-rbac-audit.md)
- [ADR 0013 — Контракт на эволюцию миграций](docs/adr/0013-migrations-evolution-contract.md)
- [ADR 0014 — Anti-Corruption Layer](docs/adr/0014-anti-corruption-layer.md)
- [ADR 0016 — Domain Event Bus](docs/adr/0016-domain-event-bus.md)
- [ADR 0024 — Verification Gate для live-активаций](docs/adr/0024-verification-gate.md)
- [ADR 0025 — 1С интеграция (draft)](docs/adr/0025-1c-integration.md)
- [Все ADR](docs/adr/)

**Дизайн**
- [Design System v1.0](docs/design/design-system-v1.md)

---

Версия: 0.5.1 (Sprint 2 Volna A)
Владелец: Мартин
Разработка: автоматическая, Claude Code + команда ИИ-субагентов
