#!/bin/bash
# test-template-sync.sh
# lint-template-sync.py の同期チェックテスト。
# 実リポジトリでの正常系と、サンドボックスでの意図的ドリフト検出を検証する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
LINT="$PROJECT_DIR/.claude/addf/addfTools/lint-template-sync.py"
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
    echo "  FAIL: $test_name (output unexpectedly contains: $needle)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  fi
}

# コードフェンス（``` / ~~~）内を除去する（verify-checksums.sh の strip_fences() と同じ発想。
# CLAUDE.repo.example.md はダウンストリーム向けの書き換え例をコードフェンス内に持つため、
# フェンスを除去しないと upstream/downstream 両方のマーカーが地の文にヒットしたと誤認する）
strip_fences_for_test() {
  awk '
    { s = $0; sub(/^[ \t]+/, "", s) }
    fence != "" { if (index(s, fence) == 1) fence = ""; next }
    substr(s, 1, 3) == "```" || substr(s, 1, 3) == "~~~" { fence = substr(s, 1, 3); next }
    { print }
  '
}

# 独立オラクル: lint 出力（$output）とは別経路で、実プロジェクトの CLAUDE.repo.md 宣言を
# 直接判定する。verify-checksums.sh / lint-template-sync.py の detect_repo_kind() と
# 同じ判定仕様（CLAUDE.repo.md の種別宣言＋@メンション1段解決／フォールバック: lock.json）
# をテスト専用に簡易再実装したもの（code-review 指摘: 分岐条件と検証が同じ $output に対する
# 同一の grep 述語だと、判定結果が何であれ両方 PASS する恒真式になり regression guard として
# 機能しない。宣言と結果の整合を検証するには、宣言そのものを独立に読む必要がある）
detect_expected_repo_kind() {
  local dir="$1" text="" line trimmed inc
  if [ -f "$dir/CLAUDE.repo.md" ]; then
    text="$(strip_fences_for_test < "$dir/CLAUDE.repo.md")"
    while IFS= read -r line; do
      trimmed="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      case "$trimmed" in
        @*.md)
          inc="${trimmed#@}"
          if [ -f "$dir/$inc" ]; then
            text="$text
$(strip_fences_for_test < "$dir/$inc")"
          fi
          ;;
      esac
    done <<EOF_LINES
$text
EOF_LINES
  fi
  if printf '%s' "$text" | grep -qF '**ADDF 開発プロジェクト**' \
     && ! printf '%s' "$text" | grep -qF '**ADDF 利用プロジェクト**'; then
    echo upstream
  elif printf '%s' "$text" | grep -qF '**ADDF 利用プロジェクト**' \
     && ! printf '%s' "$text" | grep -qF '**ADDF 開発プロジェクト**'; then
    echo downstream
  elif [ -f "$dir/.claude/addf/lock.json" ]; then
    echo downstream
  else
    echo unknown
  fi
}

make_sandbox() {
  local box
  box="$(mktemp -d)"
  mkdir -p "$box/.claude/addf/templates" "$box/.claude/commands" "$box/.claude/addf/guides"
  cp "$PROJECT_DIR/CLAUDE.md" "$PROJECT_DIR/AGENTS.md" "$PROJECT_DIR/.gitignore" "$box/"
  cp "$PROJECT_DIR/README.md" "$box/"
  # README.en.md は ADDF 本体では必須だが、英語版を持たないダウンストリームプロジェクトでは
  # 存在しない（Issue #29）。存在するときだけコピーし、無条件 cp によるノイズを避ける
  [ -f "$PROJECT_DIR/README.en.md" ] && cp "$PROJECT_DIR/README.en.md" "$box/"
  cp "$PROJECT_DIR/.claude/addf/Progress.md" "$box/.claude/addf/"
  # ProgressTemplate.addf.md は ADDF 本体専用で downstream には配布されない（Issue #30）。
  # `.md` 版は upstream / downstream ともに存在するため常にコピーし、`.addf.md` 版は
  # 存在時はそのまま・不在時は `.md` 版を疑似コピーして upstream 環境をシミュレートする
  # （Issue #31 提案。テストがサンドボックス内で `.addf.md` 経路の検査能力を保つため）。
  # サンドボックス内で明示的に downstream 環境を再現したいテストは、後段で
  # `rm -f "$box/.claude/addf/templates/ProgressTemplate.addf.md"` する（テスト 6 参照）
  cp "$PROJECT_DIR/.claude/addf/templates/ProgressTemplate.md" "$box/.claude/addf/templates/"
  if [ -f "$PROJECT_DIR/.claude/addf/templates/ProgressTemplate.addf.md" ]; then
    cp "$PROJECT_DIR/.claude/addf/templates/ProgressTemplate.addf.md" \
       "$box/.claude/addf/templates/"
  else
    cp "$PROJECT_DIR/.claude/addf/templates/ProgressTemplate.md" \
       "$box/.claude/addf/templates/ProgressTemplate.addf.md"
  fi
  cp "$PROJECT_DIR/.claude/commands/addf-init.md" "$box/.claude/commands/"
  cp "$PROJECT_DIR"/.claude/commands/addf-*.md "$box/.claude/commands/"
  cp "$PROJECT_DIR/.claude/addf/guides/development-process.md" "$box/.claude/addf/guides/"
  echo "$box"
}

echo "=== test-template-sync.sh ==="

