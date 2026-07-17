#!/bin/bash
# test-migrate-paths.sh
# migrate-paths.py / lint-residual-paths.py / paths.toml（Plan 0037 フェーズ1）を
# mktemp サンドボックスの合成プロジェクトで検証する（実リポジトリは汚さない）。
#
# 合成プロジェクト: 独自 knowhow 記事あり・docs/ 直下に Pages コンテンツ
# （docs/index.html）あり・docs/plans-add なし、のダウンストリーム相当。
# check → apply → rewrite → lint-residual-paths が ERROR ゼロになるまでを通し、
# 以下を検証する:
# - 存在≠所有（Pages コンテンツ・マップ外パスに触れない）
# - 境界チェック（docs/plans-add / docs/plans-addendum への誤マッチ防止）
# - ドリフト注入 TDD（旧パス書き戻しの ERROR 検出）
# - 行単位マーカー residual-path: allow（マーカー行は check/rewrite/lint がスキップし、
#   マーカーなし行はドキュメント内でも検出する — ファイル丸ごと除外の盲点防止）
# - dirty 拒否・実行位置（リポジトリルート）検証・apply 前 rewrite の拒否
# - backup ref の上書き拒否・空ディレクトリ衝突の許容・非空衝突の回復案内
# - symlink 越しのリポジトリ外書き込み防止（悪意ある symlink を注入して検証）
# - 未追跡の動的生成ファイル（Worktrees.md / Dashboard.md）の fs 移動
# - 拡張子なしテキスト（Makefile）の走査（check/rewrite/lint の対象一致）
# - apply 後の案内どおり「新位置のツール」で rewrite を実行する経路
# - 逆流 WARNING・.gitignore 旧位置グロブパターンの非対称 WARNING・
#   tomllib 欠如の責務別ふるまい（migrate=ERROR / lint=SKIP）
# - 射程外候補スキャン（rewrite が書き換えられない4類型を check が WARNING で
#   事前列挙する。exit code には影響しない・移動対象ゼロの移行済みリポジトリでは出さない）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS="$(cd "$SCRIPT_DIR/../.." && pwd)/addfTools"
MIGRATE="$TOOLS/migrate-paths.py"
LINT="$TOOLS/lint-residual-paths.py"
PATHS_TOML="$TOOLS/paths.toml"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
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

expect() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

# tomllib（Python 3.11+）前提のため uv があれば 3.11 を明示する（test-speculate-guard.sh と同パターン）
if command -v uv >/dev/null 2>&1; then
  runpy() { local dir="$1" script="$2"; shift 2; (cd "$dir" && uv run --python 3.11 "$script" "$@" 2>&1); }
else
  runpy() { local dir="$1" script="$2"; shift 2; (cd "$dir" && python3 "$script" "$@" 2>&1); }
fi

git_box() { git -C "$box" -c user.email=t@t -c user.name=t "$@"; }

