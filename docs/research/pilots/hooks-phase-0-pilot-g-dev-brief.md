# Dev-бриф: подзадача Г — Hooks Phase 0 Pilot

**Исполнитель:** qa-1  
**Выдан:** qa-head (coordinata56)  
**Дата:** 2026-04-18  
**Бюджет:** 120 мин (90 прогон + 30 исправления фикстур)  
**Статус фикстур:** исправления применены qa-head до передачи брифа (см. §1)

---

## §1. Исправления фикстур — применены, верифицируй

qa-head уже внёс три хирургических правки. Перед прогоном проверь что они на месте.

### Правка 1 — mine-2: путь active-workers.json

Файл: `docs/research/pilots/hooks-phase-0-test-fixtures/mine-2-git-add-all/reproduce.sh`

Было:
```
ACTIVE_WORKERS_FILE="$REPO_ROOT/.claude/active-workers.json"
```
Стало:
```
ACTIVE_WORKERS_FILE="/root/.claude/teams/default/active-workers.json"
```
Проверка: `grep ACTIVE_WORKERS_FILE docs/research/pilots/hooks-phase-0-test-fixtures/mine-2-git-add-all/reproduce.sh` должен вернуть `/root/.claude/teams/default/active-workers.json`.

### Правка 2 — mine-2: схема JSON и логика «чужих» файлов

Файл: `docs/research/pilots/hooks-phase-0-test-fixtures/mine-2-git-add-all/active-workers-fixture.json`

Ключевые изменения:
- Верхний ключ `active_workers` → `workers` (как ожидает `data.get("workers", [])` в check_add_all.py)
- Поле `subagent` → `id`
- Поле `owned_files` → `files_owned`
- Логика поменялась: воркер-б владеет 12 `_mine2_own_file*`, а файлы `_mine2_worker_a_file*` — не зарегистрированы ни у кого
- В reproduce.sh добавлен `touch -t` (mtime 6 часов назад) для файлов worker_a — это даёт им признак «чужой» (not in files_owned AND mtime > 4h)
- Placeholder `REPLACE_WITH_CURRENT_TIMESTAMP` в fixture подставляется через `sed` при прогоне

Проверка: `python3 -c "import json; d=json.load(open('docs/research/pilots/hooks-phase-0-test-fixtures/mine-2-git-add-all/active-workers-fixture.json')); print(list(d.keys()))"` должен вернуть `['_comment', '_logic', 'workers']`.

### Правка 3 — H-4 не вызывается в pre-commit

Файл: `scripts/hooks/pre-commit`

H-4 (`check_opus_prompts.py`) отсутствует в entrypoint. Варианты:
- **Вариант A (рекомендован для пилота):** Тестировать H-4 через прямой вызов:
  ```bash
  python3 scripts/hooks/check_opus_prompts.py
  ```
  при наличии подготовленного staged diff (см. §3.2 mine-4 ниже). Это соответствует тому, как сам скрипт поддерживает вызов вне pre-commit.
- **Вариант B (scope расширяется):** Добавить в pre-commit вызов H-4 информационно (аналогично H-3). Это требует правки кода — НЕ делать в рамках пилота, сначала зафиксировать как BUG в отчёте.

**Решение qa-head: использовать Вариант A, зафиксировать отсутствие H-4 в entrypoint как BUG-G-001.**

---

## §2. Подготовка окружения

### 2.1. Git worktree

```bash
cd /root
git worktree add /root/worktrees/coordinata56-hooks-pilot main
```

Если worktree уже существует:
```bash
ls /root/worktrees/coordinata56-hooks-pilot/.git
# если есть — пропустить создание
```

### 2.2. Установка хуков в worktree

```bash
cd /root/worktrees/coordinata56-hooks-pilot
bash scripts/install-hooks.sh
```

Проверка:
```bash
test -x /root/worktrees/coordinata56-hooks-pilot/.git/hooks/pre-commit && echo "OK" || echo "FAIL"
```

Проверка наличия active-workers.json:
```bash
test -f /root/.claude/teams/default/active-workers.json && echo "OK" || echo "MISSING"
```

### 2.3. Проверка opus-agents.yaml (нужен для H-4)

```bash
test -f /root/worktrees/coordinata56-hooks-pilot/docs/agents/opus-agents.yaml && echo "OK" || echo "MISSING — эскалировать к Координатору"
```

Если файл отсутствует — H-4 будет выводить WARN «файл справочника не найден» и возвращать exit 0 (пустой set). Mine 4 в этом случае результат PARTIAL, не FAIL.

