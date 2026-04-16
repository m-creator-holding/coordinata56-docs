# Code Review — Phase 3, Batch A, Step 4
**Дата:** 2026-04-15
**Ревьюер:** reviewer (субагент)
**Scope:** Stage, HouseType, OptionCatalog, House + sub-resources (21 staged файл)
**Вердикт Round 1:** `request-changes`

---

## Сводная таблица замечаний

| # | Приоритет | Файл | Суть |
|---|---|---|---|
| 1 | P0 (BLOCKER) | `backend/app/services/house.py:459-462` | ADR 0004 MUST: `select` и `session.execute` в сервисном слое |
| 2 | P0 (BLOCKER) | `backend/tests/test_auth.py:107,122` | CLAUDE.md + регламент v1.3 §3: literal-пароли в фикстурах |
| 3 | P1 (MAJOR) | `backend/app/services/house.py:496-530`, `api/houses.py:391-409,425-437` | OWASP A01 / IDOR: `house_id` из URL не проверяется при PATCH/DELETE конфигурации |
| 4 | P1 (MAJOR) | `backend/tests/test_houses.py` | Матрица RBAC: нет теста `read_only` на 403 для House write-эндпоинтов; нет теста construction_manager на DELETE house (должен 403) |
| 5 | P2 | `backend/app/services/house.py:452` | Косметика: lazy `from app.models.house import OptionCatalog` внутри метода — стиль; должно быть на уровне модуля |
| 6 | P2 | `backend/tests/test_auth.py` (весь файл) | CLAUDE.md §3: фикстуры используют literal-пароли (`"correct_password_123"`, `"accountant_password_123"` и т.д.); файл создан ДО правила но не исправлен в этом шаге |
| 7 | P2 | `backend/app/services/house.py:308` | Бизнес-правило: переход на ту же стадию (`new_stage.order_index == current_stage.order_index`) запрещён — логика верна, но check'а `new_stage_id == house.current_stage_id` нет явно; тест на self-transition отсутствует |
| 8 | P3 (NIT) | `backend/app/repositories/stage.py:65` | `except Exception: # noqa: BLE001` без logging — проглатывает ошибки тихо; должен хотя бы `logger.debug` |

---

## P0 — BLOCKER

### P0-1: ADR 0004 MUST нарушен — SQLAlchemy в сервисном слое

**Файл:** `backend/app/services/house.py`, строки 459–462

```python
# В методе HouseConfigurationService.create():
from sqlalchemy import select
option_result = await self.house_repo.session.execute(
    select(OptionCatalog).where(OptionCatalog.id == data.option_id)
)
```

**Почему P0:** ADR 0004 §MUST п.1 формулирует явный запрет: «SQLAlchemy-запросы пишутся **только** в `repositories/`. Ни роутер, ни сервис не импортируют `select`, `insert`, `update`». Это не advisory, это «MUST» по тексту ADR.

Кроме того, сервис обращается к `self.house_repo.session` напрямую — грубое нарушение инкапсуляции: сессия репозитория является деталью реализации и не должна быть доступна снаружи.

**Причина:** `HouseConfigurationService.__init__` не принимает `OptionCatalogRepository` в аргументах. Разработчик обошёл это через прямой SQL в сервисе вместо того, чтобы добавить репозиторий в конструктор.

**Требуемый фикс:**
1. Добавить `option_repo: OptionCatalogRepository` в `__init__` `HouseConfigurationService`.
2. Убрать `from sqlalchemy import select` и `self.house_repo.session.execute(...)` из сервисного метода.
3. Использовать `await self.option_repo.get_by_id(data.option_id)`.
4. Обновить `_make_cfg_service()` в `api/houses.py`: передать `OptionCatalogRepository(db)`.

---

### P0-2: Literal-пароли в `test_auth.py` — нарушение CLAUDE.md §3

**Файл:** `backend/tests/test_auth.py`, строки 107, 122 (фикстуры) + 137, 150, 169, 190, 211, 280, 299, 324, 336 и далее

```python
# Строки 107, 122 — фикстуры:
password_hash=hash_password("correct_password_123"),
password_hash=hash_password("accountant_password_123"),

# Строки 137, 169 — тела запросов:
json={"email": "test_owner@example.com", "password": "correct_password_123"},
```

