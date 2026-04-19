#!/usr/bin/env bash
# Оркестратор прогона всех 5 мин последовательно.
# Запускается в подзадаче Г после сигнала Координатора «backend-dev доставил хуки».
#
# Предусловия:
#   - Worktree /root/worktrees/coordinata56-hooks-pilot/ существует.
#   - scripts/install-hooks.sh отработал в worktree.
#   - Для H-3 и H-4 — см. reproduce.md (manual-прогон в Claude-сессии).
#
# Выход: таблица «мина → результат» в stdout + результат каждого reproduce.sh.

set -u

FIXTURE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-/root/worktrees/coordinata56-hooks-pilot}"
REPORT_LOG="$FIXTURE_DIR/run-all-mines.log"

: > "$REPORT_LOG"

echo "============================================" | tee -a "$REPORT_LOG"
echo "Hooks Phase 0 — Mine Run at $(date -Iseconds)" | tee -a "$REPORT_LOG"
echo "Repo root: $REPO_ROOT" | tee -a "$REPORT_LOG"
echo "============================================" | tee -a "$REPORT_LOG"

run_mine() {
  local n="$1"
  local slug="$2"
  local script="$FIXTURE_DIR/mine-${n}-${slug}/reproduce.sh"

  echo "" | tee -a "$REPORT_LOG"
  echo "--- Mine $n ($slug) ---" | tee -a "$REPORT_LOG"

  if [ ! -x "$script" ]; then
    # try to make executable
    chmod +x "$script" 2>/dev/null || true
  fi

  if [ ! -f "$script" ]; then
    echo "SKIP: $script не найден или manual (reproduce.md)" | tee -a "$REPORT_LOG"
    return 0
  fi

  bash "$script" 2>&1 | tee -a "$REPORT_LOG"
  local rc="${PIPESTATUS[0]}"
  echo "[mine-$n exit $rc]" | tee -a "$REPORT_LOG"
}

run_mine 1 "env-secret"
run_mine 2 "git-add-all"
# Mine 3 — manual (Claude session), пропускаем в bash-прогоне
echo "" | tee -a "$REPORT_LOG"
echo "--- Mine 3 (sendmessage-dormant) — MANUAL, см. reproduce.md ---" | tee -a "$REPORT_LOG"
# Mine 4 — manual
echo "" | tee -a "$REPORT_LOG"
echo "--- Mine 4 (agent-no-ultrathink) — MANUAL, см. reproduce.md ---" | tee -a "$REPORT_LOG"
run_mine 5 "ruff-unused-import"

echo "" | tee -a "$REPORT_LOG"
echo "============================================" | tee -a "$REPORT_LOG"
echo "Run complete. Log: $REPORT_LOG" | tee -a "$REPORT_LOG"
echo "Для Mine 3 и Mine 4 смотреть соответствующие reproduce.md и прогнать вручную." | tee -a "$REPORT_LOG"
