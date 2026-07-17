#!/bin/bash
# test-hooks-wiring.sh
# lint-hooks-wiring.py の hooks 配線チェックテスト。
# 実リポジトリでの正常系と、サンドボックスでの未配線検出（ドリフト注入）を検証する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
LINT="$PROJECT_DIR/.claude/addf/addfTools/lint-hooks-wiring.py"
PASS=0
FAIL=0

# tomllib 不要のためシステム python3 で動くが、テストは手順書（addf-lint.md）と対称に
# uv があれば uv run を使う
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

# サンドボックス生成: hooks 2本 + それを配線した settings.json
make_box() {
  local box
  box="$(mktemp -d)"
  mkdir -p "$box/.claude/hooks"
  printf '#!/bin/bash\nexit 0\n' > "$box/.claude/hooks/wired-a.sh"
  printf '#!/bin/bash\nexit 0\n' > "$box/.claude/hooks/wired-b.sh"
  cat > "$box/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/wired-a.sh" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Skill",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/wired-b.sh" }
        ]
      }
    ]
  }
}
EOF
  echo "$box"
}

echo "=== test-hooks-wiring.sh ==="

# テスト 1: 実リポジトリで全フック配線済み
# ここが FAIL したら settings.json の hooks 配線を確認する（意図的に外したフックなら
# lint の WARNING 方針に従い判断する）
echo "Test 1: 実リポジトリで OK"
output=$(run_lint "$PROJECT_DIR")
assert_exit "実リポジトリ" 0 $?
assert_contains "OK メッセージ" "OK: hooks 配線チェック通過" "$output"

# テスト 2: 全配線 OK（サンドボックス）
echo "Test 2: 全配線 OK"
box="$(make_box)"
output=$(run_lint "$box")
assert_exit "全配線で OK" 0 $?
assert_contains "配線数の報告" "2 フック配線済み" "$output"

# テスト 3: 未配線フック → WARNING (exit=2)（この lint が生まれた当のケースの再現:
# 手縫い導入で skill-usage-log.sh の配線を忘れかけた Issue #19）
echo "Test 3: 未配線の検出"
printf '#!/bin/bash\nexit 0\n' > "$box/.claude/hooks/unwired.sh"
output=$(run_lint "$box")
assert_exit "未配線で WARNING" 2 $?
assert_contains "対象ファイルの特定" "unwired.sh" "$output"
assert_not_contains "配線済みは報告しない" "wired-a.sh" "$output"
assert_contains "配線例への具体参照" "https://github.com/fruitriin/ADDF/blob/main/.claude/settings.json" "$output"

# テスト 4: settings.local.json での配線は有効（exit 0）だが NOTE で区別される
echo "Test 4: settings.local.json の配線"
cat > "$box/.claude/settings.local.json" <<'EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": ".claude/hooks/unwired.sh" } ] }
    ]
  }
}
EOF
output=$(run_lint "$box")
assert_exit "local 配線で OK" 0 $?
assert_contains "local 配線の NOTE" "NOTE: unwired.sh は settings.local.json 経由（他環境・CI には適用されない）" "$output"
rm -rf "$box"

# テスト 5: settings.json 不在 → SKIP で exit=0
echo "Test 5: settings.json 不在時の SKIP"
box="$(mktemp -d)"
mkdir -p "$box/.claude/hooks"
printf '#!/bin/bash\nexit 0\n' > "$box/.claude/hooks/some-hook.sh"
output=$(run_lint "$box")
assert_exit "settings.json 不在で OK" 0 $?
assert_contains "SKIP 表示" "SKIP: .claude/settings.json が存在しない" "$output"
rm -rf "$box"

# テスト 6: hooks が無い環境 → SKIP で exit=0
echo "Test 6: hooks 不在時の SKIP"
box="$(mktemp -d)"
mkdir -p "$box/.claude"
echo '{}' > "$box/.claude/settings.json"
output=$(run_lint "$box")
assert_exit "hooks 不在で OK" 0 $?
assert_contains "SKIP 表示" "SKIP: .claude/hooks/*.sh が存在しない" "$output"
rm -rf "$box"

# テスト 7: settings.json が不正 JSON → SKIP（構文検査は lint-json.py の責務）
echo "Test 7: 不正 JSON の SKIP"
box="$(mktemp -d)"
mkdir -p "$box/.claude/hooks"
printf '#!/bin/bash\nexit 0\n' > "$box/.claude/hooks/some-hook.sh"
echo '{ broken' > "$box/.claude/settings.json"
output=$(run_lint "$box")
assert_exit "不正 JSON で SKIP" 0 $?
assert_contains "責務の案内" "lint-json.py の責務" "$output"
rm -rf "$box"

# テスト 8: 部分文字列衝突ペア — 配線済み reset-turn-count.sh と未配線 count.sh
# （境界チェック回帰テスト: 素朴な部分文字列一致では count.sh が
#  reset-turn-count.sh の配線文字列に含まれ、配線済みと誤判定される）
echo "Test 8: 部分文字列衝突ペアの境界チェック"
box="$(mktemp -d)"
mkdir -p "$box/.claude/hooks"
printf '#!/bin/bash\nexit 0\n' > "$box/.claude/hooks/reset-turn-count.sh"
printf '#!/bin/bash\nexit 0\n' > "$box/.claude/hooks/count.sh"
cat > "$box/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/reset-turn-count.sh" }
        ]
      }
    ]
  }
}
EOF
output=$(run_lint "$box")
assert_exit "衝突ペアの未配線で WARNING" 2 $?
assert_contains "未配線 count.sh の検出" ".claude/hooks/count.sh" "$output"
rm -rf "$box"

# テスト 9: `# hooks-wiring: indirect` 宣言のフックは検査対象外（NOTE 表示）
echo "Test 9: indirect 宣言のエスケープハッチ"
box="$(make_box)"
printf '#!/bin/bash\n# hooks-wiring: indirect（wired-a.sh から source される）\nexit 0\n' \
  > "$box/.claude/hooks/helper.sh"
output=$(run_lint "$box")
assert_exit "indirect 宣言で OK" 0 $?
assert_contains "indirect の NOTE" "hooks-wiring: indirect" "$output"
assert_contains "対象フックの明示" "helper.sh" "$output"
rm -rf "$box"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