**Почему P0:** CLAUDE.md гласит: «Повторяющаяся ошибка: Phase 2 Round 2 BLOCKER-1, Phase 3 Batch A step 2 Round 1 P0-2». Правило зафиксировано повторно именно потому, что было поймано дважды и снова не исправлено. `test_auth.py` существовал до этого шага, но:

1. Файл включён в `git diff --staged` этого батча (51 «старых» тестов — именно они и есть регрессии, которые нужно было привести в соответствие правилу перед коммитом).
2. Регламент v1.3 §3 требует проверки всех тест-файлов в области staged изменений.

Если `test_auth.py` не менялся в этом шаге, ревьюер обязан эскалировать: файл содержит нарушение, которое должно быть закрыто до закрытия батча, поскольку мини-DoD требует соответствия CLAUDE.md по всем тест-файлам.

**Требуемый фикс:** Переписать все `password_hash=hash_password("...")` в фикстурах на `secrets.token_urlsafe(16)` с сохранением пароля в переменную. Переписать `json={"password": literal}` в запросах на переменные из фикстур.

---

## P1 — MAJOR

### P1-1: IDOR — `house_id` из URL не верифицируется при PATCH/DELETE конфигурации

**Файлы:**
- `backend/app/services/house.py`, методы `HouseConfigurationService.update` (строка 496) и `delete` (строка 532)
- `backend/app/api/houses.py`, эндпоинты `PATCH /{house_id}/configurations/{cfg_id}` и `DELETE /{house_id}/configurations/{cfg_id}`

**Суть:**

Эндпоинты принимают два параметра пути: `house_id` и `cfg_id`. Однако сервисный метод `update(cfg_id, ...)` и `delete(cfg_id, ...)` **не проверяют, что `cfg.house_id == house_id`**. Это означает:

- Пользователь отправляет `PATCH /api/v1/houses/42/configurations/99` — реально конфигурация 99 принадлежит дому 1, а не 42.
- Сервис выполняет `await self.get(cfg_id)` — находит запись (она существует) — применяет изменение.
- Конфигурация дома другого пользователя/проекта изменена без авторизации на конкретный дом.

**Это OWASP A01:2021 — Broken Access Control / IDOR (Insecure Direct Object Reference).**

Проверка аутентификации и роли есть (owner/construction_manager), но нет проверки принадлежности ресурса.

**Требуемый фикс в сервисе:**

```python
async def update(self, house_id: int, cfg_id: int, ...) -> HouseConfiguration:
    cfg = await self.get(cfg_id)
    if cfg.house_id != house_id:
        raise NotFoundError("HouseConfiguration", cfg_id)  # или PermissionDeniedError
    ...
```

Аналогично для `delete`. Параметр `house_id` должен передаваться из роутера в оба метода.

**Тест:** добавить тест `test_update_configuration_wrong_house_id_404`.

---

### P1-2: Матрица RBAC неполная — отсутствуют тесты для `read_only` на House

**Файл:** `backend/tests/test_houses.py`

**Мини-DoD батча** требует: «RBAC: каждый write-эндпоинт имеет зависимость `require_role(...)` и тест на 403 от чужой роли».

Выявленные пробелы:

| Эндпоинт | Роль | Тест |
|---|---|---|
| `POST /houses` | `read_only` → 403 | Отсутствует |
| `POST /houses/bulk` | `read_only` → 403 | Отсутствует |
| `PATCH /houses/{id}` | `read_only` → 403 | Отсутствует |
| `PATCH /houses/{id}/stage` | `read_only` → 403 | Отсутствует |
| `DELETE /houses/{id}` | `construction_manager` → 403 | Присутствует ✓ |
| `POST /houses/{id}/configurations` | `read_only` → 403 | Отсутствует |
| `PATCH /configurations/{cfg_id}` | `read_only` → 403 | Отсутствует |
| `DELETE /configurations/{cfg_id}` | `read_only` → 403 | Отсутствует |

Нет фикстуры `read_only_user`/`read_only_token` в `test_houses.py`. В `test_house_types.py` такая фикстура есть.

---

## P2 — MAJOR (рекомендательно)

### P2-1: Lazy import внутри метода нарушает стиль

**Файл:** `backend/app/services/house.py`, строка 452

```python
from app.models.house import OptionCatalog
```