# ---- 合成プロジェクト（ダウンストリーム相当）の構築 ----
box="$(mktemp -d)"
outside="$(mktemp -d)"
trap 'rm -rf "$box" "$outside"' EXIT
# symlink 攻撃のリンク先（リポジトリ外の犠牲ファイル）
printf 'target: docs/plans/0001-sample.md\n' > "$outside/victim.md"
(
  cd "$box"
  git init -q -b main .
  mkdir -p docs/plans docs/knowhow/ADDF docs/guides docs/plans-addendum \
           .claude/addfTools .claude/templates .claude/tests
  # ADDF 管理ドキュメント（docs/ サブディレクトリ単位で移動される側）
  printf '# Plan 0001\n参照: docs/knowhow/ADDF/tips.md\n' > docs/plans/0001-sample.md
  printf '# tips\n' > docs/knowhow/ADDF/tips.md
  printf '# 独自記事（プロジェクト所有だが knowhow の仕組みの一部として一緒に移動する）\n' > docs/knowhow/original-article.md
  printf '# ガイド。docs/plans を参照\n' > docs/guides/dev.md
  # Pages コンテンツ（ADDF 管理外 — 絶対に触らない: 存在≠所有）
  printf '<html><body>pages content</body></html>\n' > docs/index.html
  # 境界チェック用: docs/plans-add への参照（本体のみのディレクトリで、ローカルには無い）と
  # マップ外のユーザーパス docs/plans-addendum（前方一致だが別トークン）
  cat > ref-boundary.md <<'EOF'
- upstream plan: docs/plans-add/0037-addf-directory-consolidation.md
- my plan: docs/plans/0001-sample.md
- user dir (map 外・置換されてはならない): docs/plans-addendum/readme.md
EOF
  printf 'user note\n' > docs/plans-addendum/readme.md
  # 拡張子なしのテキストファイル（走査対象の一致検証: check/rewrite/lint 全てが見ること）
  printf 'all:\n\t@echo docs/plans/0001-sample.md\n' > Makefile
  # 悪意ある symlink（git は symlink を blob 追跡する。open で辿るとリポジトリ外に書く）
  ln -s "$outside/victim.md" evil-link.md
  # .claude 側（配布された paths.toml とツール自身を含む — 新位置からの再実行経路を通すため）
  cp "$PATHS_TOML" .claude/addfTools/paths.toml
  cp "$MIGRATE" .claude/addfTools/migrate-paths.py
  cp "$LINT" .claude/addfTools/lint-residual-paths.py
  printf '# ProgressTemplate\n' > .claude/templates/ProgressTemplate.md
  printf '# Progress\nテンプレート: .claude/templates/ProgressTemplate.md\n' > .claude/Progress.md
  printf '# Feedback\n' > .claude/Feedback.md
  printf '[gui-test]\nenable = false\n' > .claude/addf-Behavior.toml
  printf 'echo ok\n' > .claude/tests/run-all.sh
  printf '# CLAUDE.md\n@.claude/Feedback.md\n計画: docs/plans/ ノウハウ: docs/knowhow/\nテスト: bash .claude/tests/run-all.sh\n' > CLAUDE.md
  # 動的生成ファイルは .gitignore 対象（本体と同じ構図）
  printf '# --- ADDF Framework ---\n.claude/Dashboard.md\n.claude/Worktrees.md\n# --- /ADDF Framework ---\n' > .gitignore
  git add -A
  git -c user.email=t@t -c user.name=t commit -q -m init
  # 未追跡の動的生成ファイル（gitignore 対象なので作業ツリーは clean のまま）
  printf '# Dashboard（実行時生成）\n' > .claude/Dashboard.md
  printf '# Worktrees（実行時生成）\n' > .claude/Worktrees.md
)

echo "Test 1: check モード（既定）— 何も変更せず計画・参照数・マッチ例を提示する"
out="$(runpy "$box" "$MIGRATE")"; code=$?
check "check が exit 0" 0 "$code" "$out" "MOVE (dir): docs/plans → .claude/addf/plans"
check "docs/plans-add（不在・optional）は SKIP 明示" 0 "$code" "$out" "SKIP: docs/plans-add"
check "マッチ例（ファイル:行）を表示する" 0 "$code" "$out" "例: CLAUDE.md:"
check "拡張子なしファイル（Makefile）も走査対象" 0 "$code" "$out" "例: Makefile:"
expect "check は何も変更しない（作業ツリー clean のまま）" test -z "$(git_box status --porcelain)"

echo "Test 2: 移行前の合成プロジェクトで lint は SKIP を明示する"
out="$(runpy "$box" "$LINT")"; code=$?
check "移行前 SKIP（exit 0）" 0 "$code" "$out" "SKIP: 移行前のリポジトリ"

echo "Test 3: 本体リポジトリ（移行済み）で lint が旧パス残存ゼロを確認する（恒久の完了ゲート）"
out="$(runpy "$REPO_ROOT" "$LINT")"; code=$?
check "本体で OK（exit 0）" 0 "$code" "$out" "OK: 旧パス残存なし"

echo "Test 4: リポジトリルート以外の cwd では両スクリプトとも ERROR"
out="$(runpy "$box/docs" "$MIGRATE")"; code=$?
check "migrate: サブディレクトリ実行を拒否" 1 "$code" "$out" "リポジトリルートで実行してください"
out="$(runpy "$box/docs" "$LINT")"; code=$?
check "lint: サブディレクトリ実行を拒否" 1 "$code" "$out" "リポジトリルートで実行してください"

