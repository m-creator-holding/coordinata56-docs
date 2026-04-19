# PR #1 Волны 1 Multi-Company Foundation — Fix Round 1

**От:** backend-director
**Кому:** backend-head (распределить на backend-dev)
**Статус:** request-changes по reviewer, сборка заблокирована до устранения P0
**Scope:** 5 пунктов из отчёта reviewer (2 P0 + 1 P1 + 2 P1-смежных) в текущем раунде. P2/Nit — в бэклог (см. §«Бэклог» в конце).
**Источники правды:**
- `/root/coordinata56/docs/reviews/pr1-wave1-multicompany-pre-commit-review.md`
- `/root/coordinata56/docs/adr/0011-multi-company-architecture.md` §1.3, §2.4
- `/root/coordinata56/docs/agents/departments/backend.md` (обязательно для сотрудника)
- `/root/coordinata56/CLAUDE.md`

---

## Цель раунда

1. Устранить **IDOR на GET-by-id** по всем мультикомпанийным сервисам (P0-1 + P1-2 — это одна и та же проблема на двух слоях).
2. Убрать **литеральный пароль** из `seeds.py` (P0-2).
3. Сделать `is_holding_owner` **явным флагом модели `User`** вместо косвенного вывода (P1-1).
4. Переписать **тест 7 в `test_company_scope.py`** со строгим assertion + добавить IDOR-тесты на остальные сущности (P1-3 + расширение покрытия).
5. Локально убедиться: `pytest` зелёный, `ruff check` чисто, migration round-trip проходит.

**Reviewer round 2** после устранения должен дать **approve**.

---

## Scope round-1 (что фиксим сейчас)

| ID | Приоритет | Сделать | Не делать |
|---|---|---|---|
| P0-1 + P1-2 | P0 | IDOR-фикс через `get_by_id_scoped` + проброс `user_context` в `get()` сервиса и в GET-by-id роутер | Не менять контракт `get_or_404` в `BaseService` |
| P0-2 | P0 | `seeds.py` читает `OWNER_INITIAL_PASSWORD` из env, fallback только `secrets.token_urlsafe(16)` с логом в stderr при явном `SEEDS_ALLOW_RANDOM_OWNER_PASSWORD=1` | Не менять идемпотентность `_upsert_owner` |
| P1-1 | P1 | Колонка `users.is_holding_owner BOOLEAN NOT NULL DEFAULT false` через safe-migration + новая alembic-миграция **вторым файлом Волны 1** (после multi_company_foundation). `auth.py` читает `user.is_holding_owner`, не вычисляет из пустого `company_ids`. | Не трогать `role` поле (deprecated, остаётся) |
| P1-3 | P1 | Тест 7 → `assert resp.status_code == 404`. Добавить аналогичные IDOR-тесты на projects, payments, contractors (минимум по одному). | Не удалять/не переименовывать существующие тесты 1-6, 8 |
| Бэклог | P2/Nit | См. §«Бэклог» — в `project_tasks_log.md`, отдельной задачей | В этом раунде не трогать |

---

## Порядок выполнения (обязательная последовательность)

### Шаг 1. Миграция `is_holding_owner` (safe-migration, ADR 0013)

**Файл:** `backend/alembic/versions/2026_04_18_1000_<hash>_users_is_holding_owner.py` (второй файл миграций Волны 1 — после multi_company_foundation)

**Revision chain:** `down_revision = "f7e8d9c0b1a2"` (multi_company_foundation).

**Паттерн expand (см. ADR 0013):**
1. `op.add_column("users", sa.Column("is_holding_owner", sa.Boolean(), nullable=True))`
2. `op.execute(sa.text("UPDATE users SET is_holding_owner = false"))` — все false по умолчанию.
3. `op.execute(sa.text("UPDATE users SET is_holding_owner = true WHERE role = 'owner' AND id NOT IN (SELECT DISTINCT user_id FROM user_company_roles)"))` — существующие owner-ы без привязки к компании получают флаг, воспроизводя прежнюю логику `auth.py:127` **один раз при миграции**, чтобы не ломать боевые данные.
4. `op.alter_column("users", "is_holding_owner", nullable=False, server_default=sa.false())`

**Downgrade:** `op.drop_column("users", "is_holding_owner")`.

**Маркеры:**
- `# migration-exception: op_execute — backfill flag from deprecated implicit rule`

**Проверки:**
- Round-trip: `alembic upgrade head && alembic downgrade -1 && alembic upgrade head` — зелёный.
- `python -m tools.lint_migrations alembic/versions/` — чисто.

