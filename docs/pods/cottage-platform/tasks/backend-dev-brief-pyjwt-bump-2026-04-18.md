# Дев-бриф: Q-1 Follow-up — PyJWT bump 2.7.0 → >=2.12.0 + [tool.bandit]

- **Дата:** 2026-04-18
- **Автор:** backend-director (через backend-head)
- **Получатель:** backend-dev-1 (по загрузке, при занятости — backend-dev-2)
- **Приоритет:** P1 (HIGH CVE в auth-критичной зависимости; не откладывать)
- **Оценка:** ~0.5 дня
- **Scope-vs-ADR:** verified (ADR 0005/0006/0007/0011 не затрагиваются; auth-поверхность `core/security.py` + `api/deps.py` без изменений API); gaps: none
- **Источник:** `docs/reviews/pip-audit-baseline-2026-04-18.md` §Раздел A, `docs/reviews/bandit-baseline-2026-04-18.md` §«Предлагаемая секция [tool.bandit]»

---

## Контекст

qa-head прогнал Q-1 SAST baseline (Bandit + pip-audit). Два follow-up для бэкенда в одном PR:

1. **CVE-2026-32597 (HIGH) в PyJWT 2.7.0.** Fix: `>=2.12.0`. Суть CVE: PyJWT не валидирует `crit` header (RFC 7515 §4.1.11). В нашем коде `crit` не используется и внешние токены мы не принимаем, но уязвимость реальная и auth-критичная — закрыть сейчас.
2. **Секция `[tool.bandit]` в `backend/pyproject.toml`.** qa-head подготовил готовый фрагмент: `exclude_dirs = ["tests", "alembic/versions"]`, `skips = []`. Это нужно, чтобы Bandit-scan в CI не шумел на pytest-фикстурах и телах миграций (регламент `quality.md`).

Оба изменения — один PR. pyproject.toml и так правится — логично закрыть хвосты Q-1 одним коммитом.

---

## Что конкретно сделать

### Шаг 1. Проверить breaking changes между PyJWT 2.7.0 и 2.12.0