# テスト 1: 実リポジトリで全ペア同期済み（意図的差分が誤検出されないことの確認を兼ねる）
# リポジトリがクリーンに同期された状態であること。
# ここが FAIL したらテストではなく実ファイルのドリフトを疑い、lint の出力に従って同期する
#
# Issue #29: 以前は「ADDF 本体（upstream 宣言）での実行」を前提に pair1〜3 が SKIP
# されないことを固定でアサートしていたが、ダウンストリームプロジェクト（downstream 宣言）
# が自身の $PROJECT_DIR で実行すると pair1〜3 が正当に SKIP され、このアサーションは
# 常に FAIL していた。$PROJECT_DIR の CLAUDE.repo.md 宣言を独立オラクル
# （detect_expected_repo_kind）で判定し、その宣言と実際の SKIP/非SKIP 挙動が整合しているか
# を検証する（宣言優先の設計そのものは変えない）
echo "Test 1: 実リポジトリで OK"
output=$(run_lint "$PROJECT_DIR")
assert_exit "実リポジトリ" 0 $?
assert_contains "OK メッセージ" "OK: 同期チェック通過" "$output"
expected_kind="$(detect_expected_repo_kind "$PROJECT_DIR")"
for pair in 1 2 3; do
  case "$expected_kind" in
    downstream)
      # pair1 は非対称: .addf.md が物理残存する場合のみ SKIP メッセージを出し、
      # 不在（真のダウンストリーム）では SKIP せず ProgressTemplate.md との実比較に
      # 静かに切り替わる（check_pair1 の設計）。SKIP を無条件に期待すると
      # 真の DS リポジトリで必ず FAIL する（contribution-agent の DS 実測で検出）
      if [ "$pair" = "1" ] && [ ! -f "$PROJECT_DIR/.claude/addf/templates/ProgressTemplate.addf.md" ]; then
        echo "  情報: ペア1は .addf.md 不在（真の downstream）のため SKIP せず実比較 — exit 0 で検証済み"
        continue
      fi
      assert_contains "ペア${pair}が SKIP される（downstream 宣言）" "[$pair] SKIP" "$output"
      ;;
    upstream)
      assert_not_contains "ペア${pair}が SKIP されない（upstream 宣言）" "[$pair] SKIP" "$output"
      ;;
    *)
      echo "  情報: CLAUDE.repo.md から repo_kind を判定できず（宣言なし・lock なし）、ペア${pair}の期待値検証をスキップ"
      ;;
  esac
done

# テスト 2: ProgressTemplate.md のステップ欠落 → WARNING (exit=2)
echo "Test 2: ダウンストリーム版テンプレートのステップ欠落"
box="$(make_sandbox)"
grep -v '^15\. コミットする' "$box/.claude/addf/templates/ProgressTemplate.md" > "$box/tmp" \
  && mv "$box/tmp" "$box/.claude/addf/templates/ProgressTemplate.md"
output=$(run_lint "$box")
assert_exit "ステップ欠落で WARNING" 2 $?
assert_contains "ペア2の WARNING" "[2] WARNING" "$output"
assert_contains "欠落行の特定" "ADDF版のみ: 15. コミットする" "$output"
assert_contains "git ヒント" "ヒント(最終更新)" "$output"
rm -rf "$box"

# テスト 3: AGENTS.md のブートシーケンス手順欠落 → WARNING (exit=2)
echo "Test 3: AGENTS.md の手順欠落"
box="$(make_sandbox)"
sed -i.bak 's/^5\. /- /' "$box/AGENTS.md" && rm -f "$box/AGENTS.md.bak"
output=$(run_lint "$box")
assert_exit "手順欠落で WARNING" 2 $?
assert_contains "ペア3の WARNING" "[3] WARNING" "$output"
rm -rf "$box"

# テスト 4: Progress.md の運用ルール乖離 → ERROR (exit=1)
# 判定不能（シグナル無し）だと WARNING に格下げされるため、upstream 宣言を明示して
# ADDF 本体相当の環境をシミュレートする（格下げ側の検証はテスト 19）
echo "Test 4: Progress.md の運用ルール乖離"
box="$(make_sandbox)"
printf '# CLAUDE.repo.md\n\nこのリポジトリは **ADDF 開発プロジェクト**（フレームワーク本体）です。\n' \
  > "$box/CLAUDE.repo.md"
grep -v '^15\. コミットする' "$box/.claude/addf/Progress.md" > "$box/tmp" \
  && mv "$box/tmp" "$box/.claude/addf/Progress.md"
output=$(run_lint "$box")
assert_exit "運用ルール乖離で ERROR" 1 $?
assert_contains "ペア1の ERROR" "[1] ERROR" "$output"
rm -rf "$box"

# テスト 4b: Progress.md の `## タスク` 以降だけ変更しても ペア1 は誤検知しない
#         （Plan 0046 で明文化した境界: タスク欄は同期対象外・運用ルール節のみ検査）
echo "Test 4b: `## タスク` 以降の変更でペア1が誤検知しない"
box="$(make_sandbox)"
printf '# CLAUDE.repo.md\n\nこのリポジトリは **ADDF 開発プロジェクト**（フレームワーク本体）です。\n' \
  > "$box/CLAUDE.repo.md"
# タスク欄に日記・チェックリストを追記（運用ルール節は無変更）
cat >> "$box/.claude/addf/Progress.md" <<'PATCH'

### 現在のタスク: サンドボックスタスク

#### サブタスクチェックリスト
- [x] 何かを実装した
- [ ] まだやってないこと

#### 日記

