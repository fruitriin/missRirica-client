#!/bin/bash
# test-tools.sh
# addfTools のバイナリ疎通テスト。
# GUI テストが無効 (addf-Behavior.toml enable=false) の状態で動作確認。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
TOOLS_DIR="$PROJECT_DIR/.claude/addf/addfTools"
PASS=0
FAIL=0
SKIP=0

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

assert_file_exists() {
  local test_name="$1" path="$2"
  if [ -x "$path" ]; then
    echo "  PASS: $test_name (exists & executable)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name ($path not found or not executable)"
    FAIL=$((FAIL + 1))
  fi
}

# disabled 判定に失敗すると実際の GUI 情報取得処理に入り、権限ダイアログ待ちで
# 無期限にハングしうる（Issue #26 実測: 移行直後の旧パス参照で window-info が
# 9時間ハング）。原因によらず時間で打ち切るガードレールとして timeout でラップする。
# GNU coreutils の timeout/gtimeout が無い環境向けに手動 kill フォールバックを持つ。
run_with_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    "$@" &
    local pid=$!
    ( sleep "$secs" && kill -9 "$pid" 2>/dev/null ) &
    local watchdog=$!
    wait "$pid" 2>/dev/null
    local exit_code=$?
    kill "$watchdog" 2>/dev/null
    return $exit_code
  fi
}

echo "=== test-tools.sh ==="

# テスト 1: バイナリの存在確認
echo "Test 1: バイナリ存在確認"
assert_file_exists "window-info" "$TOOLS_DIR/window-info"
assert_file_exists "capture-window" "$TOOLS_DIR/capture-window"
assert_file_exists "annotate-grid" "$TOOLS_DIR/annotate-grid"
assert_file_exists "clip-image" "$TOOLS_DIR/clip-image"

# テスト 2〜4: バイナリの実行を伴うテスト。
# バイナリは macOS 専用 (Mach-O) のため、非 macOS 環境（Linux CI・リモート実行環境等）では
# 実行不能 (Exec format error)。Plan 0004 で Linux/Windows は未実装スコープと明示済みのため SKIP する
if [ "$(uname -s)" != "Darwin" ]; then
  echo "Test 2-4: SKIP (バイナリは macOS 専用。$(uname -s) では実行テストを行わない)"
  SKIP=$((SKIP + 3))
else
  # テスト 2: window-info (disabled 状態で実行)
  echo "Test 2: window-info (gui-test disabled)"
  stdout=$(run_with_timeout 10 "$TOOLS_DIR/window-info" dummy 2>/dev/null) || true
  if echo "$stdout" | grep -q '"disabled"'; then
    echo "  PASS: window-info returns disabled JSON"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: window-info did not return disabled JSON (got: $stdout)"
    FAIL=$((FAIL + 1))
  fi

  # テスト 3: annotate-grid (引数不正でエラー)
  echo "Test 3: annotate-grid (no args → error)"
  "$TOOLS_DIR/annotate-grid" 2>/dev/null
  actual=$?
  if [ "$actual" -ne 0 ]; then
    echo "  PASS: annotate-grid exits non-zero with no args (exit=$actual)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: annotate-grid should exit non-zero with no args"
    FAIL=$((FAIL + 1))
  fi

  # テスト 4: clip-image (引数不正でエラー)
  echo "Test 4: clip-image (no args → error)"
  "$TOOLS_DIR/clip-image" 2>/dev/null
  actual=$?
  if [ "$actual" -ne 0 ]; then
    echo "  PASS: clip-image exits non-zero with no args (exit=$actual)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: clip-image should exit non-zero with no args"
    FAIL=$((FAIL + 1))
  fi
fi

# テスト 5: build.sh の存在
echo "Test 5: build.sh 存在確認"
assert_file_exists "build.sh" "$TOOLS_DIR/build.sh"

echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