Наш код использует только три API-точки (проверено grep'ом):

| Место | Вызов |
|---|---|
| `backend/app/core/security.py:130` | `jwt.encode(payload, secret, algorithm=...)` |
| `backend/app/core/security.py:156` | `jwt.decode(token, secret, algorithms=[...])` |
| `backend/app/api/deps.py:99,102` | `except jwt.ExpiredSignatureError`, `except jwt.InvalidTokenError` |
| `backend/tests/test_auth.py:389` | `jwt.encode(...)` (для просроченного токена) |

Задача: пройти CHANGELOG PyJWT (2.8 → 2.9 → 2.10 → 2.11 → 2.12) и зафиксировать в отчёте:
- Поменялся ли сигнатурно `encode` / `decode` / типы исключений?
- Появились ли новые обязательные параметры (`options={"verify_crit": ...}`, `require=[...]`)?
- Требует ли 2.12 какой-то минимальной версии `cryptography`?

Источник: <https://pyjwt.readthedocs.io/en/stable/changelog.html>

Если API чист — продолжить. Если обнаружено breaking change — **остановиться и эскалировать backend-head** до правки кода.

### Шаг 2. Обновить версию в pyproject.toml

Файл: `backend/pyproject.toml`, строка 14.

Было:
```toml
"PyJWT[crypto]>=2.10.0",
```
Стало:
```toml
"PyJWT[crypto]>=2.12.0",
```

**Примечание.** Нижняя граница `>=2.10.0` уже в файле — это декларация. Фактически в окружении стоит `2.7.0` (см. pip-audit baseline), потому что `pip install` в проде мог быть сделан до фиксации новой границы. Поднять границу до `>=2.12.0` — принудит свежую установку и перегенерацию lock.

`requirements.txt` в репозитории отсутствует (проверено: `ls backend/requirements*.txt` пусто) — фиксация только в `pyproject.toml`.

### Шаг 3. Добавить секцию `[tool.bandit]` в pyproject.toml

Файл: `backend/pyproject.toml`. Вставить после блока `[tool.ruff.lint]` и до `[tool.mypy]` (порядок секций — как у ruff/mypy/pytest):

```toml
[tool.bandit]
# Исключаем тесты (юнит/интеграционные) и тела миграций:
# — тесты используют намеренные паттерны (assert, subprocess, небезопасные конфиги для dev)
# — тела миграций ревьюируются вручную ревьюером (регламент quality.md)
exclude_dirs = ["tests", "alembic/versions"]

# skips пустые — ни одно правило не шумит настолько, чтобы требовать глобального отключения.
# B106 и B110 — точечные ACCEPT в baseline (docs/reviews/bandit-baseline-2026-04-18.md).
skips = []
```

Комментарии оставить как есть — они документируют обоснование для ревьюера.

### Шаг 4. Переустановка зависимости и прогон тестов

```bash
cd /root/coordinata56/backend
pip install -U "PyJWT[crypto]>=2.12.0"
python -c "import jwt; print(jwt.__version__)"   # должно быть >=2.12.0
```

Прогон полного набора тестов:

```bash
cd /root/coordinata56/backend
pytest -q
```

**Ожидание:** 399 PASS (351 существующих + 48 audit-chain из PR-3 Wave 1). Таргет-модули auth:
- `backend/tests/test_auth.py` — ядро JWT issue/verify
- `backend/tests/test_pr2_rbac_integration.py` — интеграция RBAC поверх токена
- `backend/tests/test_company_scope.py` — company_ids в payload

Если `pytest -q` показывает дельту к 399 — **стоп, эскалация backend-head** с артефактом `pytest --tb=short` по упавшим тестам.

### Шаг 5. Ruff + Bandit smoke

```bash
cd /root/coordinata56/backend
ruff check app tests
bandit -r app tools alembic -q
```

Ожидание:
- ruff: 0 ошибок
- bandit: 2 findings LOW (те же, что в baseline: `auth.py:167` B106 и `stage.py:65` B110). Проверить что `tests/` и `alembic/versions/` теперь исключены из отчёта (сравнить счётчик `Total lines of code` с baseline — должен уменьшиться, т.к. tests/ выкинулся).

---

## Критерии приёмки (DoD)

- [ ] `backend/pyproject.toml`: PyJWT поднят до `>=2.12.0`
- [ ] `backend/pyproject.toml`: добавлена секция `[tool.bandit]` с `exclude_dirs = ["tests", "alembic/versions"]`, `skips = []`
- [ ] `python -c "import jwt; print(jwt.__version__)"` → `>= 2.12.0`
- [ ] Отчёт: таблица по breaking changes PyJWT 2.8→2.12 (что проверено, что не затронуто)
- [ ] `pytest -q backend/tests` → 399 PASS (0 FAIL, 0 ERROR). Вывод — в отчёт как артефакт (последние ~20 строк с summary)
- [ ] `ruff check backend/app backend/tests` — 0 ошибок
- [ ] `bandit -r backend/app backend/tools backend/alembic -q` — 2 findings LOW (не больше baseline)
- [ ] Прогон `pip-audit` в backend-venv или `pip-audit -r <формат>` → CVE-2026-32597 **отсутствует** в выводе. Приложить вывод в отчёт.
- [ ] Не коммитить. Коммит — Координатор.

---

## FILES_ALLOWED

- `backend/pyproject.toml` — только строка PyJWT и новая секция `[tool.bandit]`
- *(опционально, если при bump потребовался patch совместимости)* `backend/app/core/security.py`, `backend/app/api/deps.py`, `backend/tests/test_auth.py` — **только** при документированном breaking change, и только то, что этим change продиктовано

## FILES_FORBIDDEN

- любые другие файлы `backend/app/**`, `backend/tests/**` — **если PyJWT 2.12 API backward-compatible, изменения должны уместиться в один файл `pyproject.toml`**
- `docs/**` (кроме отчёта в чат, не .md файл)
- `.github/workflows/**`
- `alembic/versions/**`
- `frontend/**`, `scripts/**`

---

## COMMUNICATION_RULES

- Перед стартом — прочитать `CLAUDE.md` раздел «Секреты и тесты», «API» и `docs/agents/departments/backend.md` чек-лист ADR-gate (A.1–A.5).
- Если breaking change PyJWT обнаружен — стоп, сообщить backend-head до любой правки кода.
- Если `pytest -q` падает после bump — стоп, сообщить backend-head с артефактом pytest trace.
- Не трогать `audit-chain` и `RBAC v2` — их тесты не должны ломаться от PyJWT bump. Если они падают — это сигнал проблемы с JWT payload (скорее всего `datetime` / `iat` / `exp` handling, появлявшийся в PyJWT 2.8).

---

## Обязательно прочитать перед началом

1. `/root/coordinata56/CLAUDE.md` — секции «Секреты и тесты», «API»
2. `/root/coordinata56/docs/agents/departments/backend.md` — чек-лист самопроверки (ADR-gate A.1–A.5)
3. `/root/coordinata56/docs/reviews/pip-audit-baseline-2026-04-18.md` — §Раздел A, PyJWT 2.7.0 (контекст CVE)
4. `/root/coordinata56/docs/reviews/bandit-baseline-2026-04-18.md` — §«Предлагаемая секция [tool.bandit]»
5. PyJWT CHANGELOG: <https://pyjwt.readthedocs.io/en/stable/changelog.html>
6. `backend/app/core/security.py` — 162 строки, полностью
7. `backend/app/api/deps.py` — только строки 38–110 (секция JWT)

---

## Блокеры — эскалировать backend-head

- Обнаружено breaking change в PyJWT API (encode/decode/исключения) → стоп до обсуждения.
- `pytest -q` показывает дельту от 399 PASS → стоп, приложить trace.
- `pip install` отказывается ставить PyJWT 2.12 из-за конфликта версий `cryptography` → стоп, backend-head решит (возможно, нужен bump `cryptography` extras).
- Любые изменения, выходящие за `pyproject.toml` + 2 строки в security.py/deps.py → стоп, скоуп превышен.

---

## Отчёт (≤200 слов)

Структура:
1. **PyJWT CHANGELOG анализ** — breaking changes между 2.7.0 и 2.12.0 (таблица: версия / изменение / влияет на нас?)
2. **Что изменено** — `pyproject.toml` (PyJWT + [tool.bandit]). Если кода касались — файл + строки + причина
3. **pytest** — `399 PASS` (или дельта + анализ)
4. **ruff + bandit** — статусы
5. **pip-audit** — подтверждение что CVE-2026-32597 исчез
6. **Отклонения от scope** — если были (не должно)