##### 2026-07-07 — 委譲境界テスト
**やったこと**: タスク欄だけ追加してペア1 が誤検知しないことを確かめる
**今の見立て**: 誤検知しないはず
**次の自分へ**: なし
**気になっていること**: なし
PATCH
output=$(run_lint "$box")
assert_exit "タスク欄の変更でペア1 は OK" 0 $?
assert_not_contains "ペア1 の ERROR は出ない" "[1] ERROR" "$output"
assert_not_contains "ペア1 の WARNING も出ない" "[1] WARNING" "$output"
rm -rf "$box"

# テスト 5: development-process.md の手順追加ドリフト → WARNING (exit=2)
echo "Test 5: development-process.md の手順ドリフト"
box="$(make_sandbox)"
sed -i.bak 's/^4\. TODO に未完了タスクがない場合/44. TODO に未完了タスクがない場合/' \
  "$box/.claude/addf/guides/development-process.md" && rm -f "$box/.claude/addf/guides/development-process.md.bak"
output=$(run_lint "$box")
assert_exit "手順ドリフトで WARNING" 2 $?
assert_contains "ペア4の WARNING" "[4] WARNING" "$output"
rm -rf "$box"

# テスト 6: ダウンストリーム環境（ADDF 本体固有ファイルなし）→ ペア2〜4 SKIP で exit=0
# addf-init.md と .gitignore は配布対象のため存在する想定（ペア5は SKIP せず実行され OK になる）
echo "Test 6: ダウンストリーム環境シミュレーション"
box="$(make_sandbox)"
rm -f "$box/.claude/addf/templates/ProgressTemplate.addf.md" "$box/AGENTS.md"
rm -rf "$box/.claude/addf/guides"
# Progress.md をダウンストリーム版テンプレート由来の内容に変換する
sed -i.bak -e 's/ProgressTemplate\.addf\.md/ProgressTemplate.md/g' \
  -e '/ADD フレームワークテスト/d' "$box/.claude/addf/Progress.md" && rm -f "$box/.claude/addf/Progress.md.bak"
output=$(run_lint "$box")
assert_exit "ダウンストリームで OK" 0 $?
assert_contains "ペア2の SKIP" "[2] SKIP" "$output"
assert_contains "ペア3の SKIP" "[3] SKIP" "$output"
assert_contains "ペア4の SKIP" "[4] SKIP" "$output"
rm -rf "$box"

# テスト 7: CLAUDE.md に未カバーの .claude/ 参照を注入 → ペア5 WARNING (exit=2)
echo "Test 7: addf-init コピーリストのカバー漏れ検出"
box="$(make_sandbox)"
printf '\n通知の書式は `.claude/NewFeature.example.md` を参照\n' >> "$box/CLAUDE.md"
output=$(run_lint "$box")
assert_exit "カバー漏れで WARNING" 2 $?
assert_contains "ペア5の WARNING" "[5] WARNING" "$output"
assert_contains "漏れファイルの特定" "UNCOVERED: .claude/NewFeature.example.md" "$output"
rm -rf "$box"

# テスト 8: addf-init.md 欠如 → ペア5 SKIP で exit=0
# （欠如時はカバー漏れがあっても検査されない。テスト7の検出はaddf-init.md の存在が前提）
echo "Test 8: addf-init.md 欠如時の SKIP"
box="$(make_sandbox)"
rm -f "$box/.claude/commands/addf-init.md"
output=$(run_lint "$box")
assert_exit "addf-init 欠如で OK" 0 $?
assert_contains "ペア5の SKIP" "[5] SKIP" "$output"
rm -rf "$box"

# テスト 9: .gitignore 欠如 → 実行時生成ファイル（.claude/addf/Dashboard.md）がカバー不能で WARNING
# addf-init 実行後の環境では .gitignore ADDF ブロックが必ず存在するため定常運用では発生しない。
# 発生時は「未整備」を伝える早期警告として妥当 — その仕様をここで固定化する
echo "Test 9: .gitignore 欠如時のカバー漏れ検出"
box="$(make_sandbox)"
rm -f "$box/.gitignore"
output=$(run_lint "$box")
assert_exit ".gitignore 欠如で WARNING" 2 $?
assert_contains "Dashboard.md の UNCOVERED" "UNCOVERED: .claude/addf/Dashboard.md" "$output"
rm -rf "$box"

# ペア6用サンドボックス: TODO.addf.md と Plan ファイルの最小セットを作る
make_plans_sandbox() {
  local box
  box="$(make_sandbox)"
  mkdir -p "$box/.claude/addf/plans-add"
  cat > "$box/.claude/addf/plans-add/0001-sample.md" <<'EOF'
# Plan: サンプル

## 実装状況: 完了（2026-06-11）

本文
EOF
  cat > "$box/.claude/addf/plans-add/TODO.addf.md" <<'EOF'
# TODO (ADDF)

| 優先度 | Phase | 計画ファイル | 状態 |
|---|---|---|---|
| 1 | 1 | `.claude/addf/plans-add/0001-sample.md` | 完了 |
EOF
  echo "$box"
}

# テスト 10: TODO「未着手」⇔ Plan ヘッダ「完了」の矛盾 → ペア6 WARNING (exit=2)
echo "Test 10: TODO⇔Plan 状態の矛盾検出"
box="$(make_plans_sandbox)"
sed -i.bak 's/| 完了 |/| 未着手 |/' "$box/.claude/addf/plans-add/TODO.addf.md" \
  && rm -f "$box/.claude/addf/plans-add/TODO.addf.md.bak"
output=$(run_lint "$box")
assert_exit "状態矛盾で WARNING" 2 $?
assert_contains "ペア6の WARNING" "[6] WARNING" "$output"
assert_contains "矛盾の特定" "矛盾: .claude/addf/plans-add/0001-sample.md" "$output"
rm -rf "$box"

