#!/bin/bash
# test-sync-docs-links.sh
# scripts/sync-docs.mjs（Plan 0039 フェーズ2）が生成する .claude/addf/webManual/guide/*.md に、
# 書き換え漏れの相対リンク（`](../` 形式）が残っていないことを検証する。
# ADDF 本体固有の仕組みのため、scripts/sync-docs.mjs が存在しないダウンストリームでは SKIP する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SYNC_SCRIPT="$REPO_ROOT/scripts/sync-docs.mjs"
PASS=0
FAIL=0

check() {
  local desc="$1" expected_exit="$2" actual_exit="$3"
  if [ "$actual_exit" -ne "$expected_exit" ]; then
    echo "  FAIL: $desc (exit: expected=$expected_exit actual=$actual_exit)"
    FAIL=$((FAIL + 1))
    return
  fi
  echo "  PASS: $desc"
  PASS=$((PASS + 1))
}

echo "=== test-sync-docs-links.sh ==="

if [ ! -f "$SYNC_SCRIPT" ] || ! command -v node >/dev/null 2>&1; then
  echo "SKIP: scripts/sync-docs.mjs または node が見つかりません（ADDF 本体固有機能・ダウンストリームでは正常）"
  echo ""
  echo "Results: 0 passed, 0 failed, 1 skipped"
  exit 0
fi

echo "Test 1: sync-docs.mjs 実行後、.claude/addf/webManual/guide/*.md に未書き換えの上位相対リンクが残らない"
(cd "$REPO_ROOT" && node "$SYNC_SCRIPT" >/dev/null 2>&1)
sync_code=$?
check "sync-docs.mjs が正常終了する" 0 "$sync_code"

if grep -rn '](\.\./' "$REPO_ROOT/.claude/addf/webManual/guide/"*.md 2>/dev/null; then
  echo "  FAIL: 未書き換えの上位相対リンク（\`](../\`）が .claude/addf/webManual/guide/ に残存"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: 未書き換えの上位相対リンクは残っていない"
  PASS=$((PASS + 1))
fi

echo "Test 2: 生成された各ガイドに元ファイルと同じ見出しが残っている（内容欠落なし）"
missing=0
for src in "$REPO_ROOT/.claude/addf/guides/"*.md; do
  name="$(basename "$src")"
  dest="$REPO_ROOT/.claude/addf/webManual/guide/$name"
  if [ ! -f "$dest" ]; then
    echo "  FAIL: $name が .claude/addf/webManual/guide/ に生成されていない"
    missing=$((missing + 1))
    continue
  fi
  src_h1="$(grep -m1 '^# ' "$src" || true)"
  dest_h1="$(grep -m1 '^# ' "$dest" || true)"
  if [ "$src_h1" != "$dest_h1" ]; then
    echo "  FAIL: $name の見出しが元ファイルと一致しない"
    missing=$((missing + 1))
  fi
done
check "全ガイドの見出しが一致する（不一致 $missing 件）" 0 "$([ "$missing" -eq 0 ]; echo $?)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
