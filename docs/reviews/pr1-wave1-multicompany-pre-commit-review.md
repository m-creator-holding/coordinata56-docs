# Code Review: PR #1 Wave 1 — Multi-Company Foundation

**Дата**: 2026-04-18
**Ревьюер**: reviewer (субагент)
**Scope**: Волна 1, Шаг 1 Multi-company (ADR 0011 §2.4)
**Файлы**: +1562 / −145 (42 файла staged)
**ADR контракт**: ADR 0004, 0005, 0006, 0007, 0011, 0013

---

## ВЕРДИКТ: request-changes

Причина: два P0-блокера (IDOR на GET-by-id и литеральный production-пароль в seed.py), один P1 с нарушением тестовой спецификации. До устранения P0 коммит в main заблокирован.

---

## P0 — Блокеры (коммит запрещён)

### P0-1: IDOR — GET-by-id не проверяет company_id

**Файлы**: `backend/app/services/project.py:90`, `backend/app/services/contract.py:128`, `backend/app/services/payment.py:129`, `backend/app/services/contractor.py:90`

**Суть проблемы.** Методы `service.get(id)` делегируют в `BaseService.get_or_404`, который вызывает `repo.get_by_id(id)` без фильтра по `company_id`. Тот, в свою очередь, выполняет `session.get(Model, id)` — прямой lookup по PK без `WHERE company_id = ?`.

Это означает: пользователь компании A, зная числовой id ресурса компании B, может получить его через `GET /contracts/{id}`, `GET /payments/{id}`, `GET /projects/{id}`, `GET /contractors/{id}`. Ни роутер, ни сервис не проверяют принадлежность возвращённого объекта к компании из `user_context`.

**OWASP A01:2021 — Broken Access Control / IDOR.** Прямая ссылка на объект без проверки принадлежности. Степень критичности: данные другого юридического лица холдинга (суммы договоров, платежи) доступны по угадыванию id.

**ADR 0011 §1.3** прямо указывает: «Запрос без явного `WHERE company_id = ?` (исходящего из токена пользователя) не допускается на уровне сервисного слоя.» Метод `get_or_404` нарушает это требование для одиночных объектов.

**Тест 7 в `test_company_scope.py:463` фиксирует проблему явно**: `assert resp.status_code in (404, 200)` — разработчик сам признал, что не уверен, вернёт ли endpoint 404 (правильно) или 200 (утечка). Тест с таким assertion принимает оба исхода и не является защитой.

**Требуемое исправление.** Вариантов два — на выбор архитектора:
- Вариант A: сервисные методы `get(id)` принимают `user_context` и после получения объекта проверяют `obj.company_id == user_context.company_id` (если `not is_holding_owner`); при несовпадении — `NotFoundError` (не 403, чтобы не раскрывать существование ресурса).
- Вариант B: репозиторий добавляет метод `get_by_id_scoped(id, company_id)` с `WHERE id=? AND company_id=?`; сервис вызывает его вместо `get_by_id`.

Любой вариант требует обновления теста 7: assertion должен быть строго `assert resp.status_code == 404`.

---

### P0-2: Литеральный пароль в production seed

**Файл**: `backend/app/db/seeds.py:328`

```python
password_hash=_hash_password("change_me_on_first_login"),
```

Строка `"change_me_on_first_login"` — словарное значение. CLAUDE.md §«Секреты и тесты», регламент v1.3 §3 и OWASP A02:2021 (Cryptographic Failures) запрещают литеральные пароли в коде. Этот файл коммитится в репозиторий и попадёт в историю git навсегда.

Файл `seeds.py` не входит в scope staged diff (42 файла PR), однако функция `_upsert_owner` вызывается при деплое, и holding-owner с предсказуемым паролем — это вектор атаки на самую привилегированную учётную запись системы.

**Требуемое исправление.** Пароль читается из переменной окружения: `os.environ["OWNER_INITIAL_PASSWORD"]`. При отсутствии переменной — `RuntimeError`, а не fallback. Если функция не менялась в этом PR — добавить в scope ревью как сопутствующий дефект, устранить вместе.

