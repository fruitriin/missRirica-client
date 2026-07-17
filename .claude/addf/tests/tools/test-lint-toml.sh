#!/bin/bash
# test-lint-toml.sh
# lint-toml.py の構文チェックと tomllib 欠如ガードを mktemp サンドボックスで検証する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$(cd "$SCRIPT_DIR/../.." && pwd)/addfTools/lint-toml.py"
PASS=0
FAIL=0

# tomllib（Python 3.11+）前提のため uv があれば 3.11 を明示する（test-optional-skills.sh と同パターン）
if command -v uv >/dev/null 2>&1; then
  run_lint() { (cd "$1" && uv run --python 3.11 "$LINT" 2>&1); }
else
  run_lint() { (cd "$1" && python3 "$LINT" 2>&1); }
fi

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

echo "=== test-lint-toml.sh ==="

box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT
mkdir -p "$box/.claude/addf"

echo "Test 1: 正常な TOML → OK・exit 0"
printf '[gui-test]\nenable = false\n' > "$box/.claude/addf/Behavior.toml"
out="$(run_lint "$box")"; code=$?
check "正常 TOML で OK" 0 "$code" "$out" "OK"

echo "Test 2: 構文エラー → ERROR・exit 1"
printf '[gui-test\nenable = false\n' > "$box/.claude/addf/Behavior.toml"
out="$(run_lint "$box")"; code=$?
check "構文エラーを ERROR" 1 "$code" "$out" "ERROR"

echo "Test 3: ファイル不在 → SKIP・exit 0"
rm -f "$box/.claude/addf/Behavior.toml"
out="$(run_lint "$box")"; code=$?
check "ファイル不在で SKIP" 0 "$code" "$out" "SKIP"

echo "Test 4: tomllib が無い環境 → SKIP・exit 0（配布先で誤 ERROR を出さない）"
# PYTHONPATH シムで ModuleNotFoundError を注入し、旧 Python（3.9 等）を再現する
printf '[gui-test]\nenable = false\n' > "$box/.claude/addf/Behavior.toml"
shim="$(mktemp -d)"
printf 'raise ModuleNotFoundError("No module named '"'"'tomllib'"'"'")\n' > "$shim/tomllib.py"
out="$( (cd "$box" && PYTHONPATH="$shim" python3 "$LINT" 2>&1) )"; code=$?
check "tomllib 欠如で SKIP" 0 "$code" "$out" "SKIP: tomllib がありません"
rm -rf "$shim"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
