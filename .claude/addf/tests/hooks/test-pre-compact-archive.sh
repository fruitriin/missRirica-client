#!/bin/bash
# test-pre-compact-archive.sh
# pre-compact-archive.sh のテスト。
# サンドボックスで Behavior.toml とダミートランスクリプトを用意し、有効化・無効化・
# 世代掃除・入力欠損・スラグ算出のフォールバック等を検証する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
HOOK="$PROJECT_DIR/.claude/hooks/pre-compact-archive.sh"
PASS=0
FAIL=0

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

assert_file_exists() {
  local test_name="$1" path="$2"
  if [ -f "$path" ]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (missing: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_no_file() {
  local test_name="$1" glob="$2"
  # shellcheck disable=SC2086
  if ! compgen -G "$glob" > /dev/null; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (unexpected files: $(compgen -G "$glob"))"
    FAIL=$((FAIL + 1))
  fi
}

assert_count() {
  local test_name="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    echo "  PASS: $test_name (count=$actual)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (expected count=$expected, got=$actual)"
    FAIL=$((FAIL + 1))
  fi
}

# サンドボックス: enable/archive_dir/max_generations を指定した Behavior.toml と
# 偽の ~/.claude/projects/<スラグ>/<uuid>.jsonl を用意する
make_sandbox() {
  local enable="$1" max_gen="${2:-10}"
  local box
  box="$(mktemp -d)"
  mkdir -p "$box/.claude/addf" "$box/archive" "$box/projects/-tmp-slug"
  cat > "$box/.claude/addf/Behavior.toml" <<EOF
[transcript-archive]
enable = $enable
archive_dir = "$box/archive"
max_generations = $max_gen
EOF
  echo '{"type":"user","message":{"content":"hi"}}' > "$box/projects/-tmp-slug/session-1.jsonl"
  echo "$box"
}

fire_hook() {  # $1=box $2=transcript_path $3=session_id $4=trigger
  local box="$1" tpath="$2" sid="$3" trig="$4"
  printf '{"transcript_path":"%s","session_id":"%s","trigger":"%s"}' "$tpath" "$sid" "$trig" \
    | CLAUDE_PROJECT_DIR="$box" bash "$HOOK" 2>/dev/null
}

echo "=== test-pre-compact-archive.sh ==="

# テスト 1: enable = false → アーカイブしないが exit 0
echo "Test 1: 無効時は静かに終了"
box="$(make_sandbox false)"
fire_hook "$box" "$box/projects/-tmp-slug/session-1.jsonl" "abc-def" "auto"
assert_exit "exit code" 0 $?
assert_no_file "アーカイブが作られない" "$box/archive/-tmp-slug/*.jsonl"
rm -rf "$box"

# テスト 2: enable = true → アーカイブ生成・命名規約
echo "Test 2: 有効時にアーカイブ生成"
box="$(make_sandbox true)"
fire_hook "$box" "$box/projects/-tmp-slug/session-1.jsonl" "session-uuid-1" "auto"
assert_exit "exit code" 0 $?
# 命名: <日時>-<trigger>-<session-id>.jsonl（日時形式は 8桁T6桁Z）
generated=$(ls "$box/archive/-tmp-slug/"*.jsonl 2>/dev/null | head -1)
assert_file_exists "アーカイブファイルの存在" "$generated"
if [ -n "$generated" ]; then
  name=$(basename "$generated")
  case "$name" in
    2[0-9][0-9][0-9][0-1][0-9][0-3][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z-auto-session-uuid-1.jsonl)
      echo "  PASS: 命名規約（YYYYMMDDTHHMMSSZ-trigger-sid.jsonl）"
      PASS=$((PASS + 1))
      ;;
    *)
      echo "  FAIL: 命名規約に不一致（got: $name）"
      FAIL=$((FAIL + 1))
      ;;
  esac
  # 内容がコピーされているか
  if diff -q "$box/projects/-tmp-slug/session-1.jsonl" "$generated" > /dev/null 2>&1; then
    echo "  PASS: 内容が完全コピー"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: 内容が異なる"
    FAIL=$((FAIL + 1))
  fi
fi
rm -rf "$box"

# テスト 3: プロジェクトスラグは transcript_path の親ディレクトリ名を使う
echo "Test 3: スラグは transcript_path 親ディレクトリ名"
box="$(make_sandbox true)"
mkdir -p "$box/projects/-my-project-slug"
echo '{}' > "$box/projects/-my-project-slug/s.jsonl"
fire_hook "$box" "$box/projects/-my-project-slug/s.jsonl" "sid" "manual"
if [ -d "$box/archive/-my-project-slug" ] && compgen -G "$box/archive/-my-project-slug/*.jsonl" > /dev/null; then
  echo "  PASS: 親ディレクトリ名を採用"
  PASS=$((PASS + 1))
else
  echo "  FAIL: 期待するスラグディレクトリ配下にファイルなし"
  FAIL=$((FAIL + 1))
fi
rm -rf "$box"

# テスト 4: 世代数上限 → 古いものから削除
echo "Test 4: 世代数上限（max=3）"
box="$(make_sandbox true 3)"
# 4 世代コピー。mtime をずらすため touch -t で古い順に打刻。
# トランスクリプトを4本用意して連続発火する（各世代を明示的に別ファイル名で残す）
for i in 1 2 3 4; do
  echo "{\"n\":$i}" > "$box/projects/-tmp-slug/s${i}.jsonl"
  fire_hook "$box" "$box/projects/-tmp-slug/s${i}.jsonl" "sid-$i" "auto"
  # 実行間隔を空けるためスリープの代替として mtime を明示
  touch -t "20260707120${i}00" "$box/archive/-tmp-slug/"*sid-$i*.jsonl 2>/dev/null || true
done
count=$(ls -1 "$box/archive/-tmp-slug/"*.jsonl 2>/dev/null | wc -l | tr -d ' ')
assert_count "世代数が上限内" 3 "$count"
# 最古（sid-1）が消えていること
if ls "$box/archive/-tmp-slug/"*sid-1* >/dev/null 2>&1; then
  echo "  FAIL: 最古世代が残っている"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: 最古世代が削除された"
  PASS=$((PASS + 1))
fi
# 最新（sid-4）が残っていること
if ls "$box/archive/-tmp-slug/"*sid-4* >/dev/null 2>&1; then
  echo "  PASS: 最新世代が残る"
  PASS=$((PASS + 1))
else
  echo "  FAIL: 最新世代が消えている"
  FAIL=$((FAIL + 1))
fi
rm -rf "$box"

# テスト 5: transcript_path 欠損 → 静かに終了・アーカイブなし
echo "Test 5: transcript_path 欠損"
box="$(make_sandbox true)"
out=$(printf '{"session_id":"sid","trigger":"auto"}' | CLAUDE_PROJECT_DIR="$box" bash "$HOOK" 2>/dev/null)
assert_exit "exit code" 0 $?
assert_no_file "アーカイブなし" "$box/archive/*/*.jsonl"
rm -rf "$box"

# テスト 6: transcript_path 実ファイルなし → 静かに終了
echo "Test 6: transcript_path 実ファイルなし"
box="$(make_sandbox true)"
out=$(printf '{"transcript_path":"%s","session_id":"sid","trigger":"auto"}' "$box/nai.jsonl" \
  | CLAUDE_PROJECT_DIR="$box" bash "$HOOK" 2>/dev/null)
assert_exit "exit code" 0 $?
assert_no_file "アーカイブなし" "$box/archive/*/*.jsonl"
rm -rf "$box"

# テスト 7: 不正 JSON → 静かに終了
echo "Test 7: 不正 JSON stdin"
box="$(make_sandbox true)"
out=$(printf 'こわれたJSON' | CLAUDE_PROJECT_DIR="$box" bash "$HOOK" 2>/dev/null)
assert_exit "exit code" 0 $?
assert_no_file "アーカイブなし" "$box/archive/*/*.jsonl"
rm -rf "$box"

# テスト 8: Behavior.toml 不在 → デフォルト無効・静かに終了
echo "Test 8: Behavior.toml 不在（デフォルト無効）"
box="$(mktemp -d)"
mkdir -p "$box/archive" "$box/projects/-tmp-slug"
echo '{}' > "$box/projects/-tmp-slug/s.jsonl"
out=$(printf '{"transcript_path":"%s","session_id":"sid","trigger":"auto"}' \
  "$box/projects/-tmp-slug/s.jsonl" | CLAUDE_PROJECT_DIR="$box" bash "$HOOK" 2>/dev/null)
assert_exit "exit code" 0 $?
assert_no_file "アーカイブなし" "$box/archive/*/*.jsonl"
rm -rf "$box"

# テスト 9: [transcript-archive] セクションなし → デフォルト無効・静かに終了
echo "Test 9: セクション未定義（デフォルト無効）"
box="$(mktemp -d)"
mkdir -p "$box/.claude/addf" "$box/archive" "$box/projects/-tmp-slug"
cat > "$box/.claude/addf/Behavior.toml" <<'EOF'
[gui-test]
enable = false
EOF
echo '{}' > "$box/projects/-tmp-slug/s.jsonl"
out=$(printf '{"transcript_path":"%s","session_id":"sid","trigger":"auto"}' \
  "$box/projects/-tmp-slug/s.jsonl" | CLAUDE_PROJECT_DIR="$box" bash "$HOOK" 2>/dev/null)
assert_exit "exit code" 0 $?
assert_no_file "アーカイブなし" "$box/archive/*/*.jsonl"
rm -rf "$box"

# テスト 10: trigger 欠損 → "unknown" として命名
echo "Test 10: trigger 欠損時のフォールバック"
box="$(make_sandbox true)"
out=$(printf '{"transcript_path":"%s","session_id":"sid-only"}' \
  "$box/projects/-tmp-slug/session-1.jsonl" \
  | CLAUDE_PROJECT_DIR="$box" bash "$HOOK" 2>/dev/null)
assert_exit "exit code" 0 $?
if ls "$box/archive/-tmp-slug/"*-unknown-sid-only.jsonl >/dev/null 2>&1; then
  echo "  PASS: trigger=unknown フォールバック"
  PASS=$((PASS + 1))
else
  echo "  FAIL: trigger のフォールバック失敗"
  FAIL=$((FAIL + 1))
fi
rm -rf "$box"

# テスト 11: session_id 欠損 → "nosid" として命名
echo "Test 11: session_id 欠損時のフォールバック"
box="$(make_sandbox true)"
out=$(printf '{"transcript_path":"%s","trigger":"manual"}' \
  "$box/projects/-tmp-slug/session-1.jsonl" \
  | CLAUDE_PROJECT_DIR="$box" bash "$HOOK" 2>/dev/null)
assert_exit "exit code" 0 $?
if ls "$box/archive/-tmp-slug/"*-manual-nosid.jsonl >/dev/null 2>&1; then
  echo "  PASS: session_id=nosid フォールバック"
  PASS=$((PASS + 1))
else
  echo "  FAIL: session_id のフォールバック失敗"
  FAIL=$((FAIL + 1))
fi
rm -rf "$box"

# テスト 12: max_generations = 0 → 掃除なし（無限保存モード）
echo "Test 12: max_generations = 0（掃除なし）"
box="$(make_sandbox true 0)"
for i in 1 2 3 4 5; do
  echo "{\"n\":$i}" > "$box/projects/-tmp-slug/s${i}.jsonl"
  fire_hook "$box" "$box/projects/-tmp-slug/s${i}.jsonl" "sid-$i" "auto"
done
count=$(ls -1 "$box/archive/-tmp-slug/"*.jsonl 2>/dev/null | wc -l | tr -d ' ')
assert_count "掃除なしで全世代保持" 5 "$count"
rm -rf "$box"

# テスト 13: 値に "=" を含む archive_dir が切り詰められない（code-review Warning 1）
echo 'Test 13: archive_dir 値の等号保護'
box="$(mktemp -d)"
mkdir -p "$box/.claude/addf" "$box/projects/-tmp-slug"
weird="$box/arc=dir"  # 値に "=" を含むパス
cat > "$box/.claude/addf/Behavior.toml" <<EOF
[transcript-archive]
enable = true
archive_dir = "$weird"
max_generations = 10
EOF
echo '{}' > "$box/projects/-tmp-slug/s.jsonl"
fire_hook "$box" "$box/projects/-tmp-slug/s.jsonl" "sid" "auto"
if compgen -G "$weird/-tmp-slug/*.jsonl" > /dev/null; then
  echo '  PASS: "=" を含む archive_dir に正しく書き込み'
  PASS=$((PASS + 1))
else
  echo '  FAIL: "=" を含む archive_dir が切り詰められた'
  FAIL=$((FAIL + 1))
fi
rm -rf "$box"

# テスト 14: 同一秒内の命名衝突でデータロスしない（code-review Warning 2）
echo "Test 14: 同一秒発火でデータロスしない"
box="$(make_sandbox true)"
echo '{"n":1}' > "$box/projects/-tmp-slug/s1.jsonl"
echo '{"n":2}' > "$box/projects/-tmp-slug/s2.jsonl"
# 同一 session_id・同一 trigger で連続発火（TS は同一秒になる可能性が高い）
fire_hook "$box" "$box/projects/-tmp-slug/s1.jsonl" "same-sid" "auto"
fire_hook "$box" "$box/projects/-tmp-slug/s2.jsonl" "same-sid" "auto"
count=$(ls -1 "$box/archive/-tmp-slug/"*.jsonl 2>/dev/null | wc -l | tr -d ' ')
assert_count "2件のアーカイブが両方残る" 2 "$count"
# 中身が両方保存されているか（`{"n":1}` と `{"n":2}` の両方が別ファイルにある）
if grep -l '"n":1' "$box/archive/-tmp-slug/"*.jsonl >/dev/null 2>&1 \
   && grep -l '"n":2' "$box/archive/-tmp-slug/"*.jsonl >/dev/null 2>&1; then
  echo "  PASS: 両世代の内容が保存されている"
  PASS=$((PASS + 1))
else
  echo "  FAIL: 一方の内容が上書きで失われた"
  FAIL=$((FAIL + 1))
fi
rm -rf "$box"

# テスト 15: session_id / trigger のパストラバーサル対策（code-review Warning 3）
echo "Test 15: session_id / trigger のサニタイズ"
set +u  # basename との相互作用で unbound を出す bash 3.2 の癖を回避
box="$(make_sandbox true)"
# ".." を含む session_id — サニタイズで "_" に置換されるはず
fire_hook "$box" "$box/projects/-tmp-slug/session-1.jsonl" "../../etc/evil" "au/to"
# archive_dir 外に書かれていないこと
if ! compgen -G "$box/../*.jsonl" > /dev/null 2>&1 \
   && ! compgen -G "$box/etc/*" > /dev/null 2>&1; then
  echo "  PASS: archive_dir 外への書き込みなし"
  PASS=$((PASS + 1))
else
  echo "  FAIL: archive_dir 外に書き込まれた"
  FAIL=$((FAIL + 1))
fi
# 生成されたファイル名に ".." "/" が残っていないこと
listing=$(ls "$box/archive/-tmp-slug/" 2>/dev/null)
if [ -n "$listing" ]; then
  bad=$(echo "$listing" | grep -c '\.\.' || true)
  if [ "$bad" -eq 0 ]; then
    echo "  PASS: ファイル名にトラバーサル文字が残らない"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: サニタイズ漏れ（.. 残存）: $listing"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  FAIL: アーカイブファイルが生成されていない"
  FAIL=$((FAIL + 1))
fi
rm -rf "$box"
set -u

# テスト 16: jq 不在時の sed フォールバック（code-review Suggestion 4）
echo "Test 16: jq 不在時の sed フォールバック"
box="$(make_sandbox true)"
# PATH を絞って jq を意図的に落とす（cat / awk / sed / date / mkdir / cp / ls / basename / dirname / tr / cut は必要）
minimal_bin=$(mktemp -d)
# 必要な組み込みバイナリを minimal_bin に symlink（which で場所を特定）
for cmd in cat awk sed date mkdir cp ls basename dirname tr cut printf grep head wc rm mv touch chmod; do
  target=$(command -v "$cmd" 2>/dev/null) && ln -sf "$target" "$minimal_bin/$cmd" 2>/dev/null || true
done
# jq を含まない minimal PATH でフック実行
out=$(PATH="$minimal_bin" printf '{"transcript_path":"%s","session_id":"sid-nojq","trigger":"manual"}' \
  "$box/projects/-tmp-slug/session-1.jsonl" | CLAUDE_PROJECT_DIR="$box" bash "$HOOK" 2>/dev/null)
assert_exit "jq 不在で exit 0" 0 $?
if ls "$box/archive/-tmp-slug/"*-manual-sid-nojq.jsonl >/dev/null 2>&1; then
  echo "  PASS: sed フォールバック経路でアーカイブ生成"
  PASS=$((PASS + 1))
else
  echo "  FAIL: sed フォールバックが機能しない"
  FAIL=$((FAIL + 1))
fi
rm -rf "$box" "$minimal_bin"

# テスト 17: 世代掃除のスラグ分離（code-review Suggestion 5）
echo "Test 17: スラグ分離 — 他プロジェクトの世代を巻き添えにしない"
box="$(make_sandbox true 2)"  # max=2 で意図的に超過させる
mkdir -p "$box/projects/-project-a" "$box/projects/-project-b"
# project-b に触らないアーカイブを2件用意
echo '{"p":"b1"}' > "$box/projects/-project-b/s1.jsonl"
echo '{"p":"b2"}' > "$box/projects/-project-b/s2.jsonl"
fire_hook "$box" "$box/projects/-project-b/s1.jsonl" "b-sid-1" "auto"
fire_hook "$box" "$box/projects/-project-b/s2.jsonl" "b-sid-2" "auto"
b_before=$(ls -1 "$box/archive/-project-b/"*.jsonl 2>/dev/null | wc -l | tr -d ' ')
# project-a に4件アーカイブして掃除発動（max=2 なので2件残る）
for i in 1 2 3 4; do
  echo "{\"n\":$i}" > "$box/projects/-project-a/s${i}.jsonl"
  fire_hook "$box" "$box/projects/-project-a/s${i}.jsonl" "a-sid-$i" "auto"
done
b_after=$(ls -1 "$box/archive/-project-b/"*.jsonl 2>/dev/null | wc -l | tr -d ' ')
a_after=$(ls -1 "$box/archive/-project-a/"*.jsonl 2>/dev/null | wc -l | tr -d ' ')
assert_count "project-a は max=2 で掃除" 2 "$a_after"
assert_count "project-b は無傷" "$b_before" "$b_after"
rm -rf "$box"

# テスト 18: jq 経路の空文字列 trigger のフォールバック（code-review Suggestion 6）
echo "Test 18: trigger 空文字列のフォールバック（jq/sed 共通）"
box="$(make_sandbox true)"
out=$(printf '{"transcript_path":"%s","session_id":"sid","trigger":""}' \
  "$box/projects/-tmp-slug/session-1.jsonl" \
  | CLAUDE_PROJECT_DIR="$box" bash "$HOOK" 2>/dev/null)
assert_exit "空 trigger で exit 0" 0 $?
if ls "$box/archive/-tmp-slug/"*-unknown-sid.jsonl >/dev/null 2>&1; then
  echo "  PASS: 空文字列 trigger も unknown に正規化"
  PASS=$((PASS + 1))
else
  echo "  FAIL: 空文字列 trigger のフォールバック失敗"
  FAIL=$((FAIL + 1))
fi
rm -rf "$box"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