---

## P1 — Серьёзные замечания (устранить до мержа)

### P1-1: is_holding_owner определяется неверно в auth.py

**Файл**: `backend/app/api/auth.py:127`

```python
is_holding_owner = user.role == UserRole.OWNER and len(company_ids) == 0
```

Логика хрупкая и противоречит ADR 0011 §1.3. ADR определяет holding_owner как пользователя с явным флагом, а не через отсутствие привязки к компаниям. Проблема возникает при следующих сценариях:

- Новый owner создан через `/auth/register`, но seed миграции ещё не сформировал его `UserCompanyRole` — `company_ids = []`, is_holding_owner=True по ошибке, хотя пользователь не является суперадмином.
- Owner, которому удалили все `UserCompanyRole` (ошибка оператора), автоматически получает bypass всех company-фильтров.

ADR предполагает отдельный механизм назначения holding_owner, а не вывод из пустого списка компаний. На уровне M-OS-1 минимально корректное решение: добавить поле `is_holding_owner: bool` в модель `User` и читать его при логине, а не вычислять из косвенного признака.

**Риск**: privilege escalation через гонку состояний или ошибку оператора.

---

### P1-2: company_id в GET-by-id не передаётся — payment может принадлежать чужой компании

**Файл**: `backend/app/api/payments.py:163-165`

```python
async def get_payment(..., _current_user: User = Depends(require_role(*_READ_ROLES))) -> PaymentRead:
    service = _make_service(db)
    payment = await service.get(payment_id)
```

Endpoint использует `require_role` (deprecated alias), который возвращает только `User` без `UserContext`. Нет никакой возможности проверить, что `payment.company_id` соответствует компании пользователя. Аналогичная ситуация в `get_contract`, `get_project`, `get_contractor`.

Это прямое следствие P0-1, но выделено отдельно: в роутере даже нет `user_context` в сигнатуре функции — проблема не только в сервисном слое, но и в том, что роутер её не может устранить самостоятельно.

---

### P1-3: Тест 7 принимает некорректный статус-код

**Файл**: `backend/tests/test_company_scope.py:463`

```python
assert resp.status_code in (404, 200)
```

Это не тест безопасности — это тест, который пройдёт при утечке данных (200). Такой assertion нельзя считать покрытием IDOR-защиты. Тест создаёт ложное ощущение безопасности: CI зелёный, но уязвимость присутствует.

**Требование**: assertion должен быть `assert resp.status_code == 404` после устранения P0-1.

---

## P2 — Важные замечания

### P2-1: Отсутствие conftest.py в директории tests/

**Файл**: `backend/tests/` (директория)

`create_user_with_role` и `ensure_default_company` определены в `backend/conftest.py` (корень backend), а `test_company_scope.py` импортирует их явно: `from conftest import create_user_with_role, ensure_default_company`. Это работает только если pytest запускается из `backend/`. При запуске из корня проекта или в CI с иным `rootdir` импорт сломается с `ModuleNotFoundError`.

Рекомендация: вынести общие фикстуры в `backend/tests/conftest.py` (стандартное место) или добавить `__init__.py` в тесты с явным импортом пути.

---

### P2-2: Payment.company_id не защищён от подмены при update

**Файл**: `backend/app/services/payment.py:238`

```python
update_data = data.model_dump(exclude_unset=True)
payment = await self.repo.update(payment, update_data)
```

Схема `PaymentUpdate` должна явно исключать поле `company_id` из обновляемых полей. Если схема допускает передачу `company_id` в теле PATCH — пользователь может переместить платёж в чужую компанию. Требует проверки `PaymentUpdate` (файл не был прочитан полностью, требует отдельной верификации).

---

### P2-3: Seed миграции не обёрнут в явную транзакцию

**Файл**: `backend/alembic/versions/2026_04_17_0900_f7e8d9c0b1a2_multi_company_foundation.py:152-158, 285-295`

