# Code Review Round 2 — Phase 2 (Authentication, JWT, RBAC)

**Предыдущий коммит:** `15a7479`
**Дата ревью:** 2026-04-15
**Ревьюер:** субагент `reviewer`
**Основание:** повторное ревью после фикса P0/P1 из `phase2-auth-2026-04-15.md`
**ADR-источник:** `docs/adr/0003-auth-mvp.md`
**Вердикт:** **`request-changes`** (1 blocker — новый, 1 major — новый, 1 minor — остаточный)

---

## Итог проверки заявленных исправлений

| ID | Заявлено | Исправлено? | Оценка |
|---|---|---|---|
| P0-1 | timing-attack на /login | ДА | Корректно |
| P0-2 | default JWT_SECRET_KEY | ДА | Корректно — но появилась новая проблема (NB-1) |
| P1-1 | разные detail в 401 на /login | ДА | Частично — /login исправлен, /me — нет (см. R2-P1-1) |
| P1-2 | plain-text пароля в seed | ДА | Корректно |
| P1-4 | detail /register раскрывает email | ДА | Корректно |
| P2-2 | max_length=128 на password | ДА | Корректно |
| P2-4 | whitespace-only validator | ДА | Корректно |
| Nit-1 | functools.wraps в require_role | ДА | Исправлено через `__name__`/`__qualname__` — приемлемо |
| Nit-2 | устаревший комментарий в health.py | ДА | Комментарий удалён |

---

## Новые замечания

### R2-BLOCKER-1. Секрет в conftest.py закоммичен в репозиторий

**Файл:** `/root/coordinata56/backend/conftest.py:16`
**Приоритет:** blocker

```python
os.environ.setdefault(
    "JWT_SECRET_KEY",
    "xK9mP2qR7vL4nW8hY6jD3bF5tA1cU0sE9iO3kN7mQ2pX6vR4wL8hZ5jB0dG1",
)
```

Строка выглядит как случайный секрет, однако она **зафиксирована в коде репозитория** в виде литеральной строки. Это нарушает OWASP A02 и глобальное правило проекта: «секреты и ключи никогда не коммитить».

Аргумент «это только для тестов» не снимает проблему по нескольким причинам:

1. Если в CI/CD не задана переменная `JWT_SECRET_KEY`, тесты автоматически используют этот жёстко прописанный ключ. JWT-токены, подписанные в тестах, становятся валидными для любого стенда, где эта же строка используется (а она будет использована, если разработчик запустит приложение без .env).
2. Ключ попадает в историю git и не может быть удалён без полного переписывания истории.
3. Значение не содержит запрещённых слов из `_check_not_weak_secret`, поэтому validator его пропустит — но сам факт публичного секрета делает его компрометированным.

**Требуемый фикс:** заменить на `os.environ.setdefault("JWT_SECRET_KEY", secrets.token_urlsafe(32))` — генерировать случайный ключ при каждом запуске тестовой сессии. Для воспроизводимости можно использовать `os.environ.setdefault("JWT_SECRET_KEY", os.environ.get("TEST_JWT_SECRET_KEY", secrets.token_urlsafe(32)))` с отдельной переменной в CI-окружении.

---

### R2-MAJOR-1. `.env.example` содержит значение, которое проходит в продакшн

**Файл:** `/root/coordinata56/backend/.env.example:24`
**Приоритет:** major

```
JWT_SECRET_KEY=change_me_to_random_32_char_secret
```

Значение `change_me_to_random_32_char_secret` содержит подстроку `change_me` — она входит в стоп-лист `_check_not_weak_secret`. Это означает, что если разработчик скопирует `.env.example` в `.env` без изменений, приложение **упадёт при старте** с ошибкой валидации. Это правильное поведение.

Однако проблема в другом: `.env.example` используется как документация для нового разработчика/DevOps. Если они скопируют файл и подставят реальные значения для остальных параметров, но не поймут, как сгенерировать JWT-секрет, — сломанный деплой не даст подсказки о правильном способе генерации. Комментарий-инструкция в `.env.example` есть (`python -c "import secrets; print(secrets.token_urlsafe(32))"`), но он выше строки с JWT_SECRET_KEY и визуально не привязан к ней.

