#!/bin/bash
# test-destructive-git-guard.sh
# destructive-git-guard.sh のテスト。
# 破壊的 git コマンドに理由メッセージが stderr に出ることと、非破壊コマンド・
# 空入力で沈黙することを検証する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
HOOK="$PROJECT_DIR/.claude/hooks/destructive-git-guard.sh"
PASS=0
FAIL=0

assert_exit() {
  local test_name="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    echo "  PASS: $test_name (exit=$actual)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (expected=$expected, got=$actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_stderr_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  # grep -- で オプション解釈を止める（needle が -- で始まっても OK）
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (stderr missing: $needle)"
    FAIL=$((FAIL + 1))
  fi
}

assert_stderr_empty() {
  local test_name="$1" haystack="$2"
  if [ -z "$haystack" ]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (unexpected stderr: $haystack)"
    FAIL=$((FAIL + 1))
  fi
}

fire() {  # $1=command → stderr を返す
  printf '{"tool_input":{"command":"%s"}}' "$1" | bash "$HOOK" 2>&1 >/dev/null
}

echo "=== test-destructive-git-guard.sh ==="

# テスト 1: 破壊的 git コマンドは理由を stderr に出す
echo "Test 1: git reset --hard で理由メッセージ"
out=$(fire "git reset --hard HEAD~5")
assert_stderr_contains "reset --hard の理由" "git stash -u を優先" "$out"

echo "Test 2: git push --force で理由メッセージ"
out=$(fire "git push --force origin main")
assert_stderr_contains "--force の理由" "--force-with-lease を優先" "$out"

echo "Test 3: git clean -fd で理由メッセージ"
out=$(fire "git clean -fd")
assert_stderr_contains "clean -fd の理由" "dry-run" "$out"

echo "Test 4: git branch -D で理由メッセージ"
out=$(fire "git branch -D feature-x")
assert_stderr_contains "branch -D の理由" "内容を確認" "$out"

echo "Test 5: git checkout -- . で理由メッセージ"
out=$(fire "git checkout -- .")
assert_stderr_contains "checkout -- . の理由" "対象ファイルを絞る" "$out"

# テスト 6: 非破壊 git コマンドは沈黙
echo "Test 6: 非破壊 git は沈黙"
out=$(fire "git status")
assert_stderr_empty "git status" "$out"

echo "Test 7: git commit も沈黙"
out=$(fire "git commit -m 'foo'")
assert_stderr_empty "git commit" "$out"

# テスト 8: 非 git コマンドは沈黙
echo "Test 8: ls は沈黙"
out=$(fire "ls -la")
assert_stderr_empty "ls -la" "$out"

# テスト 9: 空入力・不正 JSON は静かに exit 0
echo "Test 9: 空入力"
out=$(printf '' | bash "$HOOK" 2>&1 >/dev/null)
assert_exit "空入力で exit 0" 0 $?
assert_stderr_empty "空入力の stderr" "$out"

echo "Test 10: 不正 JSON"
out=$(printf 'こわれたJSON' | bash "$HOOK" 2>&1 >/dev/null)
assert_exit "不正 JSON で exit 0" 0 $?
assert_stderr_empty "不正 JSON の stderr" "$out"

# テスト 11: フックは exit 0 で抜ける（ブロックしない）
echo "Test 11: 破壊的コマンドでも exit 0"
printf '{"tool_input":{"command":"git reset --hard HEAD"}}' | bash "$HOOK" >/dev/null 2>&1
assert_exit "reset --hard でも exit 0（ブロックしない・理由提示のみ）" 0 $?

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
