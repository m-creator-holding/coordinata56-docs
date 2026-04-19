# Code Review Round 2: PR #1 Wave 1 — Multi-Company Foundation

**Дата**: 2026-04-18
**Ревьюер**: reviewer (субагент)
**Round**: 2 (после fix от backend-head)
**Базовый ревью**: `pr1-wave1-multicompany-pre-commit-review.md`
**Fix-отчёт**: `pr1-wave1-multicompany-round-1-head-review.md`
**Staged diff**: +2142 / −221, 47 файлов

---

## ВЕРДИКТ: approve (условный — с одним P2 в бэклог)

Все P0 и P1 из round-1 закрыты корректно. Новых блокеров в diff не обнаружено.
Одно новое замечание P2-5 (не блокер, добавить в бэклог).

---

## Статус P0/P1 из round-1

### P0-1: IDOR — ЗАКРЫТ

Верификация цепочки:

**Роутер** (`api/projects.py:105`, `api/payments.py:151`, `api/contracts.py`, `api/contractors.py`)
- GET-by-id, PATCH, DELETE переведены с `Depends(require_role)` на `Depends(get_current_user)`, возвращающий `tuple[User, UserContext]`.
- `user_context` передаётся в сервисные методы.

**Сервис** (`services/project.py:93-110`, `services/payment.py:131-151`, `services/contract.py:130-148`, `services/contractor.py:92-110`)
- Все методы `get()`, `update()`, `delete()` принимают `user_context: UserContext | None = None`.
- При `user_context is not None` вызывают `_scoped_query_conditions(user_context)`, получают `[Model.company_id == user_context.company_id]` (или `[]` для holding_owner).
- Передают условия через `extra_conditions` в `get_or_404`.

**`BaseService.get_or_404`** (`services/base.py:35-62`)
- При наличии `extra_conditions` использует `repo.get_by_id_scoped` вместо `session.get`.

**`BaseRepository.get_by_id_scoped`** (`repositories/base.py:45-69`)
- `SELECT ... WHERE id=? AND <conditions>` — фильтр применяется на уровне SQL, не в Python.
- При пустом `extra_conditions` (`[]`) — оба варианта (`if extra_conditions:`) не применяют предикат: `[]` является falsy в Python, поэтому метод корректно деградирует до полного lookup для holding_owner.

**PaymentService** (`services/payment.py`)
- `approve()` (строка 344) и `reject()` (строка 432) вызывают `self.get(payment_id, user_context=user_context)` — IDOR-защита применена и на action-эндпоинтах, как требовал брифинг.

**Тест 7** (`tests/test_company_scope.py:439-480`)
- Assertion: `assert resp.status_code == 404` — строгий.
- Добавлена проверка `"error" in body`.

**Тесты 7b, 7c, 7d, 7e** (`tests/test_company_scope.py:488-670`)
- 7b: GET /projects/{id} cross-company → 404. Покрывает ProjectService.get().
- 7c: GET /contractors/{id} cross-company → 404. Покрывает ContractorService.get().
- 7d: GET /payments/{id} cross-company → 404. Покрывает PaymentService.get().
- 7e: owner без флага и с пустым company_ids не получает bypass. Фиксирует P1-1.

P0-1 закрыт полностью.

---

### P0-2: Литеральный пароль — ЗАКРЫТ

`seeds.py:331-345` — логика трёхуровневая:
1. `OWNER_INITIAL_PASSWORD` установлен → использовать.
2. `SEEDS_ALLOW_RANDOM_OWNER_PASSWORD=1` → `secrets.token_urlsafe(16)` + предупреждение в `stderr`.
3. Иначе → `RuntimeError` с объяснением.

`"change_me_on_first_login"` отсутствует в файле.
`seeds.py:352` — `is_holding_owner=True` проставлен seed-owner при создании.

P0-2 закрыт.

---

### P1-1: is_holding_owner — ЗАКРЫТ

**Модель** (`models/user.py:27-29`): поле `is_holding_owner: Mapped[bool]` с `nullable=False, server_default="false", default=False`.

**`auth.py:127`**: `is_holding_owner = bool(user.is_holding_owner)` — читается из БД-поля.

**Миграция** (`2026_04_18_1000_c34c3b715bcb_users_is_holding_owner.py`):
- Шаг 1: ADD COLUMN nullable.
- Шаг 2: `UPDATE users SET is_holding_owner = false` — нейтральный бэкфилл.
- Шаг 3: `UPDATE ... WHERE role = 'owner' AND id NOT IN (SELECT DISTINCT user_id FROM user_company_roles)` — воспроизводит прежнюю логику однократно для боевых данных.
- Шаг 4: `ALTER COLUMN ... NOT NULL` — safe, все строки заполнены.
- Оба `op.execute` маркированы комментарием `migration-exception`.
- Downgrade: `DROP COLUMN` — корректен, обратим.

Замечание по backfill-логике: шаг 3 воспроизводит старую хрупкую логику (`len(company_ids) == 0`) единожды при миграции. Это приемлемо как однократная bootstrapping-операция — задокументировано в заголовке файла. Для будущих owner-пользователей флаг должен проставляться явно через admin-endpoint или seeds (уже сделано для seeds).

P1-1 закрыт.

---

