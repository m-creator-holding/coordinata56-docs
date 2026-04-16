# ADR 0007 — Механизм записи в аудит-лог (Phase 3)

- **Статус**: proposed
- **Дата**: 2026-04-15
- **Автор**: Архитектор (Claude Code, субагент `architect`)
- **Утверждающий**: Владелец (Мартин)
- **Контекст фазы**: Phase 3 — базовые CRUD API, кросс-срезовый компонент
- **Связанные ADR**: ADR-0001 (таблица `audit_log`, поле `changes_json`), ADR-0002 (FastAPI, SQLAlchemy 2.0), ADR-0003 (JWT, `user_id` из токена), ADR-0004 (трёхслойная архитектура, аудит в сервисном слое)

---

## Контекст

Таблица `audit_log` определена в ADR-0001 и реализована в `backend/app/models/audit.py`. Поля: `user_id`, `action` (enum), `entity_type`, `entity_id`, `changes_json` (JSONB), `ip_address`, `user_agent`, `timestamp`.

ADR-0003 зафиксировал: в Фазе 2 аудит только через `structlog` (файл лога). Фаза 3 вводит полноценный аудит в таблицу `audit_log` для всех write-операций (create / update / delete).

ADR-0004 зафиксировал: вызов `audit_service.log(...)` — в сервисном слое.

Требования к аудиту:
- Каждая write-операция (create, update, soft_delete) — **без пропусков**.
- В записи есть `user_id` из JWT-токена текущего запроса.
- В `changes_json` есть информация об изменении.
- Пароли, токены и другие секреты — **не попадают** в `changes_json`.
- `AuditLog` — append-only: нет UPDATE / DELETE на этой таблице.

---

## Проблема

Нужно выбрать механизм, который:

1. Гарантирует запись в `audit_log` при каждой write-операции.
2. Имеет доступ к `user_id` из JWT.
3. Позволяет контролировать содержимое `changes_json` — что именно туда попадает.
4. Прост в реализации и проверке на соответствие.

---

## Рассмотренные альтернативы

### Вариант A: FastAPI Middleware (перехват на уровне HTTP)

Middleware обёртывает каждый запрос: после получения ответа с кодом `2xx` на методы `POST`/`PATCH`/`PUT`/`DELETE` — пишет запись в `audit_log`.

**Плюсы:**
- Централизованная точка: одна реализация покрывает все роутеры.
- Не нужно помнить добавлять аудит в каждый обработчик.

**Минусы:**
- **Содержимое `changes_json`**: middleware видит только сырое тело запроса (`request.body()`). Он не знает, что именно изменилось в БД — только то, что пришло в запросе. Для `PATCH` это не полный «до/после», а только «что прислал клиент».
- **Маскировка секретов**: middleware обязан парсить тело и убирать поля `password`, `token`, `secret` — это нетривиальная логика с риском пропустить новое поле.
- **Пропуск операций без тела**: `DELETE /houses/1` не имеет тела — middleware запишет только `entity_id` из URL, без деталей. Нужен отдельный парсинг URL.
- **Сессия БД**: middleware пишет в `audit_log` в той же транзакции или в отдельной? Если в отдельной — аудит может быть записан даже когда основная транзакция упала. Если в той же — нужен доступ к сессии запроса из middleware.
- **`user_id`**: нужно декодировать JWT в middleware повторно (или передавать через `request.state`).

**Почему отклонено**: ненадёжный `changes_json` (только входящий запрос, без «до»), сложная логика маскировки секретов, неопределённость с транзакцией.

---

### Вариант B: FastAPI `Depends`-зависимость в каждом роутере

`AuditDependency` — Depends-объект, который внедряется в каждый write-эндпоинт. Разработчик добавляет `audit: AuditContext = Depends(get_audit_context)` в сигнатуру функции.

**Плюсы:**
- `user_id` и `ip_address` берутся из Request — доступны в Depends.
- Явно видно в сигнатуре endpoint, что аудит подключён.

**Минусы:**
- Разработчик (субагент) **может забыть** добавить Depends. Нет механизма, гарантирующего наличие зависимости во всех write-эндпоинтах.
- Depends внедряет контекст, но не вызывает запись сам — всё равно нужен явный вызов `audit.log(...)`. То есть это просто способ передать контекст, а не самостоятельный механизм.
- Логика аудита разделена: Depends в роутере + явный вызов в сервисе.
- Ревьюер должен проверить каждую сигнатуру — 15 сущностей × несколько write-эндпоинтов = ~60 точек проверки.

**Почему отклонено**: нет гарантии полноты; сочетается с другими вариантами, но не является самостоятельным решением.

