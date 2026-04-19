# Bandit SAST Baseline — 2026-04-18

**Инструмент:** bandit 1.9.4  
**Скоуп:** `backend/app/` + `backend/tools/` + `backend/alembic/`  
**Команда:** `bandit -r backend/app backend/tools backend/alembic -f json`  
**Строк кода:** 15 784  
**Дата:** 2026-04-18  
**Статус:** baseline зафиксирован

---

## Сводка

| Severity | Confidence | Итого |
|---|---|---|
| HIGH | — | 0 |
| MEDIUM | — | 0 |
| LOW | MEDIUM | 1 |
| LOW | HIGH | 1 |

**Итого findings:** 2 (все LOW severity, нет HIGH/MEDIUM)

---

## Таблица findings

| # | Файл:строка | Правило | Severity | Confidence | Статус | Обоснование |
|---|---|---|---|---|---|---|
| 1 | `backend/app/api/auth.py:167` | B106 `hardcoded_password_funcarg` | LOW | MEDIUM | ACCEPT | `token_type="bearer"` — литерал типа токена OAuth2, не секрет; это публичная константа RFC 6750 |
| 2 | `backend/app/repositories/stage.py:65` | B110 `try_except_pass` | LOW | HIGH | ACCEPT | Явный `# noqa: BLE001` и комментарий уже присутствуют; блок защищает от гонки при отсутствии таблицы в ранних миграциях |

---

## Детали findings

### Finding #1 — B106 hardcoded_password_funcarg

**Файл:** `backend/app/api/auth.py`, строка 167  
**Фрагмент:**
```python
access_token=token,
token_type="bearer",   # <-- bandit видит "bearer" как пароль
consent_required=consent_required,
```
**Решение:** ACCEPT  
**Обоснование:** Строка `"bearer"` — это стандартное значение поля `token_type` в ответе OAuth2 (RFC 6749 §5.1). Это публичная константа протокола, а не учётные данные. Bandit B106 — ложноположительное срабатывание для OAuth2-кода.  
**Рекомендация:** Добавить `# nosec B106 — OAuth2 token_type literal, not a credential (RFC 6749 §5.1)` при следующем редактировании файла backend-программистом.

---

### Finding #2 — B110 try_except_pass

**Файл:** `backend/app/repositories/stage.py`, строка 65  
**Фрагмент:**
```python
except Exception:  # noqa: BLE001
    # На случай если таблица budget_plans ещё не существует в БД
    pass
```
**Решение:** ACCEPT  
**Обоснование:** Обработчик намеренный — защита от состояния гонки при первом запуске до полного применения миграций. Уже содержит пояснительный комментарий. После стабилизации схемы БД — кандидат на рефакторинг (узкий `except`, явная проверка существования таблицы).  
**Рекомендация:** Оставить в baseline. При следующем касании файла программистом — добавить `# nosec B110 — intentional fallback for pre-migration state, see comment above`.

---

## High-severity findings

Отсутствуют. HIGH findings: 0.

---

## Предлагаемая секция `[tool.bandit]` для `backend/pyproject.toml`

> НЕ применять самостоятельно — передать backend-head для внесения в pyproject.toml

```toml
[tool.bandit]
# Исключаем тесты (юнит/интеграционные) и тела миграций:
# — тесты используют намеренные паттерны (assert, subprocess, небезопасные конфиги для dev)
# — тела миграций ревьюируются вручную ревьюером (регламент quality.md)
exclude_dirs = ["tests", "alembic/versions"]

# skips пустые — ни одно правило не шумит настолько, чтобы требовать глобального отключения.
# B106 и B110 — точечные ACCEPT в baseline выше, не нуждаются в глобальном skip.
skips = []
```

**Объяснение выбора `exclude_dirs`:**
- `tests` — pytest-фикстуры намеренно используют паттерны, которые Bandit считает небезопасными (assert, subprocess и т.п.); security-аудит тестов — ручная проверка ревьюером.
- `alembic/versions` — тела миграций проверяются ревьюером вручную согласно регламенту quality.md; автоматический SAST здесь даёт шум без пользы (нет user-input, нет runtime-кода).

---

## Цикл пересмотра

- Пересмотр при подъёме версии Python или Bandit (мажорная версия).
- Раз в месяц quality-director инициирует перепроход: цель — сокращать FIX-LATER → ACCEPT/REMOVED.
- Новый PR не может добавить ACCEPT без согласования quality-director.
