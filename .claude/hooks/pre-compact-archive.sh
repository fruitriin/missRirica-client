#!/bin/bash
# pre-compact-archive.sh — compaction 直前のトランスクリプト JSONL をアーカイブ
# PreCompact フック（trigger: manual / auto）で発火する
# 意図的に set -e を使わない（フックは失敗してもセッションを妨げず exit 0 で抜ける設計）
#
# 目的:
#   compaction 前の生トランスクリプトを保全し、(a) コンテキストのアーカイブ、
#   (b) アーカイブを新 UUID にリネームして `claude --resume` すれば直前状態への復元、
#   の2つを可能にする。Plan 0042・knowhow: transcript-archive-restore.md 参照。
#
# デフォルト無効（オプトイン）: .claude/addf/Behavior.toml の
# [transcript-archive] enable = true で有効化する。

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
BEHAVIOR="$PROJECT_DIR/.claude/addf/Behavior.toml"

# Behavior.toml 不在 → デフォルト無効として静かに終了
[ -f "$BEHAVIOR" ] || exit 0

# [transcript-archive] セクションを抽出（次セクションまで、または EOF まで）。
# TOML パーサを避けるため、セクション範囲内の単純な行から enable/archive_dir/
# max_generations を読む。存在しないキーは既定値にフォールバック。
section=$(awk '
  /^\[transcript-archive\][[:space:]]*$/ { in_section=1; next }
  in_section && /^\[/ { exit }
  in_section { print }
' "$BEHAVIOR" 2>/dev/null)

# セクション無しは「無効」として静かに終了（デフォルト無効の意図）
[ -n "$section" ] || exit 0

get_key() {
  # 単純な行「key = value」形式のみ受ける。value は文字列/数値/真偽値。
  # クオート除去は末尾/先頭の " を落とすだけ（TOML の複雑なエスケープは対象外）。
  # サポートされる値の文字集合: TOML 標準文字。以下は非対応（悪意ではなく単純な使い方の範囲を想定）:
  #   - 値の中に生の `#` を含む文字列（コメント除去がクオート内外を区別しない — 単純化のため）
  #   - キー行の複数行継続・配列・インラインテーブル
  # 値の中の `=` は最初の `=` で分割することで保護している（後続の `=` は値の一部として保つ）。
  # セクションヘッダ行にはコメントを付けないこと（`^[section]$` の完全一致で抽出する — awk 側の設計制約）。
  echo "$section" | awk -v k="$1" '
    {
      # 最初の `=` で key と value を分割（後続の `=` は value に残す）
      idx = index($0, "=")
      if (idx == 0) next
      key = substr($0, 1, idx - 1)
      val = substr($0, idx + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key != k) next
      # 値の前後空白を落とし、行末コメント（クオート外の # 以降）を素朴除去し、クオートを剥がす
      sub(/^[[:space:]]*/, "", val)
      sub(/[[:space:]]*(#.*)?$/, "", val)
      gsub(/"/, "", val)
      print val
      exit
    }
  '
}

ENABLE=$(get_key enable)
[ "$ENABLE" = "true" ] || exit 0

ARCHIVE_DIR=$(get_key archive_dir)
[ -n "$ARCHIVE_DIR" ] || ARCHIVE_DIR="$HOME/.claude/addf-transcript-archive"
# ~ 展開（awk 出力から直接展開されないため）
case "$ARCHIVE_DIR" in
  "~"|"~/"*) ARCHIVE_DIR="$HOME${ARCHIVE_DIR#\~}" ;;
esac

MAX_GEN=$(get_key max_generations)
case "$MAX_GEN" in
  ''|*[!0-9]*) MAX_GEN=10 ;;  # 既定 10 世代（Plan 0042: 保守的に少なめ）
esac

# stdin の hook JSON から transcript_path / session_id / trigger を取得。
# jq 不在時は sed フォールバック（フックは環境の柔軟性を優先）。
INPUT=$(cat)
if command -v jq >/dev/null 2>&1; then
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
  TRIGGER=$(echo "$INPUT" | jq -r '.trigger // empty' 2>/dev/null)
else
  # 素朴な抽出。値に " や } を含む病的入力は対象外（フックの前提はハーネス生成 JSON）
  TRANSCRIPT_PATH=$(echo "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  SESSION_ID=$(echo "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  TRIGGER=$(echo "$INPUT" | sed -n 's/.*"trigger"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi
# 空文字列も含めた欠損チェック（jq の `//` は null/false のみで空文字列は素通しするため）
[ -n "$TRIGGER" ] || TRIGGER="unknown"

# 必須項目欠損 → 静かに終了（誤発火より無発火が安全 — context-reminder と同じ作法）
[ -n "$TRANSCRIPT_PATH" ] || exit 0
[ -f "$TRANSCRIPT_PATH" ] || exit 0

# ファイル名構成要素のサニタイズ — trigger / session_id はハーネス由来だが将来の仕様変更・
# 手動テスト実行等での偽装 stdin に備えてホワイトリスト（英数と `._-`）で正規化する。
# `..`・`/` 混入によるパストラバーサル可能性を意図的にブロックする（`cp` 挙動への偶然の
# 依存を意図の防御に変える）。
sanitize_path_segment() {
  # 空入力は空のまま返す（呼び出し側で :- フォールバックする）。
  # `.` を許可しないのは `..` の意図的な排除。ファイル名の拡張子（.jsonl）は
  # 呼び出し側でリテラル連結するため、値側にドットが必要になるケースはない。
  printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64
}
TRIGGER=$(sanitize_path_segment "$TRIGGER")
[ -n "$TRIGGER" ] || TRIGGER="unknown"
SAFE_SID=$(sanitize_path_segment "$SESSION_ID")

# プロジェクトスラグは transcript_path の親ディレクトリ名を採用する
# （`~/.claude/projects/<スラグ>/<session-id>.jsonl` の Claude Code 慣習）。
# 予期しない配置に対しては cwd 由来のスラグにフォールバック。
SLUG=$(basename "$(dirname "$TRANSCRIPT_PATH")")
if [ -z "$SLUG" ] || [ "$SLUG" = "/" ] || [ "$SLUG" = "." ]; then
  SLUG=$(echo "$PROJECT_DIR" | sed 's|/|-|g' | sed 's|^-||')
fi
SLUG=$(sanitize_path_segment "$SLUG")
[ -n "$SLUG" ] || SLUG="unknown"

DEST_DIR="$ARCHIVE_DIR/$SLUG"
mkdir -p "$DEST_DIR" 2>/dev/null || exit 0

TS=$(date -u +"%Y%m%dT%H%M%SZ")
BASE_NAME="${TS}-${TRIGGER}-${SAFE_SID:-nosid}"
# 命名衝突回避 — date は秒精度なので同一秒内の再発火や同一 session_id での連続保全を
# データロスなく保つため、既存ファイルがあれば -2, -3 の連番サフィックスを付ける。
DEST_NAME="${BASE_NAME}.jsonl"
if [ -e "$DEST_DIR/$DEST_NAME" ]; then
  n=2
  while [ -e "$DEST_DIR/${BASE_NAME}-${n}.jsonl" ] && [ "$n" -lt 100 ]; do
    n=$((n + 1))
  done
  DEST_NAME="${BASE_NAME}-${n}.jsonl"
fi
cp "$TRANSCRIPT_PATH" "$DEST_DIR/$DEST_NAME" 2>/dev/null || exit 0

# 世代掃除: 同一スラグ配下で新しい順に MAX_GEN 個を残し、それ以外を削除。
# ls -t の並びを ls の実装差から守るため、find -printf があれば優先する。
if [ "$MAX_GEN" -gt 0 ] 2>/dev/null; then
  # macOS の ls -t は mtime 降順（新しい順）。テストではモック mtime で並びを制御する
  ls -1t "$DEST_DIR"/*.jsonl 2>/dev/null | tail -n +$((MAX_GEN + 1)) | while IFS= read -r old; do
    [ -f "$old" ] && rm -f "$old"
  done
fi

exit 0
