#!/usr/bin/env bash
# Mine 2 reproduce: git add -A с 15 файлами, 3 из которых помечены как «чужие».
# Ожидание: H-2 warn/block с substring "H-2" и списком 3 подозрительных файлов.

set -u

FIXTURE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-/root/worktrees/coordinata56-hooks-pilot}"
WORK_DIR="$REPO_ROOT/backend/app/services"
# Правильный путь — тот, что читает check_add_all.py (ACTIVE_WORKERS_FILE в скрипте)
ACTIVE_WORKERS_FILE="/root/.claude/teams/default/active-workers.json"

cd "$REPO_ROOT" || { echo "FAIL: repo root $REPO_ROOT не найден"; exit 99; }

mkdir -p "$WORK_DIR"
mkdir -p "$(dirname "$ACTIVE_WORKERS_FILE")"

# --- Подготовка «чужих» файлов (mine2_worker_a_*) ---
# Файлы «чужого» агента: НЕ занесены в active-workers.json текущего воркера
# И имеют mtime > 4 часов (признак «из другой сессии»).
# check_add_all.py считает файл «чужим» если:
#   filepath NOT IN files_owned  AND  mtime > 4h
# touch -t: формат [[CC]YY]MMDDhhmm[.ss] — ставим 6 часов назад.
_OLD_MTIME="$(date -d '6 hours ago' +%Y%m%d%H%M.%S 2>/dev/null || date -v-6H +%Y%m%d%H%M.%S)"
for i in 1 2 3; do
  echo "# worker-a file $i (fixture, to be deleted)" > "$WORK_DIR/_mine2_worker_a_file${i}.py"
  # Принудительно устаревший mtime (6 часов назад > порога 4 ч)
  touch -t "$_OLD_MTIME" "$WORK_DIR/_mine2_worker_a_file${i}.py"
done

# --- Подготовка «своих» 12 файлов — dummy edits в services ---
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  echo "# my own edit $i (fixture, to be deleted)" > "$WORK_DIR/_mine2_own_file${i}.py"
done

# --- Регистрация воркера-б в active-workers.json ---
# Подставляем текущий UTC timestamp вместо placeholder'а, чтобы воркер считался живым
# (started_at < 4 часов назад по логике load_active_workers)
_NOW_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
sed "s/REPLACE_WITH_CURRENT_TIMESTAMP/$_NOW_TS/" "$FIXTURE_DIR/active-workers-fixture.json" > "$ACTIVE_WORKERS_FILE"

# --- git add -A (широкое стейджирование) ---
git add -A

STAGED_COUNT=$(git diff --cached --name-only | wc -l)
echo "Staged files: $STAGED_COUNT"

# --- Попытка коммита (автономный режим, без TTY, без COMMIT_CONFIRMED) ---
COMMIT_OUTPUT=$(git commit -m "mine-2: git add -A on 15 files with foreign workers" 2>&1)
COMMIT_EXIT=$?

echo "---- stderr+stdout ----"
echo "$COMMIT_OUTPUT"
echo "---- exit code: $COMMIT_EXIT ----"

# --- Очистка: расстейджить и удалить временные файлы ---
git reset HEAD -- "$WORK_DIR/_mine2_"*.py 2>/dev/null
rm -f "$WORK_DIR/_mine2_"*.py
rm -f "$ACTIVE_WORKERS_FILE"

# --- Вердикт ---
# Успех = substring "H-2" в выводе (warn ИЛИ block) + упоминание хотя бы одного из чужих файлов
if echo "$COMMIT_OUTPUT" | grep -qE "H-2|HOOK H-2"; then
  if echo "$COMMIT_OUTPUT" | grep -q "_mine2_worker_a"; then
    echo "RESULT: PASS (H-2 сработал + перечислил чужие файлы)"
    exit 0
  else
    echo "RESULT: PARTIAL (H-2 сработал, но не перечислил чужие файлы явно)"
    exit 2
  fi
else
  echo "RESULT: FAIL (H-2 пропустил — 15 файлов с чужими прошли молча)"
  exit 1
fi