### Шаг 2. Модель `User`

**Файл:** `backend/app/models/user.py`

Добавить поле:
```python
is_holding_owner: Mapped[bool] = mapped_column(
    Boolean, nullable=False, server_default="false", default=False
)
```

### Шаг 3. Фикс `auth.py` (P1-1)

**Файл:** `backend/app/api/auth.py:127`

Заменить:
```python
is_holding_owner = user.role == UserRole.OWNER and len(company_ids) == 0
```

на:
```python
is_holding_owner = bool(user.is_holding_owner)
```

**Nuance:** условие `len(company_ids) == 0` больше не влияет на определение holding_owner — это чисто флаг из БД.

### Шаг 4. Фикс IDOR в репозитории (P0-1)

**Файл:** `backend/app/repositories/base.py`

Добавить метод в `BaseRepository`:
```python
async def get_by_id_scoped(
    self,
    entity_id: int,
    extra_conditions: list[ColumnElement[bool]] | None = None,
) -> ModelT | None:
    """Возвращает запись по id с дополнительными SQL-условиями (WHERE id=? AND ...).

    Используется для company-scope фильтрации на уровне одиночного lookup.
    При пустом extra_conditions эквивалентен get_by_id.
    """
    stmt = select(self.model).where(self.model.id == entity_id)  # type: ignore[attr-defined]
    if extra_conditions:
        for cond in extra_conditions:
            stmt = stmt.where(cond)
    result = await self.session.execute(stmt)
    return result.scalar_one_or_none()
```

### Шаг 5. Фикс IDOR в `BaseService.get_or_404` (P0-1)

**Файл:** `backend/app/services/base.py`

Расширить сигнатуру `get_or_404`:
```python
async def get_or_404(
    self,
    entity_id: int,
    extra_conditions: list[ColumnElement[bool]] | None = None,
) -> ModelT:
    raw = await self.repo.get_by_id_scoped(entity_id, extra_conditions=extra_conditions)
    if raw is None or getattr(raw, "deleted_at", None) is not None:
        raise NotFoundError(self.entity_name, entity_id)
    return cast("ModelT", raw)
```

**Import:** `from sqlalchemy import ColumnElement`.

**Обратная совместимость:** все существующие вызовы `get_or_404(id)` работают без изменений (extra_conditions=None → без фильтра, эквивалент старому поведению).

### Шаг 6. Фикс IDOR в сервисах (P0-1) — 4 файла

**Файлы:**
- `backend/app/services/project.py:90`
- `backend/app/services/contract.py:128`
- `backend/app/services/payment.py:129`
- `backend/app/services/contractor.py:90`

**Паттерн для всех четырёх:**

```python
async def get(self, entity_id: int, user_context: UserContext | None = None) -> Model:
    extra_conditions: list[ColumnElement[bool]] = []
    if user_context is not None:
        extra_conditions.extend(await self._scoped_query_conditions(user_context))
    return await self.get_or_404(entity_id, extra_conditions=extra_conditions or None)
```

**Для payment.py** (у него ручная реализация `get` без `get_or_404`, см. строки 129-142) — переписать на такой же паттерн через `get_or_404`. Убрать прямой `self.repo.get_by_id(payment_id)`.

**Правила отдела (см. `departments/backend.md` §1 и Amendment 2026-04-18):**
- Предикаты `Model.company_id == user_context.company_id` формируются в сервисе и передаются в репозиторий. Сервис **не** делает `.execute()`, `.select()`, `.get(Model, id)`.
- `_scoped_query_conditions` в `CompanyScopedService` уже возвращает нужный список — переиспользовать его.

### Шаг 7. Фикс IDOR в роутерах GET-by-id (P1-2) — 4 файла

**Файлы:**
- `backend/app/api/projects.py` (get_project)
- `backend/app/api/contracts.py:141-158` (get_contract)
- `backend/app/api/payments.py:148-165` (get_payment)
- `backend/app/api/contractors.py` (get_contractor)

**Паттерн:**

Заменить сигнатуру:
```python
async def get_X(
    x_id: int,
    db: AsyncSession = Depends(get_db),
    _current_user: User = Depends(require_role(*_READ_ROLES)),
) -> XRead:
```

на:
```python
async def get_X(
    x_id: int,
    db: AsyncSession = Depends(get_db),
    user_pair: tuple[User, UserContext] = Depends(get_current_user),
) -> XRead:
    current_user, user_context = user_pair
    if current_user.role not in _READ_ROLES:
        raise PermissionDeniedError("Недостаточно прав")
    service = _make_service(db)
    obj = await service.get(x_id, user_context=user_context)
    return XRead.model_validate(obj)
```

