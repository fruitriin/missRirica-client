#!/bin/bash
# test-speculate-guard.sh
# speculate-guard.py の状態別ふるまいを mktemp サンドボックスで検証する。
# サンドボックスに fake git リポジトリと addf-Behavior.toml を作り、
# 設定パターンごとの exit code / 出力を確認する（実リポジトリは汚さない）。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$(cd "$SCRIPT_DIR/../.." && pwd)/addfTools/speculate-guard.py"
PASS=0
FAIL=0

check() {
  local desc="$1" expected_exit="$2" actual_exit="$3" output="$4" expected_grep="${5:-}"
  if [ "$actual_exit" -ne "$expected_exit" ]; then
    echo "  FAIL: $desc (exit: expected=$expected_exit actual=$actual_exit)"
    FAIL=$((FAIL + 1))
    return
  fi
  if [ -n "$expected_grep" ] && ! grep -q "$expected_grep" <<<"$output"; then
    echo "  FAIL: $desc (出力に '$expected_grep' が見つからない)"
    echo "$output" | sed 's/^/    | /'
    FAIL=$((FAIL + 1))
    return
  fi
  echo "  PASS: $desc"
  PASS=$((PASS + 1))
}

# サンドボックス: fake git リポジトリ
box="$(mktemp -d)"
trap 'rm -rf "$box" "$box-spec-x" "$box-other"' EXIT
(
  cd "$box"
  git init -q -b main .
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  mkdir -p .claude/addf
)

# tomllib（Python 3.11+）前提のため uv があれば 3.11 を明示する（test-optional-skills.sh と同パターン）
if command -v uv >/dev/null 2>&1; then
  run_guard() { (cd "$box" && uv run --python 3.11 "$GUARD" 2>&1); }
else
  run_guard() { (cd "$box" && python3 "$GUARD" 2>&1); }
fi

echo "Test 1: 設定ファイルなし → enable=false・exit 0（欠如 = 無効）"
rm -f "$box/.claude/addf/Behavior.toml"
out="$(run_guard)"; code=$?
check "toml なしで無効扱い" 0 "$code" "$out" "enable=false"

echo "Test 2: [speculation] セクションなし → enable=false・exit 0"
printf '[gui-test]\nenable = false\n' > "$box/.claude/addf/Behavior.toml"
out="$(run_guard)"; code=$?
check "セクションなしで無効扱い" 0 "$code" "$out" "enable=false"

echo "Test 3: enable=false → exit 0・enable=false 出力"
printf '[speculation]\nenable = false\nmax_worktrees = 3\n' > "$box/.claude/addf/Behavior.toml"
out="$(run_guard)"; code=$?
check "明示 disable" 0 "$code" "$out" "enable=false"

echo "Test 4: enable が文字列 \"false\" → exit 1（型不正 ERROR）"
printf '[speculation]\nenable = "false"\n' > "$box/.claude/addf/Behavior.toml"
out="$(run_guard)"; code=$?
check "enable 型不正を ERROR" 1 "$code" "$out" "ERROR"

echo "Test 5: max_worktrees が文字列 → exit 1（型不正 ERROR）"
printf '[speculation]\nenable = true\nmax_worktrees = "3"\n' > "$box/.claude/addf/Behavior.toml"
out="$(run_guard)"; code=$?
check "max_worktrees 型不正を ERROR" 1 "$code" "$out" "ERROR"

echo "Test 6: max_worktrees = 0 → exit 1（1 以上を要求）"
printf '[speculation]\nenable = true\nmax_worktrees = 0\n' > "$box/.claude/addf/Behavior.toml"
out="$(run_guard)"; code=$?
check "max_worktrees=0 を ERROR" 1 "$code" "$out" "ERROR"

echo "Test 7: enable=true・枠あり → exit 0・slots 出力"
printf '[speculation]\nenable = true\nmax_worktrees = 2\n' > "$box/.claude/addf/Behavior.toml"
out="$(run_guard)"; code=$?
check "枠ありで OK" 0 "$code" "$out" "slots=2"

echo "Test 8: max_worktrees 省略 → デフォルト 3 で exit 0"
printf '[speculation]\nenable = true\n' > "$box/.claude/addf/Behavior.toml"
out="$(run_guard)"; code=$?
check "デフォルト上限" 0 "$code" "$out" "max_worktrees=3"

echo "Test 9: speculative worktree が上限まで存在 → exit 2（上限到達 WARNING）"
printf '[speculation]\nenable = true\nmax_worktrees = 1\n' > "$box/.claude/addf/Behavior.toml"
(cd "$box" && git worktree add -q "$box-spec-x" -b speculative/x >/dev/null 2>&1)
out="$(run_guard)"; code=$?
check "上限到達で WARNING" 2 "$code" "$out" "active=1"
rm -rf "$box-spec-x"

echo "Test 10: speculative 以外の worktree はカウントしない"
printf '[speculation]\nenable = true\nmax_worktrees = 1\n' > "$box/.claude/addf/Behavior.toml"
(cd "$box" && git worktree prune && git worktree add -q "$box-other" -b feature/other >/dev/null 2>&1)
out="$(run_guard)"; code=$?
check "非 speculative は数えない" 0 "$code" "$out" "active=0"
rm -rf "$box-other"

echo "Test 11: tomllib が無い環境 → exit 1（フェイルセーフ ERROR。投機を開始しない）"
# PYTHONPATH シムで ModuleNotFoundError を注入し、旧 Python（3.9 等）を再現する
shim="$(mktemp -d)"
printf 'raise ModuleNotFoundError("No module named '"'"'tomllib'"'"'")\n' > "$shim/tomllib.py"
out="$( (cd "$box" && PYTHONPATH="$shim" python3 "$GUARD" 2>&1) )"; code=$?
check "tomllib 欠如でフェイルセーフ ERROR" 1 "$code" "$out" "ERROR"
rm -rf "$shim"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