Это внутри метода `HouseConfigurationService.create()`. Сам импорт безвреден технически, но фактически стал следствием P0-1: если бы был `OptionCatalogRepository`, нужда в нём исчезла бы. После фикса P0-1 эта строка удаляется автоматически.

### P2-2: Тест на self-transition (переход на текущую стадию) отсутствует

**Файл:** `backend/app/services/house.py`, строка 308

Условие `new_stage.order_index <= current_stage.order_index` корректно запрещает переход на текущую стадию (равенство) — это хорошо. Однако тест явно не проверяет сценарий «stage_id == house.current_stage_id → 409». Тест `test_change_stage_backward_409` проверяет только движение назад.

Добавить тест `test_change_stage_same_stage_409`.

---

## P3 — NIT

### P3-1: Silent exception в `StageRepository.has_references`

**Файл:** `backend/app/repositories/stage.py`, строки 57–67

```python
except Exception:  # noqa: BLE001
    # На случай если таблица budget_plans ещё не существует в БД
    pass
```

Проглатывание любого исключения без логирования скрывает ошибки. Добавить хотя бы `logger.debug("BudgetPlan reference check skipped: %s", exc)`. `# noqa: BLE001` оправдан, но необходим комментарий с датой возврата: «удалить когда Батч B создаст таблицу budget_plans».

---

## Проверка по чек-листам (прошедшие)

### CLAUDE.md — фильтры (P0-1 из прошлых ревью)

`HouseRepository.list_paginated_filtered()` — все 4 фильтра в `WHERE` на уровне SQL, `COUNT` строится из `base_stmt.subquery()` до применения `OFFSET/LIMIT`. Правило соблюдено.

`HouseStageHistoryRepository.list_for_house()` — `COUNT` из `base_stmt.subquery()`, фильтр `house_id` в WHERE. Правило соблюдено.

### ADR 0005 — формат ошибок

`main.py`: три exception_handler зарегистрированы для `HTTPException`, `AppError`, `RequestValidationError` и `Exception`. Все возвращают `{"error": {"code", "message", "details"}}`. Тесты ассертят `resp.json()["error"]["code"]`. Соответствие полное.

### ADR 0006 — пагинация

`GET /houses`, `GET /stages`, `GET /house-types`, `GET /option-catalog`, `GET /houses/{id}/stage-history` — все возвращают `ListEnvelope` с `items/total/offset/limit`. Лимит 200 через `PaginationParams` в `pagination.py`. Соответствие полное.

`POST /houses/bulk` — лимит 200 через `max_length=200` в Pydantic (`HouseBulkCreate`). Тест на 422 при 201 элементе присутствует. Правило соблюдено.

### ADR 0007 — аудит-лог

Все write-методы в `StageService`, `HouseTypeService`, `OptionCatalogService`, `HouseService`, `HouseConfigurationService` содержат явный вызов `await self.audit.log(...)`. Транзакционность обеспечена: `audit.log()` делает `session.flush()` в той же сессии, `db.commit()` — в роутере после. Аудит bulk-create: одна запись с `{"bulk_created": N, "house_ids": [...]}` — решение задокументировано в комментарии сервиса. Diff before/after в `set_compatible_options` использует `sorted(list)` — детерминированный порядок. Аудит соответствует ADR 0007.

`locked_price_cents`/`locked_cost_cents` при `HouseConfiguration.create` — копируются из `OptionCatalog.price_cents`/`cost_cents` на момент создания и попадают в `_cfg_to_dict(cfg)` в `changes["after"]`. Зафиксированы в аудите.

### ADR 0004 — трёхслойная архитектура

За исключением P0-1 (`select` в сервисе), все остальные сервисы корректно делегируют SQLAlchemy-запросы в репозиторий. `_make_service()` / `_make_house_service()` / `_make_cfg_service()` — паттерн Amendment ADR 0004 соблюдён. Роутеры не импортируют `select`/`insert`.

### OWASP A03 — Injection

Все запросы — через ORM (`select(Model).where(...)`). Нет f-string сборки SQL. `Pydantic`-валидация на границе HTTP присутствует. SQL-инъекции исключены.

### OWASP A02 — Cryptographic Failures

Пароли в `test_houses.py`, `test_stages.py`, `test_house_types.py`, `test_option_catalog.py` — все через `secrets.token_urlsafe(16)`. Производственный код не содержит секретов.

`test_auth.py` — нарушение зафиксировано в P0-2.