# テスト 11: TODO 登録漏れと参照切れ → ペア6 WARNING (exit=2)
echo "Test 11: TODO 登録漏れ・参照切れの検出"
box="$(make_plans_sandbox)"
cat > "$box/.claude/addf/plans-add/0002-unlisted.md" <<'EOF'
# Plan: 登録漏れサンプル

## 実装状況: 未着手
EOF
printf '| 2 | 2 | `.claude/addf/plans-add/0003-ghost.md` | 未着手 |\n' >> "$box/.claude/addf/plans-add/TODO.addf.md"
output=$(run_lint "$box")
assert_exit "登録漏れで WARNING" 2 $?
assert_contains "登録漏れの特定" "登録漏れ: .claude/addf/plans-add/0002-unlisted.md" "$output"
assert_contains "参照切れの特定" "不在: .claude/addf/plans-add/TODO.addf.md が参照する .claude/addf/plans-add/0003-ghost.md" "$output"
rm -rf "$box"

# テスト 12: 実装状況ヘッダの無い Plan は検査対象外（信用ベース・旧 Plan 互換）→ exit=0
# あわせて TODO が無い環境（make_sandbox のまま）で SKIP になることも確認する
# 注: テスト1と同じく実リポジトリのコピーが前提。exit≠0 ならペア6ではなく実ファイルのドリフトを疑う
echo "Test 12: ヘッダ無し Plan のスキップと TODO 不在の SKIP"
box="$(make_plans_sandbox)"
printf '# Plan: ヘッダ無し旧式\n\n本文のみ\n' > "$box/.claude/addf/plans-add/0001-sample.md"
output=$(run_lint "$box")
assert_exit "ヘッダ無しで OK" 0 $?
rm -rf "$box"
box="$(make_sandbox)"
output=$(run_lint "$box")
assert_contains "TODO 不在で SKIP" "[6] SKIP" "$output"
rm -rf "$box"

# テスト 13: `## 状態:` 等の表記ゆれヘッダ → WARNING (exit=2)
# 実装状況ヘッダの表記ゆれは「状態を書いているのに検査から漏れる」穴になる（Plan 0025 で顕在化）
echo "Test 13: 表記ゆれヘッダの検出"
box="$(make_plans_sandbox)"
printf '# Plan: 表記ゆれ\n\n## 状態: 未着手\n\n本文\n' > "$box/.claude/addf/plans-add/0001-sample.md"
output=$(run_lint "$box")
assert_exit "表記ゆれで WARNING" 2 $?
assert_contains "表記ゆれの特定" "表記ゆれ: .claude/addf/plans-add/0001-sample.md" "$output"
rm -rf "$box"

# テスト 14: addf-lock.json ありのダウンストリーム構成（Plan 0033 回帰）
# 配布・持ち込みで `.addf.md` が物理存在し、独自 AGENTS.md（ADDF ブートシーケンス
# 見出しなし）を持つケース。存在ベース判定なら「ADDF 本体」と誤認してペア1 ERROR・
# ペア3 ERROR になるが、lock を所有シグナルとして扱えば誤検知せず exit=0 になる
echo "Test 14: addf-lock.json ありダウンストリームで .addf.md / 独自 AGENTS.md が存在しても誤検知しない"
box="$(make_sandbox)"
cat > "$box/.claude/addf/lock.json" <<'EOF'
{
  "version": "0.4.0",
  "ref": "v0.4.0",
  "repository": "https://github.com/fruitriin/ADDF.git"
}
EOF
printf '# AGENTS.md\n\nダウンストリーム独自のエージェント規約。ADDF のブートシーケンス見出しは持たない。\n' > "$box/AGENTS.md"
# Progress.md はダウンストリーム版テンプレート（ProgressTemplate.md）由来の内容にする
sed -i.bak -e 's/ProgressTemplate\.addf\.md/ProgressTemplate.md/g' \
  -e '/ADD フレームワークテスト/d' "$box/.claude/addf/Progress.md" && rm -f "$box/.claude/addf/Progress.md.bak"
output=$(run_lint "$box")
assert_exit "ダウンストリーム構成で誤検知しない" 0 $?
assert_contains "ペア2の SKIP（.addf.md 物理存在でも比較しない）" "[2] SKIP" "$output"
assert_contains "ペア3の SKIP（独自 AGENTS.md を検査しない）" "[3] SKIP" "$output"
rm -rf "$box"

# テスト 15: CLAUDE.repo.md の種別宣言（一次根拠）だけでもダウンストリームと判定される
# lock なし・宣言のみのケース。コードブロック外の「ADDF 利用プロジェクト」宣言を読む
echo "Test 15: CLAUDE.repo.md の種別宣言によるダウンストリーム判定"
box="$(make_sandbox)"
printf '# CLAUDE.repo.md\n\nこのリポジトリは **ADDF 利用プロジェクト** です。\n' > "$box/CLAUDE.repo.md"
printf '# AGENTS.md\n\n独自規約のみ。\n' > "$box/AGENTS.md"
sed -i.bak -e 's/ProgressTemplate\.addf\.md/ProgressTemplate.md/g' \
  -e '/ADD フレームワークテスト/d' "$box/.claude/addf/Progress.md" && rm -f "$box/.claude/addf/Progress.md.bak"
output=$(run_lint "$box")
assert_exit "種別宣言でダウンストリーム判定" 0 $?
assert_contains "ペア3の SKIP" "[3] SKIP" "$output"
rm -rf "$box"

