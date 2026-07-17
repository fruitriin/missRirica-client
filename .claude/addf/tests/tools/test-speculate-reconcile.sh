#!/bin/bash
# test-speculate-reconcile.sh
# speculate-reconcile.py の走査（check）と確定済み削除（clean）を mktemp サンドボックスで検証する。
# bare origin 付きの fake git リポジトリで「一覧と merged_hint」「過去日付 integration の区別と削除」
# 「--delete 指定分のみ削除・判断待ち保護」「remote 無し環境の SKIP」に加え、ペルソナ並列レビューで
# 実測再現した穴（origin 単独削除・未来日付注入・日付またぎ削除・記録なし削除・dirty 破棄）を
# ドリフト注入 TDD で固定する（Plan 0028 フェーズ3）。Plan 0038 レビューで attacker が実測した
# 表パーサの穴（列順詐称・** 強調・無関係テーブル）も Test 19〜20 で固定する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECONCILE="$(cd "$SCRIPT_DIR/../.." && pwd)/addfTools/speculate-reconcile.py"
PASS=0
FAIL=0

check() {
  local desc="$1" expected_exit="$2" actual_exit="$3" output="$4" expected_grep="${5:-}"
  if [ "$actual_exit" -ne "$expected_exit" ]; then
    echo "  FAIL: $desc (exit: expected=$expected_exit actual=$actual_exit)"
    echo "$output" | sed 's/^/    | /'
    FAIL=$((FAIL + 1))
    return
  fi
  if [ -n "$expected_grep" ] && ! grep -q "$expected_grep" <<<"$output"; then
    echo "  FAIL: $desc (出力に '$expected_grep' が見つからない)"
    echo "$output" | sed 's/^/    | /'
    FAIL=$((FAIL + 1))
    return
  fi
  echo "  PASS: $desc"
  PASS=$((PASS + 1))
}

