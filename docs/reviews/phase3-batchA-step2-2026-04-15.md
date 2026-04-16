# Ревью: Фаза 3 Батч A Шаг 2 — Эталонный CRUD Project

**Дата**: 2026-04-15
**Ревьюер**: reviewer (субагент)
**Файлы (13)**:
- `backend/app/errors.py`
- `backend/app/pagination.py`
- `backend/app/main.py`
- `backend/app/schemas/project.py`
- `backend/app/repositories/__init__.py`
- `backend/app/repositories/base.py`
- `backend/app/repositories/project.py`
- `backend/app/services/__init__.py`
- `backend/app/services/audit.py`
- `backend/app/services/base.py`
- `backend/app/services/project.py`
- `backend/app/api/projects.py`
- `backend/tests/test_projects.py`

**ADR**: 0004, 0005, 0006, 0007
**Вердикт**: **REQUEST-CHANGES**

---

## P0 — BLOCKER (блокирует коммит)

### P0-1: Некорректный `total` при `is_archived=False` — пагинация врёт

**Файл**: `backend/app/services/project.py`, строки 81–85

**Код**:
```python
if is_archived is False:
    items = [p for p in items if p.status != "archived"]
    total = len(items)  # пересчитываем total после фильтрации
```

**Проблема**: `list_paginated` сначала выполняет `SELECT ... LIMIT limit OFFSET offset` на всей таблице без фильтра `status != 'archived'`, а затем Python постфильтром убирает archived-проекты из уже усечённого списка. Результат:
- Если на странице из 25 проектов оказалось 10 archived — Python вернёт 15 items.
- `total = len(items) = 15` — это количество на **текущей странице**, а не в БД.
- Клиент получает envelope `{items: [15 объектов], total: 15, offset: 0, limit: 25}` и думает, что всего 15 проектов. При offset=25 снова будет неверный total (другой slice).
- Правильный `total` должен отражать количество **всех** не-archived не-deleted проектов в БД независимо от пагинации.

**ADR 0006 нарушение**: MUST — конверт содержит `total` без учёта пагинации.

**Последствие для эталона**: этот паттерн разойдётся на 7 оставшихся сущностей и создаст системный дефект пагинации по всему батчу.

**Требуется**: добавить в `ProjectRepository` метод `list_paginated` с явным WHERE фильтром `status != 'archived'`, либо вынести фильтрацию `is_archived=False` в SQL через `NotIn`/`!=` в базовом `list_paginated`. Постобработку на Python убрать полностью.

---

### P0-2: Литеральный пароль в фикстурах тестов — нарушение регламента v1.3 §3

**Файл**: `backend/tests/test_projects.py`, строки 85, 100, 115, 130, 141, 154

**Код**:
```python
password_hash=hash_password("owner_pass_123"),
...
json={"email": "owner_projects@example.com", "password": "owner_pass_123"},
```

**Проблема**: Пароли вписаны литералом в код. Регламент v1.3 §3 явно запрещает это даже в тестах. В предыдущем раунде (Round 2, `R2-BLOCKER-1`) этот же дефект был пойман в `conftest.py` — разработчик повторил его здесь в другом файле.

**Дополнительно**: `TEST_DB_URL` строка 34 содержит пароль `change_me_please_to_strong_password` прямо в коде. Пусть это test-база, но реквизиты подключения не должны быть хардкодом.

**Требуется**:
- Пароли тестовых пользователей генерировать через `secrets.token_urlsafe(16)` или читать из `os.environ.setdefault(...)`.
- `TEST_DB_URL` читать из `os.environ.get("TEST_DATABASE_URL", "...")` — дефолт допустим как fallback для локальной среды, но пароль не должен быть осмысленным.

---

## P1 — MAJOR

### P1-1: Несоответствие ADR 0004 — директория `api/` вместо `routers/`

**Файл**: `backend/app/api/projects.py`; `backend/app/main.py` строка 17

