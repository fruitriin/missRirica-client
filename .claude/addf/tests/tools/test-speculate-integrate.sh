#!/bin/bash
# test-speculate-integrate.sh
# speculate-integrate.py の統合ふるまいを mktemp サンドボックスで検証する。
# fake git リポジトリに speculative/ ブランチ群を作り、
# 「2 feature の統合成功」「片方衝突時の記録と integration 再生成」を機械検証する（Plan 0028 フェーズ2）。
# なお Test 12 のみ speculate-integrate.py ではなく addf-speculate.md 手順3 の
# .claude 複製コマンド（cp + find + checkout）の検証である。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEGRATE="$(cd "$SCRIPT_DIR/../.." && pwd)/addfTools/speculate-integrate.py"
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

# サンドボックス: fake git リポジトリ（integration worktree は repo の隣に作られるため
# サンドボックス直下に repo/ を掘る）
box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT
repo="$box/repo"
mkdir -p "$repo"
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
(
  cd "$repo"
  git init -q -b main .
  # CI 等グローバル gitconfig の無い環境向け: スクリプト（speculate-integrate.py）が
  # この repo 内で行う commit にも効くよう、repo ローカル設定として永続化する
  git config user.name t && git config user.email t@t
  printf 'line1\n' > shared.txt
  git -c user.name=t -c user.email=t@t add shared.txt
  git -c user.name=t -c user.email=t@t commit -qm init
)

# speculative ブランチ群を用意する
# a: 独立ファイル追加 / b: 独立ファイル追加 / x, y: shared.txt の同一行を別内容に変更（相互衝突）
make_feature() {
  local name="$1" file="$2" content="$3"
  g checkout -q -b "speculative/$name" main
  printf '%s\n' "$content" > "$repo/$file"
  g add "$file"
  g commit -qm "$name"
  g checkout -q main
}
make_feature a a.txt "feature-a"
make_feature b b.txt "feature-b"
make_feature x shared.txt "x-version"
make_feature y shared.txt "y-version"
g checkout -q -b speculative/nochange main
g checkout -q main

run_integrate() {
  (cd "$repo" && python3 "$INTEGRATE" "$@" 2>&1)
}

echo "=== test-speculate-integrate.sh ==="

echo "Test 1: 独立した 2 feature の統合成功"
out="$(run_integrate --name integration/loop-test speculative/a speculative/b)"; code=$?
check "全統合で exit 0" 0 "$code" "$out" "integrated=speculative/a,speculative/b"
wt="$box/repo-integration"
assert "integration worktree が残っている" test -d "$wt"
assert "a.txt が統合されている" test -f "$wt/a.txt"
assert "b.txt が統合されている" test -f "$wt/b.txt"
count="$(g rev-list --count main..integration/loop-test)"
assert "1 feature = 1コミット（計2）" test "$count" = "2"

echo "Test 2: 衝突 feature はスキップして報告し、他は統合する"
out="$(run_integrate --name integration/loop-test speculative/x speculative/y)"; code=$?
check "衝突ありで exit 2" 2 "$code" "$out" "conflicted=speculative/y"
check "先着の x は統合される" 2 "$code" "$out" "integrated=speculative/x"
check "衝突ファイルが報告される" 2 "$code" "$out" "CONFLICT: speculative/y: shared.txt"
assert "worktree に衝突の残骸がない" test -z "$(cd "$wt" && git status --porcelain)"
assert "統合結果は x の内容" grep -q "x-version" "$wt/shared.txt"

echo "Test 3: 衝突 feature を外して integration を再生成できる（使い捨て）"
out="$(run_integrate --name integration/loop-test speculative/x)"; code=$?
check "再生成で exit 0" 0 "$code" "$out" "integrated=speculative/x"
count="$(g rev-list --count main..integration/loop-test)"
assert "再生成後は 1 コミットのみ（作り直し）" test "$count" = "1"

echo "Test 4: 存在しないブランチは missing として報告"
out="$(run_integrate --name integration/loop-test speculative/a speculative/ghost)"; code=$?
check "missing ありで exit 2" 2 "$code" "$out" "missing=speculative/ghost"
check "実在する a は統合される" 2 "$code" "$out" "integrated=speculative/a"

echo "Test 5: base と差分の無い feature は empty として報告"
out="$(run_integrate --name integration/loop-test speculative/nochange)"; code=$?
check "empty ありで exit 2" 2 "$code" "$out" "empty=speculative/nochange"

echo "Test 6: base 不在は ERROR"
out="$(run_integrate --base nosuch --name integration/loop-test speculative/a)"; code=$?
check "base 不在で exit 1" 1 "$code" "$out" "ERROR"

echo "Test 7: 置き先が git 管理外のディレクトリなら消さずに ERROR"
(cd "$repo" && git worktree remove --force "$wt" >/dev/null 2>&1; git worktree prune)
mkdir -p "$wt"
printf 'precious\n' > "$wt/user-data.txt"
out="$(run_integrate --name integration/loop-test speculative/a)"; code=$?
check "管理外ディレクトリで ERROR" 1 "$code" "$out" "ERROR"
assert "既存データが無傷" test -f "$wt/user-data.txt"
rm -rf "$wt"

echo "Test 8: commit フック拒否 → commit_failed として ERROR（差分の握り潰しを empty と偽らない）"
hook="$repo/.git/hooks/pre-commit"
printf '#!/bin/sh\nexit 1\n' > "$hook"
chmod +x "$hook"
out="$(run_integrate --name integration/loop-test speculative/a)"; code=$?
check "commit 失敗で exit 1" 1 "$code" "$out" "commit_failed=speculative/a"
check "empty には分類されない" 1 "$code" "$out" "empty=$"
rm -f "$hook"