Два `op.execute(sa.text(...))` — INSERT в companies и INSERT из users — выполняются в неявной транзакции Alembic. Если между ними что-то упадёт (например, нет пользователей в таблице users, но код продолжается), состояние БД будет частично применено. Alembic автоматически управляет транзакцией на уровне всей миграции, однако явное `op.execute(sa.text("BEGIN"))` / `SAVEPOINT` обеспечило бы атомарность seed-шагов независимо от конфигурации `transaction_per_migration` в Alembic.

Риск на практике: низкий при стандартной конфигурации Alembic. Но ADR 0013 требует обоснования для операций с данными в миграции.

---

### P2-4: Отсутствует проверка диапазона при нормализации company_ids из JWT

**Файл**: `backend/app/api/deps.py:117`

```python
company_ids = [int(cid) for cid in jwt_company_ids_raw if isinstance(cid, (int, float))]
```

`float` принимается как валидный тип, и `int(3.9)` даст `3` — неочевидное поведение. JWT стандарт допускает числа как JSON Number, но конвертация `float → int` с усечением может дать неожиданные id. Рекомендация: принимать только `int`, либо применять `round()` перед `int()` с явным комментарием.

---

## Nit — Незначительные замечания

### Nit-1: `# type: ignore[attr-defined]` без даты возврата

**Файл**: `backend/app/services/company_scoped.py:73`

```python
return [model.company_id == user_context.company_id]  # type: ignore[attr-defined]
```

Комментарий присутствует (атрибут `company_id` не статически гарантирован на `BaseRepository.model`). Это допустимо по CLAUDE.md. Однако хорошей практикой было бы добавить обоснование: почему нельзя решить через Protocol/TypeVar — чтобы следующий разработчик не убрал ignore без понимания.

---

### Nit-2: Логика `is_archived` в ProjectService потенциально конфликтует

**Файл**: `backend/app/services/project.py:72-75`

```python
filters = {"status": "archived"} if is_archived is True else None
extra_conditions: list = (
    [Project.status != "archived"] if is_archived is False else []
)
```

Когда `is_archived=True` — используется `filters` dict (возможно, через `BaseRepository.list_paginated` kwargs), когда `is_archived=False` — `extra_conditions`. Это две разные ветки для одного семантического фильтра. Если `BaseRepository.list_paginated` применяет `filters` через `WHERE field=value` и `extra_conditions` через `AND (condition)`, они не конфликтуют. Но если `filters` применяется иначе — возможна ситуация, когда `WHERE status='archived' AND status != 'archived'` (никогда не True). Рекомендуется унифицировать: оба случая через `extra_conditions`.

---

## Сводная таблица

| ID | Приоритет | Файл | Строки | Суть |
|---|---|---|---|---|
| P0-1 | P0 BLOCKER | `services/{project,contract,payment,contractor}.py` | get() методы | IDOR: get-by-id без проверки company_id |
| P0-2 | P0 BLOCKER | `app/db/seeds.py` | 328 | Литеральный пароль holding-owner |
| P1-1 | P1 | `api/auth.py` | 127 | is_holding_owner вычисляется из косвенного признака |
| P1-2 | P1 | `api/payments.py` | 163 | GET-by-id без UserContext в роутере |
| P1-3 | P1 | `tests/test_company_scope.py` | 463 | Тест принимает 200 как корректный исход IDOR |
| P2-1 | P2 | `backend/tests/` | — | conftest импортируется из нестандартного места |
| P2-2 | P2 | `services/payment.py` | 238 | company_id может быть подменён через PATCH |
| P2-3 | P2 | `alembic/versions/f7e8d9c0b1a2` | 152-295 | Seed без явной атомарности |
| P2-4 | P2 | `api/deps.py` | 117 | float принимается как company_id |
| Nit-1 | nit | `services/company_scoped.py` | 73 | `# type: ignore` без обоснования |
| Nit-2 | nit | `services/project.py` | 72-75 | Двойная логика фильтрации is_archived |

---