**Проблема**: ADR 0004 явно фиксирует структуру `app/routers/`, `app/services/`, `app/repositories/`. Реализация использует `app/api/`. Отклонение незаявленное — разработчик не остановился и не запросил согласование (нарушение регламента v1.3 §2). Комментарий в `main.py` объясняет причину ("auth уже был в api/"), но это должно было пройти через ADR amendment до начала кодинга.

**Оценка отклонения**: само по себе косметическое (имя директории не влияет на поведение и безопасность). Опасно как процессный прецедент — если первый эталон отклоняется от ADR без amendment, следующие 7 сущностей будут отклоняться дальше, не зная правила.

**Требуется**: зафиксировать amendment в ADR 0004 в формате:
```markdown
## Amendments
- 2026-04-15: директория `app/routers/` → `app/api/`. Причина: Фаза 2 уже
  поместила auth-роутер в `app/api/`; унификация важнее буквального следования имени.
  Не влияет на безопасность и совместимость. Согласовано Координатором.
```
Без этой записи следующий субагент прочитает ADR и создаст `routers/`.

---

### P1-2: `validate_status()` — ручной метод вместо Pydantic-валидатора; двойное дублирование

**Файл**: `backend/app/schemas/project.py`, строки 52–61, 90–99

**Проблема**:
1. `validate_status()` — ручной метод, который разработчик вызывает явно в сервисе (`data.validate_status()`). Это не Pydantic-валидация: если разработчик следующей сущности забудет вызвать этот метод — невалидный статус пройдёт в БД. Pydantic предоставляет `@field_validator` и `Annotated[str, AfterValidator(...)]` именно для этого.
2. Метод продублирован в `ProjectCreate` и `ProjectUpdate` дословно — нарушение DRY.
3. `_ALLOWED_STATUSES` задан как `set[str]` вместо `Literal["active", "archived", "completed"]` — теряется статический анализ (mypy не поймает опечатку в статусе).

**Последствие для эталона**: если паттерн ручного `validate_status()` замёрзнет и разойдётся на 7 сущностей — получим 7 мест, где бизнес-валидация может быть случайно пропущена.

**Требуется**: заменить на `@field_validator("status", mode="before")` или `Literal` тип. Устранить дублирование между `ProjectCreate` и `ProjectUpdate` через общий mixin или базовый класс.

---

### P1-3: `403 Forbidden` от `require_role` не соответствует ADR 0005 — mixed форматы в тестах

**Файл**: `backend/app/api/projects.py`, строки 137, 185, 235; `backend/tests/test_projects.py`, строки 228–232

**Проблема**: `require_role` бросает `HTTPException(403)` — FastAPI вернёт `{"detail": "..."}`. `AppError`-хендлер этот путь не перехватывает (перехватывает только `AppError`). Значит 403 от RBAC и 403 от `PermissionDeniedError` приходят в разных форматах:
- RBAC: `{"detail": "Недостаточно прав для выполнения операции"}`
- Доменная: `{"error": {"code": "PERMISSION_DENIED", ...}}`

ADR 0005 требует единого формата для **всех** 4xx. Тест в строке 228–232 это осознаёт (`"detail" in body or "error" in body`) и тем самым подтверждает несоответствие — тест принимает оба варианта.

**ADR 0005, риски**: явно оговорено «`HTTPException` разрешён только в слое роутера для 401/403 от `require_role`», но это делает 403 вторым форматом. ADR 0005 должен содержать явную оговорку или `HTTPException(403)` должен переопределяться хендлером.

**Требуется**: добавить `@app.exception_handler(HTTPException)` в `main.py`, который для 403 тоже оборачивает в `{"error": {"code": "PERMISSION_DENIED", ...}}`. Тест обновить — убрать `"detail" in body or`, оставить только `"error" in body`.

---

## P2 — MINOR

### P2-1: `BaseService.get_or_404` возвращает `Any` вместо `ModelT`

**Файл**: `backend/app/services/base.py`, строка 33

**Код**:
```python
async def get_or_404(self, entity_id: int) -> Any:
```

