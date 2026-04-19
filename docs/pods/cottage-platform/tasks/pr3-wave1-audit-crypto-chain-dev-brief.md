# Dev-бриф: PR #3 Волна 1 Foundation — Crypto Audit Chain + C-4 маскирование ПД

- **От:** backend-head
- **Кому:** backend-dev (назначен: backend-dev, основной исполнитель)
- **Дата:** 2026-04-18
- **Источник:** head-бриф backend-director `/root/coordinata56/docs/pods/cottage-platform/tasks/pr3-wave1-audit-crypto-chain.md`
- **Статус:** Активен. Блокер PR#2 снят — коммит `bfb7041` в main (2026-04-18).

---

## Обязательное чтение перед первой строкой кода

1. `/root/coordinata56/CLAUDE.md` — глобальные правила, особенно разделы «Данные/ПД», «Секреты и тесты», «API», «Код», «Git».
2. `/root/coordinata56/docs/agents/departments/backend.md` — правила отдела v1.3, чек-лист самопроверки (блок ADR-gate A.1–A.5).
3. `/root/coordinata56/docs/adr/0011-foundation-multi-company-rbac-audit.md` — **Часть 3 §3.1–3.3 полностью**. Формула хеша — канонична, любое отклонение — критический дефект.
4. `/root/coordinata56/docs/adr/0007-audit-log.md` — базовый контракт аудит-лога, расширяем его, не заменяем.
5. `/root/coordinata56/docs/adr/0013-migrations-evolution-contract.md` — expand/contract паттерн: `hash` nullable в этой миграции, NOT NULL — в отдельном PR после backfill.
6. `/root/coordinata56/docs/legal/m-os-1-1-foundation-legal-check.md` — раздел C-4 (штрафы по ФЗ-152 ст. 7).

**Кодовой контекст (читать прежде чем трогать файл):**
- `backend/app/models/audit.py` — текущая модель без крипто-полей, наш baseline для Блока 2.
- `backend/app/services/audit.py` — текущий `AuditService`, `AUDIT_EXCLUDED_FIELDS` (6 полей), `_sanitize` с 1-уровневой рекурсией. Baseline для Блока 2.
- `backend/app/repositories/base.py` — базовый паттерн репозитория. Образец для `AuditLogRepository`.
- `backend/app/repositories/project.py` — пример конкретного репозитория.
- `backend/app/api/deps.py` — `require_permission` уже добавлен в PR#2. Для `/verify` используем `require_permission(action="read", resource_type="audit")`.
- `backend/tools/lint_migrations.py` — прецедент расположения utility-скриптов.

---

## FILES_ALLOWED

Трогаешь строго этот список, ничего больше:

```
backend/alembic/versions/2026_04_18_XXXX_<rev>_audit_crypto_chain.py   (новая, 1 файл)
backend/app/models/audit.py                                              (расширение)
backend/app/services/audit.py                                            (расширение)
backend/app/repositories/audit.py                                        (новый)
backend/app/api/audit.py                                                 (новый)
backend/app/schemas/audit.py                                             (новый)
backend/app/main.py                                                      (только регистрация audit_router)
backend/app/api/deps.py                                                  (только если нужен get_audit_service — см. ниже)
backend/tools/audit_chain_backfill.py                                    (новый)
backend/tests/test_audit_hash.py                                         (новый)
backend/tests/test_audit_sanitize.py                                     (новый)
backend/tests/test_audit_verify_endpoint.py                              (новый)
backend/tests/test_audit_backfill.py                                     (новый)
backend/tests/test_audit_race_condition.py                               (новый, желательно)
backend/tests/test_audit_repository.py                                   (новый)
backend/tests/conftest.py                                                (только добавление фикстуры create_audit_log_entry)
```

## FILES_FORBIDDEN