Это minor по факту, но поднято до major, так как сочетается с R2-BLOCKER-1: если разработчик видит жёстко прописанный ключ в conftest.py и похожую строку в .env.example, высок риск, что он подставит conftest-ключ напрямую в .env.

**Требуемый фикс:** заменить значение на `your-random-32-char-secret-here` (не содержит стоп-слов, но явно не является реальным ключом), переместить комментарий-инструкцию непосредственно перед строкой `JWT_SECRET_KEY`.

---

### R2-MINOR-1. Enumeration через различный detail на GET /auth/me (остаток P1-1)

**Файл:** `backend/app/api/deps.py:93–97`
**Приоритет:** minor

```python
if not user.is_active:
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Аккаунт деактивирован",
        ...
    )
```

P1-1 исправлен для `/login` — все три ветки там возвращают `"Неверный email или пароль"`. Но в `get_current_user` (эндпоинт `/me` и все защищённые маршруты) деактивированный пользователь получает `"Аккаунт деактивирован"`, тогда как стандартная ошибка — `"Не удалось проверить учётные данные"`.

Это раскрывает состояние аккаунта владельцу скомпрометированного токена. При этом в тесте `test_me_with_token_for_deactivated_user_returns_401` проверяется только статус-код 401, но не совпадение detail — несоответствие осталось незамеченным.

Исходный P1-1 формулировался как «разные detail в 401 на /login» — этот вопрос закрыт корректно. Найденное расхождение в `/me` — новое замечание, аналогичного характера, но уровня minor (так как /me требует валидный токен, который уже выдан именно этому пользователю, — риск enumeration ниже).

**Требуемый фикс:** в `get_current_user` заменить `detail="Аккаунт деактивирован"` на `detail="Не удалось проверить учётные данные"` (тот же detail, что и `credentials_exception`). Либо использовать `raise credentials_exception` напрямую.

---

## Проверка тестов qa

### Покрытие заявленных 6 новых тестов

| Тест | Что покрывает | Реально покрывает? | Замечание |
|---|---|---|---|
| `test_login_with_expired_token` | P1-3 expired token | ДА | Токен создаётся вручную с корректным exp в прошлом. Покрывает `jwt.ExpiredSignatureError` в deps.py:74 |
| `test_login_deactivated_user_returns_401` | P1-1 anti-enumeration | ДА | Проверяет и статус-код, и совпадение detail — тест качественный |
| `test_me_with_token_for_deactivated_user_returns_401` | ветка is_active в deps | ЧАСТИЧНО | Проверяет только status_code 401, не проверяет detail — расхождение detail не обнаруживается |
| `test_login_password_max_length_boundary` | P2-2 max_length=128 | ДА | Граничные значения 128/129 — корректный equivalence class |
| `test_login_password_whitespace_only_returns_422` | P2-4 whitespace-only | ДА | Простой и ясный тест |
| `test_login_timing_consistency` | P0-1 timing | УСЛОВНО | Помечен `@pytest.mark.timing`, WARMUP=2, SAMPLES=5 — порог 50 мс реалистичен для локального запуска, но тест может быть нестабилен в CI под нагрузкой. Приемлемо как smoke-тест при условии исключения из CI через `-m "not timing"` |

### Итог по тестам

19 тестов (без timing) заявлены как проходящие. Тесты качественные, фикстуры с откатом транзакций корректны. Единственное замечание — `test_me_with_token_for_deactivated_user_returns_401` не проверяет detail, поэтому не обнаруживает R2-MINOR-1.

---

## Проверка conftest.py на утечку секретов

**Результат: BLOCKER.** Подробно описано в R2-BLOCKER-1.

`/root/coordinata56/backend/conftest.py` содержит литеральный JWT-ключ длиной 64 символа, закоммиченный в репозиторий. Ключ технически сгенерирован случайно, но сам факт его фиксации в коде означает компрометацию с момента коммита.

