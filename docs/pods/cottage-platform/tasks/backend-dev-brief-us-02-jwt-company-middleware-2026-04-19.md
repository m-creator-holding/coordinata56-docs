# Дев-бриф US-02 — JWT-клеймы company_ids + X-Company-ID middleware + session ContextVar

- **Дата:** 2026-04-19
- **Автор:** backend-director (через backend-head при распределении)
- **Получатель:** backend-dev-2
- **Фаза:** M-OS-1.1A, Sprint 1 (нед. 1–2), параллельно US-01 / US-03
- **Приоритет:** P0 — фундамент session-context для всех сервисов с холдинговым скопом
- **Оценка:** M — 2-3 рабочих дня (≈1 день на JWT-клеймы + middleware-обёртка, ≈1 день на ContextVar + тесты, ≈0.5 дня на документацию и self-check)
- **Scope-vs-ADR:** verified (ADR 0003 auth MVP расширяется клеймами, ADR 0011 §1.2/1.3 multi-company и X-Company-ID уже частично реализованы в `deps.py`, ADR 0005 ошибки); gaps: none
- **Источник формулировки:** `docs/pods/cottage-platform/phases/m-os-1-1a-decomposition-2026-04-18.md` §Sprint 1 / US-02
- **Блокируется:** US-01 (нужен `company_id` на таблицах для JWT-клейма `company_ids`, который собирается через `user_company_roles`).

---

## Контекст

На момент 2026-04-19 механика частично есть:

- `backend/app/api/deps.py::get_current_user` уже умеет читать `X-Company-ID` и формировать `UserContext`.
- JWT-клеймы `company_ids: list[int]` и `is_holding_owner: bool` частично поддерживаются (код есть, но не гарантированно вкладывается в токен при логине — нужно проверить `backend/app/services/auth.py` и `core/security.py`).
- `UserContext` передаётся в сервисы явно через параметр метода (`user_context=ctx`) — это работает, но громоздко. Нужно дополнительно реализовать **session ContextVar** для упрощённого доступа из глубоких слоёв (например, из сервиса без проброса через все параметры).

Задача US-02:
1. Подтвердить и довести до 100% вложение `company_ids` и `is_holding_owner` в JWT при логине.
2. Подтвердить, что guard поведения X-Company-ID соответствует DoD (в декомпозиции 3 теста: позитив/негатив 400/holding-owner bypass).
3. Реализовать `session-context ContextVar` — переменная `current_user_context: ContextVar[UserContext | None]`, автоматически устанавливается из `get_current_user` через FastAPI dependency, доступна из `.get()` в любом слое.
4. Написать 3+ теста по DoD.

---

## Что конкретно сделать

### 1. JWT-клеймы при логине

**Файл:** `backend/app/services/auth.py` (или `core/security.py` — там где формируется access token).

Убедиться, что при создании JWT payload содержит:
- `sub: str` (email) — уже есть
- `exp: int` (timestamp) — уже есть
- `company_ids: list[int]` — список компаний пользователя из `user_company_roles`
- `is_holding_owner: bool` — поле `User.is_holding_owner` (ADR 0011 §1.4)

**Проверить:** при логине user с 2 компаниями выдаётся токен с `company_ids=[1, 2]`. Декодировать вручную через `jwt.decode(token, settings.JWT_SECRET, algorithms=["HS256"])` в REPL, проверить structure.

Если клеймы уже формируются — в отчёт «подтверждено без правок». Если нет — добавить формирование в том же сервисе авторизации.

### 2. Middleware X-Company-ID

**Файл:** `backend/app/api/deps.py::get_current_user` — уже реализует guard. Проверить соответствие декомпозиции:

| Сценарий | Ожидаемое поведение |
|---|---|
| User с 1 компанией, без X-Company-ID | `active_company_id` = единственная (автопроставление) |
| User с 2+ компаниями, без X-Company-ID | 400 Bad Request, error code `COMPANY_ID_REQUIRED` (формат ADR 0005) |
| User с 2+ компаниями, X-Company-ID=1 (есть в списке) | `active_company_id=1` |
| User с 2+ компаниями, X-Company-ID=99 (НЕТ в списке) | 403 Forbidden |
| Holding-owner, X-Company-ID=5 | `active_company_id=5`, `is_holding_owner=True` (bypass в сервисах) |
| Holding-owner, без X-Company-ID | `active_company_id=None`, `is_holding_owner=True` (полный bypass) |

**Важно:** сейчас в `deps.py` ошибка при несовпадении company_ids возвращается через `HTTPException(detail="...")` — это **не** ADR 0005. Нужно привести к формату ADR 0005 `{"error": {"code": "COMPANY_ID_REQUIRED" или "COMPANY_ID_INVALID", "message": "...", "details": {...}}}`.

