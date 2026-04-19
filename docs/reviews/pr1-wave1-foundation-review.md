# Code Review — PR #1 Wave 1 Foundation + Zero-version OpenAPI stub

**Ревьюер:** reviewer (Советник L4, независимый проход)
**Дата:** 2026-04-18
**Батчи:** Батч 1 (Линтер миграций) + Батч 2 (Zero-version OpenAPI stub)
**Предыдущий проход:** backend-head (pattern-conformance, APPROVE)
**Цель этого прохода:** независимый security-oriented проход

---

## Общий вердикт

**APPROVE WITH CHANGES**

Два батча содержат качественную, хорошо структурированную работу. Один блокер (P1) и три замечания уровня P2. P0 (немедленная эскалация по безопасности) не обнаружено.

---

## 1. ADR 0011 / 0013 Compliance

### ADR 0013 (Migrations Evolution Contract)

Чек-лист MUST из ADR 0013:

| Требование | Найдено | Соответствует |
|---|---|---|
| `lint_migrations.py` покрывает ≥6 forbidden-операций | 7 правил (DROP COLUMN, RENAME COLUMN, RENAME TABLE, NOT NULL без DEFAULT, DROP TABLE, type_change, op.execute) | Да, превышает требование |
| CI-шаг `lint-migrations` — обязательный, блокирует merge | `.github/workflows/ci.yml`, job `lint-migrations`, нет флага `continue-on-error` | Да |
| CI-шаг `round-trip` добавлен | Job `round-trip` в ci.yml | Да |
| Тест `test_lint_migrations.py` — 6 forbidden-операций | 23 теста, покрывают все 7 правил + CLI + smoke | Да |
| `test_round_trip.py` — параметризация по ревизиям | Параметризация через `_get_revision_ids()` | Да |
| backend.md расширен разделом «Правила для авторов миграций» | v1.0 → v1.1, добавлен раздел | Да |

**Замечание по ADR 0013 (minor — P2):** ADR 0013 на момент PR имеет статус `proposed` (строка 4 файла), а не `approved`. Backend.md ссылается на него как на «источник истины». Это допустимо при условии, что governance-gate открыт параллельно. Если ADR 0013 не будет утверждён до мержа, CI-линтер начнёт исполнять непроверенный контракт. Рекомендация: перед коммитом убедиться что governance выдал вердикт по ADR 0013, или явно пометить в backend.md `(ADR 0013, ожидает governance)`.

### ADR 0013 — Отклонение от брифа #1 (alembic.command вместо subprocess)

**Оценка:** Приемлемо. `alembic.command` API надёжнее и тестируемее subprocess. Нарушений безопасности и контрактных ограничений нет. Отклонение заявлено в брифе. Требует amendment в ADR 0013 §«Инструмент линтера»:

```
## Amendments
- 2026-04-18: round-trip тест использует alembic.command API (программный),
  не subprocess. Причина: надёжность и тестируемость. ADR 0013 §«Инструмент линтера»
  описывал subprocess-вариант как опцию; принятый вариант безопаснее.
```

### ADR 0011 (Foundation: Multi-company, RBAC, Crypto Audit)

Батч 2 реализует zero-version stub для 4 доменов ADR 0011: companies, users (admin), roles (UserCompanyRole), auth/sessions. Схемы Pydantic (`company.py`, `user_company_role.py`, `auth_session.py`, `user_admin.py`) корректно отражают модели данных из ADR 0011 §1.1 и §1.2.

| Поле ADR 0011 | Схема | Соответствует |
|---|---|---|
| Company: inn (nullable), kpp (nullable), full_name, short_name, company_type, is_active | `CompanyCreate`, `CompanyRead` — все поля присутствуют | Да |
| UserCompanyRole: user_id, company_id, role_template, pod_id, granted_at, granted_by | `UserCompanyRoleRead`, `UserCompanyRoleCreate` — все поля | Да |
| Envelope ADR 0006 (items, total, offset, limit) | Все 4 Paginated-схемы корректны | Да |

---

## 2. CODE_OF_LAWS Compliance

### Статья 40 (секреты не литералятся)

**НАРУШЕНИЕ — P1 (blocker для коммита).**

