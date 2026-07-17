#!/bin/bash
# test-context-reminder.sh
# context-reminder.py のテスト。偽の transcript・Behavior.toml をサンドボックスに
# 用意し、実測トークン量に応じた事実注入・再通知抑制・リセット・SKIP を検証する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
TOOL="$PROJECT_DIR/.claude/addf/addfTools/context-reminder.py"
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

assert_empty() {
  local test_name="$1" stdout="$2"
  if [ -z "$stdout" ]; then
    echo "  PASS: $test_name (output empty)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (expected empty, got: $stdout)"
    FAIL=$((FAIL + 1))
  fi
}

# サンドボックス: Behavior.toml（閾値 100k・目安 opus=200k）と transcript を作る
make_sandbox() {
  local box
  box="$(mktemp -d)"
  mkdir -p "$box/.claude/addf"
  cat > "$box/.claude/addf/Behavior.toml" <<'EOF'
[context-reminder]
threshold_tokens = 100000
renotify_step_tokens = 50000

[context-reminder.effective-context]
opus = 200000
EOF
  echo "$box"
}

# usage 合算が $1 トークンの transcript を $2 に書く（モデルは $3）
# 制約: $1 は 102 以上（cache_read = total - 102 が負にならない範囲）で指定する
write_transcript() {
  local total="$1" path="$2" model="${3:-claude-opus-4-8}"
  cat > "$path" <<EOF
{"type":"user","message":{"content":"hi"}}
{"type":"assistant","isSidechain":true,"message":{"model":"$model","usage":{"input_tokens":999999,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
{"type":"assistant","message":{"model":"$model","usage":{"input_tokens":2,"cache_read_input_tokens":$((total - 102)),"cache_creation_input_tokens":100}}}
EOF
}

run_tool() {  # $1=box $2=transcript
  printf '{"transcript_path":"%s"}' "$2" | CLAUDE_PROJECT_DIR="$1" python3 "$TOOL" 2>/dev/null
}

echo "=== test-context-reminder.sh ==="

# テスト 1: 閾値未満 → 出力なし
echo "Test 1: 閾値未満（50k < 100k）"
box="$(make_sandbox)"
write_transcript 50000 "$box/t.jsonl"
out=$(run_tool "$box" "$box/t.jsonl")
assert_exit "exit code" 0 $?
assert_empty "閾値未満は沈黙" "$out"
rm -rf "$box"

# テスト 2: 閾値超過 → 実測値・目安・安心文を注入（直近エントリ採用・sidechain 除外も兼ねる）
echo "Test 2: 閾値超過（150k > 100k）"
box="$(make_sandbox)"
write_transcript 150000 "$box/t.jsonl"
out=$(run_tool "$box" "$box/t.jsonl")
assert_exit "exit code" 0 $?
assert_contains "実測値の注入" "約 150,000 トークン" "$out"
assert_contains "モデル名の注入" "claude-opus-4-8" "$out"
assert_contains "モデル別目安の注入" "約 200,000 トークン" "$out"
assert_contains "安心文" "作業を縮小・切り上げる指示ではない" "$out"
# Plan 0041: 「満杯時の出口」教義 — 止まらないことの行動指針が入る
assert_contains "止まらない教義" "止まらないこと" "$out"
assert_contains "harness と復帰フックの役割分担" "compaction を起こすのは harness の" "$out"
rm -rf "$box"

# テスト 3: 再通知抑制 — 通知後、増分が renotify_step 未満なら沈黙、超えたら再通知
echo "Test 3: 再通知抑制と増分再通知"
box="$(make_sandbox)"
write_transcript 150000 "$box/t.jsonl"
run_tool "$box" "$box/t.jsonl" > /dev/null
write_transcript 170000 "$box/t.jsonl"
out=$(run_tool "$box" "$box/t.jsonl")
assert_empty "増分 20k < 50k は沈黙" "$out"
write_transcript 210000 "$box/t.jsonl"
out=$(run_tool "$box" "$box/t.jsonl")
assert_contains "増分 60k >= 50k で再通知" "約 210,000 トークン" "$out"
rm -rf "$box"

# テスト 4: コンパクション後（実測値が前回通知より減少）→ 状態リセットして沈黙
echo "Test 4: コンパクション後の状態リセット"
box="$(make_sandbox)"
write_transcript 150000 "$box/t.jsonl"
run_tool "$box" "$box/t.jsonl" > /dev/null
write_transcript 40000 "$box/t.jsonl"
out=$(run_tool "$box" "$box/t.jsonl")
assert_empty "圧縮後は沈黙" "$out"
if [ ! -f "$box/.claude/.context-reminder-state" ]; then
  echo "  PASS: 状態ファイルがリセットされた"
  PASS=$((PASS + 1))
else
  echo "  FAIL: 状態ファイルが残っている"
  FAIL=$((FAIL + 1))
fi
# リセット後に再び閾値を超えたら再通知される
write_transcript 150000 "$box/t.jsonl"
out=$(run_tool "$box" "$box/t.jsonl")
assert_contains "リセット後の再通知" "約 150,000 トークン" "$out"
rm -rf "$box"

# テスト 5: 目安未設定モデル → 突き合わせ指示にフォールバック
echo "Test 5: 目安未設定モデルのフォールバック"
box="$(make_sandbox)"
write_transcript 150000 "$box/t.jsonl" "claude-fable-5"
out=$(run_tool "$box" "$box/t.jsonl")
assert_contains "フォールバック文" "目安は未設定" "$out"
rm -rf "$box"

# テスト 6: transcript 不在・hook JSON 不正 → 静かに exit 0
echo "Test 6: 取得不能時の静かな SKIP"
box="$(make_sandbox)"
out=$(printf '{"transcript_path":"%s"}' "$box/nai.jsonl" | CLAUDE_PROJECT_DIR="$box" python3 "$TOOL" 2>/dev/null)
assert_exit "transcript 不在で exit 0" 0 $?
assert_empty "transcript 不在は沈黙" "$out"
out=$(printf 'こわれたJSON' | CLAUDE_PROJECT_DIR="$box" python3 "$TOOL" 2>/dev/null)
assert_exit "不正 JSON で exit 0" 0 $?
assert_empty "不正 JSON は沈黙" "$out"
rm -rf "$box"

# テスト 7: threshold_tokens = 0 → 無効化
echo "Test 7: 設定による無効化"
box="$(make_sandbox)"
sed -i.bak 's/threshold_tokens = 100000/threshold_tokens = 0/' "$box/.claude/addf/Behavior.toml" \
  && rm -f "$box/.claude/addf/Behavior.toml.bak"
write_transcript 999000 "$box/t.jsonl"
out=$(run_tool "$box" "$box/t.jsonl")
assert_empty "無効化時は沈黙" "$out"
rm -rf "$box"

# テスト 8: フック経由の統合 — turn-reminder.sh が stdin を中継する
echo "Test 8: turn-reminder.sh 経由の統合"
box="$(make_sandbox)"
mkdir -p "$box/.claude/hooks" "$box/.claude/addf/addfTools"
cp "$PROJECT_DIR/.claude/hooks/turn-reminder.sh" "$box/.claude/hooks/"
cp "$TOOL" "$box/.claude/addf/addfTools/"
write_transcript 150000 "$box/t.jsonl"
echo "0" > "$box/.claude/.turn-count"
out=$(printf '{"transcript_path":"%s"}' "$box/t.jsonl" | CLAUDE_PROJECT_DIR="$box" bash "$box/.claude/hooks/turn-reminder.sh" 2>/dev/null)
assert_exit "フック経由で exit 0" 0 $?
assert_contains "フック経由で注入" "約 150,000 トークン" "$out"
# 関心事A（10ターン目）と関心事Bの同時発火 — 両ブロックが並んで出力される
echo "9" > "$box/.claude/.turn-count"
rm -f "$box/.claude/.context-reminder-state"
out=$(printf '{"transcript_path":"%s"}' "$box/t.jsonl" | CLAUDE_PROJECT_DIR="$box" bash "$box/.claude/hooks/turn-reminder.sh" 2>/dev/null)
assert_contains "同時発火: 関心事A" "10ターン経過" "$out"
assert_contains "同時発火: 関心事B" "約 150,000 トークン" "$out"
rm -rf "$box"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
