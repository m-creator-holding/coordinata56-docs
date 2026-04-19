# Бриф backend-head: PR #3 Волны 1 Foundation — Crypto Audit Chain + C-4 маскирование ПД в audit_log

- **От:** backend-director
- **Кому:** backend-head
- **Дата:** 2026-04-18
- **Тип задачи:** L-уровень (декомпозиция + распределение на ≥1 backend-dev, возможна отдельная задача для backfill-скрипта)
- **Паттерн:** Координатор-транспорт v1.6 (CLAUDE.md проекта §«Pod-архитектура»)
- **Код Директор не пишет.** Head разбивает 6 блоков скоупа на задачи backend-dev, собирает PR, проводит ревью уровня файлов, возвращает Директору на приёмку.
- **Статус брифа:** согласован с Координатором 2026-04-18 (ответы на §7 вопросы получены). Активация — после мержа PR #2 в `main`.
- **Критичность:** **PR #3 — финальный security-блокер production gate по целостности аудита (ADR 0011 Часть 3) + legal-блокер C-4 (ФЗ-152 ст. 7 — маскирование ПД в журнале).** Без крипто-цепочки журнал аудита не имеет юридического веса; без маскирования ПД в `changes_json` — штраф до 700 тыс ₽ по КоАП 13.11.

---

## 0. Блокер-зависимость от PR #2 (важно прочитать первым)

**PR #3 не стартует, пока PR #2 не смержен в `main`.** Причины:

1. Файл миграции PR #2 уже существует: `backend/alembic/versions/2026_04_18_1200_ac27c3e125c8_rbac_v2_pd_consent.py`. **Down-revision миграции PR #3 = `ac27c3e125c8`** — это строгое requirement, менять нельзя.
2. `consent_service.accept()` в PR #2 пишет в `audit_log` через `audit_service.log()` — **эта запись должна уже проходить по новой крипто-цепочке в момент мержа PR #3**. Обратное ломает цепочку: часть записей pre-hash, часть post-hash, backfill их «сошьёт», но только если порядок деплоя верный.
3. `/api/v1/audit/verify` требует права `audit.read` — оно уже засидено в PR #2 (`permissions.csv` строка 272–273). Пере-seed в PR #3 не нужен.

**Head может начинать подготовку сейчас:** читать источники, декомпозировать в задачи backend-dev, уточнять вопросы через Координатора. Но `Agent`-вызов backend-dev на имплементацию — только после сигнала Координатора «PR #2 смержен».

Координатор уведомит Директора → Директор активирует Head → Head запустит backend-dev.

---

## 1. Цель PR

Одним PR закрыть **два взаимосвязанных блока**, делающих audit_log юридически значимым и соответствующим ФЗ-152:

1. **Crypto Audit Chain — реализация ADR 0011 Часть 3.** Поля `prev_hash: str(64) | None` и `hash: str(64) NOT NULL` в `audit_log`; SHA-256 цепочка с хешированием предыдущей записи; `SELECT ... FOR UPDATE` на последнюю строку при INSERT (race-safety); endpoint `GET /api/v1/audit/verify?from=<ISO>&to=<ISO>` для верификации целостности; одноразовый backfill-скрипт для существующих записей.
2. **C-4 маскирование ПД в `changes_json` (ФЗ-152 ст. 7 ред. 24.06.2025, legal-check C-4).** Расширение `AUDIT_EXCLUDED_FIELDS` в `app/services/audit.py` набором ПД-полей (`full_name`, `email`, `phone`, `passport_number`, `pd_consent_version` — см. §3.2); глубокая рекурсивная санитизация `changes_json` (сейчас только 1-уровневые dict'ы); prospective-only — **старые записи не трогаем**, technical debt фиксируется в отчёте.

Два блока идут одним PR, а не двумя:
- обе истории меняют контракт `AuditService.log()` и формат `changes_json` (одна серия тестов, одна финальная версия сервиса);
- крипто-цепочка хеширует `changes_json` как часть payload — если маскирование ПД прилетит позже отдельным PR, хеши пересчитаются и цепочка порвётся;
- разделение удвоило бы цикл миграций и ревью без выигрыша.

**После PR #3 пойдут:**
- PR #4 (ADR 0014 каркас ACL): после PR #3 в том же Спринте Foundation.
- Regression-sweep (задача 11 из черновика) — отдельный трек после PR #4, **не в PR #3**. Решение Координатора 2026-04-18.

---

## 2. Решения Координатора (зафиксированы 2026-04-18)

Эти ответы на вопросы §7 оригинального черновика — **обязательны к исполнению**:

1. **Скоуп PR #3 = crypto chain + C-4 маскирование ПД.** Не общий security-audit. Соответствует ADR 0011 Часть 3 и C-4 legal.
2. **Retroactive masking старых записей — НЕТ.** Принимаем prospective-only. Старые `changes_json` остаются как есть. **Tech-debt фиксируется в разделе §10 отчёта Head'а Директору.** Причина: ст. 22 ФЗ-152 требует неизменяемости аудита; одноразовая фиксация «до PR #3 ПД сохранялись в `changes_json`» — меньший риск, чем модификация исторических записей.
3. **Regression-sweep (автопроверка, что все сервисы вызывают `audit_service.log()` + что все Read-схемы не возвращают ПД не-владельцам) — откладываем.** Будет отдельным треком через quality-director после PR #4.
4. **Backfill-скрипт — `backend/tools/audit_chain_backfill.py`** (не `backend/scripts/`). Упомянут `scripts/` в ADR 0011 §3.3 — **это не блокирует отклонение**, потому что в проекте нет каталога `backend/scripts/`, все tools живут в `backend/tools/` (`lint_migrations.py` как прецедент). Упомянуть в docstring скрипта: «Расположение скорректировано относительно ADR 0011 §3.3 — используем `backend/tools/` как единый каталог утилит (прецедент: `tools/lint_migrations.py`).»

---

## 3. Источники (обязательно прочесть исполнителю)

**Проектные правила:**
1. `/root/coordinata56/CLAUDE.md` — особенно разделы «Данные и БД», «Секреты и тесты», «API», «Код», «Git».
2. `/root/coordinata56/docs/agents/departments/backend.md` — правила отдела, чек-лист самопроверки, правило 1 «Слои строго по ADR 0004» (Amendment 2026-04-18 о типизированных предикатах `ColumnElement[bool]`), правила миграций (ADR 0013).

**Нормативные:**
3. `/root/coordinata56/docs/adr/0011-foundation-multi-company-rbac-audit.md` — **Часть 3 §3.1–3.3 полностью** (формула хеша, endpoint /verify, backfill). Отдельно §«Отрицательные последствия» про `SELECT FOR UPDATE`.
4. `/root/coordinata56/docs/adr/0007-audit-log.md` — базовый контракт аудит-лога; правила маскировки секретов (ADR 0007 расширяется, не заменяется).
5. `/root/coordinata56/docs/adr/0013-migrations-evolution-contract.md` — expand-pattern; в PR #3 важно: `prev_hash/hash` добавляются nullable, `hash` становится NOT NULL только ПОСЛЕ backfill отдельной миграцией-contract (см. §4.1 ниже).
6. `/root/coordinata56/docs/legal/m-os-1-1-foundation-legal-check.md` — **раздел C-4** (штрафы 60–700 тыс ₽ за нарушение ст. 7 ФЗ-152).

**Бриф-предшественник (паттерн):**
7. `/root/coordinata56/docs/pods/cottage-platform/tasks/pr2-wave1-rbac-v2-pd-consent.md` — структура бриф-шаблона, особенно §9 (ревью-маршрут) и §10 (отчёт Head'а).

**Кодовой контекст (baseline для расширения):**
8. `backend/app/models/audit.py` — текущая `AuditLog` без crypto-полей. Эталон Index по `(entity_type, entity_id, timestamp)` — PR #3 добавляет индекс по `timestamp` соло для `/verify`.
9. `backend/app/services/audit.py` — текущий `AuditService.log()`. Содержит `AUDIT_EXCLUDED_FIELDS` (6 полей) и `_sanitize()` с 1-уровневой рекурсией. **Baseline для расширения** в Блоке 2 (C-4).
10. `backend/app/models/enums.py` — `AuditAction` (CREATE/UPDATE/DELETE/APPROVE/REJECT). Формула хеша использует `action.value`.
11. `backend/alembic/versions/2026_04_18_1200_ac27c3e125c8_rbac_v2_pd_consent.py` — предшествующая миграция (down_revision для PR #3). **Не трогать.**
12. `backend/tools/lint_migrations.py` — прецедент расположения utility-скриптов в `backend/tools/`. Backfill пишется тут же.
13. `backend/app/api/deps.py` — `get_current_user`, `require_permission` (добавлен PR #2). Для `/verify` используем `require_permission(action="read", resource_type="audit")`.

---

## 4. Скоуп PR #3 — 6 блоков с acceptance criteria

Head обязан декомпозировать в задачи для backend-dev в указанном порядке §5. Каждый блок — самостоятельный acceptance-критерий для ревью.

### Блок 1. Миграция Alembic — добавление полей крипто-цепочки (expand)

**Что:** один файл в `backend/alembic/versions/` с именем вида `2026_04_18_XXXX_<rev>_audit_crypto_chain.py`. **Down-revision — `ac27c3e125c8`** (финальная миграция PR #2).

**Добавляемые объекты в таблицу `audit_log`:**

1. Колонка `prev_hash: str(64), nullable` — хеш предыдущей записи. NULL для первой записи в системе ИЛИ для легаси-записей, которые backfill пока не обработал. **Именно nullable в этой миграции** — backfill запускается после apply.
2. Колонка `hash: str(64), nullable`. **Обязательно nullable на этой миграции** — иначе `alembic upgrade head` сломается на существующих 351+ записях. NOT NULL — ВТОРОЙ, contract-миграцией (см. Блок 6) после backfill. Паттерн expand/contract (ADR 0013).
3. Индекс `ix_audit_log_timestamp` на колонке `timestamp` — нужен для `/verify?from=...&to=...` при запросах за период. Сейчас timestamp есть в составном индексе `ix_audit_log_entity_type_entity_id_timestamp`, но prefix — `entity_type`, по `timestamp` соло поиск неэффективен.

**Downgrade:** `DROP INDEX ix_audit_log_timestamp`, `DROP COLUMN audit_log.hash`, `DROP COLUMN audit_log.prev_hash`. Round-trip обязан быть чистым.

**Никакого seed'а.** Эта миграция — чистый expand DDL, без `op.execute`. Линтер должен пройти без warning'ов `op_execute`.

**Acceptance:**
- Файл миграции проходит `python -m tools.lint_migrations backend/alembic/versions/` — **0 ошибок, 0 warning'ов**.
- `alembic upgrade head && alembic downgrade -1 && alembic upgrade head` — чисто.
- После upgrade: `ruff check` чисто, модель `AuditLog` (см. Блок 2) импортируется, autogenerate не видит расхождений.

### Блок 2. ORM-модель `AuditLog` + сервис `AuditService`

**Что:**

1. **`backend/app/models/audit.py`** — обновить класс `AuditLog`:
   - Добавить `prev_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)`.
   - Добавить `hash: Mapped[str | None] = mapped_column(String(64), nullable=True)` — **пока nullable до contract-миграции Блока 6**. После контрактной миграции в отдельном PR тип обновится до `Mapped[str]`, не в этом PR.
   - Добавить `Index("ix_audit_log_timestamp", "timestamp")` в `__table_args__` рядом с существующим композитным.
   - **Не трогать** остальные поля и существующие индексы.

2. **`backend/app/services/audit.py`** — существенное расширение:
   - Константа `GENESIS_HASH: str = hashlib.sha256(b"genesis").hexdigest()` на уровне модуля. Вычисляется 1 раз при импорте.
   - Новый приватный метод `async def _compute_hash(self, prev_hash: str, entry: AuditLog) -> str` — строго по формуле ADR 0011 §3.1:
     ```
     payload = "|".join([
         prev_hash,
         entry.entity_type,
         str(entry.entity_id or ""),
         entry.action.value,
         str(entry.user_id or ""),
         entry.timestamp.isoformat(),
         json.dumps(entry.changes_json, sort_keys=True, ensure_ascii=False, separators=(",", ":")),
     ])
     return hashlib.sha256(payload.encode("utf-8")).hexdigest()
     ```
     **Это канонический алгоритм.** Любое отклонение — нарушение ADR и break-change цепочки.
   - Новый приватный метод `async def _get_last_hash_locked(self) -> str` — `SELECT hash FROM audit_log ORDER BY id DESC LIMIT 1 FOR UPDATE` (см. правила в §6 ниже про слои). Возвращает `GENESIS_HASH` если таблица пуста.
   - Расширить `log()`:
     - После `self.session.add(entry)` — выполнить `await self.session.flush()` чтобы получить `entry.timestamp` (server_default `now()`) и `entry.id`.
     - **Затем**: получить `prev_hash = await self._get_last_hash_locked()` через репозиторий (см. Блок 3). **Лок берётся ДО flush не годится** — у нас ещё нет строки. Порядок: flush → get_last_hash_locked(исключая только что добавленную строку) → compute_hash(использует timestamp из БД) → `entry.prev_hash = prev_hash; entry.hash = computed` → второй flush.
     - **Тонкий момент:** `_get_last_hash_locked()` должен возвращать hash из строки с максимальным id, **исключая `entry.id`** (который только что сгенерирован). Это важно для serializability. Реализация: передать в репозиторий `exclude_id: int | None = None`.
     - Альтернатива (если первый вариант окажется сложным в тестах): блокировать advisory-lock PostgreSQL по фиксированному ключу `pg_advisory_xact_lock(<const>)` перед любой записью. **Решение Head** — выбрать вариант; в отчёте §10 зафиксировать. Рекомендация Директора: **первый вариант (FOR UPDATE на последнюю строку с `exclude_id`)** — ближе к букве ADR 0011 §3.1.

3. **Расширение `AUDIT_EXCLUDED_FIELDS` — C-4 маскирование ПД:**
   ```python
   AUDIT_EXCLUDED_FIELDS: frozenset[str] = frozenset({
       # существующие секреты (ADR 0007):
       "password_hash", "password", "token", "secret", "key", "jwt",
       # ПД (C-4, ФЗ-152 ст. 7):
       "full_name", "email", "phone", "passport_number", "passport",
       "pd_consent_version", "pd_consent_at",
   })
   ```
   **Почему именно этот список:** фактические ПД-поля в `backend/app/models/user.py` — `email`, `full_name`; плюс `password_hash` (секрет, не ПД, но уже маскирован). `phone`, `passport_number` — превентивно на случай добавления (модель `Contractor` может их получить в M-OS-1). `pd_consent_*` — не ПД сами по себе, но юрист на legal-check сказал: «факт принятия политики можно хранить, версию и время — достаточно в `users`; в `audit_log` достаточно факта изменения, не значения».

4. **Углубление рекурсии `_sanitize`:** сейчас маскирование работает только для 1-уровневых dict'ов (`changes["before"] = {...}`). Для глубокой структуры (`changes["diff"] = [{"field": "email", "from": "a@b", "to": "c@d"}]`) ПД не маскируется. **Реализовать рекурсивный обход `_sanitize`** — применяется ко всем вложенным dict'ам/спискам:
   ```python
   def _sanitize(data):
       if isinstance(data, dict):
           return {
               k: _sanitize(v)
               for k, v in data.items()
               if k not in AUDIT_EXCLUDED_FIELDS
           }
       if isinstance(data, list):
           return [_sanitize(item) for item in data]
       # Отдельно: если элемент — dict с ключом "field" (формат diff),
       # то при field ∈ AUDIT_EXCLUDED_FIELDS — заменяем "from"/"to" на "***".
       return data
   ```
   **Head обсудит с backend-dev**: формат diff-элементов — это просто dict с ключом `field` — значит, после общей рекурсии отдельной обработки не нужно; но если diff появляется как `{"field": "email", "from": "a@b", "to": "c@d"}`, то ключ `field` — не ПД, а **значение** `email` — индикатор, что `from`/`to` надо маскировать. Это специальный случай. Реализовать: проверка `if isinstance(item, dict) and item.get("field") in AUDIT_EXCLUDED_FIELDS: mask "from"/"to" = "***"`.

**Правила:**
- Все операции сервиса — в рамках одной транзакции; `flush` без `commit`.
- Сервис может читать через репозиторий (`AuditLogRepository.get_last_locked`), но не выполняет `session.execute` напрямую. Правило 1 отдела (Amendment 2026-04-18).
- Никаких `# type: ignore` без комментария.

**Acceptance:**
- `ruff check backend/app/services/audit.py backend/app/models/audit.py` чисто.
- Hash-формула точно соответствует ADR 0011 §3.1 (тест в Блоке 5 проверяет bit-exact с эталоном).
- Глубокая маскировка ПД работает на diff-формате и вложенных dict'ах (тест в Блоке 5).

### Блок 3. Репозиторий `AuditLogRepository`

**Что:** новый файл `backend/app/repositories/audit.py`:

1. Класс `AuditLogRepository(BaseRepository[AuditLog])`.
2. Метод `async def get_last_hash_locked(self, exclude_id: int | None = None) -> str | None`:
   - `SELECT hash FROM audit_log WHERE (exclude_id IS NULL OR id != :exclude_id) ORDER BY id DESC LIMIT 1 FOR UPDATE`.
   - Возвращает `hash` последней записи (исключая `exclude_id`) или `None` если таблица пуста/исключена единственная.
   - **Важно:** `FOR UPDATE` обязателен — закрывает race при конкурентных INSERT в разные транзакции (FIND-02 OWASP, ADR 0011 §3.1 «Отрицательные последствия»).
3. Метод `async def list_by_period(self, from_ts: datetime, to_ts: datetime) -> list[AuditLog]`:
   - `SELECT * FROM audit_log WHERE timestamp >= :from_ts AND timestamp <= :to_ts ORDER BY id ASC`.
   - Без пагинации: для `/verify` нужны все записи периода; лимит длины — бизнес-уровень эндпоинта (см. §Блок 4).
4. Метод `async def iter_all_ordered(self) -> AsyncIterator[AuditLog]`:
   - Курсорный iter через `session.stream()` или через offset/limit-пакеты — **для backfill-скрипта**, чтобы не загружать всю таблицу в память.
   - Head и backend-dev решают реализацию; рекомендация Директора — `yield_per(1000)` паттерн SQLAlchemy 2.0.

**Правила:**
- Все запросы — только здесь. Никакого `.execute` в сервисах.
- `FOR UPDATE` — только внутри транзакции; caller (`AuditService`) обязан гарантировать транзакционный контекст.

**Acceptance:**
- `ruff check` чисто.
- Unit-тесты репозитория в `backend/tests/test_audit_repository.py` — по образцу существующих репозиториев (Head выбирает).

### Блок 4. Endpoint `GET /api/v1/audit/verify`

**Что:**

1. Новый файл `backend/app/api/audit.py`:
   - `GET /api/v1/audit/verify?from=<ISO8601>&to=<ISO8601>` — Query params `from: datetime`, `to: datetime` (Pydantic авто-парсинг ISO 8601).
   - Валидация: `to > from`, `to - from <= timedelta(days=90)` — лимит периода 90 дней. Причина: полная верификация O(n), при >100k записей синхронный вызов упрётся в timeout; для MVP лимит хранимой истории ~1 год, 90 дней — разумная порция. Head может обсудить другой лимит с Координатором, если есть аргументация.
   - Требует `require_permission(action="read", resource_type="audit")` — право засижено PR #2.
   - Логика:
     - Загружает записи через `audit_repo.list_by_period(from_ts, to_ts)`.
     - Если список пуст — возвращает `{"status": "ok", "checked": 0, "broken_links": [], "period": {"from": ..., "to": ...}}`.
     - Иначе: определяет `prev_hash` для первой записи периода — это `audit_repo.get_last_before(first_record.id)` (новый вспомогательный метод: последняя запись **до** начала периода, её `hash`) ИЛИ `GENESIS_HASH` если записей до периода нет. **Это критично для корректной верификации:** первая запись периода ссылается на запись вне периода.
     - Для каждой записи вычисляет `expected_hash = _compute_hash(prev_hash_effective, record)` и сравнивает с `record.hash`. При mismatch — добавляет `{"audit_log_id": record.id, "reason": "hash_mismatch"}` в `broken_links`. Также проверяет `record.prev_hash == prev_hash_effective` — при mismatch reason=`"prev_hash_mismatch"`.
     - `prev_hash_effective` для следующей итерации = `record.hash` (не пересчитанный — доверяем, что дальше цепочка может восстановиться; сценарий «одна запись подменена» даст 1 broken_link).
     - Возвращает ADR 0005 envelope с `status: "ok" | "broken"`, `checked: int`, `broken_links: list[{audit_log_id, reason}]`, `period: {from, to}`.

2. Response schema — новая Pydantic-схема `AuditVerifyResponse` в `backend/app/schemas/audit.py` (новый файл):
   - `status: Literal["ok", "broken"]`
   - `checked: int`
   - `broken_links: list[BrokenLink]` — `BrokenLink{audit_log_id: int, reason: Literal["hash_mismatch", "prev_hash_mismatch"]}`
   - `period: PeriodBounds` — `PeriodBounds{from_ts: datetime, to_ts: datetime}` (alias `from` в JSON — `from` резерв Python).
3. Регистрация роутера в `backend/app/main.py` — после существующих audit-роутеров (их пока нет, новый роутер). Префикс `/api/v1`, tags `["audit"]`.

**Правила:**
- ADR 0005 error format (стандартный global handler).
- Сервис (`AuditService.verify_chain(from, to)`) делает бизнес-логику; роутер — только парсинг query + вызов + формирование envelope. Правило 1 отдела.

**Acceptance:**
- Swagger `/docs` рендерится, эндпоинт виден с summary, description, response_model, корректным `responses={403: ..., 422: ...}`.
- Тест: `/verify` без auth → 401; без права audit.read → 403; с правом — 200 + корректный envelope.
- Тест: после ручной подмены `changes_json` на одной записи → `/verify` возвращает `status="broken"` с этой записью в `broken_links`.

### Блок 5. Backfill-скрипт `backend/tools/audit_chain_backfill.py`

**Что:** отдельный исполняемый Python-файл, запускается вручную администратором **после apply миграции Блока 1, до открытия трафика** (порядок из ADR 0011 §3.3).

1. Файл `backend/tools/audit_chain_backfill.py`:
   - Docstring: описание, ADR 0011 §3.3, отметка об отклонении от ADR по расположению (`tools/` вместо `scripts/`) с обоснованием (§2.4).
   - CLI через `argparse` или просто `sys.argv`: флаги `--dry-run` (вывод плана без записи), `--batch-size=1000` (размер пакета для iter), `--continue-on-error` (продолжать при ошибке вычисления — только логировать).
   - Импортирует `get_async_session` из `app.db`, создаёт сессию в скрипте.
   - Логика:
     - В одной транзакции: `BEGIN`.
     - Последовательно через `audit_repo.iter_all_ordered()` (Блок 3).
     - Для каждой записи: если `record.hash IS NOT NULL` — **пропустить** (идемпотентность, ADR 0011 §3.3).
     - Иначе: `prev_hash = GENESIS_HASH если это первая; иначе prev_hash = previous_record.hash` — **используя в памяти цепочку, без SELECT каждый раз** (оптимизация под большие объёмы).
     - `computed = _compute_hash(prev_hash, record)` — через `AuditService._compute_hash` (вынести на уровень модуля или staticmethod).
     - `record.prev_hash = prev_hash; record.hash = computed`.
     - После каждого `batch-size` записей — `session.flush()`; в конце — `session.commit()`.
   - Финальный отчёт в stdout: `processed=X, skipped=Y, errors=Z`.
   - При `--dry-run` — считает что бы сделал, commit не вызывается (rollback в конце).

2. Тест backfill-скрипта — `backend/tests/test_audit_backfill.py`:
   - Создаёт ≥10 AuditLog записей без `hash`.
   - Запускает backfill программно (импорт функции).
   - Проверяет: все записи получили `hash`, первая — с `prev_hash=None` (или `GENESIS_HASH` — Head уточняет контракт), каждая следующая — `prev_hash == предыдущая.hash`, `hash` воспроизводится повторным вычислением.
   - Повторный запуск — идемпотентен: `processed=0, skipped=N`.

**Правила:**
- Скрипт — НЕ часть рантайма приложения. Не регистрируется в FastAPI, не импортируется из `main.py`.
- Использует утилиты `AuditService` — не дублирует формулу хеша.
- Никаких hardcoded connection strings — читает `os.environ.get("DATABASE_URL")` или использует стандартный `settings`.

**Acceptance:**
- Скрипт идемпотентен (повторный запуск ничего не делает).
- После backfill: `GET /api/v1/audit/verify` за весь период возвращает `status="ok"`.
- Unit-тест покрывает happy-path + идемпотентность + `--dry-run`.

### Блок 6. Тесты

**Что:** в `backend/tests/`:

1. **`test_audit_hash.py`** — формула и core-логика:
   - test_genesis_hash: `GENESIS_HASH == sha256("genesis").hexdigest()` — фиксированная строка `"b77dddc9c7ad6f0a6b3df04d6e0f85c6f0bfb09e3c5027b8e45ef90f27e0f5cd"` (проверить точно в Python перед написанием теста).
   - test_compute_hash_deterministic: два вызова с одинаковым `(prev_hash, entry)` дают одинаковый hash.
   - test_compute_hash_breaks_on_changes: изменение любого поля `changes_json` меняет `hash`.
   - test_chain_sequence: вставить 3 записи подряд → `record2.prev_hash == record1.hash`, `record3.prev_hash == record2.hash`.
   - test_first_record_prev_hash_is_genesis: первая запись имеет `prev_hash == GENESIS_HASH` (или None — Head выбирает контракт и документирует).

2. **`test_audit_sanitize.py`** — C-4 маскирование:
   - test_top_level_pd_masked: `changes_json={"email": "a@b.c", "project_id": 1}` → после `_sanitize` → `{"project_id": 1}` (email удалён).
   - test_nested_dict_pd_masked: `{"before": {"full_name": "Иванов", "id": 1}, "after": {"full_name": "Петров", "id": 1}}` → `{"before": {"id": 1}, "after": {"id": 1}}`.
   - test_diff_format_pd_masked: `{"diff": [{"field": "email", "from": "a@b", "to": "c@d"}, {"field": "name", "from": "X", "to": "Y"}]}` → email-элемент получает `from="***"`, `to="***"`; name-элемент нетронут.
   - test_list_of_dicts_sanitized: `{"history": [{"email": "a@b"}, {"email": "c@d"}]}` → `{"history": [{}, {}]}`.
   - test_secrets_still_masked: проверка, что `password_hash` и `token` всё ещё удаляются (не сломать ADR 0007).
   - test_non_pd_fields_preserved: `project_name`, `amount_cents`, `company_id` остаются.

3. **`test_audit_verify_endpoint.py`** — endpoint:
   - test_verify_empty_period: 200, `status="ok"`, `checked=0`.
   - test_verify_valid_chain: 10 записей, верификация — `status="ok"`.
   - test_verify_broken_hash: вручную UPDATE `audit_log SET hash='tampered'` на записи в середине → `status="broken"`, `broken_links` содержит эту запись с `reason="hash_mismatch"`.
   - test_verify_broken_prev_hash: вручную UPDATE `prev_hash='wrong'` → reason=`"prev_hash_mismatch"`.
   - test_verify_rbac: non-owner без audit.read → 403.
   - test_verify_period_limit: `to - from > 90 days` → 422 VALIDATION_ERROR.
   - test_verify_first_record_uses_predecessor: верификация периода, начинающегося с записи id=5, корректно использует hash записи id=4 как `prev_hash_effective`.

4. **`test_audit_backfill.py`** — уже описан в Блоке 5.

5. **`test_audit_race_condition.py`** (сложный, опционально в первом раунде — но **крайне желательно**):
   - Две параллельные async-транзакции пытаются сделать `AuditService.log()` одновременно. Проверка: обе записи получают корректные `prev_hash` (одна = hash первой, вторая = hash первой), `FOR UPDATE` сериализует доступ. Тест на SQLite может не пройти (нет FOR UPDATE); использовать postgres test container — **Head уточняет, есть ли он**. Если нет — тест пропускается в SQLite, запускается только в CI с postgres. В отчёте §10 отметить.

6. **Миграция NOT NULL contract (отложить в отдельный PR):**

   **Блок 6.А** (в рамках ЭТОГО PR — не нужен, не в скоупе). После мержа PR #3 и успешного backfill на staging — **отдельной задачей backend-director планирует contract-миграцию** `audit_log.hash SET NOT NULL`. Head в отчёте §10 отметит: «Для выхода в production нужна contract-миграция NOT NULL на `hash`; сейчас поле nullable».

**Стандарты:**
- Покрытие: ≥85% строк новых модулей (`audit.py` сервис/модель/репо/api/schema, backfill скрипт).
- Никаких литералов паролей/секретов (правило 7 отдела).
- Фикстуры в `conftest.py`: `create_audit_log_entry(db, action, entity_type, entity_id, user_id=None, changes=None)` — удобная обёртка, использующая `AuditService.log()`.

**Acceptance:** `pytest backend/tests -q` зелёный, `ruff check backend/` 0 ошибок.

---

## 5. Порядок выполнения (рекомендация Head'у)

1. **День 1.** Блок 1 (миграция + индекс timestamp) + Блок 2 (модель + базовый сервис, формула хеша без FOR UPDATE пока). Прогон round-trip. Первые тесты формулы хеша (`test_audit_hash.py` на уровне unit).
2. **День 2.** Блок 2 углубление (FOR UPDATE через Блок 3 репозитория, глубокая рекурсия `_sanitize` для C-4) + Блок 5 тесты маскирования (`test_audit_sanitize.py`).
3. **День 3.** Блок 4 (endpoint `/verify` + схема + регистрация) + тесты `test_audit_verify_endpoint.py`.
4. **День 4.** Блок 5 (backfill-скрипт) + `test_audit_backfill.py`. Ручной прогон на dev-DB с ≥100 существующих записей, верификация через `/verify`.
5. **День 5.** Блок 5.5 (race condition тест) + финальная чистка + отчёт Head'а.
6. **День 6.** Раунды ревью backend-head, reviewer. Отчёт Директору.

---

## 6. Правила слоёв (напомнить backend-dev явно)

**Жёстко по ADR 0004 Amendment 2026-04-18:**

- `AuditService._compute_hash` — pure function, ОК в сервисе (не делает SQL).
- `AuditService._get_last_hash_locked` — **не делает `session.execute` сам**, а вызывает `audit_repo.get_last_hash_locked(exclude_id=...)`. Именно репозиторий делает `SELECT ... FOR UPDATE`.
- `AuditService.verify_chain` — вызывает `audit_repo.list_by_period(from, to)` и `audit_repo.get_last_before(record_id)` (если нужен), сам не делает `.execute`.
- Типизированные предикаты (`ColumnElement[bool]`) разрешены в сервисе через `extra_conditions`, но для audit они почти не нужны (сервис тоже простой).

**Если backend-dev начнёт писать `select(AuditLog).where(...).for_update()` прямо в сервисе — Head возвращает с request-changes.**

---

## 7. Связь с PR #2 и совместимость

- **`consent_service.accept()`** из PR #2 пишет в `audit_log` через `AuditService.log()`. После мержа PR #3 — эти записи автоматически попадают в новую крипто-цепочку. Это нормально, backfill обработает все записи без `hash`, включая свежие post-PR #2.
- **`require_permission("read", "audit")`** — засижено в PR #2 (`permissions.csv` строки 272–273). Пере-seed НЕ делать.
- **Контракт `AuditService.log()` сохраняется 100%** — сигнатура метода не меняется (аргументы те же: `user_id`, `action`, `entity_type`, `entity_id`, `changes`, `ip_address`, `user_agent`). Меняется только внутреннее поведение (добавляются `prev_hash`/`hash` к записи).
- **351+ существующих тест продолжает проходить** без изменений — backfill проставит им хеши при dev-deploy.

---

## 8. Риски и зависимости

- **Блокер PR #2.** Описан в §0. Без мержа PR #2 стартовать нельзя (down_revision не существует в `main`).
- **Frontend.** Новый эндпоинт `/api/v1/audit/verify` — admin-only. Фронт ещё не имеет экрана верификации. **Это ОК** — эндпоинт нужен сам по себе (CLI-вызов, support-инструмент). Экран верификации — отдельная задача FE-отдела в M-OS-1.1.
- **Performance verify.** Верификация O(n). Для 100k записей — десятки секунд SQL + CPU. Лимит 90 дней защищает от timeout. При росте системы — async job. **TODO в коде, не в скоупе PR #3.**
- **Backfill на больших БД.** Backfill всех записей в одной транзакции может висеть минутами. **Митигация:** `--batch-size` с промежуточными flush, возможность запускать порциями (второй запуск идемпотентен, обработает оставшиеся).
- **Race condition при высокой нагрузке.** `SELECT FOR UPDATE` на последнюю строку `audit_log` — точка сериализации. На MVP-нагрузке (десятки rps) некритично. **Упомянуть в отчёте §10** как отложенный технический долг (ADR 0011 §«Отрицательные последствия» уже это фиксирует).
- **Tech-debt: старые `changes_json` содержат ПД.** Prospective-only маскирование — согласовано Координатором (§2.2). В отчёте §10 зафиксировать: «До мержа PR #3 существующие записи audit_log содержат `full_name`, `email` и т.п. в `changes_json`. Retroactive mask не делаем — ст. 22 ФЗ-152 (неизменяемость). Доступ к `audit_log` ограничен `audit.read` (owner / admin), что уже снижает риск. План: при росте объёма — отдельный ADR по архивированию старых записей с возможным cold-storage.»
- **Конфликт с будущим PR #4 (ACL).** PR #4 добавит ACL (ADR 0014 каркас). AuditLog может получить ACL-проверки на read. **В скоуп PR #3 не входит.** Координация — через Директора после мержа PR #3.

---

## 9. DoD PR #3

- [ ] Все 6 блоков скоупа реализованы.
- [ ] Миграция `<rev>_audit_crypto_chain.py` проходит линтер (`lint_migrations`) без ошибок и **без warning'ов**.
- [ ] Round-trip миграции чист (CI job `round-trip` зелёный на PR).
- [ ] `pytest backend/tests -q` зелёный; покрытие новых модулей ≥85%.
- [ ] `ruff check backend/app backend/tests backend/tools` — 0 ошибок.
- [ ] Swagger `/docs` рендерится, `/api/v1/audit/verify` с `summary`/`description`/`response_model`.
- [ ] Никаких секретов-литералов в коде и тестах.
- [ ] **Crypto-acceptance:**
  - [ ] Формула хеша bit-exact соответствует ADR 0011 §3.1.
  - [ ] `FOR UPDATE` действительно берётся (или advisory lock — с явным обоснованием в отчёте).
  - [ ] `/verify` обнаруживает tampered запись на ручном UPDATE.
  - [ ] Первая запись периода корректно использует `prev_hash` предыдущей записи (вне периода) для верификации.
- [ ] **C-4 acceptance:**
  - [ ] `AUDIT_EXCLUDED_FIELDS` содержит все 7 ПД-полей из §4 Блок 2.
  - [ ] Глубокая рекурсивная маскировка работает на diff-формате и вложенных dict/list.
  - [ ] Существующие 6 секретов из ADR 0007 всё ещё маскируются (регрессия 0).
- [ ] **Backfill-acceptance:**
  - [ ] Скрипт `backend/tools/audit_chain_backfill.py` идемпотентен (повторный запуск не делает работу).
  - [ ] После backfill `/verify` за весь исторический период — `status="ok"`.
  - [ ] `--dry-run` не пишет в БД.
- [ ] Ревью backend-head — approve.
- [ ] Ревью reviewer (review-head → reviewer) — approve.
- [ ] Ручной smoke-тест `/verify` через Swagger UI (лог команды в отчёте Head).
- [ ] Существующие 351+ тестов PR #1 и PR #2 — зелёные (никаких регрессий).
- [ ] **Tech-debt зафиксирован в отчёте:** (а) старые записи с ПД, (б) contract-миграция NOT NULL для `hash` отложена, (в) race sequelization при высокой нагрузке.

---

## 10. Ревью-маршрут

1. **backend-dev → backend-head.** Head делает ревью уровня файлов: миграция, модель, сервис, репозиторий, endpoint, backfill, тесты. Особое внимание: соблюдение правила 1 (сервис не делает SQL-запросы), точность формулы хеша (bit-exact!), полнота C-4 маскировки на всех уровнях вложенности.
2. **backend-head → review-head → reviewer.** Reviewer проверяет на соответствие CLAUDE.md, ADR 0011 Часть 3, ADR 0007 (не сломать контракт), legal-check C-4. Отдельное внимание: race condition, идемпотентность backfill, отсутствие hardcoded секретов в тестах.
3. **Reviewer approve → backend-head → backend-director.** Я принимаю работу на уровне DoD: состав PR, логи CI, покрытие, smoke-тест /verify, tech-debt в отчёте.
4. **Backend-director approve → Координатору.** Координатор делает git commit + push.

---

## 11. Что Head возвращает Директору на приёмку

Head оформляет отчёт одним сообщением со следующими разделами:

1. **Состав PR.** Список всех изменённых/созданных файлов с путями.
2. **Результаты тестов.** Вывод `pytest backend/tests -q --tb=short` (последние 30–50 строк).
3. **Покрытие.** Вывод `pytest --cov=backend/app/services/audit --cov=backend/app/repositories/audit --cov=backend/app/api/audit --cov=backend/tools --cov-report=term`.
4. **Результаты линтеров.** `ruff check backend/` и `python -m tools.lint_migrations backend/alembic/versions/`.
5. **Результаты round-trip.** Вывод трёх команд `alembic upgrade head && alembic downgrade -1 && alembic upgrade head`.
6. **Swagger smoke.** Подтверждение что `/docs` рендерится; скриншот/лог запроса `GET /api/v1/audit/verify?from=...&to=...`.
7. **Crypto-smoke.**
   - Лог `curl` на `/verify` без auth → 401.
   - Лог `curl` с токеном без audit.read → 403.
   - Лог `curl` с owner-токеном → 200 + envelope.
   - Лог ручного UPDATE `audit_log SET changes_json='{"tamper":1}' WHERE id=X` → повторный `/verify` → `status="broken"` с этой записью в `broken_links`.
8. **Backfill-smoke.** Лог запуска скрипта на dev-DB с ≥100 записями (до backfill `/verify` → broken; после → ok).
9. **Замечания ревьюеров и их закрытие.** Краткая сводка (P0/P1/P2, ссылки на коммиты).
10. **Отклонения от брифа.** Любое решение Head'а, не описанное в брифе — фиксируется с обоснованием. Особенно: выбор FOR UPDATE vs advisory lock; реализация маскировки diff-формата.
11. **Tech-debt (обязательно):**
    - (а) Старые записи `audit_log` до мержа PR #3 содержат ПД в `changes_json`. Retroactive mask не делаем (ст. 22 ФЗ-152).
    - (б) Contract-миграция NOT NULL на `audit_log.hash` — отдельной задачей после подтверждения backfill на staging.
    - (в) `SELECT FOR UPDATE` на последнюю строку — точка сериализации при высокой нагрузке. M-OS-2 — секционирование per-company.
    - (г) Regression-sweep «все сервисы вызывают `audit_service.log()`» — отложен, будет через quality-director после PR #4.
12. **Метрики.** Время на задачу (план 5–6 дней чистой работы vs факт), раунды ревью.

---

## 12. Оценка времени

- **Backend-dev работа:** 5–6 дней чистой работы (Sonnet). Из них:
  - 1 день — миграция + модель + формула хеша + unit-тесты формулы;
  - 1 день — репозиторий + FOR UPDATE + глубокая маскировка + тесты;
  - 1 день — endpoint `/verify` + схема + тесты верификации (включая tampered-сценарий);
  - 1 день — backfill-скрипт + тесты идемпотентности;
  - 0.5 дня — race condition test + smoke-тесты;
  - 0.5–1 день — финальная чистка, раунды ревью.
- **Backend-head ревью:** 0.5–1 день (≥2 раунда: первый подход, после исправлений; плюс reviewer).
- **Reviewer (review-head → reviewer):** 0.5 дня.
- **Итого календарно с учётом циклов:** ~6–8 рабочих дней. Без форсажа (правило Владельца 2026-04-18 «без дедлайнов»).

---

## 13. Ограничения (жёсткие)

**FILES_ALLOWED (для backend-dev):**
- `backend/alembic/versions/2026_04_18_*_audit_crypto_chain.py` (1 новая миграция, имя по шаблону)
- `backend/app/models/audit.py` (расширение существующего)
- `backend/app/services/audit.py` (расширение существующего)
- `backend/app/repositories/audit.py` (новый файл)
- `backend/app/api/audit.py` (новый файл)
- `backend/app/schemas/audit.py` (новый файл)
- `backend/app/main.py` (регистрация нового `audit_router`)
- `backend/app/api/deps.py` (только если нужен helper `get_audit_service` — Head решает, предпочтительно да)
- `backend/tools/audit_chain_backfill.py` (новый файл)
- `backend/tests/test_audit_hash.py` (новый)
- `backend/tests/test_audit_sanitize.py` (новый)
- `backend/tests/test_audit_verify_endpoint.py` (новый)
- `backend/tests/test_audit_backfill.py` (новый)
- `backend/tests/test_audit_race_condition.py` (новый, опционально — Head оценивает сложность, но желательно)
- `backend/tests/test_audit_repository.py` (новый — unit для репозитория)
- `backend/tests/conftest.py` (только добавление фикстуры `create_audit_log_entry`, если нужна)

**FILES_FORBIDDEN:** всё остальное, в частности:
- Любые миграции кроме новой (включая `ac27c3e125c8_rbac_v2_pd_consent.py` из PR #2 — **не трогать**)
- Любые ADR-файлы (amendment не нужен; если вдруг обнаружится неоднозначность ADR 0011 §3 — эскалация Директору, не правка ADR)
- `CLAUDE.md` проектный (правила добавляются через backend-director после мержа, не из PR)
- Pod-specific сервисы и модели (`project.py`, `contract.py`, `payment.py` и т.п.) — не трогаем
- `backend/app/services/rbac.py`, `consent.py`, `role.py` и всё что из PR #2 — не трогаем
- `backend/app/models/user.py`, `role.py`, `permission.py`, `pd_policy.py` — не трогаем
- `frontend/*` — всё фронтовое
- `backend/scripts/` — такого каталога нет и не создаём (backfill живёт в `backend/tools/`)

**COMMUNICATION_RULES:**
- backend-dev не общается с другими отделами напрямую.
- Все вопросы по скоупу — только к backend-head.
- Head эскалирует Директору, если вопрос не решается через бриф или §3.
- К legal / design / frontend / db — только через Директора (backend-director).
- К Координатору / Владельцу — только через Директора.

**Жёсткие технические запреты:**
- **ADR 0002, 0004, 0005, 0006, 0007, 0011 не трогаем.** Отклонение от любого — request-changes.
- **Формула хеша — bit-exact по ADR 0011 §3.1.** Любое изменение порядка полей или разделителя — break-change цепочки, критический дефект.
- **Retroactive mask старых записей — ЗАПРЕЩЁН.** Prospective only (решение Координатора §2.2).
- **`users.pd_consent_at/version` в `audit_log.changes_json`** — маскируется вместе с ПД.
- **Никаких секретов-литералов.** Только `os.environ.get(...)` и `secrets.token_urlsafe(16)`.
- **`# type: ignore` / `# noqa` запрещены без комментария-обоснования.**
- **`git add -A` запрещён.** Только перечисление конкретных файлов.
- **Коммит — после reviewer approve.** Правило CLAUDE.md §«Reviewer — до git commit».

---

## 14. Вопросы на обсуждение с Координатором (не блокируют старт)

Эти вопросы уже заданы и получили ответы (§2 Решения Координатора). Ниже — вопросы, предусмотренные Директором **для backend-head** при старте работы. Head решает сам или эскалирует, если потребует.

1. **FOR UPDATE vs advisory lock (Блок 2).** Рекомендация Директора — FOR UPDATE с `exclude_id`. Head может выбрать advisory lock с обоснованием в отчёте. Решение фиксируется в §10 отчёта.
2. **Контракт первой записи: `prev_hash = None` vs `prev_hash = GENESIS_HASH`.** ADR 0011 §3.1 говорит: «`prev_hash at INSERT берётся из последней записи… Первая запись в системе: `prev_hash = None`, в хеш подставляется `SHA-256("genesis")`». То есть **в БД `prev_hash = None`**, но **в хеше** используется `GENESIS_HASH`. Head проверяет, что тесты `test_chain_sequence` и `test_first_record_prev_hash_is_genesis` формализуют это без двойного толкования. Если формулировка в ADR создаёт неоднозначность — эскалация через Директора к architect.
3. **Лимит периода /verify (Блок 4).** Предложение Директора — 90 дней. Head может обсудить другой лимит; если предлагает — эскалация Директору для согласования перед написанием кода.
4. **Формат diff-элементов в changes_json.** Директор описал гипотетический формат `{"field": ..., "from": ..., "to": ...}`. Head проверяет фактический формат, который уже формируется в `payment.py`, `contract.py`, `consent.py` — и адаптирует маскирование под реальный формат. Если формат неконсистентен — это P1 замечание к сервисам-авторам (не в этот PR, в regression-sweep).
5. **Race condition тест (Блок 5.5).** Если в `conftest.py` нет postgres test container (а только SQLite) — тест помечается `@pytest.mark.skipif(not has_postgres, ...)`. Head подтверждает в §10 отчёта, что настройка подтверждена.
6. **`get_last_before(record_id)` для /verify (Блок 4).** Нужен ли отдельный метод в репозитории для получения hash записи **строго до** заданного id? Директор считает — да, иначе первая запись периода не может быть корректно верифицирована. Head подтверждает реализацию или предлагает альтернативу.

**Head пишет Директору до старта backend-dev:** если по этим 6 вопросам есть мнение/выбор, фиксирует в ответном сообщении. Директор даёт зелёный свет на `Agent`-вызов backend-dev.

---

*Бриф составлен backend-director 2026-04-18 для backend-head в рамках M-OS-1 Волна 1 Foundation PR #3. Решения §7 оригинального черновика согласованы с Координатором 2026-04-18 (см. §2). Передача Head через паттерн Координатор-транспорт v1.6 — после мержа PR #2 в `main`. После вычитки Head — запрос на уточнения ко мне. После старта — отчёт по §11 на приёмку.*