Файл `/root/coordinata56/backend/tests/test_zero_version_stubs.py`, строка 73:

```python
"password": "TestPassword123",
```

Это литеральный пароль в теле тестового запроса. Формально он используется как тело POST-запроса к stub-эндпоинту, который не читает базу данных и ничего не делает с паролем. Однако:

1. Статья 40 CODE_OF_LAWS и правило 7 из `backend.md` прямо запрещают литеральные пароли в тестах без исключения — «повторяющийся дефект: 3 раза за 2 фазы».
2. OWASP A02 (Cryptographic Failures): пароль, захардкоженный в тестах, может попасть в логи CI, историю git, отчёты покрытия.
3. Прецедент: когда stub будет заменён реальной реализацией, тест будет использоваться как шаблон — и паттерн с литеральным паролем перейдёт в production-тесты.

**Требуемое исправление:**
```python
import secrets
# ...
"password": secrets.token_urlsafe(16),
```

Все остальные тесты проекта (test_budget_categories.py и другие) уже используют `secrets.token_urlsafe(16)` — этот файл нарушает сложившийся паттерн.

### Статья 45а (запрет живых интеграций)

Соответствует. Ни один из проверяемых файлов не делает внешних HTTP-запросов. Линтер миграций работает через AST-анализ и `alembic.command` (локальный API). Stub-эндпоинты не делают никаких вызовов. Замечаний нет.

### Статья 79 (безопасность — ст. 8 CODE_OF_LAWS → Конституция)

В `test_round_trip.py`, строка 37, дефолтный URL содержит `change_me`:
```python
"postgresql+psycopg://coordinata:change_me@localhost:5433/coordinata56_test"
```

Это не нарушение статьи 40 (секрет не является production-паролем, это placeholder для dev-окружения). Аналогичный паттерн используется в `conftest.py` и других тестах проекта. Приемлемо для dev/CI.

В `test_zero_version_stubs.py`, строка 23:
```python
os.environ.setdefault("JWT_SECRET_KEY", "stub-test-ci-key-minimum-32-characters-x")
```
Длина ключа ≥32 символа — требование OWASP A02 выполнено. Используется `os.environ.setdefault` — не перезаписывает если задан в окружении. Приемлемо.

---

## 3. OWASP Top 10

### A01 — Broken Access Control

**Батч 1 (линтер):** не применимо. Линтер — CLI-инструмент без HTTP-слоя.

**Батч 2 (stub-эндпоинты):** все 20 эндпоинтов возвращают 501 и не выполняют никаких операций с данными. Отсутствие auth-проверки на stub-эндпоинтах — **допустимо** для zero-version стадии, но требует обязательного контроля при реализации в PR #2.

**Замечание P2 (информационное):** четыре новых роутера (`/users/`, `/companies/`, `/roles/`, `/auth/sessions/`) не имеют никакой аутентификационной защиты. Это заглушки — сейчас правильно. При реализации PR #2 каждый из этих роутеров должен получить `require_permission` декоратор на каждый endpoint. Рекомендация: добавить TODO-комментарий непосредственно в каждый endpoint-метод с указанием требуемой роли, чтобы разработчик PR #2 не пропустил.

### A02 — Cryptographic Failures

Нет криптографического кода в обоих батчах. JWT_SECRET_KEY ≥32 символа в тестовых fixture — выполнено.

### A03 — Injection

**Батч 1:** линтер использует `ast.parse()` — безопасный статический анализ Python-кода. Никаких динамических запросов. Путь к файлам берётся из аргументов CLI (`sys.argv`), но читается через `Path.read_text()` — инъекция невозможна (OS-level path traversal ограничен правами запускающего процесса, что приемлемо для CLI).

**Батч 2:** stub-эндпоинты принимают Pydantic-схемы на входе, но не используют их (возвращают фиксированный `_stub_response()`). Уязвимостей нет.

### A05 — Security Misconfiguration

**Потенциальная проблема P2 (информационное):** в `main.py` Swagger UI (`/docs`) и ReDoc (`/redoc`) открыты без проверки окружения:

```python
docs_url="/docs",
redoc_url="/redoc",
```