# テスト 16: 欺く入力 — 否定文「ADDF 開発プロジェクトではありません」だけの CLAUDE.repo.md
# ＋ lock あり。部分文字列判定なら upstream に誤爆するが、太字マーカー込みの厳密一致なら
# 地の文にマッチせず lock フォールバックで downstream 判定になる（Plan 0033 レビュー回帰）
echo "Test 16: 否定文の種別言及に誤爆せず lock で downstream 判定"
box="$(make_sandbox)"
printf '# CLAUDE.repo.md\n\nこのリポジトリは ADDF 開発プロジェクトではありません。\n' > "$box/CLAUDE.repo.md"
printf '{ "version": "0.4.0", "ref": "v0.4.0", "repository": "https://github.com/fruitriin/ADDF.git" }\n' \
  > "$box/.claude/addf/lock.json"
printf '# AGENTS.md\n\n独自規約のみ。\n' > "$box/AGENTS.md"
sed -i.bak -e 's/ProgressTemplate\.addf\.md/ProgressTemplate.md/g' \
  -e '/ADD フレームワークテスト/d' "$box/.claude/addf/Progress.md" && rm -f "$box/.claude/addf/Progress.md.bak"
output=$(run_lint "$box")
assert_exit "否定文で誤爆しない" 0 $?
assert_contains "ペア3の SKIP（downstream 判定）" "[3] SKIP" "$output"
rm -rf "$box"

# テスト 17: 混在文 — upstream/downstream 両方の太字宣言が地の文にある ＋ lock あり。
# 無条件 upstream 優先なら誤爆するが、両ヒットは判定不能（安全側）として
# lock フォールバック経由で downstream になる
echo "Test 17: 両宣言の混在は判定不能として lock フォールバックで downstream"
box="$(make_sandbox)"
printf '# CLAUDE.repo.md\n\nかつて **ADDF 開発プロジェクト** として始まったが、現在は **ADDF 利用プロジェクト** です。\n' \
  > "$box/CLAUDE.repo.md"
printf '{ "version": "0.4.0", "ref": "v0.4.0", "repository": "https://github.com/fruitriin/ADDF.git" }\n' \
  > "$box/.claude/addf/lock.json"
printf '# AGENTS.md\n\n独自規約のみ。\n' > "$box/AGENTS.md"
sed -i.bak -e 's/ProgressTemplate\.addf\.md/ProgressTemplate.md/g' \
  -e '/ADD フレームワークテスト/d' "$box/.claude/addf/Progress.md" && rm -f "$box/.claude/addf/Progress.md.bak"
output=$(run_lint "$box")
assert_exit "混在文で upstream 優先しない" 0 $?
assert_contains "ペア3の SKIP（downstream 判定）" "[3] SKIP" "$output"
rm -rf "$box"

# テスト 18: ~~~ フェンス内の upstream 文言は宣言として扱わない（``` のみ対応だった穴の回帰）。
# 地の文の太字 downstream 宣言だけが有効で、lock なしでも downstream 判定になる
echo "Test 18: ~~~ フェンス内の upstream 文言を除外して downstream 判定"
box="$(make_sandbox)"
cat > "$box/CLAUDE.repo.md" <<'EOF'
# CLAUDE.repo.md

このリポジトリは **ADDF 利用プロジェクト** です。

~~~
このリポジトリは **ADDF 開発プロジェクト**（フレームワーク本体）です。
~~~
EOF
printf '# AGENTS.md\n\n独自規約のみ。\n' > "$box/AGENTS.md"
sed -i.bak -e 's/ProgressTemplate\.addf\.md/ProgressTemplate.md/g' \
  -e '/ADD フレームワークテスト/d' "$box/.claude/addf/Progress.md" && rm -f "$box/.claude/addf/Progress.md.bak"
output=$(run_lint "$box")
assert_exit "~~~ フェンスを除外して downstream 判定" 0 $?
assert_contains "ペア3の SKIP（downstream 判定）" "[3] SKIP" "$output"
rm -rf "$box"

# テスト 19: シグナル無し（宣言なし・lock なし = 旧配布ダウンストリーム相当）＋ .addf.md 残置
# ＋独自 AGENTS.md。判定不能を upstream と同一視すると pair1/pair3 が ERROR(1) になるが、
# 格下げ後は WARNING(2) で、種別宣言/lock の整備を促すメッセージが出る
echo "Test 19: シグナル無し環境では ERROR ではなく WARNING ＋整備の促し"
box="$(make_sandbox)"
printf '# AGENTS.md\n\n独自規約のみ。\n' > "$box/AGENTS.md"
# pair1 のドリフトはテンプレ側「## 運用ルール」節内への合成行挿入で注入する
# （スキーム非依存。末尾 >> では「## タスク」以降＝検査範囲外に落ちる）。
# 旧方式（Progress.md への sed）は host の Progress.md が upstream 由来の文言を
# 含む前提で、真の downstream（無印テンプレ由来）では no-op になり FAIL していた
awk '1; /^## 運用ルール$/ { print "- ドリフト注入用の合成ルール行ですよ" }' \
  "$box/.claude/addf/templates/ProgressTemplate.addf.md" > "$box/.claude/addf/templates/ProgressTemplate.addf.md.tmp" \
  && mv "$box/.claude/addf/templates/ProgressTemplate.addf.md.tmp" "$box/.claude/addf/templates/ProgressTemplate.addf.md"
output=$(run_lint "$box")
assert_exit "判定不能は WARNING 止まり" 2 $?
assert_contains "ペア1の WARNING 格下げ" "[1] WARNING" "$output"
assert_contains "ペア3の WARNING 格下げ" "[3] WARNING" "$output"
assert_not_contains "ペア1が ERROR にならない" "[1] ERROR" "$output"
assert_not_contains "ペア3が ERROR にならない" "[3] ERROR" "$output"
assert_contains "整備の促しメッセージ" ".claude/addf/lock.json を配置する" "$output"
rm -rf "$box"

