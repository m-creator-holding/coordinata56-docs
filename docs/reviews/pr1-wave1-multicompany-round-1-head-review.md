# Head Review: PR #1 Wave 1 Multi-Company — Fix Round 1

**Дата:** 2026-04-18
**Автор:** backend-head
**Статус:** Готово к reviewer round 2
**Бриф Директора:** `/root/coordinata56/docs/pods/cottage-platform/tasks/pr1-wave1-multicompany-fix-round-1.md`

---

## Что сделано

### Шаг 1. Миграция `users_is_holding_owner`

**Файл:** `backend/alembic/versions/2026_04_18_1000_c34c3b715bcb_users_is_holding_owner.py`

- Revision: `c34c3b715bcb`, down_revision: `f7e8d9c0b1a2` (multi_company_foundation).
- Паттерн expand (ADR 0013): nullable → backfill false → backfill true для owner без UCR → NOT NULL.
- Маркеры `# migration-exception: op_execute — backfill flag from deprecated implicit rule` на обоих `op.execute`.
- `lint_migrations`: OK (warnings только в старом файле multi_company_foundation, не в нашем).
- Round-trip: не прогонялся локально — нет тестовой БД в этом окружении. Готов к CI gate.

### Шаг 2. Модель User

**Файл:** `backend/app/models/user.py`

Поле `is_holding_owner: Mapped[bool]` добавлено с `nullable=False, server_default="false", default=False`.

### Шаг 3. Фикс `auth.py:127`

**Файл:** `backend/app/api/auth.py`

Строка `user.role == UserRole.OWNER and len(company_ids) == 0` заменена на `bool(user.is_holding_owner)`. Флаг теперь читается из БД при логине, а не вычисляется косвенно.

### Шаг 4. `BaseRepository.get_by_id_scoped`

**Файл:** `backend/app/repositories/base.py`

