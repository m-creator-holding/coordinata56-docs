# Бриф для backend-head: H-2 fix — жёсткая блокировка `git add -A` без ENV-выхода

- **Дата:** 2026-04-18
- **Автор:** backend-director
- **Получатель:** backend-head
- **Исполнитель (рекомендуемый):** backend-dev-1 (владел hooks-phase-0 imp.)
- **Приоритет:** P1 (Phase I-a Hooks, RFC-004)
- **Оценка:** 0.5 дня

---

## Контекст

RFC-004 Phase I-a утверждён Владельцем. В пилоте hooks-phase-0 прогнано 5 мин (see `docs/research/pilots/hooks-phase-0-test-fixtures/run-all-mines.log`). **Мина 2 (`git add -A` с 15 staged и 3 «чужими» файлами) — FAIL, не PASS:** коммит `mine-2: git add -A on 15 files with foreign workers` прошёл молча, exit 0. Hook H-2 не сработал.

Диагноз: пилот прогонялся в worktree `/root/worktrees/coordinata56-hooks-pilot/`, в `.git/hooks/pre-commit` — вероятно не установлен копиями из `scripts/hooks/pre-commit` или `REPO_ROOT` в `check_add_all.py` смотрит не туда. Сам скрипт `scripts/hooks/check_add_all.py` логически корректен, но не вызывается либо возвращает 0 из-за mtime-эвристики.

Цель фикса: H-2 обязан **блокировать коммит в non-TTY без `COORDINATOR_ALLOW_ADD_ALL=1`**, когда staged > 10 и ≥3 «чужих» файлов. Мина 2 после фикса должна давать `exit 1` + substring `HOOK H-2` + перечисление 3 worker-a файлов.

---

## Что конкретно сделать

1. **Отдиагностировать, почему H-2 пропустил мину 2.** Артефакт диагностики: строка в `run-all-mines.log` или в отчёте — какая из трёх причин сработала: (а) `.git/hooks/pre-commit` отсутствует/не executable в `coordinata56-hooks-pilot` worktree; (б) `REPO_ROOT` в `check_add_all.py` резолвится на основной репо, не на worktree (строка 41: `REPO_ROOT = SCRIPT_DIR.parent.parent`); (в) `is_file_old()` вернул `False` для worker-a файлов (mtime проверка не сработала).
2. **Исправить root-cause.** Возможные правки:
   - Скрипт установки хуков `scripts/install-hooks.sh` должен ставить pre-commit в `.git/hooks/` того репо/worktree, где он запущен (проверить git `--git-dir`, `core.hooksPath`).
   - `REPO_ROOT` в `check_add_all.py` определять через `git rev-parse --show-toplevel`, не через `SCRIPT_DIR.parent.parent` — иначе для worktree резолв ломается.
   - Если проблема в mtime-эвристике — добавить дополнительный жёсткий критерий: в non-TTY режиме без `COORDINATOR_ALLOW_ADD_ALL=1` при staged > 30 блокировать безусловно (независимо от реестра/mtime), потому что это само по себе признак `git add -A`.
3. **Прогнать мину 2 повторно.** `bash docs/research/pilots/hooks-phase-0-test-fixtures/mine-2-git-add-all/reproduce.sh` должен вернуть `RESULT: PASS`. Лог приложить к отчёту.
4. **Прогнать мины 1 и 5** (сейчас PASS) — убедиться, что фикс H-2 не сломал остальные. Лог — в `run-all-mines.log`.
5. **Если понадобится менять фикстуру** (например, пересоздать реестр `active-workers.json` под новый путь) — координировать с автором пилота, не переписывать молча.

---

## Критерии приёмки (DoD)

- [ ] `bash docs/research/pilots/hooks-phase-0-test-fixtures/mine-2-git-add-all/reproduce.sh` → `RESULT: PASS` (H-2 сработал + перечислил 3 worker-a файла).
- [ ] Мины 1 (env-secret) и 5 (ruff) остались PASS.
- [ ] `COORDINATOR_ALLOW_ADD_ALL=1 bash … mine-2-…/reproduce.sh` по-прежнему проходит (разовое разрешение работает, exit 0, запись в `git_add_all_log.md`).
- [ ] В отчёте PR — диагностика root-cause (какой из трёх пунктов сработал) + артефакт-doказательство.
- [ ] `ruff check scripts/hooks/` чисто; тесты хука в `scripts/hooks/tests/` (если есть) — зелёные.

---

## FILES_ALLOWED

- `scripts/hooks/check_add_all.py`
- `scripts/hooks/pre-commit`
- `scripts/install-hooks.sh` (если существует, иначе создать)
- `scripts/hooks/tests/*` (юнит-тесты хука)
- `docs/research/pilots/hooks-phase-0-test-fixtures/run-all-mines.log` (обновление лога)
- `docs/research/pilots/hooks-phase-0-test-fixtures/mine-2-git-add-all/README.md` (если нужно уточнить ожидаемое поведение после фикса)

## FILES_FORBIDDEN

- `backend/**` (не трогать бэкенд)
- `.github/workflows/**` (CI — отдельной задачей)
- `docs/adr/**` (архитектура — не в скоупе)
- `docs/agents/**` (регламент — не в скоупе)
- Основные pre-commit скрипты других H-хуков (H-1/H-3/H-5), кроме диагностики.

## COMMUNICATION_RULES

- Не коммитить. Коммит — Координатор.
- При блокере (например, `install-hooks.sh` не существует и непонятно как устанавливались хуки) — эскалировать backend-head, не решать молча.
- Отчёт ≤200 слов: что было сломано, что исправлено, логи run-all-mines.

## Обязательно к прочтению

- `/root/coordinata56/CLAUDE.md` — раздел «Git»
- `/root/coordinata56/docs/agents/departments/backend.md` — чек-лист самопроверки
- `scripts/hooks/check_add_all.py` — текущая реализация
- `docs/research/pilots/hooks-phase-0-test-fixtures/run-all-mines.log` — текущие результаты прогона
- `docs/research/pilots/hooks-phase-0-test-fixtures/mine-2-git-add-all/README.md` + `reproduce.sh`

Scope-vs-ADR: verified (RFC-004 Phase I-a); gaps: none.