# テスト 20: @メンションのパストラバーサル注入（Plan 0043 項目4）
# CLAUDE.repo.md に `@../../etc/passwd`・`@/etc/passwd`・シンボリックリンク経由の脱出を
# 仕掛けたとき、いずれも silent に無視される（宣言としてカウントされない）ことを確認する
echo "Test 20: @メンションのパストラバーサル耐性"
box="$(make_sandbox)"
# 外部ファイル（ADDF 利用プロジェクト宣言を含む）を box の外に配置
extern_dir="$(mktemp -d)"
printf 'このリポジトリは **ADDF 利用プロジェクト** です。\n' > "$extern_dir/leak.md"
# 相対パス .. で外部を参照
printf '# CLAUDE.repo.md\n\n@../%s/leak.md\n' "$(basename "$extern_dir")" > "$box/CLAUDE.repo.md"
# lock なし + 有効な種別宣言も無し → 判定不能で WARNING（脱出が成功していれば downstream 判定になり
# ペア3 SKIP で exit=0 になるため、WARNING/exit=2 を確認すれば脱出失敗の証拠になる）
output=$(run_lint "$box")
# 脱出できていれば宣言が読み取れて判定できるが、ガードが効いていれば宣言不能
assert_not_contains "パストラバーサルで downstream 判定できない" "[1] SKIP: repo_kind=downstream" "$output"
rm -rf "$box" "$extern_dir"

# 絶対パス指定でも同様に silent に無視
echo "Test 20b: @メンションの絶対パス指定を silent に無視"
box="$(make_sandbox)"
extern_dir="$(mktemp -d)"
printf 'このリポジトリは **ADDF 利用プロジェクト** です。\n' > "$extern_dir/leak.md"
printf '# CLAUDE.repo.md\n\n@%s/leak.md\n' "$extern_dir" > "$box/CLAUDE.repo.md"
output=$(run_lint "$box")
assert_not_contains "絶対パスで downstream 判定できない" "[1] SKIP: repo_kind=downstream" "$output"
rm -rf "$box" "$extern_dir"

# シンボリックリンクで box 外を指すファイルへの @メンションも無視される
echo "Test 20c: @メンションのシンボリックリンク脱出を silent に無視"
box="$(make_sandbox)"
extern_dir="$(mktemp -d)"
printf 'このリポジトリは **ADDF 利用プロジェクト** です。\n' > "$extern_dir/leak.md"
ln -sf "$extern_dir/leak.md" "$box/link.md"
printf '# CLAUDE.repo.md\n\n@link.md\n' > "$box/CLAUDE.repo.md"
output=$(run_lint "$box")
assert_not_contains "シンボリックリンク脱出で downstream 判定できない" "[1] SKIP: repo_kind=downstream" "$output"
rm -rf "$box" "$extern_dir"

# テスト 21: 新設スキルが README に未掲載 → ペア8 WARNING（upstream 宣言下）
echo "Test 21: 新設スキルの README 掲載漏れ検出"
box="$(make_sandbox)"
printf '# CLAUDE.repo.md\n\nこのリポジトリは **ADDF 開発プロジェクト**（フレームワーク本体）です。\n' \
  > "$box/CLAUDE.repo.md"
printf -- '---\nname: addf-dummy-skill\n---\n\n# ダミースキル\n' > "$box/.claude/commands/addf-dummy-skill.md"
output=$(run_lint "$box")
assert_exit "未掲載スキルで WARNING" 2 $?
assert_contains "ペア8の WARNING" "[8] WARNING" "$output"
assert_contains "未掲載スキル名の特定" "MISSING: addf-dummy-skill" "$output"
rm -rf "$box"

# テスト 22: README から既存スキルの掲載を削除 → ペア8 WARNING（両 README とも検査対象）
echo "Test 22: README からの既存スキル掲載削除を検出"
box="$(make_sandbox)"
printf '# CLAUDE.repo.md\n\nこのリポジトリは **ADDF 開発プロジェクト**（フレームワーク本体）です。\n' \
  > "$box/CLAUDE.repo.md"
sed -i.bak '/\*\*addf-plan-audit\*\*/d' "$box/README.md" && rm -f "$box/README.md.bak"
output=$(run_lint "$box")
assert_exit "掲載削除で WARNING" 2 $?
assert_contains "ペア8の WARNING（README.md）" "[8] WARNING: README.md" "$output"
assert_contains "削除したスキル名の特定" "MISSING: addf-plan-audit" "$output"
rm -rf "$box"

# テスト 23: downstream 判定では ペア8 が SKIP される（独自 README のため対象外）
echo "Test 23: downstream 判定でペア8が SKIP される"
box="$(make_sandbox)"
printf '# CLAUDE.repo.md\n\nこのリポジトリは **ADDF 利用プロジェクト** です。\n' > "$box/CLAUDE.repo.md"
printf -- '---\nname: addf-dummy-skill\n---\n\n# ダミースキル\n' > "$box/.claude/commands/addf-dummy-skill.md"
output=$(run_lint "$box")
assert_contains "ペア8の SKIP（downstream）" "[8] SKIP" "$output"
assert_not_contains "downstream では未掲載スキルを検出しない" "[8] WARNING" "$output"
rm -rf "$box"