---

### Вариант C (выбран): Явный вызов `audit_service.log(...)` в каждом handler сервисного слоя

В каждом методе сервиса, изменяющем данные, после успешного изменения явно вызывается `await self.audit.log(...)`.

```python
# services/project_service.py
async def create(self, data: ProjectCreate, actor_id: int, ip: str) -> Project:
    project = await self.repo.create(data.model_dump())
    await self.audit.log(
        user_id=actor_id,
        action=AuditAction.create,
        entity_type="Project",
        entity_id=project.id,
        changes={"after": data.model_dump()},
        ip_address=ip,
    )
    return project

async def update(self, project_id: int, data: ProjectUpdate, actor_id: int, ip: str) -> Project:
    project = await self.get_or_404(project_id)
    before = project_to_dict(project)  # снимок до изменения
    updated = await self.repo.update(project, data.model_dump(exclude_unset=True))
    after = project_to_dict(updated)
    await self.audit.log(
        user_id=actor_id,
        action=AuditAction.update,
        entity_type="Project",
        entity_id=project_id,
        changes={"before": before, "after": after},
        ip_address=ip,
    )
    return updated
```

**Плюсы:**
- **Полный контроль над `changes_json`**: сервис знает состояние объекта «до» и «после» — полный diff.
- **Маскировка секретов**: `model_dump()` возвращает Pydantic-схему, которая не содержит `password_hash` (он исключён из `ProjectRead`-схемы). Маскировка реализуется один раз на уровне схемы.
- **Транзакционность**: вызов `audit.log()` происходит в той же сессии SQLAlchemy, что и основное изменение. Если транзакция откатится — запись в аудит не сохранится. Это корректное поведение: аудит должен отражать только успешные изменения.
- **Явность и читаемость**: в каждом сервисном методе видно, что аудит записывается. Ревьюер проверяет наличие вызова по списку методов.
- **Гибкость**: разные типы изменений могут иметь разный формат `changes_json` (diff для `update`, только `after` для `create`, только `before` для `delete`).

**Минусы:**
- Субагент может написать метод без вызова `audit.log()` — ревьюер должен это поймать.
- ~45 явных вызовов `audit.log()` по всем сервисам (15 сущностей × ~3 write-метода). Это механическая работа.

---

### Вариант D: SQLAlchemy event listeners

SQLAlchemy позволяет вешать обработчики на события `after_flush` / `after_bulk_update` / `after_bulk_delete` через `@event.listens_for(Session, "after_flush")`.

**Плюсы:**
- Централизованная точка: все изменения через ORM автоматически перехватываются.
- Нельзя забыть — событие срабатывает на уровне ORM, ниже сервисного слоя.

**Минусы:**
- **Нет `user_id`**: event listener не знает контекст HTTP-запроса. `user_id` нужно передавать через thread-local / контекстную переменную `ContextVar` — это скрытый глобальный стейт, антипаттерн в async-коде.
- **Нет контроля над `changes_json`**: event listener видит «сырые» изменения ORM (какие атрибуты модели изменились), но не Pydantic-схему. Маскировка секретов — сложная ручная работа по списку полей.
- **Трудно тестировать**: event listener срабатывает неявно; тест не видит его вызов без специальной проверки.
- **Отладка**: при ошибке в event listener SQLAlchemy может проглотить исключение или откатить транзакцию неожиданным образом.
- **Конфликт с архитектурой ADR-0004**: сервисный слой ответствен за бизнес-логику — аудит является частью бизнес-логики (что писать, в каком формате). Перенос в ORM нарушает это разделение.

**Почему отклонено**: проблема с `user_id` через `ContextVar` в async-коде — фундаментальное ограничение. Нарушение разделения слоёв ADR-0004.

---

## Решение

Принимается **Вариант C**: явный вызов `audit_service.log(...)` в сервисном слое.

### AuditService

```python
# services/audit_service.py
class AuditService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def log(
        self,
        user_id: int | None,
        action: AuditAction,
        entity_type: str,
        entity_id: int | None,
        changes: dict | None,
        ip_address: str | None = None,
    ) -> None:
        entry = AuditLog(
            user_id=user_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            changes_json=changes,
            ip_address=ip_address,
        )
        self.session.add(entry)
        # flush без commit — в рамках транзакции вызывающего сервиса
        await self.session.flush()
```

`AuditService` создаётся в роутере вместе с основным сервисом и передаётся через конструктор (см. ADR-0004).

### Содержимое поля `changes_json`