### Soft-delete

`House` имеет `SoftDeleteMixin`. `GET list` — `list_paginated_filtered` всегда добавляет `deleted_at IS NULL` или `deleted_at IS NOT NULL` (is_archived). `GET /{id}` — через `get_or_404` в `BaseService`, который проверяет `deleted_at`. Тест `test_delete_house_happy_path` подтверждает, что после DELETE дом недоступен через GET. Соответствие полное.

`HouseType`, `OptionCatalog`, `Stage` — без `SoftDeleteMixin`, физическое удаление с проверкой ссылочной целостности. Корректно.

### Swagger / документация

Все роутеры имеют `summary`, `description`, `response_model`, `tags`. Ответы ошибок задокументированы через `responses={404: ..., 409: ..., 403: ...}`. Замечаний нет.

### Регрессии

`test_projects.py` (26 тестов) — не затронут изменениями; новые роутеры подключены в `main.py` аддитивно. Регрессии не ожидаются.

`test_auth.py` (19 тестов) — файл не изменялся в этом шаге. Регрессий нет.

---

## Резюме для разработчика

**Обязательно до коммита (P0 + P1):**

1. **P0-1**: Убрать `from sqlalchemy import select` и `self.house_repo.session.execute(...)` из `HouseConfigurationService.create()`. Добавить `option_repo: OptionCatalogRepository` в конструктор, обновить `_make_cfg_service()`.

2. **P0-2**: `test_auth.py` — заменить все literal-пароли в фикстурах и запросах на `secrets.token_urlsafe()`.

3. **P1-1**: Добавить проверку `cfg.house_id == house_id` в `HouseConfigurationService.update()` и `delete()`. Передать `house_id` из роутера в оба метода. Добавить тест на IDOR.

4. **P1-2**: Добавить фикстуру `read_only_user`/`read_only_token` в `test_houses.py`. Покрыть 7 недостающих RBAC-кейсов для `read_only` роли.

**Рекомендательно (P2):**

5. **P2-2**: Добавить тест `test_change_stage_same_stage_409`.

**NIT (P3):**

6. **P3-1**: Логировать проглоченное исключение в `StageRepository.has_references`.

---

*Ревьюер: reviewer | coordinata56 | Phase 3 Batch A Step 4*

---

## Round 2

**Дата:** 2026-04-15
**Ревьюер:** reviewer (субагент)
**Вердикт:** `approve`

### Проверка фиксов

#### P0-1 — ЗАКРЫТ

`backend/app/services/house.py` проверен полностью.

- Импорт `from sqlalchemy import select` отсутствует — ни на уровне модуля, ни внутри методов.
- Вызов `self.house_repo.session.execute(...)` отсутствует.
- `HouseConfigurationService.__init__` принимает `option_repo: OptionCatalogRepository` (строка 400).
- В методе `create()` используется `await self.option_repo.get_by_id(data.option_id)` (строка 459).
- `_make_cfg_service()` в `api/houses.py` передаёт `option_repo=OptionCatalogRepository(db)` (строка 73).
- P2-1 (lazy import внутри метода) устранён как следствие — лишний `from app.models.house import OptionCatalog` внутри метода исчез.

ADR 0004 §MUST соблюдён полностью.

#### P0-2 — ЗАКРЫТ

`backend/tests/test_auth.py` проверен.

- Фикстура `owner_user`: пароль `secrets.token_urlsafe(16)`, возвращает `tuple[User, str]` (строки 106–116).
- Фикстура `accountant_user`: аналогично (строки 125–135).
- `owner_token` и `accountant_token` распаковывают кортеж и используют `password` из переменной, не из литерала (строки 139–148, 151–159).
- Во всех тестах успешного входа (`test_login_correct_credentials_returns_200_and_token`, `test_register_by_owner_creates_user` и др.) `json={"password": password}` — переменная.
- Остаточные литералы `"wrong_password"` (строка 197) и `"any_password"` (строка 218) — намеренно неправильные значения в тестах сценария 401; они не являются учётными данными тестовых пользователей и не нарушают правило CLAUDE.md §3 (правило запрещает фиксировать реальные пароли, а не тестовые «заведомо неверные» строки).
- Пароль в строке подключения к тестовой БД (`change_me_please_to_strong_password`, строка 47) — конфигурационная строка dev-окружения, не пароль пользователя приложения; допустимо.

