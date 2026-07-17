#!/bin/bash
# test-reset-turn-count.sh
# reset-turn-count.sh のテスト。カウンターリセットを検証。
# 本番の .claude/.turn-count に触れないよう mktemp サンドボックスで実行する
# （実運用セッションと並行実行しても状態が競合しない。test-context-reminder.sh と同じ方式）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
HOOK="$PROJECT_DIR/.claude/hooks/reset-turn-count.sh"
SANDBOX="$(mktemp -d)"
mkdir -p "$SANDBOX/.claude"
COUNTER_FILE="$SANDBOX/.claude/.turn-count"
PASS=0
FAIL=0

cleanup() {
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

echo "=== test-reset-turn-count.sh ==="

# テスト 1: 既存カウンターのリセット
echo "Test 1: 既存カウンター (42→0)"
echo "42" > "$COUNTER_FILE"
export CLAUDE_PROJECT_DIR="$SANDBOX"
bash "$HOOK"
count=$(cat "$COUNTER_FILE")
if [ "$count" -eq 0 ]; then
  echo "  PASS: counter reset to 0"
  PASS=$((PASS + 1))
else
  echo "  FAIL: expected 0, got=$count"
  FAIL=$((FAIL + 1))
fi

# テスト 2: カウンターファイルが存在しない場合
echo "Test 2: カウンターファイルなし (→0)"
rm -f "$COUNTER_FILE"
bash "$HOOK"
count=$(cat "$COUNTER_FILE")
if [ "$count" -eq 0 ]; then
  echo "  PASS: counter created with 0"
  PASS=$((PASS + 1))
else
  echo "  FAIL: expected 0, got=$count"
  FAIL=$((FAIL + 1))
fi

# テスト 3: CLAUDE_PROJECT_DIR 未設定時のカレントディレクトリフォールバック
echo "Test 3: CLAUDE_PROJECT_DIR 未設定 (cwd フォールバック)"
rm -f "$COUNTER_FILE"
(cd "$SANDBOX" && env -u CLAUDE_PROJECT_DIR bash "$HOOK")
if [ -f "$COUNTER_FILE" ] && [ "$(cat "$COUNTER_FILE")" -eq 0 ]; then
  echo "  PASS: counter created in cwd fallback"
  PASS=$((PASS + 1))
else
  echo "  FAIL: counter not created via cwd fallback"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