| Операция | Формат `changes_json` |
|---|---|
| `create` | `{"after": <pydantic_read_schema_dict>}` |
| `update` | `{"before": <dict_before>, "after": <dict_after>, "diff": <changed_keys>}` |
| `soft_delete` | `{"before": <dict_before>}` |
| `login` | `null` |
| `access_denied` | `{"required_role": "...", "user_role": "..."}` |

**Правила маскировки секретов (MUST):**
- Поля `password_hash`, `password`, `token`, `secret`, `key` **никогда не попадают** в `changes_json`.
- Маскировка реализуется на уровне Pydantic Read-схем: схема `XxxRead` не включает эти поля по определению.
- При прямом формировании `dict` из ORM-модели (не через Pydantic) — явно исключать указанные поля через `AUDIT_EXCLUDED_FIELDS = frozenset({"password_hash", "password", "token"})`.
- Ревьюер проверяет отсутствие чувствительных полей в `changes_json` при ревью каждого батча.

### Передача `user_id` и `ip_address` в сервис

`user_id` — из `current_user.id` (Depends из ADR-0003).
`ip_address` — из `Request.client.host` (FastAPI `Request` объект).

Роутер передаёт оба значения при создании сервиса или как параметры метода:

```python
@router.post("/", response_model=ProjectRead, status_code=201)
async def create_project(
    data: ProjectCreate,
    request: Request,
    session: AsyncSession = Depends(get_session),
    current_user: User = Depends(require_role(UserRole.owner)),
):
    service = ProjectService(ProjectRepository(session), AuditService(session))
    return await service.create(data, actor_id=current_user.id, ip=request.client.host)
```

### Гарантия полноты (чек-лист ревьюера)

При ревью каждого батча ревьюер проверяет для каждого сервисного метода, изменяющего данные:

- [ ] Есть вызов `await self.audit.log(...)` после успешной операции.
- [ ] `action` соответствует типу операции (`create` / `update` / `delete`).
- [ ] `entity_type` — имя Python-класса модели (строка, например `"Project"`).
- [ ] `changes_json` не содержит полей из `AUDIT_EXCLUDED_FIELDS`.
- [ ] `user_id` передан (не None для аутентифицированных операций).

---

## Последствия

**Положительные:**
- Полный diff «до/после» в `changes_json` — восстановление истории любого объекта за O(1) запрос по `(entity_type, entity_id)`.
- Транзакционность: аудит и основное изменение — в одной транзакции. Нет «аудит есть, данных нет» и наоборот.
- Маскировка секретов — через Pydantic-схемы, а не через ручной парсинг.
- Тестируемость: `AuditService` можно подменить мок-объектом в unit-тестах сервиса.

**Отрицательные:**
- ~45 явных вызовов `audit.log()` — механическая, но обязательная работа.
- Субагент может ошибиться в `entity_type` (опечатка в строке) — нет compile-time проверки. Митигация: константы в `audit_constants.py`.

**Риски:**

| Риск | Митигация |
|---|---|
| Пропущенный вызов `audit.log()` в новом методе | Чек-лист ревьюера (см. выше); интеграционный тест `test_audit_coverage` — проверяет наличие записи в `audit_log` после каждой write-операции |
| Рост `audit_log` создаёт нагрузку на запись | Таблица append-only, индекс только на `(entity_type, entity_id, timestamp)`. При >1M строк — партиционирование по месяцу (Фаза 9) |
| `changes_json` хранит большие объекты (например, `BudgetPlan` с десятками колонок) | Ограничить глубину: хранить только изменённые поля (`"diff"` ключ), не весь объект |
| Секретное поле добавлено в модель и не включено в `AUDIT_EXCLUDED_FIELDS` | `AUDIT_EXCLUDED_FIELDS` проверяется в тесте `test_audit_no_secrets` — перечень полей сверяется с именами колонок моделей через SQLAlchemy inspection |

---

## Открытые вопросы

1. **`AUDIT_EXCLUDED_FIELDS` как централизованный реестр**: реализовать в `app/core/audit_constants.py`. Субагенты не должны вручную перечислять поля в каждом сервисе — только импортировать константу.
2. **Асинхронная запись аудита** (fire-and-forget через очередь): при нагрузке может потребоваться вынести запись в `audit_log` из основной транзакции в фоновую задачу (Celery / FastAPI BackgroundTasks). Откладывается до замера производительности по итогам Батча A (Риск R3 в `phase-3-scope.md`).
3. **`user_agent`**: поле есть в модели. В Фазе 3 — записывать из `Request.headers.get("user-agent")`. Не является ключевым, но полезно для диагностики подозрительной активности.
