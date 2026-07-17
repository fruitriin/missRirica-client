#!/bin/bash
# destructive-git-guard.sh — 破壊的 git コマンドに根拠を添える補助フック
# PreToolUse(Bash) で発火する。exit 2 でブロックはせず、permission ダイアログの前後で
# 参照できる根拠メッセージを stderr に出力する（Plan 0043 項目3）。
#
# ブロック手段は settings.json の ask ルール側に任せる分業設計。対象5パターンは
# いずれも settings.json の ask に登録されており、フックは「確認ダイアログが出る理由」を
# 補足するガイダンス役として機能する:
#   - git reset --hard*         ← ask: Bash(git reset --hard *)
#   - git push --force*         ← ask: Bash(git push *)（--force 含む push は全て）
#   - git clean -f*             ← ask: Bash(git clean *)
#   - git branch -D *           ← ask: Bash(git branch -D *)
#   - git checkout -- . / .*    ← ask: Bash(git checkout -- *) / Bash(git restore .)
#
# ⚠️ 実効性検証の申し送り（Suggestion 7 対応）: PreToolUse フックの exit 0 + stderr が
# エージェントのコンテキストに実際に表示されるかは未検証（.claude/addf/knowhow/ADDF/
# claude-code-hooks.md では exit 2 の場合のみ stderr が Claude にフィードバックされると
# 明記）。実効性が観測されない場合は JSON stdout の permissionDecisionReason 方式への
# 切り替えを検討する（.claude/addf/knowhow/ADDF/pretooluse-block-with-rationale.md）。
#
# 意図的に set -e を使わない（フックは失敗してもセッションを妨げず exit 0 で抜ける設計）。

# stdin から tool_input.command を取得（jq 不在時は空にフォールバック）
INPUT=$(cat 2>/dev/null || printf '')
if command -v jq >/dev/null 2>&1; then
  CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
else
  CMD=$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi
[ -n "$CMD" ] || exit 0

emit_reason() {
  # stderr に理由を出しても permission ダイアログの前に見せるだけ（ブロックはしない）
  printf '[destructive-git-guard] %s\n' "$1" >&2
}

case "$CMD" in
  *"git reset --hard"*)
    emit_reason "git reset --hard は未コミット変更を破棄します — 直前に git status で作業ツリー確認・必要なら git stash -u を優先してください（Plan 0043）"
    ;;
  *"git push"*"--force"*|*"git push"*"-f "*|*"git push -f"*)
    emit_reason "git push --force はリモートの履歴を上書きします — 共有ブランチでは他者の作業を消しうるため --force-with-lease を優先してください（Plan 0043）"
    ;;
  *"git clean -f"*|*"git clean"*"-fd"*|*"git clean"*"-fdx"*)
    emit_reason "git clean -f は追跡外ファイルを削除します — 進行中の実験ファイルが失われうるため -n（dry-run）で先に確認してください（Plan 0043）"
    ;;
  *"git branch -D "*)
    emit_reason "git branch -D は未マージブランチを強制削除します — 削除前に git log そのブランチ で内容を確認してください（Plan 0043）"
    ;;
  *"git checkout -- ."*|*"git restore ."*)
    emit_reason "git checkout -- . / git restore . は未コミット変更を破棄します — 対象ファイルを絞る（. の代わりに <path>）ことを検討してください（Plan 0043）"
    ;;
esac

exit 0
