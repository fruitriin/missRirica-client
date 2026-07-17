#!/bin/bash
# run-all.sh
# フック・ツールの自動テストを一括実行する。
# スキルテストは自然言語シナリオのため手動実行（.claude/addf/tests/skills/ を参照）。
#
# 設計ガイドライン（ダウンストリームでテストを追加する場合も同様）:
# - テストが依存する必須ランタイム（bun / uv / python3 等）の不在を SKIP=成功として
#   扱わない。環境起因で実行できないことと、テストが通ったことは別物として区別する。
#   ランタイム不在で 0 件実行のまま ✓ を返す構造にしないこと（ダウンストリーム実例:
#   cron の PATH 落ちで bun 不在 → 74 テストが 0 件実行のまま「All passed」を返した）
#   良い例: command -v bun >/dev/null || { echo "FAIL: bun が必要（インストールしてから再実行）"; exit 1; }
# - 環境的に実行不能なテスト（例: macOS 専用バイナリの非 macOS 実行）を飛ばす場合は、
#   SKIP を明示出力し、件数を Results 行に含める（例: test-tools.sh の
#   「Results: N passed, N failed, N skipped」）。silent に読み飛ばさない

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0

run_test() {
  local test_file="$1"
  local name="$(basename "$test_file")"
  echo ""
  echo "━━━ $name ━━━"
  if bash "$test_file"; then
    echo "→ $name: ALL PASSED"
  else
    echo "→ $name: SOME FAILED"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi
}

echo "╔══════════════════════════════════════╗"
echo "║  ADDF Framework Test Runner          ║"
echo "╚══════════════════════════════════════╝"

# フックテスト
echo ""
echo "▶ Hook Tests"
for f in "$SCRIPT_DIR"/hooks/test-*.sh; do
  [ -f "$f" ] && run_test "$f"
done

# ツールテスト
echo ""
echo "▶ Tool Tests"
for f in "$SCRIPT_DIR"/tools/test-*.sh; do
  [ -f "$f" ] && run_test "$f"
done

# スキルテスト案内
echo ""
echo "▶ Skill Tests (manual)"
echo "  スキルテストは自然言語シナリオです。手動で実行してください:"
for f in "$SCRIPT_DIR"/skills/test-*.md; do
  [ -f "$f" ] && echo "  - $(basename "$f")"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$TOTAL_FAIL" -eq 0 ]; then
  echo "✓ All automated tests passed"
  exit 0
else
  echo "✗ $TOTAL_FAIL test suite(s) had failures"
  exit 1
fi
