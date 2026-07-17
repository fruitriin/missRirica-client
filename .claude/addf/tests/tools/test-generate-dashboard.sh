#!/bin/bash
# test-generate-dashboard.sh
# generate-dashboard.py（Plan 0058）がリポジトリ状態からローカルダッシュボード
# を生成できることを検証する。
#
# 検証の主体は mktemp サンドボックスに作る合成リポジトリ（drift-injection 方式）。
# 実リポジトリの固有コンテンツに依存したアサーションを置かない — 依存すると
# ダウンストリームで必ず FAIL する（Issue #29 / Plan 0055 と同型の再発を
# contribution-agent がサンドボックス実測で検出した教訓）。
# python3（または uv）が無い環境では SKIP。vitepress の実ビルド検証は node と
# node_modules が揃っている場合のみ実施する（欠如 = SKIP 設計）。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
GEN_SCRIPT="$REPO_ROOT/.claude/addf/addfTools/generate-dashboard.py"
PASS=0
FAIL=0
SKIP=0

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

echo "=== test-generate-dashboard.sh ==="

if [ ! -f "$GEN_SCRIPT" ]; then
  echo "SKIP: generate-dashboard.py が見つかりません"
  echo ""
  echo "Results: 0 passed, 0 failed, 1 skipped"
  exit 0
fi

if command -v python3 >/dev/null 2>&1; then
  RUN_PY="python3"
elif command -v uv >/dev/null 2>&1; then
  RUN_PY="uv run"
else
  echo "SKIP: python3 も uv も見つかりません"
  echo ""
  echo "Results: 0 passed, 0 failed, 1 skipped"
  exit 0
fi

# ---- サンドボックス（ダウンストリーム構成: plans/ + TODO.md・git/gh/Questions 無し）----
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/.claude/addf/plans"

# 合成 Plan 1: FB 待ち + Vue コンパイルを壊す敵対的入力
#  - 裸の <concept>（英字開始タグ様テキスト — 実際に vitepress build を落とした再現ケース）
#  - タイトルにも <foo>（本文コピー以外のページへの挿入経路の検証）
#  - 奇数個のバッククォートを含む行（閉じ無しバッククォートでエスケープが
#    免除される退行の検証 — code-review C1）
cat > "$SANDBOX/.claude/addf/plans/0001-sample.md" <<'EOF'
# Plan 0001: サンプル計画 <foo> のタイトル

## 実装状況: 未着手

owner_feedback: 待ち
feedback_ask: テスト用の判断ですよ
feedback_since: 2026-01-01

