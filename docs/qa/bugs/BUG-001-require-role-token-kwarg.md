# BUG-001: TypeError в require_role — test_register_* падают после обновления deps.py

**Дата обнаружения:** 2026-04-15
**Обнаружен:** QA при запуске pytest после добавления новых тестов
**Приоритет:** P1 (Major — блокирует 3 теста из 16, функциональность register)
**Файл:** `backend/app/api/deps.py`
**Связано с:** Nit-1 из ревью `phase2-auth-2026-04-15.md`

---

## Симптом

При запуске тестов `test_register_by_non_owner_returns_403`,
`test_register_by_owner_creates_user`, `test_register_duplicate_email_returns_400`
все три падают с:

```
TypeError: get_current_user() got an unexpected keyword argument 'token'
fastapi/dependencies/utils.py:678: TypeError
```

## Шаги воспроизведения

1. `cd /root/coordinata56/backend`
2. `JWT_SECRET_KEY='<валидный ключ>' pytest tests/test_auth.py -v`
3. Любой тест, использующий `require_role(UserRole.OWNER)` через `Depends`

## Диагностика

`require_role` возвращает внутреннюю функцию `_check`, у которой нет
`functools.wraps(get_current_user)`. В новой версии FastAPI (текущая в окружении)
при разрешении зависимостей фреймворк пытается передать `token` как именованный
аргумент в `get_current_user`, но функция уже получает его через
`Depends(oauth2_scheme)` — конфликт.

Файл на диске корректен (`token: str = Depends(oauth2_scheme)`), проблема
в том как FastAPI разрешает вложенные зависимости без `functools.wraps`.

## Ожидаемое поведение

`POST /auth/register` с токеном owner → 201 или 403 (в зависимости от роли).

## Фактическое поведение

500 Internal Server Error / TypeError на этапе resolve dependencies.

## Фикс (для backend-dev)

Добавить `functools.wraps(get_current_user)` на `_check` в `require_role`:

```python
import functools

def require_role(*roles: UserRole):
    @functools.wraps(get_current_user)
    async def _check(current_user: User = Depends(get_current_user)) -> User:
        ...
    return _check
```

Либо — добавить явное `__name__` и `__wrapped__` атрибуты.

## Затронутые тесты

- `test_register_by_non_owner_returns_403`
- `test_register_by_owner_creates_user`
- `test_register_duplicate_email_returns_400`