CLAUDE.md §3 соблюдён.

#### P1-1 — ЗАКРЫТ

`backend/app/services/house.py`, методы `HouseConfigurationService.update` и `delete`:

- `update` принимает `house_id: int` первым параметром (строка 494).
- IDOR-проверка до мутации: `if cfg.house_id != house_id: raise NotFoundError(...)` (строки 516–517). Комментарий явно указывает причину: `# IDOR-защита: cfg_id должен принадлежать дому из URL (OWASP A01)`.
- `delete` аналогично: `house_id` в сигнатуре (строка 537), проверка перед удалением (строки 560–561).
- `api/houses.py`: роутеры `PATCH /{house_id}/configurations/{cfg_id}` и `DELETE /{house_id}/configurations/{cfg_id}` передают `house_id=house_id` в вызовы сервиса (строки 406–407, 439–440).

`backend/tests/test_houses.py`:

- `test_patch_configuration_wrong_house_returns_404` (строка 1199) — PATCH через чужой `house_id` → 404, `error.code == "NOT_FOUND"`.
- `test_delete_configuration_wrong_house_returns_404` (строка 1242) — DELETE через чужой `house_id` → 404, `error.code == "NOT_FOUND"`, плюс проверка что запись не была удалена (строки 1283–1289).

OWASP A01 закрыт. Оба теста присутствуют и проверяют именно 404, а не 403 — корректно (не раскрывает существование чужого ресурса, CLAUDE.md §API).

#### P1-2 — ЗАКРЫТ

`backend/tests/test_houses.py`:

- Фикстура `read_only_user` присутствует (строка 153), возвращает `tuple[User, str]`, пароль через `secrets.token_urlsafe(16)`.
- Фикстура `read_only_token` присутствует (строка 169).
- 8 тестов RBAC для роли `read_only` присутствуют:
  1. `test_create_house_forbidden_for_read_only` — POST /houses → 403
  2. `test_bulk_create_houses_forbidden_for_read_only` — POST /houses/bulk → 403
  3. `test_update_house_forbidden_for_read_only` — PATCH /houses/{id} → 403
  4. `test_change_stage_forbidden_for_read_only` — PATCH /houses/{id}/stage → 403
  5. `test_delete_house_forbidden_for_read_only` — DELETE /houses/{id} → 403
  6. `test_create_configuration_forbidden_for_read_only` — POST /houses/{id}/configurations → 403
  7. `test_patch_configuration_forbidden_for_read_only` — PATCH /configurations/{cfg_id} → 403
  8. `test_delete_configuration_forbidden_for_read_only` — DELETE /configurations/{cfg_id} → 403
- Все тесты ассертят `resp.json()["error"]["code"] == "PERMISSION_DENIED"`.

Матрица RBAC полная. P1-2 закрыт.

### Регрессии

`test_projects.py` — не затронут. Новые фикстуры и тесты добавлены аддитивно.

`test_auth.py` — 63 теста прошли по отчёту разработчика; структурно файл корректен.

### Итоговая оценка

| Замечание Round 1 | Статус |
|---|---|
| P0-1: SQLAlchemy в сервисном слое | ЗАКРЫТ |
| P0-2: literal-пароли в фикстурах | ЗАКРЫТ |
| P1-1: IDOR при PATCH/DELETE конфигурации | ЗАКРЫТ |
| P1-2: матрица RBAC read_only | ЗАКРЫТ |
| P2-1: lazy import (следствие P0-1) | ЗАКРЫТ автоматически |
| P2-2: тест self-transition | Открыт (не блокер) |
| P3-1: silent exception | Открыт (не блокер) |

P2-2 и P3-1 не блокируют коммит; перенести в backlog следующего батча.

### Резюме

Все 2 P0 и 2 P1 из Round 1 устранены корректно. ADR 0004 восстановлен: `option_repo` добавлен в конструктор, прямого SQL в сервисном слое нет. IDOR-защита реализована с правильной семантикой 404 и покрыта двумя тестами. Матрица RBAC для `read_only` полная — 8 тестов, все проверяют `PERMISSION_DENIED`. `test_auth.py` приведён к `secrets.token_urlsafe`. Код готов к коммиту.

---

*Ревьюер: reviewer | coordinata56 | Phase 3 Batch A Step 4 Round 2*