echo "Test 5: apply 未実施の rewrite は ERROR で拒否する（実在しないパスへの書き換え防止）"
out="$(runpy "$box" "$MIGRATE" rewrite)"; code=$?
check "apply 前の rewrite 拒否（exit 1）" 1 "$code" "$out" "apply（git mv）を先に実行してください"
expect "拒否時に参照は書き換わっていない" grep -q '計画: docs/plans/' "$box/CLAUDE.md"

echo "Test 6: dirty な作業ツリーでは apply を拒否する"
echo "dirty" >> "$box/CLAUDE.md"
out="$(runpy "$box" "$MIGRATE" apply)"; code=$?
check "dirty 拒否（exit 1）" 1 "$code" "$out" "dirty"
git_box checkout -q -- CLAUDE.md
expect "拒否時に何も移動していない" test -d "$box/docs/plans"

echo "Test 7: 既存の backup ref を上書きしない（本当の移行前を失わない）"
git_box update-ref refs/backup/pre-0037-migration HEAD
out="$(runpy "$box" "$MIGRATE" apply)"; code=$?
check "backup ref 既存で apply 拒否（exit 1）" 1 "$code" "$out" "既に存在します"
check "明示削除の案内を出す" 1 "$code" "$out" "update-ref -d"
expect "拒否時に何も移動していない（docs/plans 健在）" test -d "$box/docs/plans"
git_box update-ref -d refs/backup/pre-0037-migration

echo "Test 8: 非空の移動先は衝突 ERROR ＋回復手順の案内（check で検出）"
mkdir -p "$box/.claude/addf/templates"
printf 'stray\n' > "$box/.claude/addf/templates/stray.md"
out="$(runpy "$box" "$MIGRATE")"; code=$?
check "非空衝突を ERROR（exit 1）" 1 "$code" "$out" "衝突: .claude/addf/templates"
check "回復手順（中身確認→不要なら削除）を案内" 1 "$code" "$out" "不要なら削除"
rm -rf "$box/.claude/addf"

echo "Test 8.5: 射程外候補スキャン — rewrite が書き換えられない4類型を check が WARNING で事前列挙する"
(
  cd "$box"
  # 類型1: 移動対象内スクリプトの親ディレクトリ算出（移動で階層が変わるとずれる）
  cat > docs/guides/helper.sh <<'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."
EOF
  # 類型2: 分割断片（os.path.join の組み立て — フルパス文字列が現れず rewrite の射程外）
  cat > frag.py <<'EOF'
import os
CONF = os.path.join(ROOT, '.claude', 'addf-Behavior.toml')
EOF
  # 類型2の偽陽性抑制（W2）: .claude を含まない一般語 join（Django 定型句）は検出しない
  printf "TEMPLATES_DIR = os.path.join(BASE_DIR, 'templates')\n" > django_settings.py
  # .claude を含む行は一般語 basename でも検出する
  printf "p = os.path.join(root, '.claude', 'templates')\n" > frag2.py
  # .claude を含まなくても固有名 basename（addf を含む等）の文字列連結は検出する
  printf 'let conf = scriptDir + "/../addf-Behavior.toml"\n' > frag3.swift
  # 類型3: 移動対象内 Markdown の相対リンク（ファイル自身の階層が変わるとずれる）
  printf 'see [readme](../README.md)\n' > docs/guides/linked.md
  # 類型4: 移動対象内の実行可能バイナリ（NUL 入り）
  printf 'BIN\0DATA' > .claude/addfTools/fake-bin
  chmod +x .claude/addfTools/fake-bin
)
git_box add -A
git_box commit -q -m "inject out-of-scope"
out="$(runpy "$box" "$MIGRATE")"; code=$?
check "4類型を仕込んでも check は exit 0（WARNING は成否に影響しない）" 0 "$code" "$out" "射程外候補スキャン"
check "類型1: 相対階層参照（SCRIPT_DIR/..）を検出" 0 "$code" "$out" "docs/guides/helper.sh"
check "類型2: os.path.join 断片を検出" 0 "$code" "$out" "frag.py"
check "類型2: .claude ありの一般語 join（frag2.py）を検出" 0 "$code" "$out" "frag2.py"
check "類型2: .claude なしでも固有名連結（frag3.swift）を検出" 0 "$code" "$out" "frag3.swift"
if grep -q 'django_settings.py' <<<"$out"; then
  echo "  FAIL: 偽陽性抑制 — .claude なしの一般語 join（Django 定型句）は検出しない"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: 偽陽性抑制 — .claude なしの一般語 join（Django 定型句）は検出しない"
  PASS=$((PASS + 1))
