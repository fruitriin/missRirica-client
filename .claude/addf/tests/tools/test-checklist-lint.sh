#!/bin/bash
# test-checklist-lint.sh
# lint-checklist.py のチェックリスト裏付け検査テスト。
# 実リポジトリでの正常系と、サンドボックスでの裏付けなし項目検出を検証する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
LINT="$PROJECT_DIR/.claude/addf/addfTools/lint-checklist.py"
PASS=0
FAIL=0

if command -v uv >/dev/null 2>&1; then
  run_lint() { (cd "$1" && uv run --python 3.11 "$LINT" 2>&1); }
else
  run_lint() { (cd "$1" && python3 "$LINT" 2>&1); }
fi

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

assert_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (output missing: $needle)"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  FAIL: $test_name (output should not contain: $needle)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  fi
}

# サンドボックス: 対象手順書のうち ADDF-Release.addf.md だけを置く（他は SKIP される）
make_sandbox() {
  local box
  box="$(mktemp -d)"
  mkdir -p "$box/.claude/addf"
  echo "$box"
}

echo "=== test-checklist-lint.sh ==="

# テスト 1: 実リポジトリで全項目に裏付けあり
# ここが FAIL したらテストではなく手順書のドリフトを疑い、lint の出力に従って
# 実行チェックか human-judgment マーカーを足す（手順書側を直す。エージェントは悪くない）
echo "Test 1: 実リポジトリで OK"
output=$(run_lint "$PROJECT_DIR")
assert_exit "実リポジトリ" 0 $?
assert_contains "OK メッセージ" "OK: チェックリスト裏付け検査通過" "$output"

# テスト 2: 裏付けのない「確認」ステップ → WARNING (exit=2)
echo "Test 2: 裏付けなし項目の検出"
box="$(make_sandbox)"
cat > "$box/.claude/addf/Release.addf.md" <<'EOF'
# リリース手順

## チェック

1. タグが正しいことを確認する
EOF
output=$(run_lint "$box")
assert_exit "裏付けなしで WARNING" 2 $?
assert_contains "対象行の特定" "タグが正しいことを確認する" "$output"
assert_contains "責めないトーン（手順書側の点検であること）" "手順書側の点検です" "$output"
rm -rf "$box"

# テスト 3: 実行チェック・マーカーの各裏付け形式が認められる → exit=0
echo "Test 3: 裏付け形式（コードブロック / インラインコマンド / マーカー）"
box="$(make_sandbox)"
cat > "$box/.claude/addf/Release.addf.md" <<'EOF'
# リリース手順

## チェック

1. テストが全て通過すること
   ```bash
   bash .claude/addf/tests/run-all.sh
   ```
2. タグが存在することを確認する: `git tag -l vX.Y.Z`
3. `/addf-lint` が全チェック通過すること
4. リリースノートの文面が適切かを確認する <!-- human-judgment -->
EOF
output=$(run_lint "$box")
assert_exit "全形式で OK" 0 $?
rm -rf "$box"

# テスト 4: skip-section マーカーはサブセクションにも及ぶ → exit=0
echo "Test 4: skip-section の除外（サブセクション含む）"
box="$(make_sandbox)"
cat > "$box/.claude/addf/Release.addf.md" <<'EOF'
# リリース手順

## check モード

<!-- checklist-lint: skip-section（チェックの実装そのもの） -->

- 必須ファイルの存在を確認する

### サブセクション

- 各参照先が実在するか確認する

## 別セクション

- タグの存在を確認する: `git tag -l vX.Y.Z`
EOF
output=$(run_lint "$box")
assert_exit "除外セクションで OK" 0 $?
# 除外が次の同レベル見出しで解除されることも確認: 別セクションの裏付けを消すと WARNING
sed -i.bak 's/: `git tag -l vX.Y.Z`//' "$box/.claude/addf/Release.addf.md" \
  && rm -f "$box/.claude/addf/Release.addf.md.bak"
output=$(run_lint "$box")
assert_exit "除外解除後のセクションは検査される" 2 $?
assert_contains "解除後の対象行" "タグの存在を確認する" "$output"
assert_not_contains "除外セクション内は報告されない" "必須ファイルの存在を確認する" "$output"
rm -rf "$box"