echo "Test 9: 既存 integration worktree が dirty でも作り直すが、破棄を警告する"
run_integrate --name integration/loop-test speculative/a >/dev/null
printf 'uncommitted memo\n' > "$wt/memo.txt"
out="$(run_integrate --name integration/loop-test speculative/a)"; code=$?
check "dirty worktree の破棄を WARNING" 0 "$code" "$out" "WARNING: .*未コミット変更を破棄"
assert "作り直しは続行される" test -f "$wt/a.txt"

echo "Test 10: --base 省略・remote なしでは main にフォールバックする"
out="$(run_integrate --name integration/loop-test speculative/a)"; code=$?
check "remote なしで base=main" 0 "$code" "$out" "base=main"

echo "Test 11: --base 省略時は origin の default branch（非 main）を自動検出する"
repo2="$box/repo2"
mkdir -p "$repo2"
g2() { git -C "$repo2" -c user.name=t -c user.email=t@t "$@"; }
(
  cd "$repo2"
  git init -q -b trunk .
  git config user.name t && git config user.email t@t
  printf 'base\n' > base.txt
  git -c user.name=t -c user.email=t@t add base.txt
  git -c user.name=t -c user.email=t@t commit -qm init
)
g2 checkout -q -b speculative/z trunk
printf 'feature-z\n' > "$repo2/z.txt"
g2 add z.txt
g2 commit -qm z
g2 checkout -q trunk
git clone -q --bare "$repo2" "$box/origin2.git"
g2 remote add origin "$box/origin2.git"
g2 fetch -q origin
g2 remote set-head origin trunk
out="$(cd "$repo2" && python3 "$INTEGRATE" --name integration/loop-test speculative/z 2>&1)"; code=$?
check "default branch trunk が自動検出される" 0 "$code" "$out" "base=trunk"
check "trunk 起点で統合成功" 0 "$code" "$out" "integrated=speculative/z"
assert "trunk 起点の worktree に z.txt がある" test -f "$box/repo2-integration/z.txt"

echo "Test 12: 手順3の .claude 複製で .venv 等は除外される（venv は relocatable でない — Issue #18）"
mkdir -p "$repo/.claude/mcps/fake-mcp/.venv/lib"
printf 'marker\n' > "$repo/.claude/mcps/fake-mcp/.venv/lib/marker.txt"
printf 'exp\n' > "$repo/.claude/fake.exp.md"
# 依存をあえて git 追跡下にコミットしている構成（名前ベース除去からの復元対象）
mkdir -p "$repo/.claude/vendored/node_modules"
printf 'tracked\n' > "$repo/.claude/vendored/node_modules/lib.js"
g add .claude/vendored/node_modules/lib.js
g commit -qm vendored
spec_wt="$box/repo-spec-copytest"
g worktree add -q "$spec_wt" -b speculative/copytest main
mkdir -p "$spec_wt/.claude"
# addf-speculate.md 手順3 の複製コマンド（cp + find + checkout の3行構成）をそのまま再現する
cp -r "$repo/.claude/." "$spec_wt/.claude/"
find "$spec_wt/.claude" \( -name .venv -o -name venv -o -name node_modules -o -name __pycache__ \) \( -type d -o -type l \) -prune -exec rm -rf {} +
git -C "$spec_wt" checkout -- .claude 2>/dev/null || true
assert "gitignore 対象（.exp.md）は複製される" test -f "$spec_wt/.claude/fake.exp.md"
assert ".venv はコピー先に存在しない" test ! -e "$spec_wt/.claude/mcps/fake-mcp/.venv"
assert ".venv の親（mcps 配下）は残る" test -d "$spec_wt/.claude/mcps/fake-mcp"
assert "コピー元の .venv は無傷" test -f "$repo/.claude/mcps/fake-mcp/.venv/lib/marker.txt"
assert "git 追跡下の node_modules は checkout で復元される" test -f "$spec_wt/.claude/vendored/node_modules/lib.js"

echo "Test 13: fetch 済み・ローカル default branch 無しでは origin/<name> を起点にする（CI/コンテナ環境）"
repo3="$box/repo3"
git clone -q -b speculative/z "$box/origin2.git" "$repo3"
out="$(cd "$repo3" && python3 "$INTEGRATE" --name integration/loop-test speculative/z 2>&1)"; code=$?
check "remote-tracking の origin/trunk が起点になる" 0 "$code" "$out" "base=origin/trunk"
check "origin/trunk 起点で統合成功" 0 "$code" "$out" "integrated=speculative/z"
assert "origin/trunk 起点の worktree に z.txt がある" test -f "$box/repo3-integration/z.txt"

echo "Test 14: origin/HEAD 未設定＋stale なローカル main → main フォールバックが NOTE で可視化される"
repo4="$box/repo4"
git clone -q -b speculative/z "$box/origin2.git" "$repo4"
git -C "$repo4" remote set-head origin --delete
git -C "$repo4" branch -q --no-track main origin/trunk  # stale になりうるローカル main
out="$(cd "$repo4" && python3 "$INTEGRATE" --name integration/loop-test speculative/z 2>&1)"; code=$?
check "main にフォールバックして統合される" 0 "$code" "$out" "base=main"
check "フォールバックがサイレントでない（NOTE が出る）" 0 "$code" "$out" "NOTE: origin の default branch を検出できず"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
