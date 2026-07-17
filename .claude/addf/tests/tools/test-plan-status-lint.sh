#!/bin/bash
# test-plan-status-lint.sh
# lint-plan-status.py の Plan 状態整合（誤完了防止）テスト。
# 実リポジトリでの正常系と、サンドボックスへのドリフト注入
# （きっかけになった当のケース = ヘッダ「完了」×完了条件の未チェック残存）を検証する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
LINT="$PROJECT_DIR/.claude/addf/addfTools/lint-plan-status.py"
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

# make_sandbox [ディレクトリ名]: 既定は plans-add。`make_sandbox plans` でダウンストリーム系統
make_sandbox() {
  local box dir="${1:-plans-add}"
  box="$(mktemp -d)"
  mkdir -p "$box/.claude/addf/$dir"
  echo "$box"
}

echo "=== test-plan-status-lint.sh ==="

# テスト 1: 実リポジトリで ERROR ゼロ
# ここが FAIL したら lint ではなく Plan の実データの誤完了を疑う
# （ヘッダとチェックボックスのどちらが実態かを確認して直す。lint を通すために
#  完了状態を機械的に書き換えないこと）
echo "Test 1: 実リポジトリで OK"
output=$(run_lint "$PROJECT_DIR")
assert_exit "実リポジトリ" 0 $?
assert_contains "OK メッセージ" "OK: Plan 状態整合チェック通過" "$output"

# テスト 2: ドリフト注入 — きっかけになった当のケース
# （フェーズ分割 Plan で途中フェーズの PR マージ後、ヘッダだけ「完了」にされて
#  完了条件の未チェックが残る = 0028 型の誤完了）→ ERROR
echo "Test 2: ヘッダ完了 × 未チェック残存 → ERROR"
box="$(make_sandbox)"
cat > "$box/.claude/addf/plans-add/0001-test.md" <<'EOF'
# Plan 0001: テスト計画

## 実装状況: 完了（2026-07-05 フェーズA 完了）

## 完了条件

- [x] フェーズA を実装する
- [ ] フェーズB の lint を新設する
- [ ] lint 全パス
EOF
output=$(run_lint "$box")
assert_exit "誤完了で ERROR" 1 $?
assert_contains "対象ファイルの特定" "0001-test.md" "$output"
assert_contains "未チェック項目の列挙" "フェーズB の lint を新設する" "$output"
assert_contains "責めないトーン（直し方の提示）" "実態に合わせてどちらかを直す" "$output"
rm -rf "$box"

# テスト 3: 一部完了 × 未チェック → OK（中間状態は正当）
echo "Test 3: 一部完了 × 未チェック → OK"
box="$(make_sandbox)"
cat > "$box/.claude/addf/plans-add/0001-test.md" <<'EOF'
# Plan 0001: テスト計画

## 実装状況: 一部完了（フェーズA のみ。B・C は残り）

## 完了条件

- [x] フェーズA を実装する
- [ ] フェーズB の lint を新設する
EOF
output=$(run_lint "$box")
assert_exit "一部完了は対象外" 0 $?
rm -rf "$box"

# テスト 4: 完了 × 全チェック済み → OK（検査件数に計上される）
echo "Test 4: 完了 × 全チェック → OK"
box="$(make_sandbox)"
cat > "$box/.claude/addf/plans-add/0001-test.md" <<'EOF'
# Plan 0001: テスト計画

## 実装状況: 完了（2026-07-05）

## 完了条件

- [x] フェーズA を実装する
- [x] lint 全パス
EOF
output=$(run_lint "$box")
assert_exit "全チェック済みで OK" 0 $?
assert_contains "検査件数に計上" "検査 1 件" "$output"
rm -rf "$box"

# テスト 5: チェックボックスの無い旧書式 Plan → SKIP（明示出力・exit 0）
echo "Test 5: 旧書式（素の箇条書き完了条件）→ SKIP"
box="$(make_sandbox)"
cat > "$box/.claude/addf/plans-add/0001-old.md" <<'EOF'
# Plan 0001: 旧計画

## 実装状況: 完了（2026-03-18）

## 完了条件

- フェーズ1: run-all.sh 全パス
- ドキュメント更新
EOF
cat > "$box/.claude/addf/plans-add/0002-older.md" <<'EOF'
# Plan 0002: さらに旧い計画（完了条件セクション自体が無い）

## 実装状況: 完了（2026-03-18）

## 変更内容

- なにかした
EOF
output=$(run_lint "$box")
assert_exit "旧書式は SKIP で OK" 0 $?
assert_contains "SKIP の明示出力" "旧書式 Plan 2 件" "$output"
assert_contains "SKIP ファイル名の列挙（可視化）" "0001-old.md" "$output"
assert_contains "SKIP ファイル名の列挙（2件目）" "0002-older.md" "$output"
rm -rf "$box"