**Проблема**: возвращаемый тип `Any` теряет статическую типизацию. Подкласс `ProjectService` вызывает `await self.get_or_404(project_id)` и получает `Any`, а не `Project`. Mypy не поймает, если кто-то обратится к несуществующему атрибуту на результате. Правильный тип — `ModelT`.

**Требуется**: изменить сигнатуру на `async def get_or_404(self, entity_id: int) -> ModelT:` с корректным `Generic[ModelT]`.

---

### P2-2: `ConflictError` и `DomainValidationError` переопределяют `code` через instance-атрибут с `# type: ignore`

**Файл**: `backend/app/errors.py`, строки 104–106, 124–126

**Код**:
```python
self.code = code  # type: ignore[assignment]
super().__init__(message)
```

**Проблема**: `code` объявлен как `class attribute: str = "CONFLICT"`, но в `__init__` затирается `instance attribute`. `# type: ignore` — сигнал, что тип системно нарушен. Правильный паттерн: объявить `code` как параметр `__init__` с дефолтом, а не class attribute. Или использовать `ClassVar`.

**Требуется**: рефакторинг иерархии ошибок — `code` передаётся в `AppError.__init__` как параметр с дефолтом класса:
```python
class AppError(Exception):
    def __init__(self, message: str, code: str | None = None, ...):
        self.code = code or self.__class__.code
```

---

### P2-3: `_make_service` в роутере — скрытое отклонение от ADR 0004 п.6

**Файл**: `backend/app/api/projects.py`, строки 33–42

**Код**:
```python
def _make_service(db: AsyncSession) -> ProjectService:
    return ProjectService(repo=ProjectRepository(db), audit=AuditService(db))
```

ADR 0004 п.6: «конструирование зависимостей — в теле endpoint-функции». Вынесение в хелпер `_make_service` — прямо противоречит записанному. Функционально идентично, но создаёт прецедент: следующие 7 сущностей скопируют паттерн. ADR нарушается.

Если решено выносить в хелпер (оправдано) — нужен amendment в ADR 0004.

---

### P2-4: Тест 403 не проверяет формат ошибки — только статус

**Файл**: `backend/tests/test_projects.py`, строки 237–247, 502–523, 626–650

**Проблема**: тесты на 403 (`test_create_project_accountant_returns_403`, `test_update_project_read_only_returns_403`, `test_delete_project_read_only_returns_403`) проверяют только `assert response.status_code == 403`, не проверяя тело. Мини-DoD требует `≥1 403 на каждый endpoint` — количество тестов выполнено, но качество недостаточно согласно чек-листу `phase-3-checklist.md`: «Формат ошибок соответствует ADR 0005».

**Требуется**: добавить в каждый 403-тест проверку `assert "error" in response.json()` (или `"detail"` после исправления P1-3).

---

### P2-5: Отсутствует тест на `is_archived=False` и корректность `total`

**Файл**: `backend/tests/test_projects.py`

**Проблема**: фильтр `is_archived` вообще не покрыт тестами (поиск по файлу вернул 0 совпадений). При этом P0-1 находится именно в этой ветке кода. Регрессию P0-1 нечем поймать автоматически.

**Требуется**: добавить минимум 3 теста:
- `is_archived=True` — возвращает только archived.
- `is_archived=False` — не возвращает archived, `total` корректен (>= len(items)).
- `is_archived=None` — возвращает все (дефолт).

---

### P2-6: `construction_manager` не покрыт RBAC-тестами

**Файл**: `backend/tests/test_projects.py`

**Проблема**: фикстуры для `construction_manager` отсутствуют. Матрица RBAC по чек-листу `phase-3-checklist.md` §5 требует «для каждого эндпоинта × 4 роли = явный тест-кейс». Роль `construction_manager` не протестирована ни на одном endpoint.

**Требуется**: добавить фикстуру `construction_manager_user`/`construction_manager_token` и тесты 403 для POST/PATCH/DELETE.

---

## P3 — NIT

