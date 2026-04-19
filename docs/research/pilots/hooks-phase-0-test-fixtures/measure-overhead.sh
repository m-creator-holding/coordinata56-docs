#!/usr/bin/env bash
# Измерение оверхеда pre-commit хуков на среднем коммите (5-10 файлов).
# По §4.3 плана: разница ≤2 секунд на коммит.
#
# Методика (§5.4 брифа):
#   - 5 итераций baseline (хуки отключены), 5 итераций treatment (хуки включены).
#   - Первую итерацию в каждом режиме ОТБРАСЫВАЕМ (cold cache Python, ruff, pytest).
#   - Среднее, медиана, максимум по итерациям 2-5.
#   - Сохраняем wall-clock (real) из `time`.
#
# Результат — CSV в overhead-measurements.csv.

set -u

FIXTURE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-/root/worktrees/coordinata56-hooks-pilot}"
OUT_CSV="$FIXTURE_DIR/overhead-measurements.csv"
TMP_DIR="$REPO_ROOT/backend/tmp_benchmark"

cd "$REPO_ROOT" || { echo "FAIL: repo root $REPO_ROOT не найден"; exit 99; }

# --- Header ---
echo "run_id,mode,iteration,real_sec,user_sec,sys_sec,notes" > "$OUT_CSV"

# --- Подготовка 10 realistic Python-файлов ---
# Используем существующие файлы сервисов как шаблон (mime по ruff, есть test mapping).
# Для честного замера H-5 (ruff + pytest) используем mix: 5 service-файлов (у них есть тесты),
# 5 вспомогательных в backend/tmp_benchmark/ (без тестов).
prepare_benchmark_commit() {
  mkdir -p "$TMP_DIR"
  # 5 файлов без тестов (ruff-clean)
  for i in 1 2 3 4 5; do
    cat > "$TMP_DIR/bench_$i.py" <<'PY'
"""Benchmark fixture module."""

from __future__ import annotations


def bench_add(a: int, b: int) -> int:
    return a + b
PY
  done

  # 5 micro-правок в реальных services (меняем один комментарий)
  local real_files=(
    "backend/app/services/project.py"
    "backend/app/services/house.py"
    "backend/app/services/contract.py"
    "backend/app/services/payment.py"
    "backend/app/services/budget_plan.py"
  )
  for f in "${real_files[@]}"; do
    if [ -f "$f" ]; then
      # минимальное безопасное изменение — комментарий-маркер
      echo "# bench-marker $(date +%s%N)" >> "$f"
    fi
  done

  # staging
  git add "$TMP_DIR"/*.py
  for f in "${real_files[@]}"; do
    [ -f "$f" ] && git add "$f"
  done
}

cleanup_benchmark_commit() {
  # Откат: всегда. Убираем только временные файлы и последний коммит (если состоялся).
  git reset --hard HEAD >/dev/null 2>&1
  rm -rf "$TMP_DIR"
}

measure_one_iteration() {
  local mode="$1"
  local iter="$2"

  prepare_benchmark_commit

  # TIMEFORMAT для bash: %R = real, %U = user, %S = sys
  TIMEFORMAT='%R %U %S'
  # захват stderr `time`
  local timing
  timing=$( { time git commit -m "benchmark iteration $mode-$iter" >/dev/null 2>&1; } 2>&1 )
  local real=$(echo "$timing" | awk '{print $1}')
  local user=$(echo "$timing" | awk '{print $2}')
  local sys=$(echo "$timing" | awk '{print $3}')

  # Удаляем коммит (если произошёл) — не нужен в истории
  cleanup_benchmark_commit

  echo "bench-$mode-$iter,$mode,$iter,$real,$user,$sys," >> "$OUT_CSV"
  echo "  [$mode][iter $iter] real=${real}s user=${user}s sys=${sys}s"
}

run_mode() {
  local mode="$1"
  local setup_fn="$2"
  local teardown_fn="$3"

  echo ""
  echo "=== Mode: $mode ==="
  $setup_fn

  for iter in 1 2 3 4 5; do
    measure_one_iteration "$mode" "$iter"
  done

  $teardown_fn
}

# --- Baseline: хуки отключены ---
disable_hooks() {
  # worktree имеет свой .git/hooks через link, проверяем pre-commit
  if [ -f .git/hooks/pre-commit ]; then
    mv .git/hooks/pre-commit .git/hooks/pre-commit.disabled
  fi
  # Для Claude Code hooks baseline — не применимо (они на tool-level, не git)
}

enable_hooks() {
  if [ -f .git/hooks/pre-commit.disabled ]; then
    mv .git/hooks/pre-commit.disabled .git/hooks/pre-commit
  fi
}

no_op() { :; }

# Запуск
run_mode "baseline" disable_hooks enable_hooks
run_mode "treatment" no_op no_op

# --- Сводка ---
echo ""
echo "=== Summary (iterations 2-5, первая отброшена) ==="

compute_avg() {
  local mode="$1"
  awk -F',' -v m="$mode" '
    $2==m && $3>=2 { sum+=$4; cnt++; if($4>max) max=$4 }
    END {
      if (cnt>0) printf "%s: avg_real=%.3fs max_real=%.3fs n=%d\n", m, sum/cnt, max, cnt;
      else print m ": no data"
    }
  ' "$OUT_CSV"
}

compute_avg "baseline"
compute_avg "treatment"

# Вывод дельты
awk -F',' '
  $3>=2 && $2=="baseline" { bsum+=$4; bcnt++ }
  $3>=2 && $2=="treatment" { tsum+=$4; tcnt++ }
  END {
    if (bcnt>0 && tcnt>0) {
      bavg=bsum/bcnt; tavg=tsum/tcnt;
      diff=tavg-bavg;
      printf "overhead: diff=%.3fs (%.1f%%)\n", diff, (diff/bavg)*100;
      if (diff <= 2.0) print "ACCEPTANCE §4.3: PASS (overhead ≤ 2s)";
      else print "ACCEPTANCE §4.3: FAIL (overhead > 2s) — рассмотреть сокращение H-5 до только ruff check";
    }
  }
' "$OUT_CSV"

echo ""
echo "Log: $OUT_CSV"