fi
check "類型3: Markdown 相対リンク（](../）を検出" 0 "$code" "$out" "docs/guides/linked.md"
check "類型4: バイナリ（NUL 検査）を列挙" 0 "$code" "$out" "fake-bin"
check "偽陽性を含む目視確認の案内を明示する" 0 "$code" "$out" "偽陽性"
check "git 追跡外ファイルは走査対象外の注意を出す" 0 "$code" "$out" "走査対象外"
# 後続テスト（apply〜）を射程外注入と独立させるため取り除く
git_box rm -qf docs/guides/helper.sh frag.py frag2.py frag3.swift django_settings.py \
  docs/guides/linked.md .claude/addfTools/fake-bin
git_box commit -q -m "cleanup out-of-scope"

echo "Test 8.6: 移行済みリポジトリ（移動対象ゼロ）では射程外スキャンを実行しない"
out="$(runpy "$REPO_ROOT" "$MIGRATE")"; code=$?
check "本体（移行済み）で check は exit 0・移動 0 件" 0 "$code" "$out" "移動 0 件"
if grep -q '射程外候補スキャン' <<<"$out"; then
  echo "  FAIL: 移動対象ゼロのとき射程外スキャンを出さない"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: 移動対象ゼロのとき射程外スキャンを出さない"
  PASS=$((PASS + 1))
fi

echo "Test 9: apply — 空の移動先ディレクトリは衝突扱いせず継続する（途中クラッシュ残骸の自己ロック防止）"
mkdir -p "$box/.claude/addf/plans"   # 空ディレクトリ（git 的には不可視 = clean）
out="$(runpy "$box" "$MIGRATE" apply)"; code=$?
check "apply が exit 0（空ディレクトリを rmdir して継続）" 0 "$code" "$out" "コミットしてください"
check "backup ref 作成を出力" 0 "$code" "$out" "refs/backup/pre-0037-migration"
check "案内が新位置のツールパスを示す" 0 "$code" "$out" ".claude/addf/addfTools/migrate-paths.py rewrite"
check "動的生成ファイルは fs 移動（未追跡）" 0 "$code" "$out" "mv (dynamic, 未追跡)"
expect "backup ref が実在する" git_box rev-parse -q --verify refs/backup/pre-0037-migration
expect "docs/plans → .claude/addf/plans（空ディレクトリ経由でも中身が正しく入る）" test -f "$box/.claude/addf/plans/0001-sample.md"
expect "独自 knowhow 記事も knowhow ごと移動" test -f "$box/.claude/addf/knowhow/original-article.md"
expect "addfTools → addf/addfTools（paths.toml も追従）" test -f "$box/.claude/addf/addfTools/paths.toml"
expect "ツール自身も新位置へ移動" test -f "$box/.claude/addf/addfTools/migrate-paths.py"
expect "addf-Behavior.toml → addf/Behavior.toml（リネーム）" test -f "$box/.claude/addf/Behavior.toml"
expect "未追跡の Worktrees.md が fs 移動されている" test -f "$box/.claude/addf/Worktrees.md"
expect "未追跡の Dashboard.md が fs 移動されている" test -f "$box/.claude/addf/Dashboard.md"
expect "旧位置の Worktrees.md は消えている" test ! -e "$box/.claude/Worktrees.md"
expect "存在≠所有: Pages コンテンツ docs/index.html は動かさない" test -f "$box/docs/index.html"
expect "存在≠所有: マップ外の docs/plans-addendum は動かさない" test -f "$box/docs/plans-addendum/readme.md"
expect "旧 docs/plans は消えている" test ! -e "$box/docs/plans"
git_box add -A
git_box commit -q -m "git mv"

