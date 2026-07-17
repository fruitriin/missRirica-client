#!/bin/bash
# reset-turn-count.sh
# SessionStart フックで発火。ターンカウンターをリセットする。
# 意図的に set -e を使わない（フックは失敗してもセッションを妨げず exit 0 で抜ける設計）

# CLAUDE_PROJECT_DIR 未設定時はカレントディレクトリ（フックはプロジェクトルートで実行される）に
# フォールバックする。未設定のままだと "/.claude/..." に展開されて書き込みが静かに失敗する
COUNTER_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/.turn-count"
echo "0" > "$COUNTER_FILE"
exit 0