**Важно:** раскрытие 404 (не 403) при cross-company запросе — это фича, не баг. Reviewer и ADR 0011 §1.3 явно требуют: не раскрывай существование чужого ресурса. В тесте 7 — проверить именно 404.

**Смежные проверки:** убедись, что другие методы роутера (GET-list, POST, PATCH, DELETE) уже используют `get_current_user` с `UserContext` (listings точно используют — см. `contracts.py:82`). Если где-то ещё остался `require_role` для путей, которые должны фильтроваться по company — задокументируй в отчёте, но в этот раунд не меняй (кроме P0 GET-by-id).

### Шаг 8. Фикс литерального пароля (P0-2)

**Файл:** `backend/app/db/seeds.py:322-336`

Заменить функцию `_upsert_owner`:

```python
def _upsert_owner(db: Session) -> User:
    existing = db.scalar(select(User).where(User.email == "martin@coordinata56.local"))
    if existing:
        return existing

    env_password = os.environ.get("OWNER_INITIAL_PASSWORD")
    if env_password:
        password = env_password
    elif os.environ.get("SEEDS_ALLOW_RANDOM_OWNER_PASSWORD") == "1":
        password = secrets.token_urlsafe(16)
        print(
            f"[seeds] WARNING: OWNER_INITIAL_PASSWORD not set; "
            f"generated random password for owner: {password}",
            file=sys.stderr,
        )
    else:
        raise RuntimeError(
            "OWNER_INITIAL_PASSWORD environment variable is required to seed the owner. "
            "Set SEEDS_ALLOW_RANDOM_OWNER_PASSWORD=1 to auto-generate a random password in dev."
        )

    user = User(
        email="martin@coordinata56.local",
        password_hash=_hash_password(password),
        full_name="Мартин (Владелец)",
        role=UserRole.OWNER,
        is_holding_owner=True,  # seed-owner — суперадмин холдинга по определению
        is_active=True,
        last_login_at=None,
    )
    db.add(user)
    db.flush()
    return user
```

**Import:** `import os, sys, secrets`.

**Правило отдела (departments/backend.md §7):** никаких литералов секретов. Это повторяющаяся ошибка — 3-й раз за 2 фазы. В этой задаче — явный fail-fast через RuntimeError.

### Шаг 9. Тесты (P1-3 + покрытие)

**Файл:** `backend/tests/test_company_scope.py`

**Тест 7 — переписать строго:**
```python
@pytest.mark.asyncio
async def test_cross_company_contract_returns_404(...) -> None:
    user, password = await create_user_with_role(db_session, UserRole.OWNER, company2.id)
    token = await _token_for_user(client, user, password)

    resp = await client.get(
        f"/api/v1/contracts/{contract_c1.id}",
        headers={"Authorization": f"Bearer {token}", "X-Company-ID": str(company2.id)},
    )
    assert resp.status_code == 404, (
        f"IDOR: пользователь company2 не должен видеть договор company1, "
        f"получен status={resp.status_code}, body={resp.text}"
    )
    # Проверяем также, что тело ответа не раскрывает существование ресурса
    body = resp.json()
    assert "error" in body

    # В списке договоров company2 чужого договора тоже нет
    list_resp = await client.get(
        "/api/v1/contracts/",
        headers={"Authorization": f"Bearer {token}", "X-Company-ID": str(company2.id)},
    )
    assert list_resp.status_code == 200
    ids = [c["id"] for c in list_resp.json()["items"]]
    assert contract_c1.id not in ids
```

**Добавить 3 новых теста (IDOR на остальных сущностях):**
- `test_cross_company_project_get_by_id_returns_404` — user company2 запрашивает `/api/v1/projects/{project_c1.id}` → 404.
- `test_cross_company_contractor_get_by_id_returns_404` — аналогично для contractor.
- `test_cross_company_payment_get_by_id_returns_404` — создать payment в company1 через fixture, user company2 → 404.

**Добавить 1 тест для P1-1 (is_holding_owner — явный флаг):**
- `test_owner_without_flag_and_empty_company_ids_gets_400` — owner с `is_holding_owner=False`, без UCR, без X-Company-ID → не должен получить bypass. Логика `deps.py` оставит `active_company_id=None`, но `_scoped_query_conditions` добавит `company_id == None` → список будет пустым. Это корректно и безопасно — тест фиксирует, что bypass не происходит.