---

## §3. Прогон мин (5 штук)

### 3.1. Автоматические мины (bash)

Запускать из worktree:

```bash
REPO_ROOT=/root/worktrees/coordinata56-hooks-pilot \
  bash /root/coordinata56/docs/research/pilots/hooks-phase-0-test-fixtures/run-all-mines.sh
```

Это прогонит mine-1, mine-2, mine-5 автоматически. Mine-3 и mine-4 — manual, скрипт их пропустит с меткой MANUAL.

Для каждой из трёх автоматических мин зафиксируй:
- exit code reproduce.sh
- строку RESULT: PASS / PARTIAL / FAIL
- stderr-фрагмент (первые 20 строк вывода если длинный)

**Mine-1 (H-1 — секреты) — MANDATORY.** Если FAIL → P0 REJECT, дальнейший прогон бессмыслен, немедленно эскалировать.

### 3.2. Manual мины (прямой python3, не Claude CLI)

#### Mine 3 — H-3 (dormant notify)

Подготовка пустого реестра активных агентов:
```bash
cp /root/coordinata56/docs/research/pilots/hooks-phase-0-test-fixtures/mine-3-sendmessage-dormant/active-agents-empty.json \
   /root/.claude/teams/default/active-agents.json
```

Прямой вызов хука (H-3 — `check_dormant_notify.py`):
```bash
cd /root/worktrees/coordinata56-hooks-pilot
python3 scripts/hooks/check_dormant_notify.py
```

Зафиксировать:
- есть ли substring `H-3` в stderr?
- упоминается ли `design-director` или другой dormant-агент?

Вердикт по таблице из mine-3/reproduce.md.

Откат:
```bash
rm -f /root/.claude/teams/default/active-agents.json
```

#### Mine 4 — H-4 (opus без ultrathink)

Подготовить Python-файл с вызовом Opus-агента без ultrathink:
```bash
cat > /tmp/mine4_test.py << 'EOF'
# test fixture mine-4: Agent call to opus without ultrathink
result = Agent(
    subagent_type="backend-director",
    prompt="Проверь, нужно ли переименовать файл backend/app/api/projects.py.",
)
EOF
```

Добавить в staging и вызвать H-4 напрямую через staged diff:
```bash
cd /root/worktrees/coordinata56-hooks-pilot
cp /tmp/mine4_test.py backend/tmp_mine4_test.py
git add backend/tmp_mine4_test.py
python3 scripts/hooks/check_opus_prompts.py
git reset HEAD backend/tmp_mine4_test.py
rm -f backend/tmp_mine4_test.py
```

Зафиксировать:
- есть ли substring `H-4` в stderr?
- упоминается ли `backend-director`?
- упоминается ли `ultrathink`?

Если `opus-agents.yaml` отсутствует — H-4 вернёт предупреждение и exit 0, это PARTIAL.

---

## §4. Прогон 20 чистых сценариев (false-positive guard)

Файл сценариев: `docs/research/pilots/hooks-phase-0-test-fixtures/clean-scenarios.md`

**Автоматические (bash): сценарии 1-11, 18-20 — 17 штук.**

Для каждого выполнить команду из колонки «Команда/действие» таблицы (адаптировать пути к worktree), зафиксировать:
- exit code коммита
- наличие substring `HOOK H-N` в stderr (false-positive если есть)

Важные нюансы:
- Сценарий 10: `git add -A` на ≤10 файлов — H-2 должен молчать (порог = >10).
- Сценарии 18-20: ruff-clean файлы. Перед commit убедиться что `ruff check <file>` возвращает exit 0.

**Manual (не bash): сценарии 12-13, 14-17 — 3 группы, тоже прямой python3.**

- Сценарии 12-13 (H-3, active agent): запустить `check_dormant_notify.py` при наличии актуального `active-agents.json` (не пустого). Если воспроизвести активное состояние агента нельзя — отметить "not testable in this run", не считать false-positive.
- Сценарии 14-17 (H-4): подготовить diff с вызовом Opus-агента С ultrathink и diff с вызовом Sonnet-агента. Запустить `check_opus_prompts.py`. Ожидание: тишина в stderr (no warn).

Допустимый лимит false-positive: ≤1 из 20.

---

## §5. Измерение оверхеда

```bash
cd /root/worktrees/coordinata56-hooks-pilot
REPO_ROOT=/root/worktrees/coordinata56-hooks-pilot \
  bash docs/research/pilots/hooks-phase-0-test-fixtures/measure-overhead.sh
```