echo "Test 10: rewrite — apply の案内どおり「新位置のツール」で実行し、マップ駆動＋境界チェックで書き換える"
out="$(runpy "$box" ".claude/addf/addfTools/migrate-paths.py" rewrite)"; code=$?
check "新位置からの rewrite が exit 0" 0 "$code" "$out" "書き換えました"
check "完了案内が新位置の lint パスを示す" 0 "$code" "$out" ".claude/addf/addfTools/lint-residual-paths.py"
expect "CLAUDE.md の @メンションが新パスに" grep -q '@.claude/addf/Feedback.md' "$box/CLAUDE.md"
expect "CLAUDE.md の tests 参照が新パスに" grep -q 'bash .claude/addf/tests/run-all.sh' "$box/CLAUDE.md"
expect "docs/plans 参照が新パスに" grep -q '.claude/addf/plans/0001-sample.md' "$box/ref-boundary.md"
expect "拡張子なし Makefile も書き換わる" grep -q '.claude/addf/plans/0001-sample.md' "$box/Makefile"
expect ".gitignore の動的生成ファイル参照も新パスに" grep -q '.claude/addf/Dashboard.md' "$box/.gitignore"
expect "境界: docs/plans-add 参照は plans-add のマップで正しく変換" \
  grep -q '.claude/addf/plans-add/0037-addf-directory-consolidation.md' "$box/ref-boundary.md"
expect "境界: マップ外 docs/plans-addendum は無傷（docs/plans の置換で壊れない）" \
  grep -q 'docs/plans-addendum/readme.md' "$box/ref-boundary.md"
expect "symlink 越しにリポジトリ外を書き換えない（victim 無傷）" \
  grep -q 'target: docs/plans/0001-sample.md' "$outside/victim.md"
git_box add -A
git_box commit -q -m rewrite

echo "Test 11: 移行完了後の lint が ERROR ゼロ（完了ゲート通過。symlink 先の旧パスは検査対象外）"
out="$(runpy "$box" "$LINT")"; code=$?
check "残存なしで exit 0" 0 "$code" "$out" "OK: 旧パス残存なし"

echo "Test 12: ドリフト注入 TDD — 旧パス参照を書き戻すと lint が ERROR で検出する"
printf '旧参照が復活: docs/plans/0001-sample.md\n' > "$box/drift.md"
git_box add drift.md
out="$(runpy "$box" "$LINT")"; code=$?
check "残存を ERROR 検出（exit 1）" 1 "$code" "$out" 'drift.md:1: 旧パス `docs/plans` が残存'
check "部分適用の可能性の注記を出す" 1 "$code" "$out" "apply/rewrite が未完了の可能性"
git_box rm -qf drift.md

echo "Test 12.5: 行単位マーカー（residual-path: allow）— マーカー行は check/rewrite/lint がスキップし、マーカーなし行は（ドキュメント内でも）検出する"
cat > "$box/migration-doc.md" <<'EOF'
移行手順の説明: 道具を旧位置 docs/plans に置く例 <!-- residual-path: allow -->
uv run .claude/addfTools/migrate-paths.py check  # residual-path: allow
マーカーなしの旧パス言及: docs/plans/0001-sample.md
EOF
git_box add migration-doc.md
git_box commit -q -m "add migration-doc"
out="$(runpy "$box" "$LINT")"; code=$?
check "マーカーなし行（3行目）を ERROR 検出" 1 "$code" "$out" 'migration-doc.md:3'
if grep -qE 'migration-doc\.md:(1|2):' <<<"$out"; then
  echo "  FAIL: マーカー付き行（1〜2行目）を検出しない"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: マーカー付き行（1〜2行目）を検出しない"
  PASS=$((PASS + 1))
fi
out="$(runpy "$box" ".claude/addf/addfTools/migrate-paths.py" rewrite)"; code=$?
check "マーカー混在ファイルの rewrite が exit 0" 0 "$code" "$out" "書き換えました"
expect "マーカー行は書き換えない（旧パスのまま）" grep -q '旧位置 docs/plans に置く例' "$box/migration-doc.md"
expect "マーカーなし行は書き換わる" grep -q '.claude/addf/plans/0001-sample.md' "$box/migration-doc.md"
git_box add -A
git_box commit -q -m "rewrite migration-doc"
git_box rm -qf migration-doc.md
git_box commit -q -m "cleanup migration-doc"

