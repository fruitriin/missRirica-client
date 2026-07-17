#!/bin/bash
# test-doc-review-agent.sh
# addf-doc-review-agent は LLM 起動エージェントのため完全な自動検証は困難。
# 本テストは以下の静的・構造的チェックのみを行う（実行時の検出力は human-judgment 側で確認する）:
#   (a) エージェント定義ファイルが存在し frontmatter・見出しの必須要素を備えているか
#   (b) addf-init のコピーリストで新エージェントがカバーされているか（ペア5 相当の局所検査）
#   (c) ドリフト注入フィクスチャに、観点1〜3で検出すべきキーワードが仕込まれているか
#
# LLM を実際に走らせて検出できたかは、Plan 0039 完了条件の human-judgment 側で確認する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
AGENT="$PROJECT_DIR/.claude/agents/addf-doc-review-agent.md"
INIT="$PROJECT_DIR/.claude/commands/addf-init.md"
FIXTURES="$PROJECT_DIR/.claude/addf/tests/fixtures/doc-review-drift"
PASS=0
FAIL=0

assert_file() {
  local name="$1" path="$2"
  if [ -f "$path" ]; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (missing: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_grep() {
  local name="$1" needle="$2" file="$3"
  if grep -qF -- "$needle" "$file" 2>/dev/null; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name (needle not found: $needle in $file)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== test-doc-review-agent.sh ==="

# (a) エージェント定義ファイルの静的構造チェック
echo "Test A: addf-doc-review-agent.md の必須要素"
assert_file "エージェント定義ファイル存在" "$AGENT"
if [ -f "$AGENT" ]; then
  # frontmatter の必須フィールド
  assert_grep "frontmatter name" "name: addf-doc-review-agent" "$AGENT"
  assert_grep "frontmatter description" "description:" "$AGENT"
  assert_grep "frontmatter tools" "tools:" "$AGENT"
  assert_grep "frontmatter model" "model:" "$AGENT"
  # 汎用観点3つが本文に定義されているか
  assert_grep "観点1（実装との乖離）見出し" "観点 1: ドキュメントドリフト" "$AGENT"
  assert_grep "観点2（モチベーション vs 実装事実）見出し" "観点 2: モチベーション vs 実装事実" "$AGENT"
  assert_grep "観点3（日英同期）見出し" "観点 3: 日英ドキュメントの同期" "$AGENT"
  # 起動条件が明記されているか
  assert_grep "起動条件セクション" "起動条件" "$AGENT"
  # ダウンストリーム追記セクションの存在
  assert_grep "プロジェクト固有チェック" "プロジェクト固有チェック（ダウンストリームで追記）" "$AGENT"
fi

# (b) addf-init コピーリストの glob カバレッジ確認（.claude/agents/addf-*.md）
echo "Test B: addf-init コピーリストの glob カバレッジ"
if [ -f "$INIT" ]; then
  assert_grep "agents/addf-*.md glob エントリ" ".claude/agents/addf-*.md" "$INIT"
fi

# (c) ドリフト注入フィクスチャの必須トークン
echo "Test C: ドリフト注入フィクスチャの必須トークン"
assert_file "フィクスチャディレクトリ README" "$FIXTURES/README.md"
assert_file "観点1 フィクスチャ" "$FIXTURES/drift-impl.md"
assert_file "観点2 フィクスチャ" "$FIXTURES/drift-motivation.md"
assert_file "観点3 英語フィクスチャ" "$FIXTURES/drift-locale-en.md"
assert_file "観点3 日本語フィクスチャ" "$FIXTURES/drift-locale-ja.md"
if [ -f "$FIXTURES/drift-impl.md" ]; then
  assert_grep "観点1: 未実装トークン" "未実装" "$FIXTURES/drift-impl.md"
fi
if [ -f "$FIXTURES/drift-motivation.md" ]; then
  assert_grep "観点2: モチベーション混在パターン" "扱えないから" "$FIXTURES/drift-motivation.md"
fi
if [ -f "$FIXTURES/drift-locale-en.md" ] && [ -f "$FIXTURES/drift-locale-ja.md" ]; then
  # 英語版のオプション節（bullet 形式）にだけ `--verbose` が載っており、日本語版側の
  # オプション節には対応する `- `--verbose`` 行がない、という乖離が仕込まれているか。
  # フィクスチャ末尾の注記コメントでは両ファイルとも `--verbose` に言及するため、
  # bullet 行（`- ` 開始）に限定して片翼欠落を確認する
  if grep -qE '^- .*--verbose' "$FIXTURES/drift-locale-en.md" \
     && ! grep -qE '^- .*--verbose' "$FIXTURES/drift-locale-ja.md"; then
    echo "  PASS: 観点3: --verbose 片翼欠落（en オプション節のみ）"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: 観点3: --verbose 片翼欠落の仕込みが崩れている"
    FAIL=$((FAIL + 1))
  fi
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
