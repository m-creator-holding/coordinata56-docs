# Бриф для ri-analyst — skill `test-secrets-hardening`

**Автор брифа:** ri-director
**Дата:** 2026-04-19
**Бюджет Analyst:** до 4 часов (регламент R&I §«Бюджет внимания»)
**Финальный артефакт:** `~/.claude/skills/test-secrets-hardening/SKILL.md` + эталонный прогон на живом `conftest.py` и 1 фикстуре.

---

## Почему этот скил сейчас

Правило «не литералить секреты в тестах» ловилось **трижды** за 3 месяца:
- Phase 2 Round 2 BLOCKER-1 (hardcoded пароль в фикстуре).
- Phase 3 Batch A step 2 Round 1 P0-2 (hardcoded токен в `conftest.py`).
- Регламент v1.3 §3 (сам факт появления правила).

Повторная ошибка одного и того же типа через 2 фазы — сигнал, что text-правило в CLAUDE.md не работает. Оно применяется только при письме тестов (≈20% сессий), но висит в always-on контексте. Перенос в skill: (а) освобождает CLAUDE.md; (б) при редактировании `tests/**` Claude Code получает активный чек-лист, не пассивное упоминание.

Дополнительный драйвер: в Sprint 1 M-OS-1.1A US-01..US-15 потребуется ~20-30 новых pytest-фикстур (per-company isolation) — высокий риск повтора.

## Что скил должен делать (scope)

1. **Триггер.** user-invocable=false, auto-invoke при работе в `backend/tests/**/*.py`, `conftest.py`, или появлении `@pytest.fixture` в diff'е.
2. **Вход.** Путь к тест-файлу или conftest'у.
3. **Шаги SKILL.md.**
   - **Шаг 1: grep на prod-like литералы.** Regex-паттерны: `password\s*=\s*["'](?!.*token_urlsafe)`, `token\s*=\s*["'][A-Za-z0-9]{16,}`, `secret\s*=\s*["']`, `api_key\s*=\s*["']`, `jwt.*=\s*["']eyJ`. Любое совпадение → P0 FAIL.
   - **Шаг 2: проверка на случайную генерацию.** Фикстуры, создающие пользователей/клиентов/токены, должны использовать `secrets.token_urlsafe(N)`, `secrets.token_hex(N)`, `uuid.uuid4()`, или `Faker`. Если фикстура возвращает статичный `password="test123"` — FAIL, предложить замену.
   - **Шаг 3: конфигурация через env.** В `conftest.py` grep на `os.environ.get` / `os.getenv` для секретов. Прямое присваивание `JWT_SECRET_KEY = "..."` в pyfile — FAIL. Исключение: явно dev-default через `os.environ.get("JWT_SECRET_KEY", secrets.token_urlsafe(32))`.
   - **Шаг 4: ПД-маскирование в ассертах и логах тестов.** Если тест проверяет логи/аудит (`caplog`, `assert "..." in log`), фильтровать на raw-паспорт/СНИЛС/ИНН-12 в assert'ах. Если найдено — предложить использовать masked helper (`mask_pii(value)` из `app/utils/pii.py` если есть).
   - **Шаг 5: scope pytest-фикстуры.** Секреты-фикстуры должны быть `scope="session"` с генерацией один раз, не `scope="function"` (потеря энтропии + перфоманс). WARN, не FAIL.
   - **Шаг 6: вывод.** PASS / WARN[список] / FAIL[список с номером строки и предлагаемой заменой].
4. **Выход.** Markdown-отчёт + готовые сниппеты замены для каждого FAIL.

## Что скил НЕ делает

- Не сканирует `src/` (это `bandit`, в CI).
- Не проверяет `.env.example` или `.env` (это pre-commit hook `detect-secrets`).
- Не валидирует функциональность тестов — только гигиену секретов.
- Не заменяет bandit или git-secrets — работает на уровне Claude Code-сессии до CI.

## Источники для Analyst

- `/root/coordinata56/CLAUDE.md` строки 48-51.
- `docs/agents/regulations_draft_v1.md` §3 (правило секретов).
- `backend/tests/conftest.py` (живой эталон — проверить соответствие самому скилу; если не проходит — Analyst отметит в отчёте как open issue для backend-dev).
- `~/.claude/skills/fz152-pd-checker/SKILL.md` — стиль SKILL.md (шаги + чек-лист + ловушки).
- Phase 2 Round 2 BLOCKER-1 и Phase 3 Batch A step 2 Round 1 P0-2 — живые кейсы для раздела «Почему этот скил».

## Ограничения

- Не менять backend регламент — governance-director.
- Не коммитить — Координатор.
- Не писать pre-commit hooks / CI — только SKILL.md + прогон.

## DoD брифа

1. `~/.claude/skills/test-secrets-hardening/SKILL.md` создан (80-100 строк).
2. Прогон на `backend/tests/conftest.py` + 1 фикстура — PASS/WARN/FAIL отчёт.
3. Отчёт Analyst'а ≤500 слов + если conftest.py не проходит — список конкретных строк для backend-dev.

## Метрика успеха после adopt

За Sprint 1 M-OS-1.1A (20-30 новых фикстур): 0 CI-замечаний от `bandit`/`detect-secrets` по категории hardcoded secrets в tests/**. Baseline за последние 3 фазы: 3 инцидента (P0/BLOCKER-level).