昇格の定義は speculative/<concept> → main とする。
出力例`のようになる。閉じ無しバッククォートの後の speculative/<concept> も対象。

<details>
<summary>折りたたみの詳細（フェーズC — パススルー検証）</summary>

折りたたみ本文。ここの speculative/<concept> はエスケープされる。

</details>
EOF

# 合成 Plan 2: FB 済（キューに出ないことの検証）
cat > "$SANDBOX/.claude/addf/plans/0002-done-fb.md" <<'EOF'
# Plan 0002: フィードバック済みの計画

## 実装状況: 一部完了（テスト用）

owner_feedback: 済
EOF

cat > "$SANDBOX/TODO.md" <<'EOF'
| 優先度 | Phase | 計画ファイル | 状態 |
|---|---|---|---|
| 1 | 1 | `.claude/addf/plans/0001-sample.md` | 未着手（テスト用） |
| 2 | 2 | `.claude/addf/plans/0002-done-fb.md` | 一部完了（テスト用） |
EOF

# 合成アンカーコメント（フェーズC: 未解決1 + 解決済み1 — 未解決のみ表示される）
cat > "$SANDBOX/.claude/addf/DashboardComments.json" <<'EOF'
{
  "comments": [
    {
      "id": "dc_test1",
      "page": "/plans/0001-sample",
      "source_path": ".claude/addf/plans/0001-sample.md",
      "anchor": "合成アンカー原文",
      "body": "合成未解決コメントですよ",
      "author": "owner",
      "created_at": "2026-01-02T00:00:00Z",
      "status": "unresolved",
      "resolution": null,
      "replies": []
    },
    {
      "id": "dc_test2",
      "page": "/",
      "source_path": null,
      "anchor": "",
      "body": "解決済みコメント（表示されない）",
      "author": "owner",
      "created_at": "2026-01-02T00:00:00Z",
      "status": "resolved",
      "resolution": "対応済み",
      "replies": []
    },
    {
      "id": "dc_test3",
      "page": "/",
      "source_path": null,
      "anchor": "",
      "body": "下書きコメント（未送信 — 集約に出ない）",
      "author": "owner",
      "created_at": "2026-01-02T00:00:00Z",
      "status": "draft",
      "resolution": null,
      "replies": []
    }
  ]
}
EOF

# 合成 crit レビュー（フェーズC: ~/.crit/reviews/ を環境変数で差し替え）
CRIT_DIR="$SANDBOX/crit-reviews"
mkdir -p "$CRIT_DIR/sess01"
cat > "$CRIT_DIR/sess01/review.json" <<'EOF'
{
  "files": {
    "docs/sample.md": {
      "comments": [
        {
          "id": "c_test01",
          "start_line": 1,
          "end_line": 1,
          "body": "crit 側の未解決コメントですよ",
          "anchor": "対象行の原文",
          "author": "owner",
          "created_at": "2026-01-03T00:00:00Z"
        }
      ]
    }
  }
}
EOF

OUT="$SANDBOX/.claude/addf/dashboard"

echo "Test 1: サンドボックス（DS 構成・git/gh/Questions/Progress 無し）で正常終了する"
(cd "$SANDBOX" && ADDF_DASHBOARD_ROOT="$SANDBOX" ADDF_CRIT_REVIEWS_DIR="$CRIT_DIR" $RUN_PY "$GEN_SCRIPT" >/dev/null 2>&1)
check "生成スクリプトが exit 0（欠如フェイルセーフ）" 0 $?

echo "Test 2: 2ページ + VitePress 設定が生成される"
missing=0
for f in index.md active.md .vitepress/config.mts .vitepress/theme/custom.css .vitepress/theme/Layout.vue .vitepress/theme/index.mts; do
  if [ ! -f "$OUT/$f" ]; then
    echo "  MISSING: $f"
    missing=$((missing + 1))
  fi
done
check "必須生成物が揃っている（欠落 $missing 件）" 0 "$([ "$missing" -eq 0 ]; echo $?)"

echo "Test 3: プランビューアに合成 Plan がコピーされる"
check "plans/0001-sample.md が存在する" 0 "$([ -f "$OUT/plans/0001-sample.md" ]; echo $?)"

echo "Test 4: owner_feedback フィールドがキューに反映される（独立オラクル: 待ちは1件）"
if grep -q "オーナー判断待ちの Plan — 1件" "$OUT/index.md" \
  && grep -q "テスト用の判断ですよ" "$OUT/index.md"; then
  echo "  PASS: 待ち1件・feedback_ask がキュー行に表示される"
  PASS=$((PASS + 1))
else
  echo "  FAIL: キューの件数または feedback_ask の表示が期待と異なる"
  FAIL=$((FAIL + 1))
fi
queue_sec=$(sed -n '/^## オーナー判断待ちの Plan/,/^## /p' "$OUT/index.md")
if echo "$queue_sec" | grep -q "0002"; then
  echo "  FAIL: owner_feedback: 済 の Plan がキューに出ている"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: owner_feedback: 済 の Plan はキューに出ない"
  PASS=$((PASS + 1))
fi
# 統合ページ: FB 済の Plan は「着手可能」グループに出る
if grep -q "着手可能" "$OUT/index.md" && sed -n '/^### ✅ 着手可能/,/^### /p' "$OUT/index.md" | grep -q "0002"; then
  echo "  PASS: FB 済の Plan は着手可能グループに出る（統合ページ）"
  PASS=$((PASS + 1))
else
  echo "  FAIL: FB 済の Plan が着手可能グループに出ていない"
  FAIL=$((FAIL + 1))
fi
if [ -f "$OUT/backlog.md" ]; then
  echo "  FAIL: 統合後も backlog.md が生成されている（旧生成物が掃除されていない）"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: backlog.md は生成されない（統合済み・旧生成物は掃除）"
  PASS=$((PASS + 1))
fi

echo "Test 5: Vue コンパイルを壊す入力がエスケープされている"
bad=0
# 5a: 本文コピー — 裸の <concept> が残らず、エスケープ済み証拠がある
if grep -q 'speculative/<concept>' "$OUT/plans/0001-sample.md"; then
  echo "  FAIL: 本文コピーに裸の <concept> が残存"
  bad=$((bad + 1))
fi
if ! grep -q 'speculative/&lt;concept' "$OUT/plans/0001-sample.md"; then
  echo "  FAIL: 本文コピーにエスケープ済み証拠（&lt;concept）が無い"
  bad=$((bad + 1))
fi
# 5b: 奇数バッククォート行の後もエスケープされる（C1 リグレッション）
if ! grep -q '閉じ無しバッククォートの後の speculative/&lt;concept' "$OUT/plans/0001-sample.md"; then
  echo "  FAIL: 奇数バッククォート行の後半がエスケープされていない（C1 再発）"
  bad=$((bad + 1))
fi
# 5c: タイトル経由の挿入（index/backlog）もエスケープされる（C2 リグレッション）
if grep -q '<foo>' "$OUT/index.md" 2>/dev/null; then
  echo "  FAIL: タイトル由来の <foo> が未エスケープでページに挿入されている（C2 再発）"
  bad=$((bad + 1))
fi
if ! grep -q '&lt;foo&gt;\|&lt;foo>' "$OUT/index.md"; then
  echo "  FAIL: index.md にタイトルのエスケープ済み証拠（&lt;foo）が無い"
  bad=$((bad + 1))
fi
check "敵対的入力のエスケープ（不備 $bad 件）" 0 "$([ "$bad" -eq 0 ]; echo $?)"

echo "Test 6: アンカーコメント・crit コメントの集約（フェーズC）"
bad=0
if ! grep -q "合成未解決コメントですよ" "$OUT/index.md"; then
  echo "  FAIL: DashboardComments.json の未解決コメントが index.md に出ていない"
  bad=$((bad + 1))
fi
if grep -q "解決済みコメント（表示されない）" "$OUT/index.md"; then
  echo "  FAIL: resolved のコメントが index.md に表示されている"
  bad=$((bad + 1))
fi
if ! grep -q "crit 側の未解決コメントですよ" "$OUT/index.md"; then
  echo "  FAIL: crit レビューの未解決コメントが index.md に出ていない"
  bad=$((bad + 1))
fi
# 独立オラクル: 未解決は dashboard 1 + crit 1 = 2件（draft は数えない）
if ! grep -q ">2<small>件</small>" "$OUT/index.md"; then
  echo "  FAIL: 未解決コメント統計が 2件になっていない"
  bad=$((bad + 1))
fi
if grep -q "下書きコメント（未送信 — 集約に出ない）" "$OUT/index.md"; then
  echo "  FAIL: draft のコメント本文が index.md に表示されている"
  bad=$((bad + 1))
fi
if ! grep -q "送信待ちのコメントが 1件" "$OUT/index.md"; then
  echo "  FAIL: draft 件数の注記が index.md に無い"
  bad=$((bad + 1))
fi
check "コメント集約（不備 $bad 件）" 0 "$([ "$bad" -eq 0 ]; echo $?)"

echo "Test 7: コメント API とアンカー UI が生成物に配線されている（フェーズC）"
bad=0
grep -q "commentsApi" "$OUT/.vitepress/config.mts" || { echo "  FAIL: config.mts に commentsApi が無い"; bad=$((bad + 1)); }
grep -q "code_inline" "$OUT/.vitepress/config.mts" || { echo "  FAIL: config.mts に code_inline v-pre レンダラが無い"; bad=$((bad + 1)); }
grep -q "/api/comments" "$OUT/.vitepress/theme/Layout.vue" || { echo "  FAIL: Layout.vue が /api/comments を参照していない"; bad=$((bad + 1)); }
grep -q "Layout.vue" "$OUT/.vitepress/theme/index.mts" || { echo "  FAIL: index.mts が Layout.vue を登録していない"; bad=$((bad + 1)); }
grep -q "$(basename "$SANDBOX") ダッシュボード" "$OUT/.vitepress/config.mts" || { echo "  FAIL: サイトタイトルがリポジトリ名になっていない"; bad=$((bad + 1)); }
check "配線（不備 $bad 件）" 0 "$([ "$bad" -eq 0 ]; echo $?)"

echo "Test 8: 折りたたみ構文 <details>/<summary> のパススルー（フェーズC）"
bad=0
grep -q '^<details>$' "$OUT/plans/0001-sample.md" || { echo "  FAIL: <details> がエスケープされてしまった"; bad=$((bad + 1)); }
grep -q '<summary>折りたたみの詳細' "$OUT/plans/0001-sample.md" || { echo "  FAIL: <summary> がエスケープされてしまった"; bad=$((bad + 1)); }
grep -q 'ここの speculative/&lt;concept' "$OUT/plans/0001-sample.md" || { echo "  FAIL: details 内の <concept> がエスケープされていない"; bad=$((bad + 1)); }
check "パススルー（不備 $bad 件）" 0 "$([ "$bad" -eq 0 ]; echo $?)"

echo "Test 9: <details> 閉じ忘れは全エスケープにフォールバックする（ビューア巻き込み防止）"
cat > "$SANDBOX/.claude/addf/plans/0003-unclosed.md" <<'EOF'
# Plan 0003: 閉じ忘れの計画

## 実装状況: 未着手

<details>
<summary>閉じタグを書き忘れた折りたたみ</summary>

speculative/<concept> を含む本文。閉じタグを書き忘れたまま Plan が終わる。
EOF
# ↑ <details> 開き1・閉じ0 の不均衡（本文に閉じタグの文字列を書くとカウンタが
#   均衡してしまいテストにならない点に注意）
(cd "$SANDBOX" && ADDF_DASHBOARD_ROOT="$SANDBOX" ADDF_CRIT_REVIEWS_DIR="$CRIT_DIR" $RUN_PY "$GEN_SCRIPT" > "$SANDBOX/gen.log" 2>&1)
check "閉じ忘れがあっても生成は exit 0" 0 $?
bad=0
if grep -q '^<details>$' "$OUT/plans/0003-unclosed.md"; then
  echo "  FAIL: 閉じ忘れ Plan で <details> がパススルーされている（ビルドを壊す）"
  bad=$((bad + 1))
fi
if ! grep -q '&lt;details' "$OUT/plans/0003-unclosed.md"; then
  echo "  FAIL: 閉じ忘れ Plan の <details> がエスケープされていない"
  bad=$((bad + 1))
fi
if ! grep -q 'WARN' "$SANDBOX/gen.log"; then
  echo "  FAIL: 閉じ忘れの WARN が出力されていない"
  bad=$((bad + 1))
fi
if ! grep -q '^<details>$' "$OUT/plans/0001-sample.md"; then
  echo "  FAIL: バランスの取れた Plan 0001 のパススルーまで無効化されている"
  bad=$((bad + 1))
fi
check "閉じ忘れフォールバック（不備 $bad 件）" 0 "$([ "$bad" -eq 0 ]; echo $?)"
rm -f "$SANDBOX/.claude/addf/plans/0003-unclosed.md"

echo "Test 10: crit review.json の形状ドリフトでも生成全体は落ちない（フェイルセーフ）"
mkdir -p "$CRIT_DIR/sess02"
cat > "$CRIT_DIR/sess02/review.json" <<'EOF'
{
  "files": {
    "docs/drift1.md": "not-an-object",
    "docs/drift2.md": { "comments": "not-a-list" },
    "docs/drift3.md": { "comments": [ "not-a-dict", 42 ] }
  }
}
EOF
(cd "$SANDBOX" && ADDF_DASHBOARD_ROOT="$SANDBOX" ADDF_CRIT_REVIEWS_DIR="$CRIT_DIR" $RUN_PY "$GEN_SCRIPT" >/dev/null 2>&1)
check "形状ドリフトの review.json があっても exit 0" 0 $?
if grep -q "crit 側の未解決コメントですよ" "$OUT/index.md"; then
  echo "  PASS: 正常な sess01 のコメントは引き続き集約される"
  PASS=$((PASS + 1))
else
  echo "  FAIL: 形状ドリフトの巻き添えで正常コメントが消えた"
  FAIL=$((FAIL + 1))
fi
# 差分書き込み移行後の掃除検証: Test 9 で消した Plan 0003 のコピーが残骸として残らない
if [ -f "$OUT/plans/0003-unclosed.md" ]; then
  echo "  FAIL: 削除済み Plan のコピーが掃除されていない（rmtree 廃止の残骸）"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: 削除済み Plan のコピーは再生成で掃除される"
  PASS=$((PASS + 1))
fi
rm -rf "$CRIT_DIR/sess02"

echo "Test 11: 壊れた DashboardComments.json でも生成は失敗しない（フェイルセーフ）"
echo '{broken json' > "$SANDBOX/.claude/addf/DashboardComments.json"
(cd "$SANDBOX" && ADDF_DASHBOARD_ROOT="$SANDBOX" ADDF_CRIT_REVIEWS_DIR="$CRIT_DIR" $RUN_PY "$GEN_SCRIPT" >/dev/null 2>&1)
check "壊れた JSON で exit 0（WARN のみ）" 0 $?

echo "Test 12: コメント API スモーク（node + vitepress + curl がある場合のみ）"
if command -v node >/dev/null 2>&1 && [ -d "$REPO_ROOT/node_modules/vitepress" ] && command -v curl >/dev/null 2>&1; then
  # サンドボックス側の dashboard を対象に dev サーバーを起動する（config.mts の
  # COMMENTS_PATH はサンドボックス内を指すため、実リポジトリのコメントを汚さない）
  echo '{"comments": []}' > "$SANDBOX/.claude/addf/DashboardComments.json"
  # サンドボックスは /tmp 配下で node_modules の上方探索が届かないため symlink で解決する
  ln -sfn "$REPO_ROOT/node_modules" "$SANDBOX/node_modules"
  SMOKE_PORT=5199
  # config.mts の port 指定は --port より優先されるため環境変数で上書きする
  ADDF_DASHBOARD_PORT="$SMOKE_PORT" "$REPO_ROOT/node_modules/.bin/vitepress" dev "$OUT" >/dev/null 2>&1 &
  VP_PID=$!
  api_up=0
  for _ in $(seq 1 30); do
    if curl -s -o /dev/null "http://localhost:$SMOKE_PORT/api/comments"; then
      api_up=1
      break
    fi
    sleep 0.5
  done
  if [ "$api_up" -eq 1 ]; then
    bad=0
    resp=$(curl -s -X POST "http://localhost:$SMOKE_PORT/api/comments" \
      -H 'content-type: application/json' \
      -d '{"page":"/plans/0001-sample","anchor":"合成アンカー原文","anchor_occurrence":0,"body":"スモーク投稿ですよ"}')
    echo "$resp" | grep -q '"status":"draft"' || { echo "  FAIL: POST 応答が draft でない: $resp"; bad=$((bad + 1)); }
    grep -q "スモーク投稿ですよ" "$SANDBOX/.claude/addf/DashboardComments.json" || { echo "  FAIL: POST がファイルに書き出されていない"; bad=$((bad + 1)); }
    submit=$(curl -s -X PATCH "http://localhost:$SMOKE_PORT/api/comments" \
      -H 'content-type: application/json' \
      -d '{"action":"submit_all"}')
    echo "$submit" | grep -q '"submitted":1' || { echo "  FAIL: submit_all が 1件を確定していない: $submit"; bad=$((bad + 1)); }
    grep -q '"status": "unresolved"' "$SANDBOX/.claude/addf/DashboardComments.json" || { echo "  FAIL: submit_all 後に unresolved がファイルに無い"; bad=$((bad + 1)); }
    cid=$(echo "$resp" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
    patch=$(curl -s -X PATCH "http://localhost:$SMOKE_PORT/api/comments" \
      -H 'content-type: application/json' \
      -d "{\"id\":\"$cid\",\"status\":\"resolved\"}")
    echo "$patch" | grep -q '"status":"resolved"' || { echo "  FAIL: PATCH resolve が反映されない: $patch"; bad=$((bad + 1)); }
    check "API スモーク GET/POST/PATCH（不備 $bad 件）" 0 "$([ "$bad" -eq 0 ]; echo $?)"
  else
    echo "  FAIL: dev サーバーが起動しなかった (port ${SMOKE_PORT})"
    FAIL=$((FAIL + 1))
  fi
  kill "$VP_PID" 2>/dev/null
  wait "$VP_PID" 2>/dev/null
else
  echo "  SKIP: node / node_modules/vitepress / curl が無いためスモークは省略"
  SKIP=$((SKIP + 1))
fi

echo "Test 13: 実リポジトリでも生成が正常終了する"
(cd "$REPO_ROOT" && $RUN_PY "$GEN_SCRIPT" >/dev/null 2>&1)
check "実リポジトリで exit 0" 0 $?

echo "Test 14: vitepress 実ビルド（node + node_modules がある場合のみ）"
if command -v node >/dev/null 2>&1 && [ -d "$REPO_ROOT/node_modules/vitepress" ]; then
  (cd "$REPO_ROOT" && ./node_modules/.bin/vitepress build .claude/addf/dashboard >/dev/null 2>&1)
  check "vitepress build が通る" 0 $?
else
  echo "  SKIP: node または node_modules/vitepress が無いため実ビルドは省略"
  SKIP=$((SKIP + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