Для 400 — код `COMPANY_ID_REQUIRED`. Для 403 — код `COMPANY_ID_FORBIDDEN` (или использовать существующий `FORBIDDEN` — уточнить по глобальным handler-ам в `backend/app/errors.py`).

Минимально необходимое изменение: выбрасывать не `HTTPException(detail=...)`, а кастомное исключение из `app/errors.py`, которое глобальный `exception_handler` завернёт в ADR 0005. Если нужных исключений нет — добавить `CompanyIdRequiredError` и `CompanyIdForbiddenError` рядом с `PdConsentRequiredError`.

### 3. Session ContextVar

**Файл (новый):** `backend/app/core/request_context.py`

```python
"""Session-scoped ContextVar для UserContext текущего запроса.

Цель: избежать проброса user_context через все параметры методов в глубоких слоях.
UserContext автоматически устанавливается после прохождения Depends(get_current_user),
доступен через current_user_context.get() в любом коде, исполняемом в рамках запроса.

ОГРАНИЧЕНИЯ:
- Нельзя полагаться на ContextVar в background-tasks: при `asyncio.create_task` копируется
  контекст, но при BackgroundTasks FastAPI поведение зависит от версии — всегда пробрасывать
  явно. ContextVar — удобство, не замена явному параметру.
- В тестах, не проходящих через Depends, ContextVar не установлен — тесты должны
  использовать фикстуру `_set_user_context_for_test` либо явно прокидывать UserContext.
"""

from __future__ import annotations

from contextvars import ContextVar

from app.services.company_scoped import UserContext

current_user_context: ContextVar[UserContext | None] = ContextVar(
    "current_user_context", default=None
)
```

**Файл:** `backend/app/api/deps.py` — в `get_current_user` **после** формирования `user_context`, **перед** return:

```python
from app.core.request_context import current_user_context
...
token = current_user_context.set(user_context)  # noqa
# токен сбросить после ответа через middleware (см. §4)
return user, user_context
```

### 4. Сброс ContextVar после запроса (middleware)

**Файл:** `backend/app/main.py` — добавить middleware:

```python
from starlette.middleware.base import BaseHTTPMiddleware
from app.core.request_context import current_user_context

class UserContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        token = current_user_context.set(None)
        try:
            return await call_next(request)
        finally:
            current_user_context.reset(token)

app.add_middleware(UserContextMiddleware)
```

Цель: изоляция между запросами. Без сброса может «протекать» контекст между запросами при share'аемых worker-процессах (uvicorn with shared state).

### 5. Тесты

**Файл:** `backend/tests/test_jwt_company_middleware.py` — **создать**.

Минимум 5 тестов (вместо 3 по DoD — больше покрытия никогда не вредит):

1. `test_jwt_contains_company_ids_and_is_holding_owner` — логинится user с 2 компаниями, декодируем ответный JWT, проверяем `company_ids == [..., ...]`, `is_holding_owner in (True, False)`.
2. `test_single_company_no_header_works` — user с 1 компанией делает запрос без `X-Company-ID`, получает 200, сервер видит `active_company_id=1` (проверка через `/auth/me` или `GET /projects`).
3. `test_multi_company_no_header_400` — user с 2 компаниями без `X-Company-ID` получает 400 с телом `{"error": {"code": "COMPANY_ID_REQUIRED", "message": ..., "details": ...}}` (формат ADR 0005).
4. `test_multi_company_wrong_header_403` — user с 2 компаниями, `X-Company-ID=99` (нет доступа), получает 403 с кодом `COMPANY_ID_FORBIDDEN` (или `FORBIDDEN`, по существующему контракту).
5. `test_holding_owner_bypass` — holding-owner (флаг `is_holding_owner=True`) с `X-Company-ID=5` (любая компания) — успех, в сервисе `_scoped_query_conditions()` возвращает пустой список.
6. **Бонус:** `test_context_var_propagates` — внутри сервиса (замокать сервис-метод) проверяется, что `current_user_context.get()` возвращает корректный `UserContext`.

Используйте существующие фикстуры `test_client`, `test_user`, `test_db` (из `backend/tests/conftest.py`).

### 6. Самопроверка (перед сдачей backend-head)

- [ ] Прочитан `CLAUDE.md` (секции «API», «Секреты и тесты») и `departments/backend.md` (ADR-gate A.1–A.5)
- [ ] Прочитан ADR 0011 §1.3/1.4 и ADR 0005 (формат ошибок)
- [ ] Выполнен ADR-gate:
  - A.1 — никаких литералов секретов в тестах (пароли через `secrets.token_urlsafe(16)`, JWT_SECRET — `os.environ.get()`)
  - A.2 — ничего в сервисах SQL-уровня не добавлено (deps.py использует существующие репозитории)
  - A.3 — не применимо (US-02 — инфраструктура auth, не бизнес-endpoint)
  - A.4 — 400 и 403 возвращают формат ADR 0005; не `{"detail": "..."}`
  - A.5 — не применимо (US-02 не делает write-операций бизнес-объектов)