## Что проверено и соответствует (approve по этим пунктам)

- **ADR 0004 MUST #1a**: `select`, `insert`, `update`, `delete`, `session.execute` отсутствуют в `services/`. Репозитории единственные держатели запросов. Соответствует.
- **ADR 0004 MUST #1b**: `CompanyScopedService._scoped_query_conditions` возвращает `list[ColumnElement[bool]]`, не выполняет запрос. `and_`, `or_` не используются в сервисах напрямую. Соответствует Amendment 2026-04-18.
- **ADR 0005 (error envelope)**: все доменные исключения наследуют `AppError`, возвращают `{"error": {"code", "message", "details"}}`. Соответствует.
- **ADR 0006 (pagination)**: все list-endpoints возвращают `ListEnvelope` с `items`, `total`, `offset`, `limit`. Фильтры применяются через `extra_conditions` на уровне SQL — `total` корректен. Соответствует.
- **ADR 0007 (audit)**: все write-операции в сервисах содержат `await self.audit.log(...)` в той же транзакции. В scope проверены: ProjectService (create/update/delete), PaymentService (create/update/delete/approve/reject), ContractService (create/update/delete). Соответствует.
- **ADR 0011 §2.4 JWT claims**: `company_ids: list[int]` и `is_holding_owner: bool` добавлены в `create_access_token`. Декодирование в `deps.py` обрабатывает отсутствие клеймов (обратная совместимость со старыми токенами). Соответствует.
- **ADR 0013 (migration rules)**: миграция использует паттерн ADD COLUMN nullable → UPDATE → SET NOT NULL (safe-migration). Нет `DROP COLUMN`, `RENAME COLUMN`, `RENAME TABLE`. Downgrade реализован в обратном порядке. Round-trip задокументирован. Соответствует.
- **OWASP A02 (Cryptographic)**: пароли хешируются bcrypt, `JWT_SECRET_KEY` читается из env без дефолта, `dummy_verify` защищает от timing-атак на `/login`. Соответствует.
- **OWASP A03 (Injection)**: все SQL — через SQLAlchemy ORM или `sa.text()` с параметрами. f-string-сборки SQL не обнаружено. `conftest.py` генерирует пароли через `secrets.token_urlsafe`. Соответствует (за исключением P0-2 в seeds.py).
- **Тесты (логическая проверка)**: тесты 1, 2, 3, 4, 5, 6, 8 в `test_company_scope.py` логически корректны. Тест 7 — не проходит валидацию (см. P1-3).
- **Обратная совместимость**: `require_role` сохранён как deprecated alias. Поле `users.role` не удаляется в миграции (deprecated, но живо). Соответствует ADR 0011 §1.5.
- **Идемпотентность seed**: `INSERT INTO companies ... VALUES (1, NULL, ...)` — если запись уже существует, повторная вставка упадёт на PRIMARY KEY constraint. Это не идемпотентная операция. При round-trip (downgrade → upgrade) проблемы нет (таблица пересоздаётся), но прямой повторный запуск upgrade на уже мигрированной БД упадёт. Это приемлемо для Alembic-миграций (не предназначены для повторного запуска), но стоит задокументировать.

---

## Требуемые действия перед коммитом

1. **P0-1**: добавить проверку `company_id` в методы `get(id)` всех мультикомпанийных сервисов. Тест 7 переписать со строгим assertion `== 404`.
2. **P0-2**: заменить `"change_me_on_first_login"` на чтение из `os.environ["OWNER_INITIAL_PASSWORD"]` с `RuntimeError` при отсутствии.
3. **P1-1**: добавить поле `is_holding_owner: bool` в модель `User` или ввести отдельный механизм назначения вместо вывода из `len(company_ids) == 0`.
4. **P1-2**: обновить GET-by-id endpoints для Company-scoped сущностей — передавать `user_context` и проверять принадлежность объекта.

P2 и Nit — устранить до или сразу после мержа по договорённости с backend-director.

---

*Ревью выполнено на staged diff. Reviewer не вносит правок в код.*