Всё остальное. Критически важно:
- `backend/alembic/versions/2026_04_18_1200_ac27c3e125c8_rbac_v2_pd_consent.py` — **не трогать** ни при каких обстоятельствах.
- Любые ADR-файлы (`docs/adr/`).
- `backend/app/services/rbac.py`, `consent.py`, `role.py` и все сервисы PR#2.
- `backend/app/models/user.py`, `role.py`, `permission.py`, `pd_policy.py`.
- Любые pod-specific файлы (`project.py`, `contract.py`, `payment.py` и т.п.).
- `frontend/` — полностью.
- `backend/scripts/` — такой директории нет и не создаём.

---

## Жёсткие технические запреты

1. **Формула хеша — bit-exact по ADR 0011 §3.1.** Порядок полей: `prev_hash | entity_type | str(entity_id or "") | action.value | str(user_id or "") | timestamp.isoformat() | json.dumps(changes_json, sort_keys=True, ensure_ascii=False, separators=(",", ":"))`. Разделитель `"|"`. Малейшее отклонение — break-change цепочки.
2. **Сервис не делает SQL-запросы напрямую.** `_get_last_hash_locked` вызывает `audit_repo.get_last_hash_locked(exclude_id=...)`, репозиторий выполняет `SELECT ... FOR UPDATE`. Если напишешь `session.execute(select(...))` в сервисе — вернёт с request-changes.
3. **Retroactive masking запрещён.** Старые записи не трогаем. Prospective-only.
4. **Никаких литералов секретов.** Только `secrets.token_urlsafe(16)` и `os.environ.get(...)`.
5. **`# type: ignore` / `# noqa` только с комментарием-обоснованием.**
6. **Не коммитить** — работа сдаётся head'у, коммит делает Координатор после reviewer approve.

---

## Декомпозиция по блокам

### Блок 1. Миграция Alembic (expand)

**Файл:** `backend/alembic/versions/2026_04_18_XXXX_<rev>_audit_crypto_chain.py`

**down_revision:** `"ac27c3e125c8"` — строго так, это финальная миграция PR#2.

**Что добавляет в таблицу `audit_log`:**
1. Колонка `prev_hash VARCHAR(64) NULLABLE` — хеш предыдущей записи. NULL допустим для легаси-записей и для первой записи системы (в БД `prev_hash = None`, в хеш подставляется `GENESIS_HASH`).
2. Колонка `hash VARCHAR(64) NULLABLE` — **обязательно nullable в этой миграции**. Если сделаешь NOT NULL — `alembic upgrade head` упадёт на существующих записях. NOT NULL придёт отдельной contract-миграцией после backfill (не в этом PR).
3. Индекс `ix_audit_log_timestamp` на колонке `timestamp` соло — нужен для `/verify?from=...&to=...`.

**Downgrade:** `DROP INDEX ix_audit_log_timestamp`, `DROP COLUMN hash`, `DROP COLUMN prev_hash`. Round-trip обязан быть чистым.

**Никакого `op.execute` — только DDL.** Иначе линтер выдаст warning. Если вдруг понадобится — добавь `# migration-exception: op_execute — <обоснование>` строкой выше.

**Acceptance Блока 1:**
- `cd backend && python -m tools.lint_migrations alembic/versions/` — 0 ошибок, 0 warning.
- `alembic upgrade head && alembic downgrade -1 && alembic upgrade head` — чисто.
- `ruff check backend/alembic/` — 0 ошибок.

---

### Блок 2. ORM-модель `AuditLog` + сервис `AuditService`

**Чекпоинт 1 (критичный) — сдать head'у после завершения этого блока.**

#### 2.1. `backend/app/models/audit.py`

Добавить в класс `AuditLog`:

```python
prev_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
```

Добавить в `__table_args__` рядом с существующим индексом:

```python
Index("ix_audit_log_timestamp", "timestamp"),
```

Не трогать остальные поля, существующие индексы, docstring.

#### 2.2. `backend/app/services/audit.py`

**Добавить импорты на уровне модуля:**

```python
import hashlib
import json
from datetime import datetime
```

**Добавить константы на уровне модуля:**