Нет условия `docs_url="/docs" if settings.app_env != "production" else None`. Это существующий код (не новый в этих батчах), но 4 новых роутера добавляют 20 новых эндпоинтов в открытую документацию. Согласно OWASP A05, Swagger в production должен быть закрыт. Это **не блокер** для данного PR (паттерн существующий, не введён этими батчами), но подлежит фиксу до production-gate.

### A07 — Identification and Authentication Failures

Не применимо к батчам — stub-эндпоинты не реализуют аутентификацию (намеренно).

### A09 — Security Logging

**Батч 1:** линтер пишет в `stderr`. Никаких секретов в вывод не попадает — анализируются имена операций Alembic, не данные. Хорошо.

**Батч 2:** stub-эндпоинты не логируют запросы (они ничего не делают). При реализации в PR #2 обязательно добавить аудит-лог для write-операций (ADR 0007, backend.md п. 5).

---

## 4. Python / Pydantic v2 / FastAPI Best Practices

### Батч 1 — линтер

- `from __future__ import annotations` — присутствует, корректно.
- Типизация полная: `lint_file` → `tuple[list[LintError], list[LintWarning]]`, CLI → `int`. Хорошо.
- Классы `LintError` и `LintWarning` — plain Python, не dataclass и не Pydantic. Приемлемо для этого инструмента (dataclass усложнил бы без выгоды).
- `_SAFE_TYPE_WIDENING` и `_NARROWING_PAIRS` определены, но `_NARROWING_PAIRS` **нигде не используется** в коде (строки 115–122). Логика `_is_narrowing_type_change` возвращает `True` для любого распознанного типа (строка 152). Это означает, что `_NARROWING_PAIRS` — мёртвый код. **P2 (minor):** либо удалить, либо задокументировать намерение.
- `_collect_upgrade_nodes` возвращает список узлов только из `upgrade()` — корректное архитектурное решение, исключает ложные срабатывания на `downgrade()`.
- `_collect_new_nullable_columns` корректно реализует safe-migration паттерн.
- Обработка `SyntaxError` при `ast.parse()` — через `LintError`, корректно.
- `except Exception: # noqa: BLE001` в `_db_available` — обоснование есть (намеренный catch-all для availability check). Корректно.

### Батч 2 — stub-роутеры и схемы

- Все схемы используют `from __future__ import annotations`. Хорошо.
- `model_config = {"from_attributes": True}` — только на Read-схемах (не на Create/Update). Правильно.
- `model_config = {"str_strip_whitespace": True}` в `CompanyCreate` и `CompanyUpdate` — добавленная защита от пробелов в критичных полях (full_name, short_name). Хорошо.
- `_STUB_BODY` дублируется в каждом из 4 роутеров дословно. **P2 (nit):** это код-смелл дублирования. Правильное решение — вынести в общий модуль `app.api._stub_utils` или в `app.api.__init__`. Не блокер.
- **Проблема типов (P2, minor):** DELETE-эндпоинты объявлены с `status_code=204` (декоратор роутера), но функция `return _stub_response()` возвращает `JSONResponse(501)`. FastAPI при `Response` как возвращаемом значении использует возвращённый объект как есть — статус 501 будет передан. Однако объявление `status_code=204` в декораторе ввводит в заблуждение в OpenAPI-схеме (она покажет 204 как primary response). Тест корректно игнорирует тело для 204-ответов (`if response.status_code == 204: return`), но фактически ответ будет 501. Это непоследовательность в OpenAPI-контракте. Рекомендация: для DELETE-stubs либо объявить `status_code=501`, либо добавить `responses={501: ...}` как primary response.

---

## 5. Тестовая архитектура

### Батч 1 — test_lint_migrations.py

- 23 теста: 2 positive/negative на каждое из 6 правил = 12, плюс 3 на op.execute, 1 на маркер, 2 smoke, 5 CLI. Покрытие требований DoD ADR 0013 выполнено.
- Фикстуры — файлы `_fixture_*.py` без секретов. Не содержат паролей, токенов, ключей. Соответствие статье 40.
- Тест `test_real_migrations_count` проверяет ровно 8 файлов (`== 8`). При добавлении новой миграции тест упадёт и потребует ручного обновления константы. **P2 (minor):** жёсткая константа хрупка. Более устойчивый паттерн: `>= 8`. Аргумент за оставить как есть: тест явно документирует ожидаемое число миграций и защищает от случайного удаления. Принять можно в обе стороны — на усмотрение backend-head.
- Teardown в `clean_db` fixture — `contextlib.suppress(Exception)` с `downgrade("base")`. Корректно.

