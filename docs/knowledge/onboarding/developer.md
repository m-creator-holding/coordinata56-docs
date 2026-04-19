# Онбординг разработчика — M-OS / coordinata56

> **Для кого:** backend-разработчики, входящие в проект.
> **Время чтения:** 20–30 минут.
> **Дата последнего обновления:** 2026-04-19

---

## Контекст: что здесь строим

M-OS — внутреннее корпоративное ПО холдинга (AI-native, multi-company). Не публичный продукт.  
Первый модуль — **cottage-platform-pod**: управление строительством 85 коттеджей.

Стек: Python 3.12 + FastAPI + SQLAlchemy 2.0 + PostgreSQL 16 + React + TypeScript + Vite + shadcn/ui + Docker.

---

## Что читать в первый день (строго по порядку)

Список упорядочен от общего к частному. Не пропускайте шаги — каждый следующий опирается на предыдущий.

| Шаг | Документ | Что даёт |
|-----|----------|----------|
| 1 | `CLAUDE.md` | Антипаттерник, ссылочный навигатор, ключевые правила с примерами реальных ошибок |
| 2 | `docs/agents/CODE_OF_LAWS.md` | Операционный кодекс (47 статей): что можно, что нельзя, как принимать решения |
| 3 | `docs/adr/0013-migrations-evolution-contract.md` | Правила миграций БД — первая задача (US-01) касается миграции |
| 4 | `docs/adr/0014-anti-corruption-layer.md` | Каркас адаптеров — понять, что такое `IntegrationAdapter` и почему нельзя делать HTTP-вызовы напрямую |
| 5 | `docs/pods/cottage-platform/m-os-1-plan.md` | Общий план M-OS-1 «Скелет»: что будет сделано за 14–15 недель и почему |
| 6 | `docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md` | Декомпозиция Sprint 1: конкретные User Stories, acceptance criteria, исполнители |
| 7 | `docs/agents/departments/backend.md` | Правила работы backend-команды, чек-лист A.1–A.5 перед каждым PR |

---

## Первый запуск

```bash
git clone <repo-url> coordinata56
cd coordinata56
cp .env.dev.example .env.dev
# Отредактируйте .env.dev: смените POSTGRES_PASSWORD и JWT_SECRET_KEY
make up
```

После запуска:

| Сервис    | Адрес                       |
|-----------|-----------------------------|
| Backend   | http://127.0.0.1:8000       |
| Swagger   | http://127.0.0.1:8000/docs  |
| Frontend  | http://127.0.0.1:5173       |
| Adminer   | http://127.0.0.1:8080       |

Ключевые команды:

```bash
make logs        # логи всех сервисов
make migrate     # применить миграции (alembic upgrade head)
make shell-back  # bash внутри backend-контейнера
make reset-db    # ОСТОРОЖНО: удалить все данные БД
```

---

## Нормативная база (прочитать до написания первой строки кода)

1. `CLAUDE.md` — антипаттерник и ссылочный навигатор; загружается в Claude Code автоматически
2. `docs/CONSTITUTION.md` — основной закон, 96 статей
3. `docs/agents/CODE_OF_LAWS.md` — операционный кодекс, 47 статей
4. `docs/agents/departments/backend.md` — правила работы backend-команды
5. ADR, относящиеся к вашей задаче (см. `docs/adr/`)

---

## Hooks: механическая защита

Репозиторий защищён набором из пяти pre-commit хуков (Hooks Phase 0). Установите их один раз после клонирования:

```bash
bash scripts/install-hooks.sh
```

### Пять хуков

| Хук | Что делает | Блокирует коммит? |
|-----|------------|:-----------------:|
| **H-1** `check_secrets.py` | Сканирует staged-файлы на секреты: `.env*`, `*.key`, литеральные пароли, GitHub PAT-токены | Да |
| **H-2** `check_add_all.py` | При staged > 10 файлов — предупреждает о «чужих» файлах от фоновых агентов | Да (при ≥3 чужих) |
| **H-3** `check_dormant_notify.py` | Предупреждает о зависших фоновых сессиях агентов | Нет (info) |
| **H-4** `check_opus_prompts.py` | Проверяет, что вызовы Opus-субагентов содержат `ultrathink` | Нет (warn) |
| **H-5** `run_lint_and_tests.sh` | Запускает `ruff check`, `ruff format --check` и pytest для staged Python-файлов | Да |