echo "Test 13: 境界: docs/plans-addendum への言及は残存として誤検出しない"
printf 'ユーザーパス: docs/plans-addendum/readme.md\n' > "$box/user-note.md"
git_box add user-note.md
out="$(runpy "$box" "$LINT")"; code=$?
check "マップ外パスは残存扱いしない（exit 0）" 0 "$code" "$out" "OK: 旧パス残存なし"
git_box rm -qf user-note.md

echo "Test 13.5: 境界（Issue #33）— 外部 URL / 他プロジェクト絶対パスは残存扱いしない・自リポジトリ絶対パスは検出する"
# Issue #33 の誤検知3パターンと検出漏れ対処のドリフト注入 TDD:
#   (a) 外部 URL 内の旧パス文字列 → 検出してはならない（Supabase 公式スキル配布物の実例）
#   (b) 他プロジェクトへの絶対パス言及 → 検出してはならない（knowhow で別リポジトリを参照する例）
#   (c) `./` 相対の本物の残存 → 引き続き検出する
#   (d) 自リポジトリ絶対パスの残存 → 検出する（basename マッチの self_prefix）
#   (e) rewrite が (a)(b) を壊さない（外部 URL を書き換える潜在バグの塞ぎ）
box_basename="$(basename "$box")"
cat > "$box/external-refs.md" <<EOF
外部 URL（Supabase 公式スキル相当・rewrite で書き換えて壊してはならない）:
- https://supabase.com/docs/plans/getting-started
- https://example.com/docs/knowhow/faq

他プロジェクトへの絶対パス言及（knowhow で他リポジトリを参照する典型例）:
- ~/workspace/OTHER_PROJECT/docs/plans/0001.md
- /Users/dev/repos/AnotherRepo/docs/knowhow/tips.md
EOF
cat > "$box/self-abs.md" <<EOF
自リポジトリの絶対パス言及（本物の残存 — 検出されるべき）:
- /Users/dev/repos/$box_basename/docs/plans/0001-sample.md
EOF
cat > "$box/rel-drift.md" <<'EOF'
./ 相対の本物の残存（引き続き検出する）: ./docs/plans/0001-sample.md
EOF
git_box add external-refs.md self-abs.md rel-drift.md
out="$(runpy "$box" "$LINT")"; code=$?
check "本物の残存（./ 相対）を ERROR 検出（exit 1）" 1 "$code" "$out" 'rel-drift.md'
check "自リポジトリ絶対パス残存も検出（basename マッチの self_prefix）" 1 "$code" "$out" 'self-abs.md'
if grep -qE 'external-refs\.md' <<<"$out"; then
  echo "  FAIL: 外部 URL・他プロジェクト絶対パスを誤検出（残存扱いしてはならない）"
  echo "$out" | grep -E 'external-refs' | sed 's/^/    | /'
  FAIL=$((FAIL + 1))
else
  echo "  PASS: 外部 URL・他プロジェクト絶対パスは残存扱いしない（誤検知なし）"
  PASS=$((PASS + 1))
fi
# 誤検知除外を確認したら、続く rewrite 検査（外部 URL 無傷）のため本物残存は取り除く。
# external-refs.md（外部URL・他プロジェクト言及）だけ残して rewrite を通し、書き換えられていないことを確認する。
git_box rm -qf rel-drift.md self-abs.md
git_box commit -q -m "keep external-refs for rewrite invariance check"
out="$(runpy "$box" ".claude/addf/addfTools/migrate-paths.py" rewrite)"; code=$?
check "rewrite が exit 0（外部 URL 混在下でも成功）" 0 "$code" "$out"
expect "rewrite が外部 URL を書き換えていない（supabase.com/docs/plans 無傷）" \
  grep -q 'https://supabase.com/docs/plans/getting-started' "$box/external-refs.md"
expect "rewrite が外部 URL を書き換えていない（example.com/docs/knowhow 無傷）" \
  grep -q 'https://example.com/docs/knowhow/faq' "$box/external-refs.md"
