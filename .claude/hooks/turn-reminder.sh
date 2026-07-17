#!/bin/bash
# turn-reminder.sh
# UserPromptSubmit フックで発火。2つの関心事を分担する（Plan 0023）:
#   A. 知見の定期棚卸し — ターン数ベース。10/15ターンで /addf-knowhow を促す。
#      コンテキスト残量には言及しない（根拠なく状態を断言しない）
#   B. 能動コンパクション促し — 実測トークン数ベース。stdin の hook JSON を
#      context-reminder.py に中継し、閾値超過時のみ観測事実を注入する

# 意図的に set -e を使わない（フックは失敗してもセッションを妨げず exit 0 で抜ける設計）
# CLAUDE_PROJECT_DIR 未設定時はカレントディレクトリにフォールバック（reset-turn-count.sh と同じ方針)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
COUNTER_FILE="$PROJECT_DIR/.claude/.turn-count"

# 関心事A: ターンカウンターによる棚卸しリマインダー
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

if [ "$COUNT" -eq 10 ] || [ "$COUNT" -eq 15 ]; then
  cat <<EOF
<user-prompt-submit-hook>
${COUNT}ターン経過しました。ここまでで重要な知見・分かれ道があれば /addf-knowhow や日記に記録することを検討してください。
これは作業を切り上げる指示ではありません。コンテキスト残量とは無関係の定期的な棚卸しです。記録したらそのまま作業を継続してください。
</user-prompt-submit-hook>
EOF
fi

# 関心事B: stdin（hook JSON）を context-reminder.py に中継する。
# stdin が TTY の場合（手動実行・旧テスト）は中継しない。python3 不在なら静かにスキップ
if [ ! -t 0 ] && command -v python3 >/dev/null 2>&1; then
  python3 "$PROJECT_DIR/.claude/addf/addfTools/context-reminder.py" 2>/dev/null
fi

exit 0
