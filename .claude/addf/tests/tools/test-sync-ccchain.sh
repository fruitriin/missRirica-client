#!/bin/bash
# test-sync-ccchain.sh
# sync-ccchain.py（Plan 0040 フェーズ2・ccchain オプトイン配布機構）のテスト。
# 実リポジトリでの整合確認と、サンドボックスでの配置・撤去・他フック保護を検証する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SYNC_SRC="$PROJECT_DIR/.claude/addf/addfTools/sync-ccchain.py"
CONF_SRC="$PROJECT_DIR/.claude/addf/optional/ccchain/.ccchain.conf"
PASS=0
FAIL=0

if command -v uv >/dev/null 2>&1; then
  run_sync() {
    local d="$1" out code; shift
    cd "$d"; out=$(uv run --python 3.11 .claude/addf/addfTools/sync-ccchain.py "$@" 2>&1); code=$?
    cd - >/dev/null
    printf '%s' "$out"
    return "$code"
  }
else
  run_sync() {
    local d="$1" out code; shift
    cd "$d"; out=$(python3 .claude/addf/addfTools/sync-ccchain.py "$@" 2>&1); code=$?
    cd - >/dev/null
    printf '%s' "$out"
    return "$code"
  }
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
    echo "  FAIL: $test_name (output unexpectedly contained: $needle)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  fi
}

make_sandbox() {
  local box enable="$1"
  box="$(mktemp -d)"
  mkdir -p "$box/.claude/addf/optional/ccchain" "$box/.claude/addf/addfTools" "$box/.claude/hooks"
  cp "$SYNC_SRC" "$box/.claude/addf/addfTools/sync-ccchain.py"
  cp "$CONF_SRC" "$box/.claude/addf/optional/ccchain/.ccchain.conf"
  printf '[ccchain]\nenable = %s\n' "$enable" > "$box/.claude/addf/Behavior.toml"
  # destructive-git-guard.sh 相当の既存フックを持つ settings.json（ccchain 以外を壊さないか検証）
  cat > "$box/.claude/settings.json" << 'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/destructive-git-guard.sh"}
        ]
      }
    ]
  },
  "permissions": {"allow": []}
}
EOF
  echo "$box"
}

echo "=== test-sync-ccchain.sh ==="

# テスト 1: 実リポジトリで整合しているか（現状に応じて OK/WARNING いずれも許容し、exit 0/2 のみ検証）
echo "Test 1: 実リポジトリで ERROR にならない"
output=$(run_sync "$PROJECT_DIR")
code=$?
if [ "$code" -eq 0 ] || [ "$code" -eq 2 ]; then
  echo "  PASS: 実リポジトリ (exit=$code, ERROR ではない)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: 実リポジトリ (exit=$code, ERROR)"
  echo "$output" | sed 's/^/    | /'
  FAIL=$((FAIL + 1))
fi

# テスト 2: enable=true で未配置・未配線 → WARNING（バイナリ不在の WARNING も出る）
echo "Test 2: 有効化・未配置検出"
box="$(make_sandbox true)"
output=$(run_sync "$box")
assert_exit "未配置で WARNING" 2 $?
assert_contains "conf 未配置の特定" "未配置: .ccchain.conf" "$output"
assert_contains "hook 未配線の特定" "未配線:" "$output"
assert_contains "バイナリ不在の特定" "バイナリ不在" "$output"

# テスト 3: apply で配置・配線（バイナリはまだ無いので WARNING は残る）
echo "Test 3: apply で配置・配線"
output=$(run_sync "$box" apply)
assert_exit "apply 後もバイナリ不在で WARNING (exit 2)" 2 $?
[ -f "$box/.ccchain.conf" ]
assert_exit ".ccchain.conf が配置されている" 0 $?
grep -q 'ccchain hook pre' "$box/.claude/settings.json"
assert_exit "settings.json に ccchain フックが配線されている" 0 $?
grep -q 'destructive-git-guard.sh' "$box/.claude/settings.json"
assert_exit "既存の destructive-git-guard.sh フックが保持されている" 0 $?

# テスト 4: バイナリを配置すると OK になる
echo "Test 4: バイナリ配置後は OK"
touch "$box/ccchain" && chmod +x "$box/ccchain"
output=$(run_sync "$box")
assert_exit "バイナリ配置後 OK (exit 0)" 0 $?
assert_contains "OK メッセージ" "OK: ccchain 同期" "$output"

# テスト 5: .ccchain.conf を改変しても apply で上書きされない（GUI テストと違い書き換え可能前提）
echo "Test 5: 配置後の .ccchain.conf は改変してもよい（apply で上書きされない）"
echo "# my custom rule" >> "$box/.ccchain.conf"
before_hash=$(cat "$box/.ccchain.conf")
run_sync "$box" apply >/dev/null
after_hash=$(cat "$box/.ccchain.conf")
[ "$before_hash" = "$after_hash" ]
assert_exit "改変した .ccchain.conf が保持されている" 0 $?

# テスト 6: enable=false へ切り替え → 残存 WARNING、apply で hook のみ撤去（conf は残す）
echo "Test 6: 無効化と撤去（hook のみ・conf は残す設計）"
printf '[ccchain]\nenable = false\n' > "$box/.claude/addf/Behavior.toml"
output=$(run_sync "$box")
assert_exit "無効化直後は残存 WARNING" 2 $?
assert_contains "hook 残存の特定" "残存: .claude/settings.json" "$output"
assert_contains "conf 残存の特定" "残存: .ccchain.conf" "$output"
output=$(run_sync "$box" apply)
assert_contains "apply 後も conf 残存の案内は出る（自動削除しない設計）" "残存: .ccchain.conf" "$output"
grep -q 'ccchain hook pre' "$box/.claude/settings.json"
actual=$?
if [ "$actual" -ne 0 ]; then
  echo "  PASS: settings.json から ccchain フックが撤去されている"
  PASS=$((PASS + 1))
else
  echo "  FAIL: settings.json に ccchain フックが残っている"
  FAIL=$((FAIL + 1))
fi
grep -q 'destructive-git-guard.sh' "$box/.claude/settings.json"
assert_exit "撤去後も既存フックは保持されている" 0 $?
[ -f "$box/.ccchain.conf" ]
assert_exit "改変済み .ccchain.conf は自動削除されない" 0 $?

# テスト 7: .claude/addf/optional/ccchain が無い場合 SKIP
echo "Test 7: optional/ccchain 不在は SKIP"
box2="$(mktemp -d)"
mkdir -p "$box2/.claude/addf/addfTools" "$box2/.claude"
cp "$SYNC_SRC" "$box2/.claude/addf/addfTools/sync-ccchain.py"
printf '[ccchain]\nenable = true\n' > "$box2/.claude/addf/Behavior.toml"
output=$(run_sync "$box2")
assert_exit "optional/ccchain 不在で SKIP (exit 0)" 0 $?
assert_contains "SKIP メッセージ" "SKIP:" "$output"

# テスト 8: Behavior.toml 不在は SKIP
echo "Test 8: Behavior.toml 不在は SKIP"
box3="$(mktemp -d)"
mkdir -p "$box3/.claude/addf/optional/ccchain" "$box3/.claude/addf/addfTools"
cp "$SYNC_SRC" "$box3/.claude/addf/addfTools/sync-ccchain.py"
cp "$CONF_SRC" "$box3/.claude/addf/optional/ccchain/.ccchain.conf"
output=$(run_sync "$box3")
assert_exit "Behavior.toml 不在で SKIP (exit 0)" 0 $?
assert_contains "SKIP メッセージ" "SKIP:" "$output"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