expect "rewrite が他プロジェクト絶対パスを書き換えていない（OTHER_PROJECT/docs/plans 無傷）" \
  grep -q 'workspace/OTHER_PROJECT/docs/plans/0001.md' "$box/external-refs.md"
expect "rewrite が他プロジェクト絶対パスを書き換えていない（AnotherRepo/docs/knowhow 無傷）" \
  grep -q 'AnotherRepo/docs/knowhow/tips.md' "$box/external-refs.md"
git_box rm -qf external-refs.md
git_box commit -q -m "cleanup Test 13.5"

echo "Test 14: 逆流 — 移行後に docs/ 配下へ ADDF 管理ファイルを再追加すると WARNING"
mkdir -p "$box/docs/knowhow"
printf '# 逆流記事\n' > "$box/docs/knowhow/reflux.md"
git_box add docs/knowhow/reflux.md
out="$(runpy "$box" "$LINT")"; code=$?
check "逆流を WARNING 検出（exit 2）" 2 "$code" "$out" "逆流"
git_box rm -qf docs/knowhow/reflux.md
rmdir "$box/docs/knowhow" 2>/dev/null

echo "Test 14.6: ドリフト注入 TDD — .gitignore のグロブパターンが旧位置にのみマッチし新位置にマッチしないと WARNING（Issue #26）"
cp "$box/.gitignore" "$box/.gitignore.bak"
printf '.claude/*.md\n' >> "$box/.gitignore"
# '?' で1文字だけワイルドカード化し、旧パスの完全リテラル出現（既存 ERROR 検査）と
# 衝突せずにディレクトリ限定（末尾 '/'）パターンの非対称検出だけを単独で確認する
printf '.claude/addfTool?/\n' >> "$box/.gitignore"
git_box add .gitignore
out="$(runpy "$box" "$LINT")"; code=$?
check ".gitignore 非対称パターンを WARNING 検出（exit 2）" 2 "$code" "$out" "\.gitignore.*パターン.*マッチしない"
check ".gitignore 末尾スラッシュ（ディレクトリ限定）パターンも WARNING 検出" 2 "$code" "$out" ".claude/addfTool?/\`"
mv "$box/.gitignore.bak" "$box/.gitignore"
git_box add .gitignore
out="$(runpy "$box" "$LINT")"; code=$?
check ".gitignore を元に戻すと WARNING が消える" 0 "$code" "$out" "OK: 旧パス残存なし"

echo "Test 14.5: サイズ上限 — 5MB 超のファイルは読み込まずスキップし、件数付きで手動確認を案内する"
{ printf '旧パス入りの巨大ファイル: docs/plans/0001-sample.md\n'; head -c 6000000 /dev/zero | tr '\0' 'a'; } > "$box/huge.txt"
git_box add huge.txt
out="$(runpy "$box" "$LINT")"; code=$?
check "lint: サイズ超過は ERROR にせずスキップ案内を出す（exit 0）" 0 "$code" "$out" "サイズ上限"
check "lint: スキップしたパスを列挙する" 0 "$code" "$out" "huge.txt"
out="$(runpy "$box" ".claude/addf/addfTools/migrate-paths.py")"; code=$?
check "check: サイズ超過の案内を出す" 0 "$code" "$out" "サイズ上限"
git_box rm -qf huge.txt

echo "Test 15: tomllib が無い環境 — migrate は ERROR（変更系）・lint は SKIP（受動 lint）"
# PYTHONPATH シムで ModuleNotFoundError を注入し、旧 Python（3.9 等）を再現する
shim="$(mktemp -d)"
printf 'raise ModuleNotFoundError("No module named '"'"'tomllib'"'"'")\n' > "$shim/tomllib.py"
out="$( (cd "$box" && PYTHONPATH="$shim" python3 "$MIGRATE" check 2>&1) )"; code=$?
check "migrate: tomllib 欠如で ERROR（フェイルセーフ）" 1 "$code" "$out" "ERROR"
out="$( (cd "$box" && PYTHONPATH="$shim" python3 "$LINT" 2>&1) )"; code=$?
check "lint: tomllib 欠如で SKIP（誤 ERROR を出さない）" 0 "$code" "$out" "SKIP"
rm -rf "$shim"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