```python
GENESIS_HASH: str = hashlib.sha256(b"genesis").hexdigest()
# Вычисляется один раз при импорте модуля.
```

**Расширить `AUDIT_EXCLUDED_FIELDS`** — заменить текущее определение:

```python
AUDIT_EXCLUDED_FIELDS: frozenset[str] = frozenset({
    # секреты (ADR 0007):
    "password_hash", "password", "token", "secret", "key", "jwt",
    # ПД (C-4, ФЗ-152 ст. 7):
    "full_name", "email", "phone", "passport_number", "passport",
    "pd_consent_version", "pd_consent_at",
})
```

**Заменить `_sanitize`** — текущая версия маскирует только 1-й уровень. Новая версия — рекурсивная:

```python
def _sanitize(data: Any) -> Any:
    """Рекурсивно удаляет ПД и секреты из changes_json (C-4, ADR 0007).

    Обрабатывает три случая:
    1. dict — удаляет ключи из AUDIT_EXCLUDED_FIELDS, рекурсивно обходит значения.
    2. list — рекурсивно обходит элементы.
    3. dict с ключом "field" в diff-формате {"field": X, "from": ..., "to": ...}:
       если field ∈ AUDIT_EXCLUDED_FIELDS — маскирует "from"/"to" → "***".
    4. Всё остальное — возвращает as-is.
    """
    if isinstance(data, dict):
        # Специальный случай: diff-элемент {"field": "email", "from": ..., "to": ...}
        if "field" in data and data.get("field") in AUDIT_EXCLUDED_FIELDS:
            result = {k: v for k, v in data.items() if k not in AUDIT_EXCLUDED_FIELDS}
            result["from"] = "***"
            result["to"] = "***"
            return result
        return {
            k: _sanitize(v)
            for k, v in data.items()
            if k not in AUDIT_EXCLUDED_FIELDS
        }
    if isinstance(data, list):
        return [_sanitize(item) for item in data]
    return data
```

**Добавить в `AuditService` приватный метод `_compute_hash`** — pure function (без SQL):

```python
@staticmethod
def _compute_hash(prev_hash: str, entry: "AuditLog") -> str:
    """Вычисляет SHA-256 хеш записи аудита строго по ADR 0011 §3.1.

    Формула канонична. Менять порядок полей или разделитель запрещено —
    это break-change всей крипто-цепочки.

    Args:
        prev_hash: хеш предыдущей записи (GENESIS_HASH для первой).
        entry: запись аудита с заполненными полями (после flush).

    Returns:
        Hex-digest SHA-256 (64 символа).
    """
    payload = "|".join([
        prev_hash,
        entry.entity_type,
        str(entry.entity_id or ""),
        entry.action.value,
        str(entry.user_id or ""),
        entry.timestamp.isoformat(),
        json.dumps(
            entry.changes_json,
            sort_keys=True,
            ensure_ascii=False,
            separators=(",", ":"),
        ),
    ])
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()
```

**Добавить зависимость от репозитория в `AuditService.__init__`:**

```python
from app.repositories.audit import AuditLogRepository

class AuditService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self._audit_repo = AuditLogRepository(session)
```

**Добавить приватный метод `_get_last_hash_locked`:**

```python
async def _get_last_hash_locked(self, exclude_id: int) -> str:
    """Возвращает hash последней записи audit_log с FOR UPDATE.

    Блокирует строку для сериализации конкурентных INSERT (ADR 0011 §3.1,
    FIND-02 OWASP). Исключает только что добавленную запись (exclude_id).

    Args:
        exclude_id: id новой записи, которую нужно исключить из поиска.

    Returns:
        hash последней записи или GENESIS_HASH если таблица пуста.
    """
    last_hash = await self._audit_repo.get_last_hash_locked(exclude_id=exclude_id)
    return last_hash if last_hash is not None else GENESIS_HASH
```

**Расширить метод `log()`** — текущий порядок: `session.add(entry)` → `await session.flush()`. Новый порядок после flush:

