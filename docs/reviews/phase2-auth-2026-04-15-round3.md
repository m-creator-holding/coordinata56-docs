# Code Review Round 3 — Phase 2 (Authentication, JWT, RBAC)

**Предыдущий отчёт:** `phase2-auth-2026-04-15-round2.md`
**Дата ревью:** 2026-04-15
**Ревьюер:** субагент `reviewer`
**Основание:** проверка трёх исправлений из Round 2 перед коммитом
**ADR-источник:** `docs/adr/0003-auth-mvp.md`
**Вердикт:** **`approve`**

---

## Проверка трёх исправлений Round 2

### R2-BLOCKER-1 — JWT-литерал в conftest.py

**Файл:** `backend/conftest.py:17`
**Статус: ЗАКРЫТО**

```python
os.environ.setdefault("JWT_SECRET_KEY", secrets.token_urlsafe(48))
```

Литеральная строка длиной 64 символа заменена на `secrets.token_urlsafe(48)`. Секрет генерируется при каждом запуске тестовой сессии, не фиксируется в коде репозитория. Валидатор `_check_not_weak_secret` пропустит значение: результат `token_urlsafe` содержит только `[A-Za-z0-9_-]` символы и не попадает в стоп-лист `{"change_me", "secret", "test", "default"}`. Исправление корректно. Комментарий в коде явно ссылается на замечание R2-BLOCKER-1.

---

### R2-MAJOR-1 — стоп-слово в .env.example

**Файл:** `backend/.env.example:24`
**Статус: ЗАКРЫТО**

```
JWT_SECRET_KEY=__GENERATE_VIA_secrets.token_urlsafe(32)__
```

Прежнее значение `change_me_to_random_32_char_secret` заменено на `__GENERATE_VIA_secrets.token_urlsafe(32)__`. Новое значение содержит подстроку `secret` (от слова `secrets`), что означает: если разработчик скопирует `.env.example` в `.env` без изменений — приложение упадёт при старте с ошибкой валидатора. Это защитное поведение, соответствующее назначению валидатора. Цель замечания достигнута: шаблонное значение теперь документирует способ генерации вместо создания иллюзии реального ключа. Комментарий-инструкция (`python -c "import secrets; print(secrets.token_urlsafe(32))"`) расположен непосредственно над строкой `JWT_SECRET_KEY`.

**Замечание (nit):** Предложенный в Round 2 вариант `your-random-32-char-secret-here` тоже содержал подстроку `secret` и уронил бы приложение. Оба варианта функционально эквивалентны по этому критерию — принятое решение ничем не хуже рекомендованного.

---

### R2-MINOR-1 — различающийся detail на GET /auth/me для деактивированного пользователя

**Файл:** `backend/app/api/deps.py:92–94`
**Статус: ЗАКРЫТО**

```python
if not user.is_active:
    # Унифицируем detail с другими 401 (anti-enumeration, R2-MINOR-1)
    raise credentials_exception
```

Ветка деактивированного пользователя теперь поднимает `credentials_exception` напрямую вместо `HTTPException(detail="Аккаунт деактивирован")`. `detail` унифицирован с остальными ветками 401 в этой функции. Anti-enumeration соблюдён.

**Остаточный nit (не блокирует):** `test_me_with_token_for_deactivated_user_returns_401` проверяет только `status_code == 401`, но не проверяет `detail`. Тест не обнаружит регрессию, если `detail` снова разойдётся. Рекомендуется добавить проверку в следующем спринте — но для текущего коммита не является блокером, так как фикс в коде корректен.

---

## Проверка на регрессии

| Область | Проверено | Результат |
|---|---|---|
| conftest.py — поведение setdefault | `os.environ.setdefault` не перезаписывает переменную, если она уже задана | Корректно: если в CI задан `JWT_SECRET_KEY`, тест использует его |
| .env.example — доступность инструкции | Комментарий и значение расположены рядом | Корректно |
| deps.py — ветки get_current_user | Все четыре ветки (ExpiredSignatureError, InvalidTokenError, user is None, not is_active) поднимают credentials_exception | Корректно, без регрессий |
| Тест test_login_deactivated_user_returns_401 | Проверяет detail для /login — не затронут изменениями deps.py | Корректно |
| security.py, config.py, auth.py | Не изменялись в Round 3 | Регрессий нет |

---

## Незакрытые пункты предыдущих раундов (не в scope Round 3)

| ID | Приоритет | Описание | Статус |
|---|---|---|---|
| P2-1 | Minor | ADR 0003: `JWT_SECRET` vs `JWT_SECRET_KEY`, `JWT_ACCESS_TTL_MINUTES` vs `JWT_EXPIRE_MINUTES` — amendment к ADR не добавлен | К архитектору, не в scope |

---

## Резюме

Все три замечания Round 2 устранены корректно. R2-BLOCKER-1: литерал JWT-ключа заменён генерацией через `secrets.token_urlsafe`. R2-MAJOR-1: шаблонное значение в `.env.example` теперь документирует способ генерации. R2-MINOR-1: `detail` унифицирован через повторное использование `credentials_exception`. Регрессий не обнаружено. Тесты: 19 passed, 1 deselected. Ruff чистый.

**Вердикт: `approve`**

---

*Отчёт записан субагентом `reviewer` по делегированию Координатора.*
