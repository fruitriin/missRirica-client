#!/bin/bash
# スキル使用計測フック
# PreToolUse の Skill マッチャーで発火し、使用をログする
# 意図的に set -e を使わない（フックは失敗してもセッションを妨げず exit 0 で抜ける設計）

LOG_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/logs"
LOG_FILE="${LOG_DIR}/skill-usage.jsonl"

# ログディレクトリを作成
mkdir -p "$LOG_DIR"

# stdin から tool_input を読む
INPUT=$(cat)

# セッション ID
SESSION_ID="${CLAUDE_SESSION_ID:-$(uuidgen 2>/dev/null || date +%Y%m%d-%H%M%S)}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# jq でエントリ全体を生成（文字列エスケープを jq に委ねる）
echo "$INPUT" | jq -c --arg ts "$TIMESTAMP" --arg sid "$SESSION_ID" \
  '{timestamp: $ts, skill: (.tool_input.skill // "unknown"), session_id: $sid}' >> "$LOG_FILE" 2>/dev/null \
  || echo "{\"timestamp\":\"${TIMESTAMP}\",\"skill\":\"unknown\",\"session_id\":\"${SESSION_ID}\"}" >> "$LOG_FILE" 2>/dev/null

# ログ書き込みの成否がスキル呼び出しフローに影響しないよう、常に成功で抜ける
exit 0