**Не ломать существующие тесты 1-6, 8** — они используют `create_access_token(..., is_holding_owner=...)` напрямую с явным флагом, никак не завязаны на косвенное вычисление. Проверь:
- Тест 2 (`test_holding_owner_sees_all_companies`) — создаёт User без записи в UCR и выдаёт токен с `is_holding_owner=True`. После миграции `users.is_holding_owner` будет default=False — но **токен приходит с явным True, и `auth.py` читается только при login**; `deps.py:112` берёт флаг из JWT, а не из БД. Тест проходит без изменений. **НО:** если тест делает login через `_token_for_user`, тогда `auth.py` теперь читает `user.is_holding_owner` из БД — и там будет False. Тест 2 использует `create_access_token` напрямую (строка 238) — токен формируется руками, не через /login. **Тест проходит.**
- Тесты 4, 5 — тоже используют `create_access_token` напрямую. Без изменений.
- Тест 6 (require_role deprecated alias) — не зависит от is_holding_owner. Без изменений.

**Осторожно с тестом 3** (`test_payment_inherits_company_id_from_contract`) — после фикса payment.get() через get_or_404 контракт POST не меняется, но убедись, что тест проходит.

---

## FILES_ALLOWED (обязательный список)

```
backend/alembic/versions/2026_04_18_1000_<new_hash>_users_is_holding_owner.py   # новый файл
backend/app/models/user.py
backend/app/api/auth.py
backend/app/api/projects.py
backend/app/api/contracts.py
backend/app/api/payments.py
backend/app/api/contractors.py
backend/app/services/base.py
backend/app/services/project.py
backend/app/services/contract.py
backend/app/services/payment.py
backend/app/services/contractor.py
backend/app/repositories/base.py
backend/app/db/seeds.py
backend/tests/test_company_scope.py
```

## FILES_FORBIDDEN

Всё, что не в FILES_ALLOWED. Особенно:
- `backend/app/services/company_scoped.py` — не трогать, там всё корректно по ADR.
- `backend/app/api/deps.py` — P2-4 (float в company_ids) в бэклог.
- Миграция `2026_04_17_0900_f7e8d9c0b1a2_multi_company_foundation.py` — **не редактировать**. Только добавить новую миграцию поверх.
- Прочие сервисы/роутеры вне списка.

---

## COMMUNICATION_RULES

- Сотрудник читает **обязательно:**
  1. `/root/coordinata56/CLAUDE.md`
  2. `/root/coordinata56/docs/agents/departments/backend.md` — полностью
  3. `/root/coordinata56/docs/adr/0011-multi-company-architecture.md` §1.3, §2.4
  4. `/root/coordinata56/docs/adr/0013-migrations-evolution-contract.md`
  5. `/root/coordinata56/docs/reviews/pr1-wave1-multicompany-pre-commit-review.md`
- Перед сдачей — чек-лист самопроверки из `departments/backend.md` §«Чек-лист самопроверки backend-dev» (все пункты, включая пункт про миграции и round-trip).
- Отчёт backend-head: ≤250 слов, формат `departments/backend.md` §«Шаблон commit-message» адаптированный к отчёту.
- **Git:** только `git add <конкретные файлы из FILES_ALLOWED>`. `git add -A` — запрещён. **Не коммитить** — коммит делает Координатор после reviewer round 2.
- При сомнениях в ADR-трактовке — эскалация backend-head → backend-director, **не молча**.

---

## Definition of Done

1. `pytest backend/tests -q` — **зелёный**, включая новые 4 теста и переписанный тест 7.
2. `ruff check backend/app backend/tests` — **0 ошибок**.
3. `mypy backend/app` (если есть в CI) — не добавляет новых ошибок.
4. `python -m tools.lint_migrations alembic/versions/` — **чисто**, включая новую миграцию.
5. Round-trip миграций: `alembic upgrade head && alembic downgrade -1 && alembic upgrade head` — без ошибок.
6. `git diff --staged` содержит ровно файлы из FILES_ALLOWED, ничего лишнего.
7. **Reviewer round 2** (после head → director) выдаёт **approve** на все 5 пунктов round-1.
8. backend-head подтверждает, что правило отдела №1 (предикаты в сервисе, запросы в репозитории) соблюдено во всех 4 сервисах.

---

## Бэклог (не в этом раунде — в `project_tasks_log.md`)