---

## Прогон по OWASP Top 10

| Категория | Статус | Комментарий |
|---|---|---|
| A01 Broken Access Control | ✅ | RBAC через `require_role` корректен. Нет IDOR в текущих эндпоинтах |
| A02 Cryptographic Failures | ✅ (для кода) / ⚠️ (конфиг) | Код: bcrypt правильно, JWT-секрет без дефолта. Конфиг: conftest.py раскрывает ключ (R2-BLOCKER-1) |
| A03 Injection | ✅ | Seed-миграция использует параметризованные запросы через `sa.text()` с dict-параметрами |
| A04 Insecure Design | ✅ | Brute-force/rate-limiting — осознанно отложены (ADR Known risks) |
| A05 Security Misconfiguration | ⚠️ | R2-BLOCKER-1: ключ в коде. `initial_owner_password` в `config.py` имеет `default=""` — приемлемо (без него seed-миграция пропускается) |
| A06 Vulnerable Components | не проверялось | Вне скоупа этого ревью |
| A07 Identification & Auth | ✅ для /login | Timing защита реализована корректно. /me: R2-MINOR-1 (различающийся detail) |
| A08 Software/Data Integrity | ✅ | Нет небезопасной десериализации |
| A09 Logging & Monitoring | ✅ | Структурированное логирование всех событий входа с IP и user_id |
| A10 SSRF | ✅ | Нет user-controlled URL-запросов |

---

## Проверка соответствия ADR 0003

| Требование ADR | Реализовано? | Комментарий |
|---|---|---|
| OAuth2PasswordBearer | ДА | `fastapi.security.OAuth2PasswordBearer` |
| bcrypt через passlib | ДА | `CryptContext(schemes=["bcrypt"])` |
| HS256 | ДА | |
| JWT_SECRET обязательный без дефолта | ДА | `Field(...)` + field_validator |
| JWT_ACCESS_TTL_MINUTES (ADR) vs JWT_EXPIRE_MINUTES (код) | Незакрытое отклонение | ADR §3 требует amendment (P2-1 из раунда 1 — к архитектору, статус не изменился) |
| `JWT_SECRET` (ADR) vs `JWT_SECRET_KEY` (код) | Незакрытое отклонение | Аналогично P2-1 |
| plain-text пароля в памяти не сохраняется | ДА | `del password` в seed |
| Идемпотентная seed-миграция | ДА | |
| Аудит входов: user_id, IP, статус | ДА | |
| require_role dependency | ДА | |

---

## Итоговая сводная таблица

| ID | Приоритет | Файл | Описание | Статус |
|---|---|---|---|---|
| R2-BLOCKER-1 | Blocker | `backend/conftest.py:16` | JWT-ключ зафиксирован в коде репозитория | **Новое** |
| R2-MAJOR-1 | Major | `backend/.env.example:24` | Шаблонное значение JWT_SECRET_KEY может ввести в заблуждение | **Новое** |
| R2-MINOR-1 | Minor | `backend/app/api/deps.py:95` | Различающийся detail 401 для деактивированного пользователя на /me | **Новое** |
| P2-1 | Minor | ADR 0003 | JWT_SECRET / JWT_SECRET_KEY, JWT_ACCESS_TTL_MINUTES / JWT_EXPIRE_MINUTES — amendment не добавлен | К архитектору (не в scope этого раунда) |

---

## Резюме

Все заявленные исправления (P0-1, P0-2, P1-1 /login, P1-2, P1-4, P2-2, P2-4, Nit-1, Nit-2) выполнены корректно. Тесты qa качественные. Однако при реализации conftest.py допущена новая P0-уровневая ошибка: JWT-ключ закоммичен в репозиторий в открытом виде. Это нарушает OWASP A02 и глобальный регламент проекта. До устранения R2-BLOCKER-1 код не может быть принят.

**Вердикт: `request-changes`**

---

*Отчёт записан субагентом `reviewer` (исключение из ограничений на запись — собственный отчёт ревьюера по делегированию Координатора).*
