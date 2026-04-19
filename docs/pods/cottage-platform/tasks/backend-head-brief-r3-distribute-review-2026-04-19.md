# backend-head brief — Sprint 1 regression Round 3 (distribute + review)

**Волна:** Sprint 1 regression hotfix Round 3.
**От:** backend-director.
**Источник:** `docs/pods/cottage-platform/quality/sprint1-regression-report-round2-2026-04-19.md` (RED STOP).
**Pattern:** Pattern 5 fan-out, 2 Worker параллельно.
**Твоя роль (L3):** распределить → первичный review diff'ов → отчитаться Директору.

---

## ПЕРЕД СТАРТОМ — ПРОЧТИ

1. `/root/coordinata56/CLAUDE.md` (Git §: запрет `git add -A` при активных агентах).
2. `/root/coordinata56/docs/agents/departments/backend.md` (Pattern 5 §, ADR-gate).
3. `docs/agents/departments/backend-queue.md` — свежая запись «Wave: Sprint 1 regression hotfix Round 3».
4. Отчёт Round 2 полностью.

---

## Твоя работа

### Шаг 1 — Распределить

Координатор спавнит 2 backend-dev'а параллельно. Ты в этот момент уже знаешь, какие брифы им дали (видишь queue). Проверь у обоих, что они прочитали свой бриф (в отчёте — упоминание брифа по имени).

### Шаг 2 — Принять diff'ы и сделать первичное ревью

Когда оба Worker'а вернулись, выполни:

```bash
cd /root/coordinata56
git status --short
git diff --stat
```

Проверь по **Worker A**:
- Ровно 8 файлов изменены (+/- может быть 1 если test_permissions_api.py потребовал правки).
- `permission.py`: Literal расширен до 7 actions в обоих схемах (Read и Create).
- 6 BUG-005 файлов: единственное изменение — строка fallback URL (все идентичные).
- `test_multi_company_isolation.py`: 1 строка (FINISH → INTERIOR).
- Никакого расширения scope.

Проверь по **Worker B**:
- Ровно 6 файлов изменены.
- В каждом добавлен импорт `from app.models.user_company_role import UserCompanyRole`.
- В каждом user-fixture (owner, read_only, accountant, cm — где был в файле) создаётся UCR с **совпадающим** `role_template`.
- В fixtures для Stage / HouseType / OptionCatalog / House / HouseConfiguration / HouseStageHistory / HouseTypeOptionCompat есть `company_id=1`.
- BudgetCategory / BudgetPlan / MaterialPurchase Worker B **не трогал** (они — территория Worker A по BUG-005).

### Шаг 3 — Acceptance regression

```bash
cd /root/coordinata56
docker compose -f docker-compose.dev.yml up -d postgres  # если ещё не поднято
TEST_DATABASE_URL="postgresql+psycopg://coordinata:change_me_please_to_strong_password@localhost:5433/coordinata56_test" \
  pytest backend/tests -q --tb=no 2>&1 | tail -15
```

**Ожидание (DoD волны):**
- `PASSED >= 400`
- `ERROR == 0`
- `FAILED <= ~40` (pre-existing test_zero_version_stubs 16 штук допустимы; остальные — максимум BUG-004 migration count 1 шт., BUG-006 consent 1 шт., и мелочь)
- **НЕТ 403 на owner-эндпоинтах.**
- **НЕТ NotNullViolation.**
- **НЕТ no password supplied.**
- **НЕТ Literal validation error на permissions.**

Если acceptance не выполнен — возвращай Worker'у с конкретным указанием «в файле X осталось Y, см. тест Z вывод W». Не принимай partial fix, это анти-паттерн Round 2.

### Шаг 4 — Ruff + линт-миграции

```bash
cd /root/coordinata56/backend && ruff check app tests
cd /root/coordinata56/backend && python -m tools.lint_migrations alembic/versions/
```

Оба должны быть чистыми (миграции не трогались, но double-check).

### Шаг 5 — Отчёт Директору

Формат (≤200 слов):
- **Вердикт:** accepted / returned.
- **Счётчики pytest:** PASS / FAIL / ERROR.
- **Изменённые файлы:** по Worker, с LOC.
- **Paczka ADR-gate self-check:** A.1-A.5 pass/fail по каждому Worker.
- **Open questions:** остающиеся FAIL с их причиной (BUG-004, BUG-006 — not in scope R3; pre-existing).
- **Следующая волна (если нужна):** BUG-004, BUG-006.

---

## FILES_ALLOWED (для тебя как ревьюера — только чтение)

- Всё, что в брифах A и B.

## FILES_ALLOWED (если сам правишь — исключение Pattern 5)

- Только при конфликте между Worker A и Worker B (маловероятно, файлы эксклюзивные). Если случилось — правишь конкретный конфликт, помечаешь в отчёте Директору. Остальное — только через Worker'ов.

## FILES_FORBIDDEN

- Миграции (`backend/alembic/**`) — не трогаем.
- Эндпоинты (`backend/app/api/**`) — не трогаем.

---

## COMMUNICATION_RULES

- Возврат Worker'у — прямое сообщение через Координатора (ты не спавнишь Worker'ов сам). В сообщении Координатору: «Worker X вернул, нужна доработка Y, передай ему такой followup».
- Отчёт Директору — один сводный, когда оба Worker'а приняты.
- Если после 2 раундов ревью один из Worker'ов не справился — эскалируй Директору, не давай 3-й раунд без его решения.

---

## Чек-лист приёмки волны (делаешь ты)

- [ ] Оба Worker'а отчитались и указали свой бриф.
- [ ] `git status --short` показывает ровно ожидаемые файлы (8 + 6 = 14; допустимо меньше, не больше).
- [ ] `git diff --stat` — объём изменений соразмерен (каждый файл — десятки строк).
- [ ] Ruff чисто.
- [ ] lint-migrations чисто.
- [ ] pytest: 0 ERROR, ≥400 PASS, 0 P0.
- [ ] ADR-gate самопроверок из обоих Worker-отчётов укомплектован.
- [ ] Отчёт Директору готов.
