# Дев-бриф: H-2 fix — блокировка git add -A в worktree (RFC-004 Phase I-a)

- **Дата:** 2026-04-18
- **Автор:** backend-head
- **Получатель:** backend-dev-1
- **Приоритет:** P1
- **Оценка:** 0.5 дня (подтверждена)
- **Scope-vs-ADR:** verified (RFC-004 Phase I-a); gaps: none

---

## Контекст

Пилот hooks-phase-0 прогонялся в worktree `/root/worktrees/coordinata56-hooks-pilot/`. Мина 2 (15 staged файлов, 3 «чужих» с устаревшим mtime) завершилась FAIL: коммит прошёл молча, H-2 не сработал.

Диагностика показала **две независимые причины** (обе требуют исправления):

**Причина А (корневая) — hook не установлен в worktree.**
`install-hooks.sh` вычисляет `GIT_HOOKS_DIR="${REPO_ROOT}/.git/hooks"`. В git-worktree нет физической папки `.git/` — вместо неё файл `.git` с указателем на `gitdir`. Проверка `[[ ! -d "${GIT_HOOKS_DIR}" ]]` провалится и скрипт завершится с ошибкой (или, если `.git` — файл, а не директория, путь просто окажется неверным). Хук в worktree не ставится — `git commit` вызывает hook из общего `.git/worktrees/<name>/hooks/` или не вызывает вовсе.

**Причина Б (вторичная) — неверный REPO_ROOT в check_add_all.py.**
Строка 41 `check_add_all.py`:
```python
REPO_ROOT = SCRIPT_DIR.parent.parent
```
Когда хук запускается из worktree, `SCRIPT_DIR` указывает на директорию внутри `.git/worktrees/<name>/hooks/`. Путь `.parent.parent` резолвится на `.git/worktrees/<name>/` — не на корень worktree. В результате `git -C str(REPO_ROOT) status --porcelain` отрабатывает в неверной директории, возвращает пустой список staged файлов, и `len(staged) <= 10` → `return 0`.

---

## Что конкретно сделать

### Шаг 1. Диагностика (артефакт обязателен)

Запустить в worktree:
```bash
ls /root/worktrees/coordinata56-hooks-pilot/.git 2>&1
# Если файл (не директория) — причина А подтверждена
git -C /root/worktrees/coordinata56-hooks-pilot rev-parse --git-dir
git -C /root/worktrees/coordinata56-hooks-pilot rev-parse --show-toplevel
```
Вывод приложить в отчёт как артефакт-доказательство.

### Шаг 2. Исправление install-hooks.sh

Файл: `scripts/install-hooks.sh`

Проблема: `GIT_HOOKS_DIR="${REPO_ROOT}/.git/hooks"` — не работает для worktree.

Исправление: определять `GIT_HOOKS_DIR` через `git rev-parse`:
```bash
GIT_HOOKS_DIR="$(git -C "${REPO_ROOT}" rev-parse --git-dir)/hooks"
```
`git rev-parse --git-dir` для worktree возвращает реальный путь к git-метаданным (например, `/root/coordinata56/.git/worktrees/coordinata56-hooks-pilot`), а не символический `.git`. После дописать `/hooks` — и `mkdir -p` при необходимости.

Также убрать проверку `[[ ! -d "${GIT_HOOKS_DIR}" ]]` как индикатор git-репо — вместо неё использовать `git rev-parse --is-inside-work-tree`.

### Шаг 3. Исправление check_add_all.py

Файл: `scripts/hooks/check_add_all.py`

Проблема: строка 41 `REPO_ROOT = SCRIPT_DIR.parent.parent`.

Исправление — заменить на:
```python
import subprocess as _sp
_result = _sp.run(
    ["git", "rev-parse", "--show-toplevel"],
    capture_output=True, text=True, check=False
)
REPO_ROOT = Path(_result.stdout.strip()) if _result.returncode == 0 else SCRIPT_DIR.parent.parent
```
Это надёжно работает как для основного репо, так и для любого worktree.

### Шаг 4. Жёсткий fallback (дополнительный критерий)