### P3-1: `# type: ignore[attr-defined]` в `base.py` для `self.model.id`

**Файл**: `backend/app/repositories/base.py`, строка 90

```python
base_stmt = base_stmt.order_by(self.model.id.asc())  # type: ignore[attr-defined]
```

`Base` не гарантирует наличие `id`. Правильнее добавить `id: Mapped[int]` в базовый класс `Base` или ввести протокол `HasId`. `# type: ignore` скрывает типовую проблему вместо её решения.

---

### P3-2: `ListEnvelope[T]` использует синтаксис PEP 695 — требует Python 3.12+

**Файлы**: `backend/app/pagination.py` строка 48; `backend/app/repositories/base.py` строка 23; `backend/app/services/base.py` строка 18

```python
class ListEnvelope[T](BaseModel):  # PEP 695
class BaseRepository[ModelT: Base]:  # PEP 695
class BaseService[ModelT, RepoT: BaseRepository[Any]]:  # PEP 695
```

Синтаксис PEP 695 (`class Foo[T]`) доступен только начиная с Python 3.12. Если CI или production-образ работает на Python 3.11 — импорт упадёт с `SyntaxError`. В ADR 0002 минимальная версия Python не зафиксирована. Если проект официально на 3.12 — нарушений нет, но это стоит явно зафиксировать в ADR 0002.

---

### P3-3: `print()` в `seeds.py` — не входит в diff, но в пространстве кода

**Файл**: `backend/app/db/seeds.py`, строки 374, 376

`print()` вместо `logger.info()`. Не входит в staged diff — не блокирует, но при следующем коммите этого файла потребует исправления.

---

### P3-4: Нет теста на повторное создание с тем же кодом для soft-deleted проекта

**Файл**: `backend/tests/test_projects.py`

**Проблема**: `get_by_code` фильтрует `deleted_at IS NULL`. Если создать проект с `code="test"`, удалить его, потом снова создать с `code="test"` — второе создание пройдёт (soft-deleted не блокирует). Это допустимо, но не покрыто тестом. Чек-лист `phase-3-checklist.md` §4 упоминает: «Soft-deleted сущности нельзя случайно создать заново».

Поведение нужно явно определить и покрыть тестом в ту или иную сторону.

---

## Сводная таблица ADR-соответствия

| Требование ADR | Найдено? | Соответствует? | Примечание |
|---|---|---|---|
| ADR 0004: роутеры в `app/routers/` | Нет — в `app/api/` | Нет | P1-1, незаявленное отклонение |
| ADR 0004: SQLAlchemy только в `repositories/` | Да | Да | |
| ADR 0004: аудит в сервисном слое | Да | Да | |
| ADR 0004: DI в теле endpoint | Частично | Нет | P2-3, вынесено в `_make_service` |
| ADR 0005: единый формат ошибок | Частично | Нет | P1-3, 403 от `require_role` не в формате |
| ADR 0005: `VALIDATION_ERROR` из Pydantic | Да | Да | |
| ADR 0005: секреты не в 5xx | Да | Да | |
| ADR 0006: `limit` клиппится к 200 | Да | Да | |
| ADR 0006: `total` без учёта пагинации | Нет при `is_archived=False` | Нет | P0-1, BLOCKER |
| ADR 0006: конверт `{items, total, offset, limit}` | Да | Да | |
| ADR 0007: явный `audit.log()` в сервисе | Да | Да | |
| ADR 0007: аудит в одной транзакции | Да | Да | |
| ADR 0007: diff before/after | Да | Да | |
| ADR 0007: маскировка через Pydantic Read-схему | Да | Да | |
| Регламент v1.3 §3: нет литеральных секретов | Нет | Нет | P0-2, BLOCKER |

---

## OWASP-сверка (релевантные пункты)