check_absent() {
  local desc="$1" output="$2" pattern="$3"
  if grep -q "$pattern" <<<"$output"; then
    echo "  FAIL: $desc (出力に '$pattern' が含まれている)"
    echo "$output" | sed 's/^/    | /'
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

assert() {
  local desc="$1"; shift
  if "$@"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

# --today は「過去日付の注入のみ許容」のため、実システム日付基準で動的に組む
TODAY="$(date +%F)"
YESTERDAY="$(python3 -c 'import datetime; print(datetime.date.today() - datetime.timedelta(days=1))')"
TWO_DAYS_AGO="$(python3 -c 'import datetime; print(datetime.date.today() - datetime.timedelta(days=2))')"
FUTURE="$(python3 -c 'import datetime; print(datetime.date.today() + datetime.timedelta(days=1))')"
PAST="2020-01-01"

# サンドボックス: bare origin + clone 相当の fake リポジトリ
# （macOS では /var → /private/var のため、git が報告する実体パスに解決しておく）
box="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$box"' EXIT
origin="$box/origin.git"
git init -q --bare -b main "$origin"
repo="$box/repo"
mkdir -p "$repo"
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
(
  cd "$repo"
  git init -q -b main .
  printf 'line1\n' > base.txt
  git -c user.name=t -c user.email=t@t add base.txt
  git -c user.name=t -c user.email=t@t commit -qm init
  git remote add origin "$origin"
  git push -q origin main
)

make_feature() {
  local name="$1" file="$2"
  g checkout -q -b "speculative/$name" main
  printf 'content-%s\n' "$name" > "$repo/$file"
  g add "$file"
  g commit -qm "$name"
  g checkout -q main
}

# Worktrees.md を行指定で書く（各引数 = 「ブランチ 状態」のペア）
write_worktrees_md() {
  mkdir -p "$repo/.claude/addf"
  {
    echo "# Worktrees（投機の進行状態）"
    echo ""
    echo "| worktree パス | ブランチ | 対象概念（出典） | 状態 | 最終更新 |"
    echo "|---|---|---|---|---|"
    local pair
    for pair in "$@"; do
      echo "| ../wt | ${pair%% *} | test | ${pair#* } | $TODAY |"
    done
  } > "$repo/.claude/addf/Worktrees.md"
}

# a: worktree あり・origin あり・未マージ / b: worktree なし・origin あり・未マージ
make_feature a a.txt
make_feature b b.txt
g push -q origin speculative/a speculative/b
g worktree add -q "$box/repo-spec-a" speculative/a
# done: main に ff マージ済み（cherry で merged_hint=yes になる）
make_feature done d.txt
g merge -q --ff-only speculative/done
# integration: 過去日付（worktree 付き）と当日
g branch integration/loop-$PAST main
g worktree add -q "$box/repo-int-old" integration/loop-$PAST
g branch integration/loop-$TODAY main

run_reconcile() {
  (cd "$repo" && python3 "$RECONCILE" "$@" 2>&1)
}

echo "=== test-speculate-reconcile.sh ==="

echo "Test 1: check — speculative ブランチ一覧と機械的事実（worktree 有無・origin・merged_hint）"
out="$(run_reconcile --today $TODAY)"; code=$?
check "走査完了で exit 0" 0 "$code" "$out" "local_speculative=speculative/a,speculative/b,speculative/done"
check "worktree ありの a" 0 "$code" "$out" "branch=speculative/a worktree=yes origin=yes merged_hint=no"
check "worktree なしの b" 0 "$code" "$out" "branch=speculative/b worktree=no origin=yes merged_hint=no"
check "マージ済み done は merged_hint=yes" 0 "$code" "$out" "branch=speculative/done worktree=no origin=no merged_hint=yes"
check "speculative worktree のパスが出る" 0 "$code" "$out" "speculative_worktree=speculative/a:$box/repo-spec-a"
check "origin/speculative の一覧が出る" 0 "$code" "$out" "remote_speculative=speculative/a,speculative/b"

echo "Test 2: check — --today 指定で過去日付 integration が「過去」と区別される"
check "過去日付は integration_past" 0 "$code" "$out" "integration_past=integration/loop-$PAST"
check "当日分は integration_today" 0 "$code" "$out" "integration_today=integration/loop-$TODAY"

echo "Test 3: check — rm -rf された stale worktree を prune して数え続けない"
g worktree add -q "$box/repo-spec-b" speculative/b
rm -rf "$box/repo-spec-b"
out="$(run_reconcile --today $TODAY)"; code=$?
check "prune 後は b の worktree なし" 0 "$code" "$out" "branch=speculative/b worktree=no"

echo "Test 4: check — detached HEAD の worktree が detached_worktree= で報告される"
g worktree add -q --detach "$box/repo-detached" main
out="$(run_reconcile --today $TODAY)"; code=$?
check "detached worktree が報告される" 0 "$code" "$out" "detached_worktree=$box/repo-detached"
g worktree remove "$box/repo-detached"

echo "Test 5: check — 前日の integration は猶予で「今日」側、2日前は「過去」側"
g branch integration/loop-$YESTERDAY main
g branch integration/loop-$TWO_DAYS_AGO main
out="$(run_reconcile --today $TODAY)"; code=$?
check "前日分は integration_today 側（猶予）" 0 "$code" "$out" "integration_today=.*integration/loop-$YESTERDAY"
check "2日前は integration_past 側" 0 "$code" "$out" "integration_past=.*integration/loop-$TWO_DAYS_AGO"

echo "Test 6: clean --keep-integrations — 過去 integration の自動削除をオプトアウトできる"
out="$(run_reconcile clean --today $TODAY --keep-integrations)"; code=$?
check "keep 指定で exit 0" 0 "$code" "$out" "kept=branch:integration/loop-$PAST (--keep-integrations で保護)"
assert "過去 integration が残っている" test -n "$(g branch --list integration/loop-$PAST)"

echo "Test 7: clean --delete — 指定ブランチの worktree/ローカル/origin が消え、判断待ちは残る"
write_worktrees_md "speculative/a 昇格済み"
out="$(run_reconcile clean --today $TODAY --delete speculative/a)"; code=$?
check "削除完了で exit 0" 0 "$code" "$out" "removed=branch:speculative/a"
check "worktree の除去が報告される" 0 "$code" "$out" "removed=worktree:$box/repo-spec-a"
check "origin 側の削除が報告される" 0 "$code" "$out" "removed=origin:speculative/a"
check "指定外の b は判断待ち保護" 0 "$code" "$out" "kept=branch:speculative/b (判断待ち保護)"
assert "worktree ディレクトリが消えている" test ! -d "$box/repo-spec-a"
assert "ローカルブランチが消えている" test -z "$(g branch --list speculative/a)"
assert "origin 側も消えている" test -z "$(git -C "$origin" branch --list speculative/a)"
assert "判断待ちの b はローカルに残る" test -n "$(g branch --list speculative/b)"
assert "判断待ちの b は origin にも残る" test -n "$(git -C "$origin" branch --list speculative/b)"

echo "Test 8: clean — 過去日付 integration（と worktree）は消え、猶予内は残る"
check "過去日付 integration の削除" 0 "$code" "$out" "removed=branch:integration/loop-$PAST"
check "2日前の integration も削除" 0 "$code" "$out" "removed=branch:integration/loop-$TWO_DAYS_AGO"
check "当日 integration は保護" 0 "$code" "$out" "kept=branch:integration/loop-$TODAY (猶予内の integration)"
check "前日 integration も猶予で保護" 0 "$code" "$out" "kept=branch:integration/loop-$YESTERDAY (猶予内の integration)"
assert "過去 integration の worktree が消えている" test ! -d "$box/repo-int-old"
assert "過去 integration ブランチが消えている" test -z "$(g branch --list integration/loop-$PAST)"
assert "当日 integration ブランチは残る" test -n "$(g branch --list integration/loop-$TODAY)"
assert "前日 integration ブランチは残る" test -n "$(g branch --list integration/loop-$YESTERDAY)"

echo "Test 9: clean --delete — Worktrees.md の記録と突合しないと削除できない"
write_worktrees_md "speculative/other 昇格済み"
out="$(run_reconcile clean --today $TODAY --delete speculative/b)"; code=$?
check "記録なしは ERROR（exit 1）" 1 "$code" "$out" "記録なし"
assert "b のブランチは消えていない" test -n "$(g branch --list speculative/b)"
assert "b は origin にも残っている" test -n "$(git -C "$origin" branch --list speculative/b)"
write_worktrees_md "speculative/b 開発中"
out="$(run_reconcile clean --today $TODAY --delete speculative/b)"; code=$?
check "「開発中」は削除不可の ERROR" 1 "$code" "$out" "状態「開発中」"
assert "開発中の b は消えていない" test -n "$(g branch --list speculative/b)"
rm "$repo/.claude/addf/Worktrees.md"
out="$(run_reconcile clean --today $TODAY --delete speculative/b)"; code=$?
check "Worktrees.md 自体が無ければ記録なし ERROR" 1 "$code" "$out" "記録を確認できない"

echo "Test 10: clean --delete — 「昇格済み」記載ありなら削除でき、重複指定でも誤警告が出ない"
write_worktrees_md "speculative/b 昇格済み"
out="$(run_reconcile clean --today $TODAY --delete speculative/b --delete speculative/b)"; code=$?
check "重複指定でも exit 0（誤警告なし）" 0 "$code" "$out" "removed=branch:speculative/b"
check "origin 側も削除される" 0 "$code" "$out" "removed=origin:speculative/b"
check_absent "「見つからない」の NOTE が出ない" "$out" "見つからない"
check_absent "WARNING が出ない" "$out" "WARNING:"
assert "b が消えている" test -z "$(g branch --list speculative/b)"

echo "Test 11: clean --delete --force-delete — 記録なしでも突合をスキップして削除できる"
rm -f "$repo/.claude/addf/Worktrees.md"
out="$(run_reconcile clean --today $TODAY --delete speculative/done --force-delete)"; code=$?
check "--force-delete で突合スキップ" 0 "$code" "$out" "removed=branch:speculative/done"
assert "done が消えている" test -z "$(g branch --list speculative/done)"

echo "Test 12: clean --delete — ローカル削除が失敗したら origin 側は保護される（lock 注入）"
make_feature c c.txt
g push -q origin speculative/c
g worktree add -q "$box/repo-spec-c" speculative/c
g worktree lock "$box/repo-spec-c"
write_worktrees_md "speculative/c 放棄"
out="$(run_reconcile clean --today $TODAY --delete speculative/c)"; code=$?
check "ローカル失敗は WARNING（exit 2）" 2 "$code" "$out" "WARNING:"
check "origin 側の保護が報告される" 2 "$code" "$out" "kept=origin:speculative/c（ローカル削除未完了のため保護）"
check_absent "origin 側の削除が実行されていない" "$out" "removed=origin:speculative/c"
assert "origin 側にブランチが残っている" test -n "$(git -C "$origin" branch --list speculative/c)"
g worktree unlock "$box/repo-spec-c"
out="$(run_reconcile clean --today $TODAY --delete speculative/c)"; code=$?
check "unlock 後は削除が完了する" 0 "$code" "$out" "removed=origin:speculative/c"

echo "Test 13: clean --delete — dirty worktree は既定で削除拒否、--force-delete で破棄"
make_feature d d2.txt
g worktree add -q "$box/repo-spec-d" speculative/d
printf 'uncommitted\n' > "$box/repo-spec-d/dirty.txt"
write_worktrees_md "speculative/d 放棄"
out="$(run_reconcile clean --today $TODAY --delete speculative/d)"; code=$?
check "dirty は既定で拒否（exit 2）" 2 "$code" "$out" "kept=worktree:$box/repo-spec-d (未コミット変更があるため保護"
assert "worktree が残っている" test -d "$box/repo-spec-d"
assert "ブランチも残っている" test -n "$(g branch --list speculative/d)"
out="$(run_reconcile clean --today $TODAY --delete speculative/d --force-delete)"; code=$?
check "--force-delete は WARNING を出して破棄（exit 2）" 2 "$code" "$out" "WARNING: .*未コミット変更を破棄した"
check "worktree の除去が報告される" 2 "$code" "$out" "removed=worktree:$box/repo-spec-d"
check "ブランチも削除される" 2 "$code" "$out" "removed=branch:speculative/d"
assert "worktree が消えている" test ! -d "$box/repo-spec-d"
assert "ブランチが消えている" test -z "$(g branch --list speculative/d)"

echo "Test 14: clean — 未マージ実体のある無指定ブランチは何度 clean しても消えない"
make_feature e e.txt
out="$(run_reconcile clean --today $TODAY)"; code=$?
check "無指定 clean は exit 0" 0 "$code" "$out" "kept=branch:speculative/e (判断待ち保護)"
assert "e のブランチは残っている" test -n "$(g branch --list speculative/e)"

echo "Test 15: clean --prune-worktrees — worktree だけ外れ、ブランチは残る"
g worktree add -q "$box/repo-spec-e" speculative/e
out="$(run_reconcile clean --today $TODAY --prune-worktrees)"; code=$?
check "worktree の除去が報告される" 0 "$code" "$out" "removed=worktree:$box/repo-spec-e"
check "ブランチは判断待ち保護のまま" 0 "$code" "$out" "kept=branch:speculative/e (判断待ち保護。worktree のみ外した)"
assert "worktree ディレクトリが消えている" test ! -d "$box/repo-spec-e"
assert "ブランチは残っている" test -n "$(g branch --list speculative/e)"

echo "Test 16: remote 無し環境で check/clean が SKIP 表記で正常動作する"
repo2="$box/repo2"
mkdir -p "$repo2"
g2() { git -C "$repo2" -c user.name=t -c user.email=t@t "$@"; }
(
  cd "$repo2"
  git init -q -b main .
  printf 'x\n' > x.txt
  git -c user.name=t -c user.email=t@t add x.txt
  git -c user.name=t -c user.email=t@t commit -qm init
)
g2 checkout -q -b speculative/x main
printf 'y\n' > "$repo2/y.txt"
g2 add y.txt
g2 commit -qm x
g2 checkout -q main
out="$(cd "$repo2" && python3 "$RECONCILE" --today $TODAY 2>&1)"; code=$?
check "remote 無し check は exit 0" 0 "$code" "$out" "SKIP: remote なし"
check "origin は unknown 扱い" 0 "$code" "$out" "branch=speculative/x worktree=no origin=unknown merged_hint=no"
mkdir -p "$repo2/.claude/addf"
printf '| ../wt | speculative/x | test | 放棄 | %s |\n' "$TODAY" > "$repo2/.claude/addf/Worktrees.md"
out="$(cd "$repo2" && python3 "$RECONCILE" clean --today $TODAY --delete speculative/x 2>&1)"; code=$?
check "remote 無し clean は exit 0" 0 "$code" "$out" "SKIP: remote なし"
check "「放棄」記載でローカルブランチは削除される" 0 "$code" "$out" "removed=branch:speculative/x"
assert "speculative/x が消えている" test -z "$(g2 branch --list speculative/x)"

echo "Test 17: 異常系 — リポジトリ外・不正な --today・未来日付の --today は ERROR"
nonrepo="$box/nonrepo"
mkdir -p "$nonrepo"
out="$(cd "$nonrepo" && python3 "$RECONCILE" 2>&1)"; code=$?
check "リポジトリ外で exit 1" 1 "$code" "$out" "ERROR"
out="$(cd "$repo" && python3 "$RECONCILE" --today not-a-date 2>&1)"; code=$?
check "不正な --today で exit 1" 1 "$code" "$out" "ERROR"
out="$(run_reconcile clean --today $FUTURE)"; code=$?
check "未来日付の --today は exit 1" 1 "$code" "$out" "未来日付は指定できない"
assert "未来日付注入で当日 integration が消えていない" test -n "$(g branch --list integration/loop-$TODAY)"

echo "Test 18: clean --delete — 「Pending」は状態として認識され、削除対象外の ERROR になる"
make_feature p p.txt
write_worktrees_md "speculative/p Pending"
out="$(run_reconcile clean --today $TODAY --delete speculative/p)"; code=$?
check "Pending は削除不可の ERROR（exit 1）" 1 "$code" "$out" "状態「Pending」"
check "削除できる状態の案内が出る" 1 "$code" "$out" "削除できるのは「昇格済み」「放棄」のみ"
check_absent "状態「不明」ではない（Pending が語彙として認識される）" "$out" "状態「不明」"
check_absent "削除が実行されていない" "$out" "removed=branch:speculative/p"
assert "Pending の p はローカルに残っている" test -n "$(g branch --list speculative/p)"

echo "Test 19: check — pending_count / active_count が Worktrees.md の行数を報告する（在庫の機械シグナル）"
write_worktrees_md "speculative/p Pending" "speculative/q Pending（PR #9）" "speculative/e 開発中"
out="$(run_reconcile --today $TODAY)"; code=$?
check "Pending 2行（注記付き含む）で pending_count=2" 0 "$code" "$out" "pending_count=2"
check "進行中1行（開発中）で active_count=1" 0 "$code" "$out" "active_count=1"
write_worktrees_md "speculative/e 開発中"
out="$(run_reconcile --today $TODAY)"; code=$?
check "Pending 0行で pending_count=0" 0 "$code" "$out" "pending_count=0"
check "開発中のみでも active_count=1" 0 "$code" "$out" "active_count=1"
rm "$repo/.claude/addf/Worktrees.md"
out="$(run_reconcile --today $TODAY)"; code=$?
check "Worktrees.md 無しは pending_count=0" 0 "$code" "$out" "pending_count=0"
check "Worktrees.md 無しは active_count=0" 0 "$code" "$out" "active_count=0"

echo "Test 20: check — 騙し入力（列順詐称・強調・無関係テーブル）を列位置ベースで正しく捌く"
# 20-1: 列順詐称 — 概念名列が状態語（Pending/テスト通過）で始まっても、状態列だけを判定する
mkdir -p "$repo/.claude/addf"
cat > "$repo/.claude/addf/Worktrees.md" <<EOF
# Worktrees（投機の進行状態）

| worktree パス | ブランチ | 対象概念（出典） | 状態 | 最終更新 |
|---|---|---|---|---|
| ../wt1 | speculative/p | Pending整理の試作（概念名が状態語で始まる） | 昇格済み | $TODAY |
| ../wt2 | speculative/q | テスト通過率の可視化（同上） | 放棄 | $TODAY |
EOF
out="$(run_reconcile --today $TODAY)"; code=$?
check "列順詐称: 概念名列の Pending は数えない" 0 "$code" "$out" "pending_count=0"
check "列順詐称: 概念名列のテスト通過は active に数えない" 0 "$code" "$out" "active_count=0"
# 20-2: 強調 — 状態セルの **Pending** / **開発中** は装飾を剥がして数える
cat > "$repo/.claude/addf/Worktrees.md" <<EOF
| worktree パス | ブランチ | 対象概念（出典） | 状態 | 最終更新 |
|---|---|---|---|---|
| ../wt1 | speculative/p | test | **Pending** | $TODAY |
| ../wt2 | speculative/q | test | **開発中** | $TODAY |
EOF
out="$(run_reconcile --today $TODAY)"; code=$?
check "強調 **Pending** を剥がして数える" 0 "$code" "$out" "pending_count=1"
check "強調 **開発中** を剥がして active に数える" 0 "$code" "$out" "active_count=1"
# 20-3: 無関係テーブル・ヘッダなし表 — 「ブランチ」「状態」ヘッダの無い表は対象外
cat > "$repo/.claude/addf/Worktrees.md" <<EOF
# Worktrees（投機の進行状態）

## 無関係テーブル（投機管理表ではない）

| 項目 | メモ |
|---|---|
| Pending | 無関係表の Pending は数えない |
| 開発中 | 無関係表の進行中も数えない |

| ヘッダなし表の行 | Pending | これも数えない |
EOF
out="$(run_reconcile --today $TODAY)"; code=$?
check "無関係テーブルの Pending は数えない" 0 "$code" "$out" "pending_count=0"
check "無関係テーブル・ヘッダなし表の進行中は数えない" 0 "$code" "$out" "active_count=0"
# 20-4: active_count の計上 — 進行中7状態は数え、昇格済み/放棄/掃除済み/Pending は含めない
cat > "$repo/.claude/addf/Worktrees.md" <<EOF
| worktree パス | ブランチ | 対象概念（出典） | 状態 | 最終更新 |
|---|---|---|---|---|
| ../wt1 | speculative/a | test | 開発中 | $TODAY |
| ../wt2 | speculative/b | test | テスト通過 | $TODAY |
| ../wt3 | speculative/c | test | テスト失敗 | $TODAY |
| ../wt4 | speculative/d | test | 衝突 | $TODAY |
| ../wt5 | speculative/e | test | 統合済み | $TODAY |
| ../wt6 | speculative/f | test | 要再検証 | $TODAY |
| ../wt7 | speculative/g | test | 上限で待機 | $TODAY |
| ../wt8 | speculative/h | test | 昇格済み | $TODAY |
| ../wt9 | speculative/i | test | 放棄（実体なし） | $TODAY |
| ../wt10 | speculative/j | test | 掃除済み | $TODAY |
| ../wt11 | speculative/k | test | Pending（PR #9） | $TODAY |
EOF
out="$(run_reconcile --today $TODAY)"; code=$?
check "進行中7状態が active_count に計上される" 0 "$code" "$out" "active_count=7"
check "Pending は active ではなく pending 側に数える" 0 "$code" "$out" "pending_count=1"
rm "$repo/.claude/addf/Worktrees.md"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