- [ ] `cd backend && pytest backend/tests/test_jwt_company_middleware.py -v` — все новые тесты зелёные
- [ ] `cd backend && pytest` — все 351+ существующих тестов зелёные
- [ ] `cd backend && ruff check app tests` — 0 ошибок
- [ ] `cd backend && mypy app` — нет новых ошибок
- [ ] `git status` — только файлы из FILES_ALLOWED
- [ ] Не коммитить

---

## DoD

1. JWT при логине содержит `company_ids: list[int]` и `is_holding_owner: bool`.
2. Middleware / dependency X-Company-ID соответствует всем 6 сценариям из таблицы §2.
3. Ошибки 400/403 от middleware возвращаются в формате ADR 0005.
4. `current_user_context: ContextVar` доступен из любого слоя внутри запроса.
5. `UserContextMiddleware` сбрасывает ContextVar после каждого запроса.
6. ≥5 тестов в `test_jwt_company_middleware.py` зелёные.
7. 351 существующий тест зелёный.
8. `ruff`, `mypy` — чистые.

---

## FILES_ALLOWED

- `backend/app/core/request_context.py` — **создать**
- `backend/app/api/deps.py` — дополнить импортом `current_user_context` и `.set(user_context)` перед return
- `backend/app/main.py` — добавить `UserContextMiddleware`
- `backend/app/errors.py` — добавить `CompanyIdRequiredError`, `CompanyIdForbiddenError` (если отсутствуют)
- `backend/app/services/auth.py` и/или `backend/app/core/security.py` — если JWT-клеймы `company_ids`/`is_holding_owner` не вкладываются, добавить
- `backend/tests/test_jwt_company_middleware.py` — **создать**

## FILES_FORBIDDEN

- `backend/app/models/**` — US-01 работает с моделями, US-02 их не трогает
- `backend/app/services/company_scoped.py`, `rbac.py`, `base.py` — ядро, не трогать
- `backend/app/api/<entity>.py` — роутеры сущностей (US-01 и US-03 работают с ними)
- `frontend/**`, `docs/**` кроме отчётного сообщения
- `alembic/versions/**` — миграций в US-02 нет
- `.github/workflows/**`

---

## Зависимости

- **Блокирует:** ничего напрямую; но US-03 `require_permission` для полноценного теста RBAC требует корректного `UserContext`, что обеспечивается US-02.
- **Блокируется:** US-01 (нужен `company_id` на таблицах + обратная связь `user_company_roles` для формирования `company_ids`).

---

## COMMUNICATION_RULES

- Перед стартом — прочитать `CLAUDE.md`, `departments/backend.md`, ADR 0003/0005/0011, `backend/app/api/deps.py`, `backend/app/services/company_scoped.py`, `backend/app/services/auth.py`.
- Если JWT-клейм `company_ids` уже вкладывается — зафиксировать в отчёте «подтверждено без правок» со ссылкой на код-линию.
- Если формат ошибок 400/403 в `deps.py` уже ADR 0005 — также зафиксировать «подтверждено».
- Если ContextVar «не прокидывается» в тестах (тесты ходят мимо Depends) — это нормально: тест должен либо использовать реальный `TestClient` с JWT, либо явно установить `current_user_context.set(ctx)` в setup. Не «протаскивать» ContextVar обходными путями.
- Никаких сторонних зависимостей.

---

## Обязательно прочитать перед началом

1. `/root/coordinata56/CLAUDE.md` — секции «API», «Секреты и тесты», «Код»
2. `/root/coordinata56/docs/agents/departments/backend.md` — ADR-gate A.1–A.5
3. `/root/coordinata56/docs/adr/0003-auth-mvp.md` — базовый auth
4. `/root/coordinata56/docs/adr/0005-api-error-format.md` — формат ошибок
5. `/root/coordinata56/docs/adr/0011-foundation-multi-company-rbac-audit.md` — §1.2, §1.3, §1.4
6. `/root/coordinata56/backend/app/api/deps.py` — текущий guard X-Company-ID
7. `/root/coordinata56/backend/app/services/company_scoped.py` — `UserContext`
8. `/root/coordinata56/backend/app/errors.py` — паттерн кастомных исключений

---

## Отчёт (≤ 300 слов)

Структура:
1. **JWT-клеймы** — подтверждение или правки, место в коде.
2. **Middleware X-Company-ID** — соответствие 6 сценариям таблицы §2; правки формата ошибок на ADR 0005.
3. **ContextVar** — путь к `request_context.py`, где set/reset.
4. **Middleware** — где зарегистрирован `UserContextMiddleware`.
5. **Тесты** — количество новых тестов, список имён, результат `pytest`.
6. **ADR-gate** — A.1/A.2/A.4 pass/fail + артефакты.
7. **Отклонения от scope** — если были.