В `check_add_all.py` после строки `if len(staged) <= STAGED_THRESHOLD: return 0` добавить:
```python
# Жёсткий fallback: staged > 30 в non-TTY без ENV → безусловный блок
# (признак git add -A независимо от реестра/mtime)
NON_TTY_HARD_BLOCK_THRESHOLD = 30
if len(staged) > NON_TTY_HARD_BLOCK_THRESHOLD and not sys.stdin.isatty():
    if not os.environ.get("COORDINATOR_ALLOW_ADD_ALL") == "1":
        print(
            f"HOOK H-2 BLOCK: non-TTY, staged {len(staged)} > {NON_TTY_HARD_BLOCK_THRESHOLD} "
            f"без COORDINATOR_ALLOW_ADD_ALL=1. Безусловный блок.",
            file=sys.stderr,
        )
        return 1
```
Размещение: сразу после порогового раннего выхода `<= STAGED_THRESHOLD`, до вызова `classify_foreign_files`.

Константу `NON_TTY_HARD_BLOCK_THRESHOLD = 30` разместить в секции констант рядом с `STAGED_THRESHOLD`.

### Шаг 5. Прогон тестов

После правок:
```bash
# Переустановить хук в worktree:
cd /root/worktrees/coordinata56-hooks-pilot && bash /root/coordinata56/scripts/install-hooks.sh

# Мина 2 должна вернуть RESULT: PASS:
bash /root/coordinata56/docs/research/pilots/hooks-phase-0-test-fixtures/mine-2-git-add-all/reproduce.sh

# ENV-обход мины 2 должен по-прежнему работать (exit 0):
COORDINATOR_ALLOW_ADD_ALL=1 bash /root/coordinata56/docs/research/pilots/hooks-phase-0-test-fixtures/mine-2-git-add-all/reproduce.sh

# Мины 1 и 5 не должны сломаться:
# (прогнать вручную из основного репо или через run-all-mines)

# ruff:
ruff check /root/coordinata56/scripts/hooks/
```

Лог вывода каждой команды приложить в отчёт.

---

## Критерии приёмки (DoD)

- [ ] `bash mine-2-git-add-all/reproduce.sh` → `RESULT: PASS` (H-2 сработал + перечислил `_mine2_worker_a` файлы)
- [ ] `COORDINATOR_ALLOW_ADD_ALL=1 bash mine-2-git-add-all/reproduce.sh` → `exit 0` + запись в `git_add_all_log.md`
- [ ] Мины 1 и 5 — по-прежнему PASS (регрессия недопустима)
- [ ] В отчёте: диагностика root-cause с артефактом (`ls .git`, `git rev-parse` выводы)
- [ ] `ruff check scripts/hooks/` — 0 ошибок
- [ ] Не коммитить. Коммит — Координатор.

---

## FILES_ALLOWED

- `scripts/hooks/check_add_all.py`
- `scripts/hooks/pre-commit` (только при необходимости)
- `scripts/install-hooks.sh`
- `scripts/hooks/tests/*` (если есть — обновить тесты под новый REPO_ROOT)
- `docs/research/pilots/hooks-phase-0-test-fixtures/run-all-mines.log` (обновление лога)

## FILES_FORBIDDEN

- `backend/**`
- `.github/workflows/**`
- `docs/adr/**`
- `docs/agents/**`
- Скрипты других H-хуков (H-1, H-3, H-5), кроме диагностического чтения

---

## Обязательно прочитать перед началом

1. `/root/coordinata56/CLAUDE.md` — раздел «Git»
2. `/root/coordinata56/docs/agents/departments/backend.md` — чек-лист самопроверки
3. `scripts/hooks/check_add_all.py` — текущая реализация (строка 41 — ключевая)
4. `scripts/install-hooks.sh` — строки 17-19, 35-38 (проблемная логика GIT_HOOKS_DIR)
5. `docs/research/pilots/hooks-phase-0-test-fixtures/run-all-mines.log` — текущие результаты
6. `docs/research/pilots/hooks-phase-0-test-fixtures/mine-2-git-add-all/reproduce.sh` — фикстура мины 2

---

## Блокеры — эскалировать backend-head

- Если worktree `/root/worktrees/coordinata56-hooks-pilot/` не существует — сообщить, не воссоздавать самостоятельно.
- Если при установке хука в worktree возникает ошибка `core.hooksPath` из глобального git-конфига — сообщить.

---

## Отчёт (≤200 слов)

Структура:
1. Root-cause (какой из вариантов подтверждён артефактом)
2. Что исправлено (файл + строки)
3. Результат прогона мин (PASS/FAIL по каждой)
4. ruff статус