### Батч 2 — test_zero_version_stubs.py

- **P1 (blocker):** строка 73 содержит `"TestPassword123"` — литеральный пароль. Описано в секции 2 выше.
- 20×4 параметризованных теста + 5 OpenAPI-тестов = 85 проверок. Покрытие полное.
- Тест `test_endpoint_body_no_stacktrace` содержит неоднозначную проверку (строка 173):
  ```python
  assert "traceback" not in body_text.lower() or "tracking" in body_text
  ```
  Условие истинно при наличии слова `traceback` в теле — если тело одновременно содержит `tracking` (что всегда так, ведь `_STUB_BODY` содержит `"tracking": "wave-1-pr-2"`). Это означает, что вторая проверка на `traceback` фактически **не работает** — условие `A or B` с вечно-истинным `B`. **P2 (minor):** логика должна быть `assert "traceback" not in body_text.lower()` без условия. Поле `tracking` не является исключением для traceback.

### Батч 1 — test_round_trip.py

- Параметризация динамическая через `_get_revision_ids()` — правильный подход.
- Teardown корректен: `contextlib.suppress(Exception)` после `downgrade("base")`.
- Тест пропускается (`pytest.skip`) если Postgres недоступен — корректное поведение для CI с опциональной БД.

---

## 6. Отклонения от брифа

| Отклонение | Оценка ревьюера |
|---|---|
| Батч 1: `alembic.command` API вместо subprocess | Приемлемо. Более надёжное решение. Требует amendment в ADR 0013. |
| Батч 2: `JSONResponse(...)` вместо `raise HTTPException` для stub | Приемлемо. Корректный обход задокументированного бага handler'а ADR 0005. Обоснование зафиксировано в комментариях роутеров и брифе. |

---

## 7. Сводная таблица замечаний

| ID | Файл:строка | Приоритет | Категория | Описание |
|---|---|---|---|---|
| F-1 | `tests/test_zero_version_stubs.py:73` | **P1 / blocker** | CODE_OF_LAWS ст. 40, OWASP A02 | Литеральный пароль `TestPassword123` в теле тестового запроса. Заменить на `secrets.token_urlsafe(16)`. |
| F-2 | `tests/test_zero_version_stubs.py:173` | P2 / minor | Тестовая логика | Проверка `"traceback" not in body_text.lower() or "tracking" in body_text` всегда истинна из-за `tracking` в stub-body. Убрать `or`-часть. |
| F-3 | `tools/lint_migrations.py:115-122` | P2 / nit | Мёртвый код | `_NARROWING_PAIRS` определён но не используется. Удалить или применить. |
| F-4 | `app/api/auth_sessions.py`, `companies.py`, `users.py`, `roles.py` | P2 / nit | Дублирование | `_STUB_BODY` дублируется в 4 файлах. Вынести в общий модуль. |
| F-5 | `docs/adr/0013-migrations-evolution-contract.md` | P2 / minor | ADR governance | ADR 0013 имеет статус `proposed`. Требует governance-вердикта до коммита. Amendment по отклонению `alembic.command`. |

---

## 8. Рекомендация Координатору

**Возвратить на правки перед коммитом.** Один P1 (литеральный пароль в тесте) блокирует коммит согласно регламенту v1.3 §1 и CODE_OF_LAWS ст. 40.

Правки минимальны: одна строка в `test_zero_version_stubs.py`. После устранения F-1 и опционального устранения F-2 (рекомендуется) — батчи готовы к approve backend-director и коммиту Координатором.

P2-замечания (F-3, F-4, F-5) не блокируют коммит, но рекомендуются к отработке:
- F-5 (governance по ADR 0013) — координировать с governance параллельно.
- F-3 и F-4 — технический долг, зафиксировать в трекере задач.

---

*Ревью выполнено: reviewer (Советник L4), 2026-04-18. Независимый security-oriented проход. Инструменты: чтение файлов, OWASP Top 10 чек-лист, ADR compliance checker.*