```python
# После существующего flush:
# 1. Получаем id и timestamp из БД (они заполнились после flush).
# 2. Берём hash предыдущей записи с FOR UPDATE (исключая только что добавленную).
prev_hash = await self._get_last_hash_locked(exclude_id=entry.id)
# 3. Вычисляем hash текущей записи.
computed_hash = self._compute_hash(prev_hash, entry)
# 4. Записываем в объект.
entry.prev_hash = prev_hash if prev_hash != GENESIS_HASH else None
entry.hash = computed_hash
# 5. Второй flush для сохранения prev_hash/hash.
await self.session.flush()
```

**Важный нюанс контракта первой записи:** в БД `prev_hash = None` (первая запись), но в формулу хеша подставляется `GENESIS_HASH`. Это соответствует ADR 0011 §3.1. `_get_last_hash_locked` возвращает `GENESIS_HASH` при пустой таблице → `entry.prev_hash = None` (не записываем GENESIS_HASH в БД).

**Все операции — в рамках одной транзакции**, flush без commit. Сервис не вызывает `commit()`.

**Acceptance Блока 2:**
- `ruff check backend/app/services/audit.py backend/app/models/audit.py` — 0 ошибок.
- Формула хеша bit-exact соответствует ADR 0011 §3.1 (тест `test_audit_hash.py` проверит).
- Глубокая маскировка работает на diff-формате и вложенных dict/list (тест `test_audit_sanitize.py`).
- **Сдать head'у на Чекпоинт 1.**

---

### Блок 3. Репозиторий `AuditLogRepository`

**Файл:** `backend/app/repositories/audit.py` (новый)

**Класс:** `AuditLogRepository(BaseRepository[AuditLog])`

Реализовать четыре метода:

**1. `get_last_hash_locked`:**

```python
async def get_last_hash_locked(self, exclude_id: int | None = None) -> str | None:
    """Возвращает hash последней записи с блокировкой FOR UPDATE.

    Блокировка закрывает race condition при конкурентных INSERT (ADR 0011 §3.1).
    Вызов обязан быть внутри активной транзакции — иначе FOR UPDATE бессмысленно.

    Args:
        exclude_id: id записи, которую нужно исключить (только что вставленная).

    Returns:
        hash строки или None если таблица пуста / все строки исключены.
    """
    # SELECT hash FROM audit_log WHERE (id != :exclude_id) ORDER BY id DESC LIMIT 1 FOR UPDATE
```

Используй `sqlalchemy.dialects.postgresql` или конструкцию `.with_for_update()` в запросе. Передавать сырой SQL не нужно — `select(...).where(...).order_by(...).limit(1).with_for_update()` достаточно.

**2. `list_by_period`:**

```python
async def list_by_period(self, from_ts: datetime, to_ts: datetime) -> list[AuditLog]:
    """Возвращает все записи за период упорядоченно по id ASC.

    Без пагинации: для /verify нужны все записи периода.
    Лимит периода — ответственность эндпоинта (90 дней), не репозитория.

    Args:
        from_ts: начало периода (включительно).
        to_ts: конец периода (включительно).
    """
    # SELECT * FROM audit_log WHERE timestamp >= :from_ts AND timestamp <= :to_ts ORDER BY id ASC
```

**3. `get_last_before`:**

```python
async def get_last_before(self, record_id: int) -> str | None:
    """Возвращает hash последней записи строго до заданного id.

    Нужен для корректной верификации начала периода: первая запись периода
    ссылается на запись вне периода.

    Args:
        record_id: id первой записи периода.

    Returns:
        hash предшествующей записи или None если это первая запись системы.
    """
    # SELECT hash FROM audit_log WHERE id < :record_id ORDER BY id DESC LIMIT 1
```

**4. `iter_all_ordered`:**

