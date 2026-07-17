#!/bin/bash
# check-screen-recording.sh — Screen Recording 権限の確認と要求
#
# Usage: check-screen-recording.sh [--request]
#   引数なし: 現在の権限ステータスを確認
#   --request: 権限がなければシステム環境設定を開く

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TMP_DIR="$PROJECT_ROOT/tmp"

check_capture_tool() {
    local capture_tool="$SCRIPT_DIR/capture-window"

    if [ ! -x "$capture_tool" ]; then
        echo "not_built"
        return
    fi

    # capture-window を存在しないPIDでテスト実行
    # 権限問題なら SIGABRT (134)、PID未発見なら exit 1（権限OK）
    mkdir -p "$TMP_DIR"
    local tmp_file="$TMP_DIR/check-sr-$$.png"
    "$capture_tool" --pid 99999 "$tmp_file" >/dev/null 2>&1
    local exit_code=$?
    rm -f "$tmp_file"

    if [ $exit_code -eq 134 ]; then
        echo "denied_or_restart_needed"
    else
        # exit 1 = PID not found (正常動作、権限はある)
        echo "granted"
    fi
}

open_settings() {
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" 2>/dev/null \
        || open "/System/Library/PreferencePanes/Security.prefPane" 2>/dev/null \
        || echo "ERROR: システム環境設定を開けませんでした"
}

# --- Main ---

echo "=== Screen Recording 権限チェック ==="
echo ""

# 1. capture-window ツールの直接テスト
echo -n "capture-window: "
ct_status=$(check_capture_tool)
case "$ct_status" in
    granted)
        echo "OK — 正常動作"
        ;;
    denied_or_restart_needed)
        echo "NG — SIGABRT (権限なし or VSCode 再起動が必要)"
        ;;
    not_built)
        echo "SKIP — 未ビルド (tools/test-utils/build.sh を実行)"
        ;;
esac

# 2. 親プロセス情報
echo ""
echo "--- 親プロセス情報 ---"
TERMINAL_PID=$(ps -o ppid= -p $$ | tr -d ' ')
TERMINAL_NAME=$(ps -o comm= -p "$TERMINAL_PID" 2>/dev/null || echo "unknown")
echo "ターミナル PID: $TERMINAL_PID ($TERMINAL_NAME)"
echo ""
echo "NOTE: 権限変更後は VSCode / ターミナルの完全再起動が必要です"

# 3. --request オプション
if [ "${1:-}" = "--request" ]; then
    if [ "$ct_status" = "denied_or_restart_needed" ] || [ "$ct_status" = "not_built" ]; then
        echo ""
        echo "システム環境設定を開きます..."
        open_settings
        echo "  1. 「画面収録」で VSCode (または Code) にチェックを入れる"
        echo "  2. VSCode を完全に終了して再起動する"
    else
        echo ""
        echo "権限は既に付与されています"
    fi
fi