| Пункт | Статус |
|---|---|
| A01 Broken Access Control: RBAC на write-эндпоинтах | Есть, но 403 формат смешан (P1-3) |
| A01 IDOR: нет подстановки чужого ID для чтения чужих данных | ОК — у Project нет владельца, читают все |
| A01 CORS с `allow_credentials=True` при не `["*"]` | ОК — origins ограничены dev-списком |
| A03 Injection: ORM без f-string | ОК |
| A05 Stack trace клиенту | ОК — `unhandled_error_handler` маскирует |
| A07 JWT_SECRET без дефолта | ОК — `...` (обязательный) |
| A09 Пароли в логах/коде | P0-2 — пароли в тестовом коде |

---

## Что сделано хорошо

1. **`BaseRepository`** переиспользуем и Generic: `get_by_id`, `list_paginated`, `create`, `update`, `soft_delete` — вся механика обобщена. Наследование однострочное.
2. **`AuditService`**: транзакционность через `flush()` без `commit()` — точно по ADR 0007. Санитизация через `_sanitize()` работает правильно.
3. **Формат ошибок**: `errors.py` — чистая иерархия, `to_response()` корректен. Pydantic-ошибки приводятся к ADR 0005 с `details`.
4. **Soft-delete**: `list_paginated` фильтрует `deleted_at IS NULL` через `hasattr` — переиспользуется без кода в подклассе. GET по id мягко удалённого → 404 через `get_or_404`.
5. **Аудит**: полный diff `{before, after, diff}` для update; `before` для delete; `after` для create — точно по ADR 0007.
6. **`ProjectRead` маскировка**: `_project_to_dict` через `ProjectRead.model_validate(project).model_dump(mode="json")` — нет ручного перечисления полей, маскировка автоматическая.
7. **Тесты аудита**: три отдельных теста проверяют наличие записи в `audit_log` после create/update/delete с assert на содержимое `changes_json` — это правильная практика.
8. **Swagger**: все endpoints имеют `summary`, `description`, `response_model`, примеры в полях схемы.

---

## Требуемые действия перед повторным ревью

| # | Приоритет | Файл | Действие |
|---|---|---|---|
| 1 | P0 | `services/project.py:81–85` | Перенести `is_archived=False` фильтр в SQL; убрать постобработку Python |
| 2 | P0 | `tests/test_projects.py:34,85,100,115` | Секреты через env/`secrets.token_urlsafe`; пароли не хардкодить |
| 3 | P1 | `docs/adr/0004-crud-layer-structure.md` | Amendment: `api/` вместо `routers/`, `_make_service` паттерн |
| 4 | P1 | `app/main.py` | Добавить `@app.exception_handler(HTTPException)` для единого формата 403 |
| 5 | P1 | `schemas/project.py` | Заменить ручной `validate_status()` на `@field_validator` или `Literal` |
| 6 | P2 | `services/base.py:33` | Исправить возвращаемый тип `get_or_404` с `Any` на `ModelT` |
| 7 | P2 | `errors.py:104,124` | Устранить `# type: ignore[assignment]` через рефакторинг иерархии |
| 8 | P2 | `tests/test_projects.py` | Добавить тесты `is_archived` (3 кейса) и `construction_manager` RBAC (3 кейса) |
| 9 | P2 | `tests/test_projects.py` | В 403-тестах добавить assert на тело ответа |

---

## Round 2

**Дата**: 2026-04-15
**Ревьюер**: reviewer (субагент)
**Вердикт**: **APPROVE**

---

### Итог проверки фиксов

#### P0-1 — ЗАКРЫТ

`services/project.py` строки 71–82: фильтрация перенесена полностью в SQL.

- `is_archived=True` → `filters={"status": "archived"}` — уходит в `base_stmt.where(col == "archived")`.
- `is_archived=False` → `extra_conditions=[Project.status != "archived"]` — уходит в `base_stmt.where(...)`.
- `total` считается через `SELECT COUNT(*) FROM (base_stmt с теми же WHERE).subquery()` — одинаковые условия для `COUNT` и для `SELECT`. Python-постобработки нет.