### Обходы (использовать осознанно)

| Ситуация | Команда |
|----------|---------|
| Полный обход всех хуков | `git commit --no-verify` — **не рекомендуется**, ответственность за чистоту переходит к вам |
| Обход только H-5 (lint/tests) | `SKIP_HOOKS=H-5 git commit` |
| Разрешить `git add -A` (H-2) | `COORDINATOR_ALLOW_ADD_ALL=1 git commit` |
| Исключить строку из H-1 | Добавить `# hook-exception: H-1 <причина>` в эту строку |

Факт добавления маркера `hook-exception` фиксируется в stderr — reviewer видит его при ревью.

Полное описание: `scripts/hooks/README.md`.

---

## Чек-лист A.1–A.5 перед PR

Блок обязательных пунктов из `docs/agents/departments/backend.md` v1.3 (ADR-gate). Каждый пункт подтверждается в отчёте PR с артефактом (grep-вывод, diff-строки, ID теста). Отчёт без артефактов невалиден — reviewer переключится с spot-check на полный чек-лист.

- **A.1 — Литералы секретов.** В diff нет литеральных паролей, токенов, bearer-значений, JWT-строк. Тестовые пароли — через `secrets.token_urlsafe(16)`, конфиги — через `os.environ.get(...)`.

- **A.2 — SQL только через репозитории.** Все обращения к БД в сервисном слое — через репозитории. Прямые `db.execute(select(...))` или `session.get(...)` в `services/` или `api/deps.py` — запрещены. Разрешены типизированные предикаты `ColumnElement[bool]` через `extra_conditions=` (ADR 0004 MUST #1a/#1b).

- **A.3 — RBAC на write-эндпоинтах.** Все ручки POST/PATCH/DELETE используют `require_permission(action, resource_type)` с явным `user_context`. Устаревший `require_role` в новом коде не применяется — только как deprecated-alias на период миграции. Источник: ADR 0011 §2.3–2.4.

- **A.4 — Формат ошибок и пагинации.** Ошибки — строго формат ADR 0005: `{"error": {"code", "message", "details"}}`. Пагинация — строго envelope ADR 0006: `{"items", "total", "offset", "limit"}`. Голый массив в ответе запрещён.

- **A.5 — Аудит-лог write-операций.** Для каждой write-операции `audit_service.log()` вызывается **в той же транзакции**, что и запись в БД — не после `commit()`. Источник: ADR 0007.

---

## Аудит и персональные данные

### Crypto Audit Chain (PR #3, ADR 0011 Шаг 3)

Таблица `audit_log` теперь содержит криптографическую цепочку: поля `prev_hash` и `hash` (SHA-256) связывают каждую запись с предыдущей. Подмена или удаление любой записи обнаруживается при верификации.

Что важно знать при разработке:

- `INSERT` в `audit_log` требует `SELECT ... FOR UPDATE` на последнюю строку — защита от race condition при параллельных записях.
- Никогда не делайте прямой INSERT в `audit_log`, минуя `audit_service` — это нарушит цепочку.
- Ретроактивное заполнение хешей при миграции: `scripts/audit_chain_backfill.py`.

Верификация цепочки:

```
GET /api/v1/audit/verify?from=<ISO8601>&to=<ISO8601>
```

Endpoint доступен только holding owner (`is_holding_owner=True`). При нарушении цепочки возвращается позиция первой сломанной записи.

### Маскирование персональных данных

13 полей персональных данных маскируются в `audit_log` и во всех логах — **на всех средах**, включая dev и staging:

| Категория | Поля |
|-----------|------|
| Документы | серия паспорта, номер паспорта, СНИЛС, ИНН физлица |
| Контакты | номер телефона, email |
| Адрес | полный адрес регистрации |
| Финансы | номер счёта, номер карты |
| Прочее | дата рождения, место рождения, ФИО полностью (в audit-контексте), биометрические данные |

Формат маски: `****<последние 4 символа>`, например `****1234`.

Маскирование происходит в Pydantic Read-схемах через `field_serializer`. Если добавляете новую сущность с ПД — проверьте, что Read-схема не возвращает поля в открытом виде.

### Политика skeleton-first

Любой код, затрагивающий ПД, строится сначала как скелет: структуры с масками, заглушки согласий, заглушки политик хранения. Живые compliance-процедуры (уведомление Роскомнадзора, реальные согласия по ФЗ-152) реализуются отдельным треком перед production-gate. Подробнее: `CLAUDE.md` раздел «Данные / ПД».

---

## Что изменилось в Волне 1 (M-OS-1, 2026-04)

Волна 1 — первая волна Foundation. Половина закрыта (PR #1 ✅, PR #2 на ревью, PR #3 в подготовке).

### 1. Multi-company (ADR 0011, Шаг 1)

**Что появилось:**
- Таблицы `companies` и `user_company_roles` в ядре (`backend/app/core/master_data/`).
- Поле `company_id` добавлено во все объекты предметной логики: `projects`, `contracts`, `contractors`, `payments`.
- Payment получает `company_id` денормализованно из `Contract` — синхронно в сервисном слое.

**Что меняется в ежедневной работе:**
- Любой запрос к объектам предметной логики обязан содержать фильтр `WHERE company_id = ?`, исходящий из JWT-токена пользователя. Запрос без этого фильтра — дефект.
- Базовый класс `CompanyScopedService` реализует метод `_scoped_query_conditions(user_context)`, возвращающий типизированный предикат SQLAlchemy. Все сервисы предметной логики наследуют его.
- JWT-токен теперь содержит клеймы `company_ids: list[int]` и `is_holding_owner: bool`.
- Клиент передаёт заголовок `X-Company-ID: <id>` при работе с несколькими компаниями.
- Суперадмин с `is_holding_owner=True` получает bypass фильтра компании.

**Обратная совместимость:** при миграции все существующие объекты получают `company_id=1` (seed-компания «Холдинг по умолчанию»). Все 351 тест продолжают работать.

### 2. Fine-grained RBAC v2 (ADR 0011, Шаг 2)

**Что появилось:**
- Таблица `role_permissions` — матрица прав (Configuration-as-data, принцип 10 ADR 0008).
- Функция `can(user_context, action, resource) -> bool` в ядре.
- Декоратор `require_permission(action, resource_type)` заменяет `require_role`.

**Что меняется:**

```python
# Было:
@require_role(UserRole.OWNER, UserRole.ACCOUNTANT)

# Стало:
@require_permission(action="write", resource_type="contract")
```

Старый `require_role` остаётся как deprecated alias — все текущие тесты проходят без изменений.

Правило: при написании нового endpoint — только `require_permission`. Использование `require_role` в новом коде — дефект при ревью.

**Граничные случаи, которые нужно знать:**
- Holding-owner получает `True` без проверки матрицы.
- Если у пользователя несколько ролей в одной компании — право выдаётся если хотя бы одна роль разрешает.
- Права конфигурируются через данные, не через код: чтобы добавить новое право — строка в `role_permissions`, а не деплой.

### 3. Crypto Audit Chain (ADR 0011, Шаг 3)

Подробно описано в секции «Аудит и персональные данные» выше.

### 4. Контракт на эволюцию миграций (ADR 0013)

Это правило теперь является CI-требованием, а не рекомендацией.

**Запрещено в одном шаге** (блокируется линтером в CI):
- `DROP COLUMN` — нужен deprecation-период 2 спринта
- `RENAME COLUMN` / `RENAME TABLE` — только через expand/contract
- `ALTER COLUMN ... NOT NULL` без DEFAULT
- `DROP TABLE` — только через переименование в `_deprecated_<name>` и 2 спринта ожидания

**Разрешено без ограничений:**
- Добавление новой таблицы
- Добавление nullable-колонки или колонки с DEFAULT
- Расширение enum (добавление нового значения)

**Обязательный round-trip в CI:**

```
alembic upgrade head
alembic downgrade -1
alembic upgrade head
```

Все три шага должны проходить без ошибок. PR не мержится, если round-trip сломан.

**Операции, требующие комментария в теле миграции:**
- Изменение типа без потери данных
- Добавление NOT NULL с DEFAULT
- Добавление CHECK на непустую таблицу
- Изменение индексов

Полный регламент: `docs/adr/0013-migrations-evolution-contract.md`.

### 5. Anti-Corruption Layer (ADR 0014 — принят 2026-04-18)

ADR 0014 принят в статусе `accepted` (force-majeure, backup-mode через governance-auditor 2026-04-18). Реализация продолжается.

**Что вводится:**
- Базовый класс `IntegrationAdapter` в `backend/app/core/integrations/base.py`.
- Три состояния адаптера: `written` → `enabled_mock` → `enabled_live`.
- Runtime-guard: при попытке сделать живой вызов из non-production среды — выбрасывается `AdapterDisabledError`.
- `pytest-socket` в корневом `conftest.py` с `autouse=True` — блокирует все сетевые вызовы в тестах по умолчанию.

**Практические правила уже сейчас:**
- Не пишите HTTP-вызовы к внешним системам напрямую в бизнес-сервисах.
- Любой внешний сервис — только через наследник `IntegrationAdapter`.
- Telegram — единственный живой адаптер в M-OS-1. Все остальные (`sberbank`, `1c`, `rosreestr` и т.д.) — в состоянии `written` (CODE_OF_LAWS ст. 45а/45б).

---

## M-OS-1.1A — что мы построили в Sprint 1

> **Explanation** — ориентир для нового разработчика, входящего после завершения Sprint 1

Sprint 1 M-OS-1.1A (US-01, US-02, US-03) закладывает фундамент, на котором стоит вся остальная разработка M-OS-1. Если вы входите в проект после его завершения, вот что уже готово и почему это важно.

### Что построено

**Многокомпанийная изоляция данных (US-01)**

Каждая таблица с деловыми данными (проекты, договоры, платежи, подрядчики и другие) теперь содержит поле `company_id`. Это поле гарантирует, что бухгалтер одного юрлица никогда не увидит данные другого. Реализовано через базовый класс `CompanyScopedService` — все сервисы предметной логики наследуют его.

**JWT с информацией о компаниях (US-02)**

Токен авторизации теперь содержит список ID компаний пользователя и флаг `is_holding_owner`. При запросах к данным клиент указывает активную компанию через заголовок `X-Company-ID`. `UserContextMiddleware` обрабатывает этот заголовок и передаёт контекст в сервисы через `ContextVar`.

**Тонкая настройка прав (US-03)**

Права больше не определяются ролью («бухгалтер»). Они определяются тройкой: роль + действие + тип ресурса. Матрица хранится в таблице `role_permissions` — это данные, не код. Все write-эндпоинты переведены с `require_role` на `require_permission`.

### Где смотреть код

| Компонент | Путь |
|-----------|------|
| Модели Company, UserCompanyRole | `backend/app/core/master_data/` |
| Базовый класс CompanyScopedService | `backend/app/core/` |
| UserContextMiddleware | `backend/app/api/` |
| Декоратор require_permission | `backend/app/api/` |
| Матрица прав (seed) | `migrations/versions/` — ищите миграцию с US-03 |
| Тест изоляции компаний | `backend/tests/` — `test_cross_company_isolation` |

### Архитектурные диаграммы

Подробные Mermaid-диаграммы всех трёх частей Sprint 1 — в отдельном документе:

`docs/pods/cottage-platform/architecture/m-os-1-1a-overview-2026-04-19.md`

---

## Паттерн CompanyScopedService

> **How-to** — как правильно написать сервис для нового ресурса

Каждый новый сервис предметной логики (не core, не integrations) обязан наследовать `CompanyScopedService`. Это гарантирует, что запросы к данным автоматически фильтруются по компании.

### Шаблон нового сервиса

```python
from app.core.company_scoped import CompanyScopedService
from app.models import MyNewModel
from app.schemas.my_new import MyNewRead, MyNewCreate
from app.core.auth import UserContext
from sqlalchemy.orm import Session
from sqlalchemy import ColumnElement


class MyNewService(CompanyScopedService):
    """
    Сервис для <описание ресурса>.
    Наследует компанийный фильтр — запросы возвращают только данные
    активной компании из UserContext.
    """

    def _scoped_query_conditions(
        self, user_context: UserContext
    ) -> list[ColumnElement[bool]]:
        # Стандартный фильтр по company_id.
        # Если у ресурса нет собственного company_id — не наследуйте
        # CompanyScopedService, обсудите с backend-head.
        return [MyNewModel.company_id == user_context.company_id]

    def get_list(self, db: Session, user_context: UserContext, ...):
        conditions = self._scoped_query_conditions(user_context)
        # Передаём conditions в репозиторий через extra_conditions=
        # (прямой SELECT в сервисе запрещён — A.2)
        return self.repository.list_paginated(db, extra_conditions=conditions, ...)

    def create(self, db: Session, user_context: UserContext, data: MyNewCreate):
        # company_id берётся из контекста, не из тела запроса
        obj = MyNewModel(
            **data.model_dump(),
            company_id=user_context.company_id,
        )
        ...
```

### Эндпоинт к этому сервису

```python
from fastapi import APIRouter, Depends
from app.api.deps import get_user_context
from app.core.auth import UserContext, require_permission

router = APIRouter()

@router.post("/my-resource")
@require_permission(action="write", resource_type="my_resource")
async def create_my_resource(
    data: MyNewCreate,
    user_context: UserContext = Depends(get_user_context),
    db: Session = Depends(get_db),
):
    return my_new_service.create(db, user_context, data)
```

### Чек-лист при создании нового ресурса

- [ ] Модель содержит `company_id: int, FK → companies.id, NOT NULL, index=True`
- [ ] Сервис наследует `CompanyScopedService`
- [ ] `_scoped_query_conditions` возвращает фильтр по `company_id`
- [ ] `company_id` при создании берётся из `user_context`, не из тела запроса
- [ ] Эндпоинт использует `require_permission`, не `require_role`
- [ ] Миграция написана по safe-pattern (nullable → backfill → NOT NULL)
- [ ] Тест проверяет изоляцию: пользователь компании A не видит данные компании B

### Добавление нового права в матрицу

Если ваш ресурс требует нового права, которого ещё нет в `role_permissions`:

1. Добавьте строку в seed-скрипт миграции:
   ```sql
   INSERT INTO role_permissions (role_template, action, resource_type, is_allowed)
   VALUES ('accountant', 'write', 'my_resource', true);
   ```
2. Запустите `make migrate`.
3. Не нужен деплой кода — это изменение данных.

Полный список существующих прав: проверьте `role_permissions` через `make shell-back` → psql → `SELECT * FROM role_permissions`.

---

## M-OS-1.1A Sprint 1: что делаете вы

Sprint 1 стартует после разблокировки Gate-0 (ADR-0014 ratified 2026-04-18). Оценка: 2 недели.

### Ваша первая задача: US-01

**Суть:** добавить `company_id` на все оставшиеся таблицы cottage-platform (до 16 таблиц ещё без этого поля), обернуть их в `CompanyScopedService`, настроить фильтрацию.

**Что конкретно нужно сделать:**

1. Найти все таблицы без `company_id` (проверяем `backend/app/models/`).
2. Написать миграцию Alembic по **safe-migration pattern** (ADR-0013):
   - Шаг 1: добавить `company_id` как nullable (`ALTER TABLE ... ADD COLUMN company_id INT NULL`).
   - Шаг 2: заполнить `UPDATE ... SET company_id = 1 WHERE company_id IS NULL`.
   - Шаг 3: поставить NOT NULL (`ALTER TABLE ... ALTER COLUMN company_id SET NOT NULL`).
   - Все три шага — в одном файле миграции через отдельные `op.execute(...)`.
3. Добавить FK `→ companies.id` и индекс на `company_id`.
4. Сервисы для этих сущностей — переписать на наследование от `CompanyScopedService`.
5. Написать тест `test_cross_company_isolation`: пользователь компании A запрашивает GET `/projects` — видит только свои; GET `/projects/<id из компании B>` → 404.
6. Убедиться что все 351 существующих теста зелёные.

**Acceptance criteria:** описаны в `docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md`, US-01.

### Дополнительные задачи Sprint 1 (US-02, US-03)

После US-01:

- **US-02** (backend-dev-2): JWT-клеймы `company_ids` + `is_holding_owner` + заголовок `X-Company-ID`.
- **US-03** (backend-dev-1): перевод всех write-эндпоинтов с `require_role` на `require_permission`.

---

## Иерархия команды

Знать, к кому обращаться, важно — неправильный адрес замедляет работу:

```
Координатор (Президент)
  └── backend-director (L2 Директор)
        └── backend-head (L3 Начальник отдела)
              └── backend-dev (L4 Разработчик) ← вы здесь
```

**Правило:** задачи приходят от backend-head. Вопросы по задаче — к backend-head. Если backend-head не может ответить — он эскалирует к backend-director. Вы не обращаетесь к Координатору напрямую.

---

## Где получить помощь

| Вопрос | Куда |
|--------|------|
| «Я не понимаю, что делать по US-01» | К **tutor** — субагент для обучения, объясняет с нуля |
| «Как правильно написать этот код» | `docs/knowledge/claude-code-guide.md` + **backend-head** |
| «Конфликт с ADR или неоднозначность» | К **architect** через backend-head |
| «Что можно, что нельзя по регламенту» | `docs/agents/CODE_OF_LAWS.md` → если не нашли → к **backend-head** |
| «Нарушение безопасности в коде» | К **backend-director** немедленно, без цепочки |

---

## Ключевые правила из CLAUDE.md (кратко)

| Категория | Правило |
|-----------|---------|
| API | Формат ошибок — только ADR 0005: `{"error": {"code", "message", "details"}}` |
| API | Пагинация — только envelope ADR 0006: `{"items", "total", "offset", "limit"}` |
| API | Вложенные ресурсы: всегда проверяй `child.parent_id == pid`, иначе 404 |
| БД | Фильтры — в SQL WHERE, не постобработкой в Python после LIMIT |
| БД | Enum в миграции: значения совпадают с `.value` Python-enum, включая регистр |
| Код | `# type: ignore` / `# noqa` — только с комментарием-обоснованием |
| Git | `git add -A` запрещён без `git status --short` |
| Тесты | Пароли в фикстурах — только `secrets.token_urlsafe(16)`, не литералы |
| Reviewer | Ревью — до `git commit`, не после; работает на `git diff --staged` |
| ПД | Маскирование 13 ПД-полей — на всех средах, не только production |
| Интеграции | HTTP к внешним сервисам — только через `IntegrationAdapter` (ADR 0014) |

---

## Структура кода

```
backend/
├── app/
│   ├── api/          # FastAPI-роутеры (НЕ routers/ — исторически, ADR 0004)
│   ├── core/         # Ядро M-OS: master_data, integrations, auth, events
│   │   ├── master_data/    # Company, UserCompanyRole
│   │   ├── integrations/   # IntegrationAdapter, AdapterState (ADR 0014)
│   │   └── events/         # BusinessEventBus, AgentControlBus (ADR 0016, Sprint 2)
│   ├── models/       # SQLAlchemy-модели
│   ├── services/     # Бизнес-логика (наследники CompanyScopedService)
│   └── schemas/      # Pydantic-схемы
├── tests/            # Тесты
migrations/
└── versions/         # Alembic-ревизии
scripts/
└── hooks/            # Pre-commit хуки H-1..H-5
```

---

## Полезные ссылки

- `docs/adr/0011-foundation-multi-company-rbac-audit.md` — multi-company, RBAC v2, crypto audit
- `docs/adr/0013-migrations-evolution-contract.md` — контракт на эволюцию миграций
- `docs/adr/0014-anti-corruption-layer.md` — каркас адаптеров (принят 2026-04-18)
- `docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md` — декомпозиция Sprint 1 (12 US)
- `docs/pods/cottage-platform/m-os-1-plan.md` — общий план M-OS-1 «Скелет»
- `docs/pods/cottage-platform/architecture/m-os-1-1a-overview-2026-04-19.md` — архитектурные диаграммы Sprint 1
- `docs/knowledge/api/auth-rbac-api-2026-04-19.md` — API Reference: авторизация и права доступа
- `docs/agents/departments/backend.md` — правила backend-команды (включая ADR-gate A.1–A.5)
- `docs/agents/departments/quality.md` — правила QA и spot-check
- `scripts/hooks/README.md` — документация хуков H-1..H-5
- `docs/knowledge/onboarding/designer-onboarding.md` — онбординг дизайнера