```python
async def iter_all_ordered(self, batch_size: int = 1000) -> AsyncIterator[AuditLog]:
    """Курсорный обход всех записей в порядке возрастания id.

    Использует yield_per для экономии памяти при backfill больших таблиц.
    Не загружает всю таблицу в память сразу.

    Args:
        batch_size: размер буфера SQLAlchemy yield_per.
    """
    # stream + yield_per(batch_size) паттерн SQLAlchemy 2.0
```

**Acceptance Блока 3:**
- `ruff check backend/app/repositories/audit.py` — 0 ошибок.
- Unit-тесты в `test_audit_repository.py` — минимум: get_last_hash_locked возвращает None на пустой таблице; возвращает hash последней записи; exclude_id работает; list_by_period возвращает только записи в периоде.

---

### Блок 4. Endpoint `GET /api/v1/audit/verify`

**Чекпоинт 2 — сдать head'у после этого блока.**

**Файл 1:** `backend/app/schemas/audit.py` (новый)

Pydantic-схемы:

```python
class BrokenLink(BaseModel):
    audit_log_id: int
    reason: Literal["hash_mismatch", "prev_hash_mismatch"]

class PeriodBounds(BaseModel):
    from_ts: datetime
    to_ts: datetime

    model_config = ConfigDict(populate_by_name=True)

class AuditVerifyResponse(BaseModel):
    status: Literal["ok", "broken"]
    checked: int
    broken_links: list[BrokenLink]
    period: PeriodBounds
```

Формат ошибок — ADR 0005 `{error: {code, message, details}}`. Используй глобальный handler, не пиши своих exception_handler.

**Файл 2:** `backend/app/api/audit.py` (новый)

```python
router = APIRouter(prefix="/audit", tags=["audit"])

@router.get(
    "/verify",
    response_model=AuditVerifyResponse,
    summary="...",
    description="...",
    responses={403: ..., 422: ...},
)
async def verify_audit_chain(
    from_ts: datetime = Query(..., alias="from"),
    to_ts: datetime = Query(..., alias="to"),
    pair: tuple[User, UserContext] = Depends(require_permission("read", "audit")),
    db: AsyncSession = Depends(get_db),
) -> AuditVerifyResponse:
    ...
```

Бизнес-логика — не в роутере, а в `AuditService.verify_chain(from_ts, to_ts)`. Роутер: парсинг query → вызов → формирование envelope.

**Метод `AuditService.verify_chain`** (добавить в `audit.py`):

Логика:
1. Валидация: `to_ts > from_ts`, иначе 422. `to_ts - from_ts <= timedelta(days=90)`, иначе 422.
2. Загружает записи через `self._audit_repo.list_by_period(from_ts, to_ts)`.
3. Если пусто — возвращает `status="ok", checked=0, broken_links=[]`.
4. Для первой записи периода: `prev_hash_effective = await self._audit_repo.get_last_before(records[0].id)` → если None, то `GENESIS_HASH`; иначе значение из БД.
5. Для каждой записи:
   - `expected_hash = self._compute_hash(prev_hash_effective, record)`.
   - Если `record.hash != expected_hash` → broken_links += `{audit_log_id: record.id, reason: "hash_mismatch"}`.
   - Если `record.prev_hash != prev_hash_effective` (и `record.prev_hash` не None) → broken_links += `{..., reason: "prev_hash_mismatch"}`.
   - `prev_hash_effective = record.hash` (движемся вперёд по цепочке).
6. Возвращает `status="broken"` если broken_links непустой, иначе `status="ok"`.

**Регистрация в `backend/app/main.py`** — добавить после существующих роутеров:

```python
from app.api.audit import router as audit_router
app.include_router(audit_router, prefix="/api/v1")
```

**Зависимость `get_audit_service`** — добавить в `backend/app/api/deps.py`:

```python
def get_audit_service(db: AsyncSession = Depends(get_db)) -> AuditService:
    """Фабрика зависимости AuditService."""
    return AuditService(db)
```