Механика `count_stmt = select(func.count()).select_from(base_stmt.subquery())` в `base.py` строка 91 — корректна: подзапрос наследует все WHERE-условия из `base_stmt`, включая `extra_conditions`. `total` будет одинаковым на любой странице при одинаковых фильтрах. ADR 0006 соблюдён.

#### P0-2 — ЗАКРЫТ (в `test_projects.py`, остаток в `test_auth.py` — вне скоупа)

`test_projects.py`: все четыре фикстуры (строки 89, 105, 121, 137) используют `secrets.token_urlsafe(16)`. Литеральных паролей нет. `TEST_DB_URL` читается из `os.environ.get("TEST_DATABASE_URL", "...")`, дефолтный пароль `change_me` — семантически нейтральный placeholder, не осмысленный секрет.

`test_auth.py` строки 44–46, 107, 122 — содержат литеральные пароли (`correct_password_123`, `accountant_password_123`, `strong_password_123` и т.д.) и жёстко прописан `TEST_DB_URL` с паролем `change_me_please_to_strong_password`. Этот файл относится к Фазе 2 и не входит в staged diff данного батча. Фиксировать в рамках текущего PR не требуется, однако при следующем коммите `test_auth.py` — P0 повторится. Добавляю как carry-over замечание (см. ниже).

#### P1-1 (ADR 0004 amendment `api/`) — ЗАКРЫТ

`docs/adr/0004-crud-layer-structure.md` содержит раздел `## Amendments` с двумя записями:
- Amendment про `api/` вместо `routers/` — содержательный: указана причина (Фаза 2 уже использовала `api/`), последствия, явное «не влияет на безопасность». Форма соответствует требованию adr-compliance-checker.
- Amendment про `_make_service` — содержательный: причина (5 идентичных блоков = источник ошибок), решение, применимость.

Оба amendment не требуют указания конкретного commit hash (hash появится только после коммита), однако дата зафиксирована. Принято.

#### P1-2 (validate_status) — ЗАКРЫТ

`schemas/project.py` строки 21–48: введён `_StatusValidatorMixin` с `@field_validator("status", mode="before", check_fields=False)`. Тип `ProjectStatus = Literal["active", "archived", "completed"]` обеспечивает статический анализ. Дублирования нет — mixin наследуется обоими классами. Pydantic гарантирует вызов валидатора при парсинге.

Одно уточнение (nit, не блокирует): валидатор проверяет `allowed = {"active", "archived", "completed"}` вручную, тогда как `Literal`-тип на поле уже выполняет эту проверку через Pydantic. Двойная проверка не вредит, но создаёт точку расхождения при будущем расширении списка статусов — придётся обновлять и `Literal`, и `allowed`. При следующем касании схемы рекомендуется убрать ручной `allowed`-сет и положиться только на `Literal`. Сейчас — nit, не блокирует.

#### P1-3 (единый формат 403) — ЗАКРЫТ

`main.py` строки 48–74: добавлен `@app.exception_handler(HTTPException)` с маппингом:
- 401 → `UNAUTHORIZED`
- 403 → `PERMISSION_DENIED`
- 404 → `NOT_FOUND`
- прочие → `HTTP_ERROR`

Все 403 из `require_role` теперь проходят через этот handler и возвращают `{"error": {"code": "PERMISSION_DENIED", ...}}`. Тесты `test_create_project_read_only_returns_403` (строка 276), `test_create_project_accountant_returns_403` (строка 295), `test_create_project_construction_manager_returns_403` (строка 313), а также аналогичные для PATCH/DELETE — все проверяют `assert "error" in body` и `assert body["error"]["code"] == "PERMISSION_DENIED"`. Формат единый.

#### P2-1 (тип get_or_404) — ЗАКРЫТ

`services/base.py` строка 33: сигнатура `async def get_or_404(self, entity_id: int) -> ModelT:`. Реализация использует `cast("ModelT", raw)` с поясняющим комментарием о ограничении mypy при PEP 695. Тип корректен.

#### P2-2 (type: ignore в errors.py) — ЗАКРЫТ