- **P2-1** — вынести `create_user_with_role` в `backend/tests/conftest.py`. Задача для отдела бэкенда отдельным PR.
- **P2-2** — проверить, что `PaymentUpdate` и другие Update-схемы не допускают подмену `company_id` через PATCH. Провести аудит всех Update-схем.
- **P2-3** — явный SAVEPOINT в seed-миграции multi_company_foundation. Низкий риск, в бэклог.
- **P2-4** — убрать `float` из приёма `company_ids` в `deps.py:117`, оставить только `int`.
- **Nit-1** — обоснование `# type: ignore` в `company_scoped.py:73`.
- **Nit-2** — унификация фильтра `is_archived` в `ProjectService.list`.

Координатор занесёт эти пункты в `project_tasks_log.md` как P2-BACKLOG после успешного коммита round-1.

---

## Риск-анализ (что может сломаться)

1. **Тест 2 `test_holding_owner_sees_all_companies`:** создаёт User без записи в БД `is_holding_owner=True`. После миграции поле default=False в БД, но тест формирует JWT **вручную** с `is_holding_owner=True` (строка 238), и `deps.py:112` читает флаг из JWT. **Безопасно.**
2. **Тест 4 `test_x_company_id_header_selects_company`:** аналогично — JWT вручную, не через login. **Безопасно.**
3. **Обратная совместимость `get_or_404`:** новая сигнатура с `extra_conditions=None` по умолчанию — все старые вызовы работают. Но **проверь** все 4 сервиса: после изменения `get()` сигнатуры все вызовы `service.get(id)` в других сервисах (если есть) надо посмотреть. В `update`/`delete` сервисов используется `self.get_or_404(id)` — не `self.get(id)` — поэтому они продолжат работать без company-scope фильтрации на update/delete. **Это отдельная проблема** (обновить/удалить можно чужой объект, если угадан id): её фиксим в round-1 или эскалируем?
   - **Решение:** **фиксим в round-1**, потому что это та же IDOR-уязвимость. В сервисах `update`/`delete` методах добавить `user_context` параметр и при вычислении `get_or_404` передавать `extra_conditions` из `_scoped_query_conditions`. Роутеры `update`/`delete` уже используют `get_current_user` (с UserContext) — проверить и при необходимости пробросить.
   - **Конкретно проверить в роутерах:** `update_contract` (строка 233), `delete_contract` (строка 286) — они используют `require_role(*_WRITE_ROLES)`, не `get_current_user`. **Это тоже IDOR.** Меняем на `get_current_user` + явная проверка роли, аналогично GET-by-id. Аналогично для projects, payments, contractors.
   - **Обновлённая формулировка P1-2:** применяется ко всем non-list методам (GET-by-id, PATCH, DELETE, action-endpoints типа /approve, /reject). **Сотрудник должен** применить паттерн «get_current_user + проверка роли + service.X(id, user_context=user_context)» ко всем таким методам в 4 роутерах.
4. **Alembic round-trip:** новая миграция `2026_04_18_1000` в даунгрейде удаляет колонку — round-trip восстанавливает состояние до неё. Убедиться, что тесты (которые могут уже рассчитывать на колонку) прогоняются на upgrade head, а не на промежуточных состояниях.
5. **seeds.py:** если CI/dev-bootstrap полагается на идемпотентный seed без env-переменной — **сломается**. Требуется: обновить инструкцию запуска (`.env.example`, README dev-секция, docker-compose), добавить `OWNER_INITIAL_PASSWORD` или флаг `SEEDS_ALLOW_RANDOM_OWNER_PASSWORD=1` для dev. backend-head — проверь и задокументируй в отчёте, какие скрипты затронуты.

---

## Шаблон отчёта backend-head → backend-director

```
Round 1 fix PR#1 Wave 1 — выполнено

Миграция: <hash> users_is_holding_owner, round-trip OK, линтер OK.
Модель/auth/router: 4 роутера обновлены на get_current_user + UserContext,
service.get(id, user_context=...) пробрасывает company-фильтр на уровень SQL
через get_by_id_scoped. Дополнительно: update/delete тоже провалидированы на
IDOR — см. п.3 риск-анализа.

Seeds: литерал убран, env-driven + fallback для dev через флаг.

Тесты: test_7 переписан на assert == 404, +3 IDOR-теста на projects/contractors/payments,
+1 тест на is_holding_owner-флаг. Всего 12 тестов в test_company_scope.py, все зелёные.

Линтер: ruff clean. Round-trip: OK. lint-migrations: OK.

Готово к reviewer round 2.
```
