#!/bin/bash
# test-run-lint.sh
# .github/scripts/run-lint.sh（CI の exit code 3値マッピングラッパー）を mktemp フィクスチャで検証する。
# 検査対象は ADDF 本体固有（.github/ はダウンストリームに配布されない）のため、
# スクリプト不在の環境では SKIP を明示して exit 0 する（配布先で誤 FAIL を出さない）。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
RUNLINT="$REPO_ROOT/.github/scripts/run-lint.sh"
PASS=0
FAIL=0

echo "=== test-run-lint.sh ==="

if [ ! -f "$RUNLINT" ]; then
  echo "  SKIP: .github/scripts/run-lint.sh がありません（ADDF 本体固有。ダウンストリームでは検査対象外）"
  echo "Results: 0 passed, 0 failed, 1 skipped"
  exit 0
fi

# run-lint.sh は uv 前提（CI では setup-uv が導入する）。必須ランタイムの不在は
# SKIP=成功にしない（run-all.sh の設計ガイドライン準拠）
if ! command -v uv >/dev/null 2>&1; then
  echo "  FAIL: uv が必要（インストールしてから再実行）"
  echo "Results: 0 passed, 1 failed"
  exit 1
fi

check() {
  local desc="$1" expected_exit="$2" actual_exit="$3" output="$4" expected_grep="${5:-}"
  if [ "$actual_exit" -ne "$expected_exit" ]; then
    echo "  FAIL: $desc (exit: expected=$expected_exit actual=$actual_exit)"
    echo "$output" | sed 's/^/    | /'
    FAIL=$((FAIL + 1))
    return
  fi
  if [ -n "$expected_grep" ] && ! grep -qF "$expected_grep" <<<"$output"; then
    echo "  FAIL: $desc (出力に '$expected_grep' が見つからない)"
    echo "$output" | sed 's/^/    | /'
    FAIL=$((FAIL + 1))
    return
  fi
  echo "  PASS: $desc"
  PASS=$((PASS + 1))
}

box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT

# フィクスチャ: exit code 3値＋攻撃入力を模した擬似 lint スクリプト
printf 'print("OK")\n' > "$box/ok.py"
printf 'import sys\nprint("WARNING: dummy warning")\nsys.exit(2)\n' > "$box/warn.py"
printf 'import sys\nprint("ERROR: dummy error")\nsys.exit(1)\n' > "$box/err.py"
printf 'import sys\nprint("::error::injected")\nprint("::warning::also injected")\nsys.exit(2)\n' > "$box/inject.py"
printf 'import sys\nprint("W" * 6000)\nsys.exit(2)\n' > "$box/huge.py"
printf 'import sys\nprint("error: Failed to spawn: dummy")\nsys.exit(2)\n' > "$box/spawnfail.py"

echo "Test 1: exit 0 → 素通し（annotation なし・exit 0）"
out="$(bash "$RUNLINT" "$box/ok.py")"; code=$?
check "exit 0 で成功" 0 "$code" "$out" "OK"
if grep -qE '^::(warning|error)' <<<"$out"; then
  echo "  FAIL: exit 0 なのに annotation が出ている"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: exit 0 で annotation なし"
  PASS=$((PASS + 1))
fi

echo "Test 2: exit 2 → ::warning:: annotation + exit 0"
out="$(bash "$RUNLINT" "$box/warn.py")"; code=$?
check "exit 2 で通過" 0 "$code" "$out" "::warning title=warn.py exited 2 (WARNING)::"

echo "Test 3: exit 1 → ::error:: annotation + exit 1"
out="$(bash "$RUNLINT" "$box/err.py")"; code=$?
check "exit 1 でジョブ失敗" 1 "$code" "$out" "::error title=err.py exited 1::"

echo "Test 4: スクリプト不在 → ::error:: + exit 1（silent green を防ぐ — C1）"
out="$(bash "$RUNLINT" "$box/no-such-lint.py")"; code=$?
check "不在スクリプトで ERROR" 1 "$code" "$out" "lint スクリプトが見つかりません"

echo "Test 5: 行頭 :: 注入が ::stop-commands:: でブラケットされる（C2）"
out="$(bash "$RUNLINT" "$box/inject.py")"; code=$?
stop_line="$(grep -nm1 '^::stop-commands::' <<<"$out" | cut -d: -f1)"
inject_line="$(grep -nm1 '^::error::injected' <<<"$out" | cut -d: -f1)"
token="$(grep -m1 '^::stop-commands::' <<<"$out" | sed 's/^::stop-commands:://')"
resume_line="$(grep -nm1 "^::${token}::\$" <<<"$out" | cut -d: -f1)"
if [ -n "$stop_line" ] && [ -n "$inject_line" ] && [ -n "$resume_line" ] \
  && [ "$stop_line" -lt "$inject_line" ] && [ "$inject_line" -lt "$resume_line" ]; then
  echo "  PASS: 注入行が stop-commands（$stop_line 行目）〜 resume（$resume_line 行目）の間にある"
  PASS=$((PASS + 1))
else
  echo "  FAIL: 注入行がブラケットされていない (stop=$stop_line inject=$inject_line resume=$resume_line)"
  echo "$out" | sed 's/^/    | /'
  FAIL=$((FAIL + 1))
fi
check "注入スクリプト自体は exit 2 として通過" 0 "$code" "$out"

echo "Test 6: 巨大出力（6000字）→ annotation が 4000 字で切り詰められる（W5）"
out="$(bash "$RUNLINT" "$box/huge.py")"; code=$?
check "巨大 WARNING で通過＋truncated 付記" 0 "$code" "$out" "...(truncated — 全文はステップログ参照)"
annot_line="$(grep -m1 '^::warning title=huge.py' <<<"$out")"
if [ "${#annot_line}" -lt 6000 ]; then
  echo "  PASS: annotation 行が切り詰められている（${#annot_line} 字）"
  PASS=$((PASS + 1))
else
  echo "  FAIL: annotation 行が切り詰められていない（${#annot_line} 字）"
  FAIL=$((FAIL + 1))
fi

echo "Test 7: exit 2 + spawn 失敗痕跡 → ERROR に昇格（C1）"
out="$(bash "$RUNLINT" "$box/spawnfail.py")"; code=$?
check "Failed to spawn 痕跡で exit 1 に昇格" 1 "$code" "$out" "uv の起動失敗（Failed to spawn）を検出しました"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