**Acceptance Блока 4:**
- Swagger `/docs` рендерится, `/api/v1/audit/verify` виден с `summary`, `description`, `response_model`.
- `ruff check backend/app/api/audit.py backend/app/schemas/audit.py` — 0 ошибок.
- **Сдать head'у на Чекпоинт 2.**

---

### Блок 5. Backfill-скрипт

**Файл:** `backend/tools/audit_chain_backfill.py` (новый)

**Docstring обязателен в начале файла:**

```
Backfill-скрипт для заполнения prev_hash/hash в существующих записях audit_log.

ADR 0011 §3.3. Запускается однократно после apply миграции Блока 1,
до открытия трафика. Идемпотентен: пропускает записи с hash IS NOT NULL.

Расположение скорректировано относительно ADR 0011 §3.3 — используем
backend/tools/ как единый каталог утилит (прецедент: tools/lint_migrations.py).
```

**CLI-аргументы через `argparse`:**
- `--dry-run` — вывод плана без записи в БД.
- `--batch-size` (default=1000) — размер пакета для промежуточного flush.
- `--continue-on-error` — при ошибке вычисления логировать и продолжать.

**Логика:**
1. Читает `DATABASE_URL` из переменных окружения (`os.environ.get("DATABASE_URL")` или стандартный `settings`).
2. Создаёт AsyncSession через `get_async_session`.
3. В одной транзакции (`BEGIN`): итерирует через `audit_repo.iter_all_ordered(batch_size)`.
4. Для каждой записи: если `record.hash IS NOT NULL` — пропустить (идемпотентность).
5. Иначе: `prev_hash = GENESIS_HASH если первая; иначе prev_hash = предыдущая.hash` — цепочка строится **в памяти**, без SELECT на каждую запись.
6. `computed = AuditService._compute_hash(prev_hash, record)`.
7. `record.prev_hash = prev_hash if prev_hash != GENESIS_HASH else None`.
8. `record.hash = computed`.
9. После каждых `batch_size` записей — `await session.flush()`.
10. В конце: если `--dry-run` → rollback; иначе → commit.
11. Stdout: `processed=X, skipped=Y, errors=Z`.

**Примечание:** `AuditService._compute_hash` объявлен как `@staticmethod` — вызывай его напрямую `AuditService._compute_hash(prev_hash, record)` без создания экземпляра сервиса.

**Acceptance Блока 5:**
- `ruff check backend/tools/audit_chain_backfill.py` — 0 ошибок.
- Скрипт идемпотентен: повторный запуск выдаёт `processed=0, skipped=N`.
- `--dry-run` не делает commit.

---

### Блок 6. Тесты

**Чекпоинт 3 (финал) — сдать head'у после всех тестов зелёных.**

#### `backend/tests/test_audit_hash.py`

5 тестов формулы и цепочки:

1. **test_genesis_hash** — `GENESIS_HASH == hashlib.sha256(b"genesis").hexdigest()`. Проверяет константу перед написанием теста вычисли точное значение в Python.
2. **test_compute_hash_deterministic** — два вызова с одинаковым `(prev_hash, entry)` дают одинаковый hash.
3. **test_compute_hash_breaks_on_changes** — изменение любого поля `changes_json` меняет hash.
4. **test_chain_sequence** — 3 записи подряд: `record2.prev_hash == record1.hash`, `record3.prev_hash == record2.hash`.
5. **test_first_record_prev_hash_is_none** — первая запись имеет `prev_hash == None` в БД (но hash вычисляется с `GENESIS_HASH`).

#### `backend/tests/test_audit_sanitize.py`

6 тестов маскирования C-4:

1. **test_top_level_pd_masked** — `{"email": "a@b.c", "project_id": 1}` → `{"project_id": 1}`.
2. **test_nested_dict_pd_masked** — `{"before": {"full_name": "Иванов", "id": 1}}` → `{"before": {"id": 1}}`.
3. **test_diff_format_pd_masked** — `{"diff": [{"field": "email", "from": "a@b", "to": "c@d"}, {"field": "name", "from": "X", "to": "Y"}]}` → email-элемент: `from="***"`, `to="***"`; name-элемент нетронут.
4. **test_list_of_dicts_sanitized** — `{"history": [{"email": "a@b"}, {"email": "c@d"}]}` → `{"history": [{}, {}]}`.
5. **test_secrets_still_masked** — `password_hash` и `token` всё ещё удаляются (регрессия ADR 0007).
6. **test_non_pd_fields_preserved** — `project_name`, `amount_cents`, `company_id` остаются.