## Новые замечания в round-2 diff

### P2-5: Хардкод `created_by_user_id=1` в тестовой фикстуре (major)

**Файл**: `backend/tests/test_company_scope.py:574`

```python
created_by_user_id=1,
```

Фикстура `payment_c1` создаёт Payment с жёсткой ссылкой на user_id=1. Если в тестовой БД пользователя с id=1 нет (тест использует rollback-транзакцию, seed не запускается), то либо нарушается FK-ограничение, либо тест проходит случайно потому что FK отключён. Даже если FK нет — это семантически неверно: `created_by_user_id` должен ссылаться на реально созданного пользователя из фикстуры, а не на магическое число.

Правильный вариант: использовать id пользователя из фикстуры `company1` или создать пользователя в фикстуре и передать его id.

Блокером не является: тест покрывает именно IDOR по company-scope, и user_id в Payment не влияет на company-scope предикат. Но нарушает принцип «тестовые данные — не литералы» (CLAUDE.md §«Секреты и тесты»).

**Приоритет**: P2 (major). Добавить в бэклог к P2-1/P2-4.

---

### Nit-1: Тест 7e — мягкая проверка статуса

**Файл**: `backend/tests/test_company_scope.py:660-669`

```python
if resp.status_code == 200:
    ids = [p["id"] for p in resp.json()["items"]]
    assert project_c1.id not in ids, ...
else:
    assert resp.status_code in (400, 403), ...
```

Тест допускает три исхода: 200, 400, 403. Семантически это верно (поведение зависит от того, как deps обрабатывает пустой company_ids без is_holding_owner), однако тест не является детерминированной спецификацией: он принимает разные HTTP-статусы без фиксации ожидаемого. Для security-теста лучше знать точно, какой статус ожидается, и зафиксировать его. Но это не блокер — логика защиты верна в обоих вариантах.

**Приоритет**: nit.

---

## Дополнительные проверки

### Backward compat JWT

`deps.py:123-124`: если `company_ids` из JWT пустые, но в БД есть `UserCompanyRole` — пересобирается из БД. Это сохраняет совместимость со старыми токенами. Риска нет — обратная совместимость задокументирована в комментарии.

### ADR 0004 Amendment (предикаты в сервисе, запросы в репозитории)

- `_scoped_query_conditions` в `CompanyScopedService` формирует `ColumnElement` предикаты, не выполняет запросов.
- `BaseRepository.get_by_id_scoped` выполняет запрос с переданными предикатами.
- Граница соблюдена: сервис — логика, репозиторий — SQL. ADR 0004 Amendment соответствует.

### ADR 0013 (expand-pattern)

Миграция `c34c3b715bcb` корректно следует паттерну: nullable → backfill → NOT NULL. Downgrade — DROP COLUMN. Round-trip обоснован в заголовке миграции. Оба `op.execute` маркированы исключением.

### OWASP A01 (Broken Access Control)

- Все GET-by-id, PATCH, DELETE на мультикомпанийных сущностях получают user_context.
- `_scoped_query_conditions` при `is_holding_owner=True` возвращает `[]` — bypass без SQL-условий. Это корректное поведение для суперадмина.
- Критичный путь: пользователь без is_holding_owner и без company_id (active_company_id=None) попадёт в `_scoped_query_conditions` с `user_context.company_id=None`, что создаёт предикат `Model.company_id == None` — фактически `WHERE company_id IS NULL`. Это не откроет чужие данные, но может вернуть пустой результат или записи без company_id. Для данной схемы, где company_id всегда заполнен, риска нет. Но если когда-либо появятся записи с company_id=NULL, поведение станет неожиданным. Задокументировать в ADR 0011 как допущение (nit).

### OWASP A02 (Secrets)

- `seeds.py`: литерал удалён, `secrets.token_urlsafe` используется корректно.
- `test_company_scope.py`: пароли через `secrets.token_urlsafe(16)`. Исключение: `created_by_user_id=1` (см. P2-5).

---

## Сводная таблица round-2

| ID | Приоритет | Файл | Строка | Суть |
|---|---|---|---|---|
| P0-1 | ЗАКРЫТ | 4 сервиса + BaseRepo + тесты | — | IDOR: get_by_id_scoped с company-scope |
| P0-2 | ЗАКРЫТ | `seeds.py` | 331-345 | RuntimeError + secrets.token_urlsafe |
| P1-1 | ЗАКРЫТ | `auth.py` + миграция + модель | 127 | is_holding_owner из БД-поля |
| P2-5 | P2 (new) | `tests/test_company_scope.py` | 574 | `created_by_user_id=1` — хардкод user_id |
| Nit-1 | nit (new) | `tests/test_company_scope.py` | 660-669 | Тест 7e принимает 3 исхода (400/403/200) |

P2-1, P2-2, P2-3, P2-4, Nit-1 (round-1) — перенесены в бэклог backend-head, статус не изменился.

---

## Итог

Round-1 fix выполнен корректно и полностью. Новый P2 (хардкод user_id в тесте) не блокирует коммит — добавить в бэклог. CI gate (pytest + round-trip миграции) обязателен перед мержем.

**APPROVE** с условием: CI gate зелёный.

---

*Ревью выполнено на staged diff. Reviewer не вносит правок в код.*
