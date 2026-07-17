#!/bin/bash
# test-optional-skills.sh
# sync-optional-skills.py のオプショナルスキル同期テスト。
# 実リポジトリでの正常系と、サンドボックスでの配置・撤去・改変保護を検証する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SYNC="$PROJECT_DIR/.claude/addf/addfTools/sync-optional-skills.py"
PASS=0
FAIL=0

if command -v uv >/dev/null 2>&1; then
  run_sync() { local d="$1"; shift; (cd "$d" && uv run --python 3.11 "$SYNC" "$@" 2>&1); }
else
  run_sync() { local d="$1"; shift; (cd "$d" && python3 "$SYNC" "$@" 2>&1); }
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

make_sandbox() {
  local box enable="$1"
  box="$(mktemp -d)"
  mkdir -p "$box/.claude/addf/optional/commands" "$box/.claude/addf/optional/agents" \
           "$box/.claude/commands" "$box/.claude/agents"
  printf -- '---\nname: addf-fake-gui\ndescription: fake\n---\n\n# fake skill\n' \
    > "$box/.claude/addf/optional/commands/addf-fake-gui.md"
  printf -- '---\nname: addf-fake-agent\ndescription: fake\n---\n\n# fake agent\n' \
    > "$box/.claude/addf/optional/agents/addf-fake-agent.md"
  printf '[gui-test]\nenable = %s\n' "$enable" > "$box/.claude/addf/Behavior.toml"
  echo "$box"
}

echo "=== test-optional-skills.sh ==="

# テスト 1: 実リポジトリで整合（enable の状態と実体が一致していること）
# ここが FAIL したら sync-optional-skills.py apply で整合させる
echo "Test 1: 実リポジトリで OK"
output=$(run_sync "$PROJECT_DIR")
assert_exit "実リポジトリ" 0 $?
assert_contains "OK メッセージ" "OK: オプショナルスキル同期" "$output"

# テスト 2: enable=true で未配置 → WARNING、apply で配置 → OK
echo "Test 2: 有効化と配置"
box="$(make_sandbox true)"
output=$(run_sync "$box")
assert_exit "未配置で WARNING" 2 $?
assert_contains "未配置の特定" "未配置: .claude/commands/addf-fake-gui.md" "$output"
output=$(run_sync "$box" apply)
assert_exit "apply で配置" 0 $?
[ -f "$box/.claude/commands/addf-fake-gui.md" ] && [ -f "$box/.claude/agents/addf-fake-agent.md" ]
assert_exit "有効化コピーが存在する" 0 $?
output=$(run_sync "$box")
assert_exit "配置後の check は OK" 0 $?

# テスト 3: enable=false へ切り替え → 残存 WARNING、apply で撤去 → OK
echo "Test 3: 無効化と撤去"
printf '[gui-test]\nenable = false\n' > "$box/.claude/addf/Behavior.toml"
output=$(run_sync "$box")
assert_exit "残存で WARNING" 2 $?
output=$(run_sync "$box" apply)
assert_exit "apply で撤去" 0 $?
[ ! -f "$box/.claude/commands/addf-fake-gui.md" ]
assert_exit "有効化コピーが撤去された" 0 $?
rm -rf "$box"

# テスト 4: 改変された有効化コピーは apply でも削除・上書きしない（保護の要）
echo "Test 4: 改変保護"
box="$(make_sandbox true)"
run_sync "$box" apply >/dev/null
echo "ローカルで直接編集された行" >> "$box/.claude/commands/addf-fake-gui.md"
# enable=true のまま: 原本と異なる → 上書きせず WARNING
output=$(run_sync "$box" apply)
assert_exit "有効時の差分は上書きしない" 2 $?
assert_contains "差分の報告" "差分: .claude/commands/addf-fake-gui.md" "$output"
grep -q "ローカルで直接編集された行" "$box/.claude/commands/addf-fake-gui.md"
assert_exit "編集内容が保持されている" 0 $?
# enable=false に切り替え: 改変ありコピーは削除しない
printf '[gui-test]\nenable = false\n' > "$box/.claude/addf/Behavior.toml"
output=$(run_sync "$box" apply)
assert_exit "無効時も改変コピーは削除しない" 2 $?
assert_contains "改変保護の報告" "残存(改変あり)" "$output"
[ -f "$box/.claude/commands/addf-fake-gui.md" ]
assert_exit "改変コピーが残っている" 0 $?
rm -rf "$box"

# テスト 5: .claude/addf/optional/ が無い環境 → SKIP で exit=0
echo "Test 5: optional 不在時の SKIP"
box="$(mktemp -d)"
mkdir -p "$box/.claude/addf"
output=$(run_sync "$box")
assert_exit "optional 不在で OK" 0 $?
assert_contains "SKIP 表示" "SKIP: .claude/addf/optional が存在しない" "$output"
rm -rf "$box"

# テスト 6: Behavior.toml の構文エラー → SKIP (exit=0)、enable の型不正 → ERROR (exit=1)
echo "Test 6: 設定不正の扱い"
box="$(make_sandbox true)"
printf '[gui-test\nenable = true\n' > "$box/.claude/addf/Behavior.toml"
output=$(run_sync "$box")
assert_exit "構文エラーは SKIP" 0 $?
assert_contains "lint-toml への責務分離の案内" "lint-toml.py" "$output"
printf '[gui-test]\nenable = "false"\n' > "$box/.claude/addf/Behavior.toml"
output=$(run_sync "$box")
assert_exit "クオート付き文字列は ERROR" 1 $?
assert_contains "型不正の説明" "真偽値である必要がある" "$output"
rm -rf "$box"

# テスト 7: gitignore 列挙漏れと孤児コピーの検出
echo "Test 7: gitignore 整合（列挙漏れ・孤立）"
box="$(make_sandbox false)"
# ADDF ブロックに commands 側のみ列挙（agents 側は列挙漏れ）＋ 原本の無い孤児を仕込む
cat > "$box/.gitignore" <<'EOF'
# --- ADDF Framework (do not remove) ---
.claude/commands/addf-fake-gui.md
.claude/commands/addf-renamed-away.md
# --- /ADDF Framework ---
EOF
printf '# 原本を失った有効化コピー\n' > "$box/.claude/commands/addf-renamed-away.md"
output=$(run_sync "$box")
assert_exit "不整合で WARNING" 2 $?
assert_contains "列挙漏れの特定" "gitignore 列挙漏れ: .claude/agents/addf-fake-agent.md" "$output"
assert_contains "孤児の特定" "孤立: .claude/commands/addf-renamed-away.md" "$output"
rm -rf "$box"

# テスト 8: tomllib が無い環境（旧 Python） → check は SKIP (exit=0)、apply は ERROR (exit=1)
echo "Test 8: tomllib 欠如時のガード"
box="$(make_sandbox true)"
# PYTHONPATH シムで ModuleNotFoundError を注入し、旧 Python（3.9 等）を再現する
shim="$(mktemp -d)"
printf 'raise ModuleNotFoundError("No module named '"'"'tomllib'"'"'")\n' > "$shim/tomllib.py"
output=$( (cd "$box" && PYTHONPATH="$shim" python3 "$SYNC" 2>&1) )
assert_exit "check は SKIP" 0 $?
assert_contains "SKIP 案内" "SKIP: tomllib がありません" "$output"
output=$( (cd "$box" && PYTHONPATH="$shim" python3 "$SYNC" apply 2>&1) )
assert_exit "apply は ERROR（成功を装わない）" 1 $?
assert_contains "ERROR 案内" "ERROR: tomllib がありません" "$output"
rm -rf "$shim" "$box"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