# テスト 24: markdown リンク書式の TODO 行が pair6 で誤検出されない（Issue #31 現象1 回帰）
# バックティック書式 `path` に加え、markdown リンク書式 [title](path) も受理する
# （下流の TODO.md は clickable リンク化のため markdown 書式を採用するケースが多い）
echo "Test 24: markdown リンク書式の TODO 行を pair6 が受理"
box="$(make_sandbox)"
mkdir -p "$box/.claude/addf/plans-add"
cat > "$box/.claude/addf/plans-add/0001-sample.md" <<'EOF'
# Plan: サンプル

## 実装状況: 完了（2026-07-16）

本文
EOF
# バックティックではなく markdown リンク書式で参照
cat > "$box/.claude/addf/plans-add/TODO.addf.md" <<'EOF'
# TODO (ADDF)

| 優先度 | Phase | 計画ファイル | 状態 |
|---|---|---|---|
| 1 | 1 | [Sample Plan](.claude/addf/plans-add/0001-sample.md) | 完了 |
EOF
output=$(run_lint "$box")
assert_exit "markdown リンク書式で pair6 が OK" 0 $?
assert_not_contains "登録漏れ WARNING が出ない" "登録漏れ: .claude/addf/plans-add/0001-sample.md" "$output"
assert_not_contains "pair6 に WARNING が出ない" "[6] WARNING" "$output"
rm -rf "$box"

# テスト 24b: markdown リンク書式でも状態の突合が動く（矛盾は検出される）
echo "Test 24b: markdown リンク書式でも状態矛盾は検出される"
box="$(make_sandbox)"
mkdir -p "$box/.claude/addf/plans-add"
cat > "$box/.claude/addf/plans-add/0001-sample.md" <<'EOF'
# Plan: サンプル

## 実装状況: 完了（2026-07-16）

本文
EOF
cat > "$box/.claude/addf/plans-add/TODO.addf.md" <<'EOF'
# TODO (ADDF)

| 優先度 | Phase | 計画ファイル | 状態 |
|---|---|---|---|
| 1 | 1 | [Sample Plan](.claude/addf/plans-add/0001-sample.md) | 未着手 |
EOF
output=$(run_lint "$box")
assert_exit "リンク書式でも矛盾で WARNING" 2 $?
assert_contains "矛盾の特定（リンク書式経由）" "矛盾: .claude/addf/plans-add/0001-sample.md" "$output"
rm -rf "$box"

# テスト 24c: 混在（バックティック + markdown リンク書式）も同一 TODO 内で動く
echo "Test 24c: 混在書式（バックティック + markdown リンク）で両方認識"
box="$(make_sandbox)"
mkdir -p "$box/.claude/addf/plans-add"
cat > "$box/.claude/addf/plans-add/0001-sample.md" <<'EOF'
# Plan: サンプルA

## 実装状況: 完了
EOF
cat > "$box/.claude/addf/plans-add/0002-sample.md" <<'EOF'
# Plan: サンプルB

## 実装状況: 完了
EOF
cat > "$box/.claude/addf/plans-add/TODO.addf.md" <<'EOF'
# TODO (ADDF)

| 優先度 | Phase | 計画ファイル | 状態 |
|---|---|---|---|
| 1 | 1 | `.claude/addf/plans-add/0001-sample.md` | 完了 |
| 2 | 2 | [Sample B](.claude/addf/plans-add/0002-sample.md) | 完了 |
EOF
output=$(run_lint "$box")
assert_exit "混在書式で pair6 が OK" 0 $?
assert_not_contains "0001 が登録漏れ扱いにならない" "登録漏れ: .claude/addf/plans-add/0001-sample.md" "$output"
assert_not_contains "0002 が登録漏れ扱いにならない" "登録漏れ: .claude/addf/plans-add/0002-sample.md" "$output"
rm -rf "$box"

# テスト 24d: リンクタイトルにバックティックでパスを併記した行は href 側を採用する
# （code-review M-2 回帰: re.search の左優先でタイトル側の古いパスを拾っていた）
echo "Test 24d: [\`旧path\`](新path) 形式でリンク href 側が採用される"
box="$(make_sandbox)"
cat > "$box/.claude/addf/plans-add/0001-new.md" <<'EOF'
# Plan 0001: リネーム後の計画

## 実装状況: 未着手
EOF
cat > "$box/.claude/addf/plans-add/TODO.addf.md" <<'EOF'
# TODO (ADDF)

| 優先度 | Phase | 計画ファイル | 状態 |
|---|---|---|---|
| 1 | 1 | [`.claude/addf/plans-add/0001-old.md`](.claude/addf/plans-add/0001-new.md) | 未着手 |
EOF
output=$(run_lint "$box")
assert_not_contains "タイトル側の旧パスを不在扱いしない" "0001-old.md" "$output"
rm -rf "$box"