# テスト 5: 対象ファイルが無い環境（ダウンストリーム相当）→ SKIP で exit=0
echo "Test 5: 対象ファイル欠如時の SKIP"
box="$(make_sandbox)"
output=$(run_lint "$box")
assert_exit "全対象欠如で OK" 0 $?
assert_contains "SKIP 表示" "SKIP: .claude/addf/Release.addf.md が存在しない" "$output"
rm -rf "$box"

# テスト 6: リスト直後の引用・平文中のコマンドは裏付けに数えない（レビュー指摘の回帰テスト）
echo "Test 6: リスト外の解説文への裏付け漏出防止"
box="$(make_sandbox)"
cat > "$box/.claude/addf/Release.addf.md" <<'EOF'
# リリース手順

## チェック

1. タグが正しいことを確認する

> 補足説明として `git tag -l vX.Y.Z` のようなコマンドがあります。
> これは解説文であり、上のステップ1の裏付けではありません。

## 次のセクション
EOF
output=$(run_lint "$box")
assert_exit "引用中のコマンドでは裏付けにならない" 2 $?
assert_contains "対象行の特定" "タグが正しいことを確認する" "$output"
rm -rf "$box"

# テスト 7: 「〜こと」の後に説明が続く形も候補になる（レビュー指摘の回帰テスト）
echo "Test 7: 「〜こと — 説明:」形式の候補判定"
box="$(make_sandbox)"
cat > "$box/.claude/addf/Release.addf.md" <<'EOF'
# リリース手順

## チェック

1. ブロッカーがないこと — 未着手タスクを機械抽出して判断する:
EOF
output=$(run_lint "$box")
assert_exit "説明が続く形でも WARNING" 2 $?
assert_contains "対象行の特定" "ブロッカーがないこと" "$output"
# 同じ項目に裏付け（コードブロック＋マーカー）を足すと OK になる
cat > "$box/.claude/addf/Release.addf.md" <<'EOF'
# リリース手順

## チェック

1. ブロッカーがないこと — 未着手タスクを機械抽出して判断する:
   ```bash
   grep -n '未着手' TODO.md || echo '(なし)'
   ```
   ブロッカーかどうかは人間の判断 <!-- human-judgment -->
EOF
output=$(run_lint "$box")
assert_exit "裏付けを足すと OK" 0 $?
rm -rf "$box"

# テスト 8: コードフェンス内の疑似リスト項目は検査対象外
echo "Test 8: コードフェンス内の除外"
box="$(make_sandbox)"
cat > "$box/.claude/addf/Release.addf.md" <<'EOF'
# リリース手順

## レポート例

```
1. タグが正しいことを確認する
2. lock との一致を検証する
```
EOF
output=$(run_lint "$box")
assert_exit "フェンス内は検査されない" 0 $?
rm -rf "$box"

# テスト 9: WHITELIST 記載行は裏付けなしでも除外される
echo "Test 9: WHITELIST の短絡"
box="$(make_sandbox)"
cat > "$box/.claude/addf/Release.addf.md" <<'EOF'
# リリース手順

## チェック

- 修正後、ビルド・Lint・テストを再実行して通過を確認する
EOF
output=$(run_lint "$box")
assert_exit "WHITELIST 行は OK" 0 $?
rm -rf "$box"

# テスト 10: addf-plan-audit.md のドリフト注入（human-judgment マーカー剥がし → 検出）
# 実物のスキルファイルからマーカーを剥がした状態を再現し、lint が実際に検出することを確認する
# （lint が生まれるきっかけになったケースの再現テスト — ドリフト注入 TDD）
echo "Test 10: addf-plan-audit.md のマーカー剥がし検出"
box="$(make_sandbox)"
mkdir -p "$box/.claude/commands"
cp "$PROJECT_DIR/.claude/commands/addf-plan-audit.md" "$box/.claude/commands/"
output=$(run_lint "$box")
assert_exit "実物コピーは OK（マーカーあり）" 0 $?
sed -i.bak 's/<!-- human-judgment -->//' "$box/.claude/commands/addf-plan-audit.md" \
  && rm -f "$box/.claude/commands/addf-plan-audit.md.bak"
output=$(run_lint "$box")
assert_exit "マーカー剥がしで WARNING" 2 $?
assert_contains "剥がされた項目の特定" "処置の最終判断はオーナーが行う" "$output"
rm -rf "$box"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
