#!/usr/bin/env bash
# Mine 5 reproduce: добавить unused import в backend/app/services/project.py, попытаться закоммитить.
# Ожидание: H-5 блокирует с ruff F401.

set -u

FIXTURE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-/root/worktrees/coordinata56-hooks-pilot}"
TARGET_FILE="backend/app/services/project.py"

cd "$REPO_ROOT" || { echo "FAIL: repo root $REPO_ROOT не найден"; exit 99; }

# Сохранить оригинал
if [ ! -f "$TARGET_FILE" ]; then
  echo "FAIL: target file $TARGET_FILE не существует в $REPO_ROOT"
  exit 99
fi

cp "$TARGET_FILE" "/tmp/mine5-project-backup.py"

# Применить minimal edit: добавить 'import os' в первую строку
# (без git apply, т.к. line numbers могут сдвинуться между версиями)
{
  echo "import os  # mine-5 fixture: intentional unused import"
  cat "$TARGET_FILE"
} > "$TARGET_FILE.tmp" && mv "$TARGET_FILE.tmp" "$TARGET_FILE"

# Staged
git add "$TARGET_FILE"

# Коммит — ожидание fail
COMMIT_OUTPUT=$(git commit -m "mine-5: unused import in project.py" 2>&1)
COMMIT_EXIT=$?

echo "---- stderr+stdout ----"
echo "$COMMIT_OUTPUT"
echo "---- exit code: $COMMIT_EXIT ----"

# Очистка: unstage и восстановить оригинал
git reset HEAD -- "$TARGET_FILE" 2>/dev/null
cp "/tmp/mine5-project-backup.py" "$TARGET_FILE"
rm -f "/tmp/mine5-project-backup.py"

# Вердикт
if [ "$COMMIT_EXIT" -ne 0 ]; then
  if echo "$COMMIT_OUTPUT" | grep -qiE "ruff|F401|unused"; then
    echo "RESULT: PASS (H-5 заблокировал с ruff/F401)"
    exit 0
  else
    echo "RESULT: PARTIAL (блок есть, но причина не 'ruff' — проверить что это не H-1/H-2)"
    exit 2
  fi
else
  echo "RESULT: FAIL (H-5 пропустил unused import)"
  exit 1
fi