# テスト 6: コードフェンス内のチェックボックス・見出し例示は無視
echo "Test 6: コードフェンス内の例示は検査しない"
box="$(make_sandbox)"
cat > "$box/.claude/addf/plans-add/0001-test.md" <<'EOF'
# Plan 0001: テンプレートを説明する計画

## 実装状況: 完了（2026-07-05）

## 変更内容

テンプレートの書式例:

```markdown
## 完了条件

- [ ] 例示のチェックボックス（未チェックだが例示なので無視される）
```

## 完了条件

- [x] テンプレートを作成する
EOF
output=$(run_lint "$box")
assert_exit "フェンス内は無視して OK" 0 $?
rm -rf "$box"

# テスト 7: ヘッダ無し旧 Plan・未着手 Plan は対象外
echo "Test 7: ヘッダ無し・未着手は対象外"
box="$(make_sandbox)"
cat > "$box/.claude/addf/plans-add/0001-noheader.md" <<'EOF'
# Plan 0001: ヘッダの無い旧計画

## 完了条件

- [ ] 未チェックだがヘッダが無いので対象外
EOF
cat > "$box/.claude/addf/plans-add/0002-notstarted.md" <<'EOF'
# Plan 0002: 未着手計画

## 実装状況: 未着手

## 完了条件

- [ ] これから
EOF
output=$(run_lint "$box")
assert_exit "ヘッダ無し・未着手で OK" 0 $?
assert_contains "対象外の件数計上" "対象外 2 件" "$output"
rm -rf "$box"

# テスト 8: .claude/addf/plans（ダウンストリーム系統）も検査される・plans-add 不在は SKIP
echo "Test 8: ダウンストリーム系統（.claude/addf/plans）の検査と plans-add 不在 SKIP"
box="$(make_sandbox plans)"
cat > "$box/.claude/addf/plans/0001-downstream.md" <<'EOF'
# Plan 0001: ダウンストリーム計画

## 実装状況: 完了

## 完了条件

- [ ] 未完の項目
EOF
output=$(run_lint "$box")
assert_exit "ダウンストリーム系統でも ERROR" 1 $?
assert_contains "plans-add 不在の SKIP 明示" "SKIP: .claude/addf/plans-add が存在しない" "$output"
assert_contains ".claude/addf/plans 側の検出" ".claude/addf/plans/0001-downstream.md" "$output"
rm -rf "$box"

# テスト 9: 水平線 --- で完了条件セクションが終わる（以降のチェックボックスは対象外）
echo "Test 9: セクション境界（水平線）"
box="$(make_sandbox)"
cat > "$box/.claude/addf/plans-add/0001-test.md" <<'EOF'
# Plan 0001: テスト計画

## 実装状況: 完了

## 完了条件

- [x] 実装する

---

補足メモ:

- [ ] これは完了条件ではない作業メモ
EOF
output=$(run_lint "$box")
assert_exit "水平線以降は対象外で OK" 0 $?
assert_not_contains "セクション外は報告されない" "作業メモ" "$output"
rm -rf "$box"

# テスト 10: GFM マーカー網羅 — `+ [ ]`（修正前のすり抜け穴）と番号付き `1. [ ]` / `1) [ ]`
# （ドリフト注入 TDD: CHECKBOX_RE が `[-*]` のみだった頃の false negative を固定する）
echo "Test 10: + マーカー・番号付きリストのチェックボックスも検出（ERROR）"
box="$(make_sandbox)"
cat > "$box/.claude/addf/plans-add/0001-plus.md" <<'EOF'
# Plan 0001: + マーカーの計画

## 実装状況: 完了

## 完了条件

+ [x] 実装する
+ [ ] plus マーカーの未チェック項目
EOF
cat > "$box/.claude/addf/plans-add/0002-numbered.md" <<'EOF'
# Plan 0002: 番号付きリストの計画

## 実装状況: 完了

## 完了条件

1. [x] 実装する
2. [ ] ドット番号の未チェック項目
3) [ ] 括弧番号の未チェック項目
EOF
output=$(run_lint "$box")
assert_exit "+ / 番号付きの未チェックで ERROR" 1 $?
assert_contains "+ マーカーのすり抜け防止" "plus マーカーの未チェック項目" "$output"
assert_contains "番号付き（ドット）の検出" "ドット番号の未チェック項目" "$output"
assert_contains "番号付き（括弧）の検出" "括弧番号の未チェック項目" "$output"
rm -rf "$box"

# テスト 11: 表記ゆれ状態ヘッダ × チェックボックス保有 → WARNING（exit 2）
# （`## 状態:` / レベル違い `### 実装状況:` / コロン無し `## 実装状況 完了` の3類型）
echo "Test 11: 表記ゆれヘッダは無言スキップせず WARNING"
box="$(make_sandbox)"
cat > "$box/.claude/addf/plans-add/0001-alt.md" <<'EOF'
# Plan 0001: 状態ヘッダの計画

