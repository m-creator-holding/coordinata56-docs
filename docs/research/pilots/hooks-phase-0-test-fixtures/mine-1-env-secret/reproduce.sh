#!/usr/bin/env bash
# Mine 1 reproduce: попытка закоммитить .env с FAKE-секретами.
# Ожидание: H-1 блокирует (exit code != 0), stderr содержит "HOOK H-1".
#
# Требование: скрипт должен запускаться из worktree /root/worktrees/coordinata56-hooks-pilot/.
# Перед запуском хуки должны быть установлены через scripts/install-hooks.sh.

set -u

FIXTURE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-/root/worktrees/coordinata56-hooks-pilot}"

cd "$REPO_ROOT" || { echo "FAIL: repo root $REPO_ROOT не найден"; exit 99; }

# Подготовка: скопировать минированный .env в корень репо под именем .env.production
cp "$FIXTURE_DIR/.env.dirty" "$REPO_ROOT/.env.production"

# Staged
git add .env.production 2>/dev/null

# Попытка коммита (не push) — хук должен сработать
# Захватываем stderr отдельно
COMMIT_OUTPUT=$(git commit -m "mine-1: staged .env.production" 2>&1)
COMMIT_EXIT=$?

echo "---- stderr+stdout ----"
echo "$COMMIT_OUTPUT"
echo "---- exit code: $COMMIT_EXIT ----"

# Очистка: расстейджить и удалить
git reset HEAD .env.production 2>/dev/null
rm -f "$REPO_ROOT/.env.production"

# Вердикт
if [ "$COMMIT_EXIT" -ne 0 ] && echo "$COMMIT_OUTPUT" | grep -q "HOOK H-1"; then
  echo "RESULT: PASS (H-1 заблокировал, substring найден)"
  exit 0
elif [ "$COMMIT_EXIT" -ne 0 ]; then
  echo "RESULT: PARTIAL (блок есть, но substring 'HOOK H-1' не найден — проверить текст сообщения)"
  exit 2
else
  echo "RESULT: FAIL (H-1 пропустил секрет — P0 REJECT)"
  exit 1
fi
