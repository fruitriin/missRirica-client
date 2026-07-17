#!/bin/bash
# test-hooks-exec-lint.sh
# lint-hooks-exec.py の実行権限チェックテスト。
# 実リポジトリでの正常系と、サンドボックスでの権限喪失検出（ドリフト注入）を検証する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
LINT="$PROJECT_DIR/.claude/addf/addfTools/lint-hooks-exec.py"
PASS=0
FAIL=0

if command -v uv >/dev/null 2>&1; then
  run_lint() { (cd "$1" && uv run --python 3.11 "$LINT" 2>&1); }
else
  run_lint() { (cd "$1" && python3 "$LINT" 2>&1); }
fi

assert_exit() {
  local test_name="$1" expected_exit="$2" actual_exit="$3"
  if [ "$actual_exit" -eq "$expected_exit" ]; then
    echo "  PASS: $test_name (exit=$actual_exit)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (expected exit=$expected_exit, got=$actual_exit)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (output missing: $needle)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== test-hooks-exec-lint.sh ==="

# テスト 1: 実リポジトリで全フック実行可能
# ここが FAIL したら chmod +x で権限を付与する（lint の指示に従う）
echo "Test 1: 実リポジトリで OK"
output=$(run_lint "$PROJECT_DIR")
assert_exit "実リポジトリ" 0 $?
assert_contains "OK メッセージ" "OK: hooks 実行権限チェック通過" "$output"

# テスト 2: 実行権限のないフック → WARNING (exit=2)（この lint が生まれた当のケースの再現）
echo "Test 2: 権限喪失の検出"
box="$(mktemp -d)"
mkdir -p "$box/.claude/hooks"
printf '#!/bin/bash\nexit 0\n' > "$box/.claude/hooks/broken-hook.sh"
chmod -x "$box/.claude/hooks/broken-hook.sh"
printf '#!/bin/bash\nexit 0\n' > "$box/.claude/hooks/good-hook.sh"
chmod +x "$box/.claude/hooks/good-hook.sh"
output=$(run_lint "$box")
assert_exit "権限なしで WARNING" 2 $?
assert_contains "対象ファイルの特定" "broken-hook.sh" "$output"
assert_contains "修正手段の提示" "chmod +x" "$output"

# テスト 3: 権限を付与すると OK に戻る
echo "Test 3: 権限付与後の回復"
chmod +x "$box/.claude/hooks/broken-hook.sh"
output=$(run_lint "$box")
assert_exit "付与後は OK" 0 $?
rm -rf "$box"

# テスト 4: hooks ディレクトリが無い環境 → SKIP で exit=0
echo "Test 4: hooks 不在時の SKIP"
box="$(mktemp -d)"
output=$(run_lint "$box")
assert_exit "hooks 不在で OK" 0 $?
assert_contains "SKIP 表示" "SKIP: .claude/hooks が存在しない" "$output"
rm -rf "$box"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