## 状態: 完了

## 完了条件

- [ ] 未チェックだが表記ゆれヘッダのため ERROR 検査からは漏れる
EOF
cat > "$box/.claude/addf/plans-add/0002-level.md" <<'EOF'
# Plan 0002: レベル違いヘッダの計画

### 実装状況: 完了

## 完了条件

- [ ] 未チェック
EOF
cat > "$box/.claude/addf/plans-add/0003-nocolon.md" <<'EOF'
# Plan 0003: コロン無しヘッダの計画

## 実装状況 完了

## 完了条件

- [ ] 未チェック
EOF
output=$(run_lint "$box")
assert_exit "表記ゆれで WARNING（exit 2）" 2 $?
assert_contains "統一の促し" "「## 実装状況:」に統一する" "$output"
assert_contains "「## 状態:」の検出" "0001-alt.md" "$output"
assert_contains "レベル違い「### 実装状況:」の検出" "0002-level.md" "$output"
assert_contains "コロン無し「実装状況 完了」の検出" "0003-nocolon.md" "$output"
rm -rf "$box"

# テスト 11b: 表記ゆれヘッダでもチェックボックスが無ければ WARNING しない（旧 Plan の平穏を守る）
echo "Test 11b: 表記ゆれ × チェックボックス無し → 対象外のまま OK"
box="$(make_sandbox)"
cat > "$box/.claude/addf/plans-add/0001-alt-nobox.md" <<'EOF'
# Plan 0001: 状態ヘッダはあるがチェックボックスの無い旧計画

## 状態: 完了

## 完了条件

- 素の箇条書きの条件
EOF
output=$(run_lint "$box")
assert_exit "チェックボックス無しは WARNING しない" 0 $?
rm -rf "$box"

# テスト 12: ~~~ フェンス・4連バッククォートフェンス内の例示は無視
# （attacker 実測の false positive: ~~~ 内の例示チェックボックスで正当 Plan が ERROR になっていた）
echo "Test 12: ~~~ / ```` フェンス内の例示は検査しない"
box="$(make_sandbox)"
cat > "$box/.claude/addf/plans-add/0001-tilde.md" <<'EOF'
# Plan 0001: チルダフェンスで例示する計画

## 実装状況: 完了

## 変更内容

書式例:

~~~markdown
## 完了条件

- [ ] チルダフェンス内の例示（無視される）
~~~

さらに4連バッククォートの例:

````markdown
## 完了条件

- [ ] 4連フェンス内の例示（無視される）
````

## 完了条件

- [x] 実装する
EOF
output=$(run_lint "$box")
assert_exit "チルダ・4連フェンス内は無視して OK" 0 $?
rm -rf "$box"

# テスト 13: 見出しに「完了条件」を含むセクション（### フェーズA: 完了条件）も検出
echo "Test 13: 「完了条件」を含む見出し（前置き付き）も対象"
box="$(make_sandbox)"
cat > "$box/.claude/addf/plans-add/0001-phase.md" <<'EOF'
# Plan 0001: フェーズ分割の計画

## 実装状況: 完了

### フェーズA: 完了条件

- [x] A を実装する
- [ ] フェーズA の残項目
EOF
output=$(run_lint "$box")
assert_exit "前置き付き見出しでも ERROR" 1 $?
assert_contains "前置き付きセクション内の検出" "フェーズA の残項目" "$output"
rm -rf "$box"

# テスト 14: 複数の完了条件セクションは全部拾う（2つ目の未チェックも検出）
echo "Test 14: 複数の完了条件セクションを全て検査"
box="$(make_sandbox)"
cat > "$box/.claude/addf/plans-add/0001-multi.md" <<'EOF'
# Plan 0001: 完了条件が2つある計画

## 実装状況: 完了

## 完了条件

- [x] 1つ目のセクションは全チェック

## 補足

本文。

## 完了条件（追加分）

- [ ] 2つ目のセクションの未チェック項目
EOF
output=$(run_lint "$box")
assert_exit "2つ目のセクションでも ERROR" 1 $?
assert_contains "2つ目のセクション内の検出" "2つ目のセクションの未チェック項目" "$output"
rm -rf "$box"

# テスト 15: 検査対象 0 件（docs/ 自体が無い）→ exit 0 + 実行場所確認の NOTE
echo "Test 15: 検査対象 0 件で NOTE"
box="$(mktemp -d)"
output=$(run_lint "$box")
assert_exit "0 件でも OK（exit 0）" 0 $?
assert_contains "実行場所確認の NOTE" "NOTE: 検査対象 0 件" "$output"
rm -rf "$box"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
