#!/bin/bash
# test-lint-frontmatter.sh
# lint-frontmatter.py の frontmatter 検査と pyyaml 欠如ガードを mktemp サンドボックスで検証する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$(cd "$SCRIPT_DIR/../.." && pwd)/addfTools/lint-frontmatter.py"
PASS=0
FAIL=0

# pyyaml（PEP 723 依存）前提のため uv があれば 3.11 を明示する（test-lint-toml.sh と同パターン）
if command -v uv >/dev/null 2>&1; then
  run_lint() { (cd "$1" && uv run --python 3.11 "$LINT" 2>&1); }
else
  run_lint() { (cd "$1" && python3 "$LINT" 2>&1); }
fi

check() {
  local desc="$1" expected_exit="$2" actual_exit="$3" output="$4" expected_grep="${5:-}"
  if [ "$actual_exit" -ne "$expected_exit" ]; then
    echo "  FAIL: $desc (exit: expected=$expected_exit actual=$actual_exit)"
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

echo "=== test-lint-frontmatter.sh ==="

box="$(mktemp -d)"
trap 'rm -rf "$box"' EXIT
mkdir -p "$box/.claude/commands"

echo "Test 1: 正常な frontmatter → exit 0"
cat > "$box/.claude/commands/addf-sample.md" <<'EOF'
---
name: addf-sample
description: サンドボックス検証用のサンプルスキル
---

# addf-sample
EOF
out="$(run_lint "$box")"; code=$?
check "正常 frontmatter で OK" 0 "$code" "$out"

echo "Test 2: description フィールド欠落 → exit 1"
cat > "$box/.claude/commands/addf-broken.md" <<'EOF'
---
name: addf-broken
---

# addf-broken
EOF
out="$(run_lint "$box")"; code=$?
check "description 欠落を検出" 1 "$code" "$out" "description フィールドなし"
rm -f "$box/.claude/commands/addf-broken.md"

echo "Test 3: pyyaml が無い環境 → SKIP・exit 0（受動的 lint は配布先で誤 ERROR を出さない）"
# PYTHONPATH シムで ModuleNotFoundError を注入し、pyyaml 未導入の python3 直接実行を再現する
shim="$(mktemp -d)"
printf 'raise ModuleNotFoundError("No module named '"'"'yaml'"'"'")\n' > "$shim/yaml.py"
out="$( (cd "$box" && PYTHONPATH="$shim" python3 "$LINT" 2>&1) )"; code=$?
check "pyyaml 欠如で SKIP" 0 "$code" "$out" "SKIP: pyyaml がありません"
rm -rf "$shim"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