# ヘルパー: PROJECT_DIR に相当する downstream シミュレーション ディレクトリを作る
# （.addf.md 一切なし・lock.json あり・CLAUDE.repo.md で downstream 宣言・Plan 0件）
# Feedback.md の教訓「このアサーションは Plan が0件の空のダウンストリームリポジトリでも
# 成立するか？」の検証土台
make_fake_downstream_project() {
  local proj
  proj="$(mktemp -d)"
  mkdir -p "$proj/.claude/addf/templates" "$proj/.claude/addf/plans" \
           "$proj/.claude/addf/guides" "$proj/.claude/commands" \
           "$proj/.claude/addf"
  # downstream シグナル: 種別宣言 ＋ lock.json（両方を意図的に持たせる）
  cat > "$proj/CLAUDE.repo.md" <<'EOF'
# CLAUDE.repo.md

このリポジトリは **ADDF 利用プロジェクト** です。
EOF
  printf '{"version":"0.6.2","ref":"v0.6.2"}\n' > "$proj/.claude/addf/lock.json"
  # 配布される汎用ファイル（.addf.md サフィックス版は含めない — downstream の物理不在を再現）
  cp "$PROJECT_DIR/CLAUDE.md" "$proj/"
  cp "$PROJECT_DIR/AGENTS.md" "$proj/"
  cp "$PROJECT_DIR/.gitignore" "$proj/"
  cp "$PROJECT_DIR/README.md" "$proj/"
  cp "$PROJECT_DIR/.claude/addf/templates/ProgressTemplate.md" "$proj/.claude/addf/templates/"
  # Progress.md はダウンストリーム版テンプレート由来の内容にする
  sed -e 's/ProgressTemplate\.addf\.md/ProgressTemplate.md/g' \
      -e '/ADD フレームワークテスト/d' \
      "$PROJECT_DIR/.claude/addf/Progress.md" > "$proj/.claude/addf/Progress.md"
  cp "$PROJECT_DIR"/.claude/commands/addf-*.md "$proj/.claude/commands/"
  cp "$PROJECT_DIR/.claude/addf/guides/development-process.md" "$proj/.claude/addf/guides/"
  echo "$proj"
}

# テスト 25: 0件Plan の空ダウンストリームリポジトリで lint が誤検出しない（Issue #30/#31 の主眼）
# Feedback.md 教訓「Plan が0件の空 DS リポジトリでも成立するか？」を機械検証する
echo "Test 25: 0件Plan の空 downstream プロジェクトで lint が誤検出しない"
fake_proj="$(make_fake_downstream_project)"
output=$(run_lint "$fake_proj")
assert_exit "空 downstream で lint が OK" 0 $?
assert_contains "downstream 判定" "OK: 同期チェック通過" "$output"
# downstream で SKIP されるのは pair2/3/8（upstream 専用ファイル依存）と pair6/7（存在依存）。
# pair1/4/5 は downstream 側のファイルも検査対象のため実行される（ここでは OK になること）
assert_contains "ペア2が SKIP" "[2] SKIP" "$output"
assert_contains "ペア3が SKIP" "[3] SKIP" "$output"
assert_contains "ペア8が SKIP" "[8] SKIP" "$output"
assert_not_contains "ペア1に ERROR が出ない" "[1] ERROR" "$output"
assert_not_contains "ペア1に WARNING が出ない" "[1] WARNING" "$output"
assert_not_contains "ペア4に WARNING が出ない" "[4] WARNING" "$output"
assert_not_contains "ペア5に WARNING が出ない" "[5] WARNING" "$output"
# Plan 0件の空 downstream で pair6 は SKIP（TODO 不在）— 誤 WARNING が出ないことを確認
assert_not_contains "空Plan で pair6 が WARNING しない" "[6] WARNING" "$output"
rm -rf "$fake_proj"

# テスト 26: PROJECT_DIR が .addf.md を持たない構成でも make_sandbox が cp エラーで死なない
# （Issue #30 の中核回帰: 以前は無条件 cp で FAIL していた）
echo "Test 26: downstream 構成 PROJECT_DIR でも make_sandbox が cp エラーで死なない"
fake_proj="$(make_fake_downstream_project)"
saved_project_dir="$PROJECT_DIR"
PROJECT_DIR="$fake_proj"
sandbox_out="$(make_sandbox 2>&1)"
sandbox_rc=$?
PROJECT_DIR="$saved_project_dir"
if [ "$sandbox_rc" -eq 0 ] && [ -d "$sandbox_out" ]; then
  echo "  PASS: make_sandbox が downstream PROJECT_DIR で成功"
  PASS=$((PASS + 1))
  # 疑似コピー方針の確認: .addf.md が .md 版内容で埋められている
  if [ -f "$sandbox_out/.claude/addf/templates/ProgressTemplate.addf.md" ]; then
    if diff -q "$sandbox_out/.claude/addf/templates/ProgressTemplate.addf.md" \
              "$sandbox_out/.claude/addf/templates/ProgressTemplate.md" >/dev/null 2>&1; then
      echo "  PASS: .addf.md が .md 版で疑似コピーされている（upstream 環境シミュレート）"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: .addf.md と .md 版が一致していない（疑似コピーが機能していない）"
      FAIL=$((FAIL + 1))
    fi
    # 疑似コピー後もドリフト検出能力が落ちていないこと（code-review L-1 の実験手順を固定化）:
    # コピー直後は pair2 が恒真（完全一致）だが、片側だけ変更すれば WARNING が出る
    sed -i.bak 's/^15\. コミットする$/15. コミットしてタグを打つ/' \
      "$sandbox_out/.claude/addf/templates/ProgressTemplate.md" 2>/dev/null
    rm -f "$sandbox_out/.claude/addf/templates/ProgressTemplate.md.bak"
    drift_out="$(run_lint "$sandbox_out")"
    if echo "$drift_out" | grep -q '\[2\] WARNING'; then
      echo "  PASS: 疑似コピー後の post-copy ドリフトを pair2 が検出する"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: 疑似コピー後のドリフトが pair2 で検出されない（恒真化の懸念が顕在化）"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  FAIL: .addf.md が sandbox に用意されていない（テストの前提が崩れる）"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$sandbox_out"
else
  echo "  FAIL: make_sandbox が downstream PROJECT_DIR で失敗 (rc=$sandbox_rc): $sandbox_out"
  FAIL=$((FAIL + 1))
fi
rm -rf "$fake_proj"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