#### `backend/tests/test_audit_repository.py`

Unit-тесты репозитория:
- `get_last_hash_locked` возвращает None на пустой таблице.
- `get_last_hash_locked` возвращает hash последней записи.
- `exclude_id` корректно исключает запись.
- `list_by_period` возвращает только записи в диапазоне.
- `get_last_before` возвращает None для первой записи.

#### `backend/tests/test_audit_verify_endpoint.py`

7 тестов endpoint'а:

1. **test_verify_empty_period** — 200, `status="ok"`, `checked=0`.
2. **test_verify_valid_chain** — 10 записей, `status="ok"`.
3. **test_verify_broken_hash** — ручной UPDATE `hash='tampered'` на записи в середине → `status="broken"`, `broken_links` содержит эту запись, `reason="hash_mismatch"`.
4. **test_verify_broken_prev_hash** — ручной UPDATE `prev_hash='wrong'` → `reason="prev_hash_mismatch"`.
5. **test_verify_rbac** — пользователь без `audit.read` → 403.
6. **test_verify_period_limit** — `to - from > 90 дней` → 422.
7. **test_verify_first_record_uses_predecessor** — верификация периода с записи id=5 корректно использует hash записи id=4 как `prev_hash_effective`.

#### `backend/tests/test_audit_backfill.py`

- Создать ≥10 записей без `hash`.
- Запустить backfill программно.
- Проверить: все записи получили hash, первая — `prev_hash=None`, каждая следующая — `prev_hash == предыдущая.hash`, hash воспроизводится повторным вычислением.
- Повторный запуск идемпотентен: `processed=0, skipped=N`.
- `--dry-run` не меняет БД.

#### `backend/tests/test_audit_race_condition.py` (желательно)

Две параллельные async-транзакции вызывают `AuditService.log()`. Проверить, что `FOR UPDATE` сериализует: обе записи получают корректные `prev_hash`. Если в `conftest.py` нет postgres test container (только SQLite) — тест помечается `@pytest.mark.skipif(not HAS_POSTGRES, ...)`. Уточни у head'а перед написанием.

#### Фикстура в `conftest.py`

Добавить (только если ещё нет):

```python
async def create_audit_log_entry(
    db: AsyncSession,
    action: AuditAction,
    entity_type: str,
    entity_id: int,
    user_id: int | None = None,
    changes: dict | None = None,
) -> AuditLog:
    """Создаёт запись audit_log через AuditService.log() — для тестов."""
    audit = AuditService(db)
    await audit.log(
        user_id=user_id,
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        changes=changes,
    )
    # После flush в той же сессии — последняя запись доступна через репозиторий.
    ...
```

**Acceptance Блока 6:**
- `pytest backend/tests -q` — зелёный (новые 6 файлов + все 351+ существующих тестов).
- `ruff check backend/app backend/tests backend/tools` — 0 ошибок.
- Покрытие новых модулей ≥ 85%.
- **Сдать head'у на Чекпоинт 3 (финал).**

---

## DoD (определение готовности)

Работа считается готовой к сдаче head'у, когда:

- [ ] Все 6 блоков реализованы.
- [ ] Миграция проходит линтер: `python -m tools.lint_migrations alembic/versions/` — 0 ошибок, 0 warning.
- [ ] Round-trip чист: `alembic upgrade head && alembic downgrade -1 && alembic upgrade head`.
- [ ] `pytest backend/tests -q` — зелёный, включая 351+ тестов PR#1 и PR#2.
- [ ] `ruff check backend/app backend/tests backend/tools` — 0 ошибок.
- [ ] Swagger `/docs` рендерится, `/api/v1/audit/verify` виден с `summary`/`description`/`response_model`.
- [ ] Никаких секретов-литералов в коде и тестах.
- [ ] Крипто-acceptance:
  - [ ] Формула хеша bit-exact по ADR 0011 §3.1.
  - [ ] `FOR UPDATE` берётся в репозитории (не в сервисе).
  - [ ] `/verify` обнаруживает tampered запись при ручном UPDATE.
  - [ ] Первая запись периода корректно использует `prev_hash` предыдущей записи.
- [ ] C-4 acceptance:
  - [ ] `AUDIT_EXCLUDED_FIELDS` содержит 6 секретов + 7 ПД-полей = 13 итого.
  - [ ] Глубокая рекурсивная маскировка работает на diff-формате и вложенных dict/list.
  - [ ] Существующие секреты из ADR 0007 всё ещё маскируются.
- [ ] Backfill-acceptance:
  - [ ] Скрипт идемпотентен.
  - [ ] `--dry-run` не пишет в БД.
- [ ] Чек-лист ADR-gate A.1–A.5 пройден явно (с артефактами).
- [ ] `git status` показывает только файлы из FILES_ALLOWED.

---

## Чекпоинты для head'а

| Чекпоинт | После блока | Что проверяет head |
|---|---|---|
| **CP-1 (критичный)** | Блок 2 | Формула хеша bit-exact ADR 0011 §3.1. FOR UPDATE через репозиторий. Маскирование ПД рекурсивное. Контракт первой записи (prev_hash=None в БД). |
| **CP-2** | Блок 4 | Endpoint зарегистрирован. Swagger рендерится. Логика verify_chain через сервис, не в роутере. 422 на период >90 дней. |
| **CP-3 (финал)** | Блок 6 | 6 тестовых файлов зелёные. 351+ регрессионных зелёные. Покрытие ≥85%. Smoke-тест /verify через curl. |

---

## Open items — уточни у head'а до начала кода

1. **Тест race condition (Блок 6, `test_audit_race_condition.py`):** есть ли в проекте postgres test container в `conftest.py`? Сообщи head'у результат проверки — от этого зависит, пишем тест с `@pytest.mark.skipif` или полноценно.

2. **Формат diff-элементов в `changes_json`:** Директор описал гипотетический формат `{"field": "email", "from": ..., "to": ...}`. Проверь фактический формат в `backend/app/services/contract.py`, `payment.py`, `consent.py` — именно там audit.log() вызывается с diff. Если формат другой или неконсистентный — сообщи head'у **до** реализации маскирования.

3. **Итоговый счёт полей в `AUDIT_EXCLUDED_FIELDS`:** текущая версия в сервисе содержит 6 полей. Dev-бриф добавляет 7 ПД-полей — итого 13. Убедись что при слиянии не теряешь существующие 6.

4. **Контракт `iter_all_ordered`:** возвращает `AsyncIterator[AuditLog]` через `yield_per` — убедись, что SQLAlchemy 2.0 stream + yield_per корректно работает в вашем async setup (проверь, как session создаётся в `db/session.py`).

---

## Напоминание об эскалации

Если в ходе работы обнаружишь:
- Неоднозначность в ADR 0011 §3 — **остановись**, сообщи head'у, не интерпретируй самостоятельно.
- Формат `changes_json` в существующих сервисах не соответствует описанному — сообщи head'у (это P1, не правишь сам).
- Любое решение, не покрытое этим брифом — сообщи head'у перед реализацией.

Вопросы других отделов — только через head'а. Не общаешься с db-head, qa-head, frontend-dev напрямую.

---

*Dev-бриф составлен backend-head 2026-04-18. Исполнитель — backend-dev. Источник — head-бриф backend-director (14 разделов). Чекпоинты: CP-1 после Блока 2, CP-2 после Блока 4, CP-3 финал после Блока 6.*