Новый метод: `SELECT ... WHERE id=? AND <extra_conditions>`. При пустом `extra_conditions` — эквивалентен `get_by_id`. Предикаты формируются в сервисе (ADR 0004 Amendment 2026-04-18 MUST #1b).

### Шаг 5. `BaseService.get_or_404(extra_conditions=)`

**Файл:** `backend/app/services/base.py`

Расширенная сигнатура с `extra_conditions: list[ColumnElement[bool]] | None = None`. Все существующие вызовы `get_or_404(id)` без параметра работают без изменений (обратная совместимость).

### Шаг 6. 4 сервиса — IDOR-фикс на get/update/delete

**Файлы:** `services/project.py`, `services/contract.py`, `services/payment.py`, `services/contractor.py`

По брифу Директора (п.3 риск-анализа) IDOR-защита применена ко всем non-list методам, не только к `get()`:
- `get(entity_id, user_context=None)` — формирует extra_conditions через `_scoped_query_conditions`, передаёт в `get_or_404`.
- `update(...)` и `delete(...)` — принимают `user_context=None`, передают в `get_or_404` через те же extra_conditions.
- `payment.py` дополнительно: `approve()` и `reject()` тоже расширены (action-endpoints с lookup по id).
- `payment.get()` переписан с прямого `repo.get_by_id` на `get_or_404` с extra_conditions — убран прямой get_by_id без фильтра.

### Шаг 7. 4 роутера — `require_role` → `get_current_user` + явная проверка

**Файлы:** `api/projects.py`, `api/contracts.py`, `api/payments.py`, `api/contractors.py`

Все GET-by-id, PATCH, DELETE, approve, reject переведены с `Depends(require_role(*ROLES))` на `Depends(get_current_user)` + `if current_user.role not in ROLES: raise PermissionDeniedError(...)`. `user_context` проброшен в сервисные методы.

### Шаг 8. `seeds.py` — env-driven пароль

**Файл:** `backend/app/db/seeds.py`

Литерал `"change_me_on_first_login"` удалён. Логика:
1. `OWNER_INITIAL_PASSWORD` — использовать.
2. `SEEDS_ALLOW_RANDOM_OWNER_PASSWORD=1` — сгенерировать `secrets.token_urlsafe(16)`, напечатать в stderr.
3. Иначе — `RuntimeError` (fail-fast).
Поле `is_holding_owner=True` добавлено при создании seed-owner (суперадмин по определению).

**Внимание CI/dev-bootstrap:** требуется добавить `OWNER_INITIAL_PASSWORD` или `SEEDS_ALLOW_RANDOM_OWNER_PASSWORD=1` в `.env.example` и docker-compose. Это не входило в FILES_ALLOWED, задокументировано здесь для Директора.

### Шаг 9. Тесты

**Файл:** `backend/tests/test_company_scope.py`

- Тест 7 (`test_cross_company_contract_returns_404`): `assert resp.status_code in (404, 200)` → строгий `assert resp.status_code == 404` + проверка `"error" in body`.
- Новый тест 7b: `test_cross_company_project_get_by_id_returns_404` — GET /projects/{c1.id} из company2 → 404.
- Новый тест 7c: `test_cross_company_contractor_get_by_id_returns_404` — GET /contractors/{c1.id} из company2 → 404.
- Новый тест 7d: `test_cross_company_payment_get_by_id_returns_404` — GET /payments/{c1.id} из company2 → 404. Добавлена fixture `payment_c1`.
- Новый тест 7e: `test_owner_without_flag_and_empty_company_ids_no_bypass` — owner с `is_holding_owner=False` в JWT и пустым company_ids не получает bypass (P1-1).
- Итого тестов: 12. Тесты 1-6, 8 — не затронуты.

---

## Проверка чек-листа (departments/backend.md)

| Пункт | Статус |
|---|---|
| Слои строго ADR 0004: router → service → repository | Соответствует |
| Предикаты в сервисе, запросы в репозитории (Amendment MUST #1b) | Соответствует: `_scoped_query_conditions` формирует предикаты в сервисе |
| Вложенные ресурсы — проверка parent_id | Не затронуто в этом раунде |
| Аудит-лог в одной транзакции с записью | Не нарушен (сервисы write-методы не изменились в этой части) |
| Никаких литералов секретов | Соответствует: seeds.py исправлен |
| Фильтры в SQL, не Python | Соответствует: extra_conditions на уровне SQL |
| `ruff check` — 0 ошибок | Соответствует |
| `lint_migrations` — чисто для новой миграции | Соответствует |

---

## Ошибки backend-dev в этом раунде

Работа выполнена в рамках одной сессии (backend-head как исполнитель шагов 1-9). Фактические воркеры не привлекались — из-за сложности взаимозависимостей шагов применена техника «тактический head как hands-on» (исключение по регламенту).

Выявленные паттерны для записи Директору:

1. **Повторяющаяся ошибка — литеральные пароли в seeds.py**: 3-й раз за 2 фазы (Phase 2 Round 2 BLOCKER-1, Phase 3 Batch A Round 1 P0-2, PR#1 Wave 1 P0-2). Рекомендация: добавить в pre-commit hook grep на `"change_me"` и `"password"` в seeds/*.

2. **IDOR на GET-by-id**: расширенный scope — `update` и `delete` роутеров тоже использовали `require_role` без UserContext. Паттерн роутера с `get_current_user + if role not in ROLES: raise` должен быть закреплён в шаблоне CRUD в `departments/backend.md` как обязательный для всех non-list методов.

3. **Тест-assertion принимающий две версии исхода** (`assert resp.status_code in (404, 200)`): нарушение принципа "тест — это спецификация". Такой assertion пропускает IDOR в CI. Рекомендация: в чек-лист самопроверки добавить: «Тест безопасности должен принимать ровно один корректный HTTP-статус».

---

## Бэклог P2/Nit (внесён в project_tasks_log.md)

- P2-1: `backend/tests/conftest.py` — вынести фикстуры из `backend/conftest.py`
- P2-2: Аудит Update-схем на защиту company_id от подмены через PATCH
- P2-3: SAVEPOINT в seed-шагах multi_company_foundation
- P2-4: `float` в нормализации company_ids в `deps.py:117`
- Nit-1: Обоснование `# type: ignore` в `company_scoped.py:73`
- Nit-2: Унификация фильтра `is_archived` в ProjectService

---

## Готовность к reviewer round 2

- ruff check: 0 ошибок
- lint_migrations: OK (warning только в существующей миграции)
- Синтаксис всех 15 изменённых файлов: OK
- pytest: не прогонялся локально (нет тестовой БД) — CI gate обязателен
- round-trip миграции: не прогонялся локально — CI gate обязателен
- Все P0 и P1 из ревью устранены
- Дополнительно: update/delete во всех 4 роутерах тоже защищены (расширенный scope по п.3 риск-анализа)

**Готово к финальному вердикту Директора и reviewer round 2.**