`errors.py` строки 57–80: `AppError.__init__` принимает `code: str | None = None` и сохраняет `self.code: str = code if code is not None else self.__class__.default_code`. `ConflictError` и `DomainValidationError` передают `code=code` через `super().__init__()` — никаких `# type: ignore`. Иерархия чистая.

#### P2-3 (amendment _make_service) — ЗАКРЫТ (см. P1-1 выше)

#### P2-4 (тело 403 в тестах) — ЗАКРЫТ

Все 403-тесты в `test_projects.py` проверяют `assert "error" in body` и `assert body["error"]["code"] == "PERMISSION_DENIED"`.

#### P2-5 (тесты is_archived) — ЗАКРЫТ

Добавлено три теста (строки 453–540):
- `test_list_projects_is_archived_false_excludes_archived` — проверяет отсутствие `archived` в статусах и корректность `total >= len(items)`.
- `test_list_projects_is_archived_true_returns_only_archived` — проверяет, что все возвращённые проекты имеют статус `archived`.
- `test_list_projects_is_archived_none_returns_all` — проверяет наличие обоих статусов при отсутствии фильтра.

#### P2-6 (construction_manager RBAC) — ЗАКРЫТ

Фикстуры `construction_manager_user` (строка 135) и `construction_manager_token` (строка 189) добавлены. Тесты для POST (строка 299), PATCH (строка 692) и DELETE (строка 850) — все три с проверкой тела ответа.

---

### Carry-over: замечания, не блокирующие текущий коммит

| # | Приоритет | Файл | Замечание |
|---|---|---|---|
| CO-1 | P1 | `backend/tests/test_auth.py:44–46, 107, 122, 137 и др.` | Литеральные пароли (`correct_password_123`, `strong_password_123` и т.д.) и жёсткий `TEST_DB_URL` с паролем. Фаза 2, вне diff. При следующем коммите `test_auth.py` — обязательный фикс до merge. |
| CO-2 | nit | `backend/app/schemas/project.py:43` | Ручной `allowed`-сет дублирует `Literal`. Убрать при следующем касании схемы. |
| CO-3 | nit | `backend/app/repositories/base.py:101` | `self.model.id.asc() # type: ignore[attr-defined]` — остаётся. Решается добавлением `id: Mapped[int]` в базовый `Base` или протоколом `HasId`. При следующем касании `base.py`. |

---

### Оценка паттерна для заморозки

`BaseRepository` и `BaseService` оценены как готовые к заморозке для 7 оставшихся сущностей:

- **Нет течи Project-специфики в базовые классы.** `BaseRepository` не знает про статусы, `BaseService` не знает про `code`. Вся специфика Project изолирована в `ProjectRepository.get_by_code()` и `ProjectService.create()`.
- **`extra_conditions: list[ColumnElement[bool]]`** — правильная точка расширения: позволяет передавать произвольные SQL-условия без изменения базового класса. Следующие сущности используют тот же механизм.
- **`entity_name: str = "Entity"`** в `BaseService` — шаблонное имя для ошибок корректно переопределяется в подклассах (`entity_name = "Project"`). Паттерн применим к любой сущности без изменений.

Единственный архитектурный момент: параметр `filters: dict[str, Any]` в `list_paginated` принимает `col_name → value` для фильтрации равенством. Для сущностей с enum-статусами (большинство из 15) этого достаточно. Для сущностей с диапазонами (даты, суммы) нужен `extra_conditions` — механизм уже есть.

---

### Резюме Round 2

Все 2 P0 и 5 P1/P2 закрыты реально, не формально. P0-1: фильтр переведён в SQL, `total` через `COUNT(subquery)` — корректен независимо от страницы. P0-2: пароли через `secrets.token_urlsafe` во всех фикстурах `test_projects.py`. Единый формат 403 обеспечен глобальным `HTTPException`-хендлером. ADR 0004 получил два содержательных amendment. Базовые классы чисты от Project-специфики. Carry-over P1 по `test_auth.py` — требует фикса при следующем коммите этого файла.