Зафиксировать строки из Summary:
```
baseline: avg_real=X.XXXs ...
treatment: avg_real=X.XXXs ...
overhead: diff=X.XXXs
ACCEPTANCE §4.3: PASS/FAIL
```

Acceptance: overhead ≤ 2.0s.

---

## §6. Rollback verification

Проверить что rollback работает за ≤1 минуту:

```bash
cd /root/worktrees/coordinata56-hooks-pilot
time bash scripts/rollback-hooks.sh
```

Зафиксировать:
- время выполнения (должно быть < 60 секунд)
- наличие/отсутствие `.git/hooks/pre-commit` после rollback
- наличие `.git/hooks/pre-commit.bak` (оригинальный backup)

После проверки — восстановить хук для дальнейшей работы:
```bash
bash scripts/install-hooks.sh
```

---

## §7. Acceptance criteria (из §4 RFC-004 Phase 0 plan)

| Критерий | Требование | Статус |
|----------|------------|--------|
| AC-1 | ≥4/5 мин заблокированы/пойманы (warn считается) | _заполнить_ |
| AC-2 | ≤1/20 false-positive на чистых сценариях | _заполнить_ |
| AC-3 | Оверхед pre-commit ≤2 сек | _заполнить_ |
| AC-4 | Rollback ≤1 минуты | _заполнить_ |
| AC-5 | H-1 (секреты) mandatory — FAIL → P0 REJECT | _заполнить_ |

---

## §8. Формат отчёта

Сохранить в: `docs/research/pilots/2026-04-18-hooks-phase-0-report.md`

Структура (шаблон ri-analyst):

```markdown
# Hooks Phase 0 — Отчёт пилота

**Дата:** 2026-04-18  
**Исполнитель:** qa-1  
**Статус:** PASS / CONDITIONAL_PASS / REJECT  

## §1. Итог по минам

| Мина | Хук | Результат | Exit code | Substring найден | Примечания |
|------|-----|-----------|-----------|------------------|------------|
| 1    | H-1 | PASS/FAIL |           |                  |            |
| 2    | H-2 | ...       |           |                  |            |
| 3    | H-3 | ...       |           |                  |            |
| 4    | H-4 | ...       |           |                  |            |
| 5    | H-5 | ...       |           |                  |            |

## §2. False-positive guard (20 сценариев)

| Сценарии | False-positive count | Нарушители | Итог |
|----------|---------------------|-----------|------|
| 1-20     |                     |           |      |

## §3. Оверхед

| Режим | avg_real | max_real | n |
|-------|----------|----------|---|
| baseline |       |          |   |
| treatment |      |          |   |
| overhead diff |  |          |   |

Acceptance §4.3: PASS/FAIL

## §4. Rollback

Время: Xс  
Acceptance: PASS/FAIL  

## §5. Баги

| BUG-ID | Хук | Описание | Severity |
|--------|-----|----------|----------|
| BUG-G-001 | H-4 | check_opus_prompts.py не вызывается в pre-commit entrypoint | P1 |
| ...    |     |          |          |

## §6. Acceptance criteria — финальная таблица

| AC | Требование | Факт | Статус |
|----|-----------|------|--------|
| AC-1 | ≥4/5 мин | X/5 | PASS/FAIL |
| AC-2 | ≤1/20 false-pos | X/20 | PASS/FAIL |
| AC-3 | overhead ≤2s | Xs | PASS/FAIL |
| AC-4 | rollback ≤60s | Xs | PASS/FAIL |
| AC-5 | H-1 mandatory | PASS/FAIL | PASS/FAIL |

## §7. Вердикт

PASS / CONDITIONAL_PASS / REJECT + обоснование.
```

---

## §9. Что НЕ входит в scope

- Правка кода хуков (репортить как баг, не чинить)
- Добавление H-4 в pre-commit entrypoint (BUG-G-001, решение — за backend-dev)
- Тестирование H-3 через реальный Claude CLI (manual-прогоны через прямой python3)
- Любые изменения в `scripts/hooks/*.py`

---

## §10. Контакты и эскалация

- P0 (H-1 fail) → немедленно остановить, сообщить qa-head
- Отсутствие `opus-agents.yaml` → сообщить qa-head, прогон mine-4 пометить PARTIAL
- worktree не создаётся (конфликт) → `git worktree remove --force` и пересоздать
