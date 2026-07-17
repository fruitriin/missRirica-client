---
title: bash + awk による簡易 TOML パースの落とし穴
created: 2026-07-07
last_verified: 2026-07-07
depends_on: [sync-lint-design.md, claude-code-hooks.md]
status: active
---

# bash + awk による簡易 TOML パースの落とし穴

Plan 0042 の `.claude/hooks/pre-compact-archive.sh` 実装で、Python 依存を避けるため bash + awk で Behavior.toml をパースした際に発見した罠と対策の類型化。

## 発見した知見

### 背景 — 「Python 依存を避ける」判断は正当だが罠を伴う

sync-lint-design.md の3類型（lint=SKIP・実行前ゲート=フェイルセーフ ERROR・変更系=ERROR）では、Python 3.11+ の tomllib を使う addfTools スクリプトは責務別に環境ガードを分ける。しかしフック（`.claude/hooks/*.sh`）は**セッション毎に毎ターン発火しうる**（PreCompact フックは compaction 時のみだが、UserPromptSubmit フックは常時）ため、Python 起動コストと依存を避けたい場面が現実にある。bash + awk で最小限のパースを書く選択は正しいが、次の罠に落ちる。

### 罠1: `awk -F'='` は値に含まれる `=` を silent に切り捨てる

```awk
awk -F'=' '$1 ~ /^[[:space:]]*archive_dir[[:space:]]*$/ { print $2 }'
```

これで `archive_dir = "/tmp/arc=weird"` を読むと `/tmp/arc` になる。code-review エージェントが実際に境界ケースを試して発見した。**エラーが出ず違うパスに書き続ける**サイレントな誤動作。

**対策**: `-F'='` を使わず `index($0, "=")` で**最初の `=` だけ**で分割する:

```awk
awk '{
  idx = index($0, "=")
  if (idx == 0) next
  key = substr($0, 1, idx - 1)
  val = substr($0, idx + 1)
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
  if (key != "target_key") next
  # val の処理...
}'
```

これで後続の `=` は値の一部として保たれる。

### 罠2: コメント除去がクオート内外を区別しない

```awk
sub(/[[:space:]]*(#.*)?$/, "", val)
```

これで `archive_dir = "/tmp/my#archive"` を処理すると `/tmp/my` に切り詰められる。値の中の `#` は TOML の文字列では正当だが、素朴な正規表現はクオートを見ない。

**対策**: 完全な回避には状態機械が必要になるため、**サポート値の文字集合をスクリプトのコメントで明記する**のが現実解（フルパーサ導入は過剰）。ADDF フックでは Behavior.toml の設定値に `#` を含めるユースケースは想定しない前提を明示した。

### 罠3: セクションヘッダの行末アンカー

```awk
/^\[transcript-archive\][[:space:]]*$/ { in_section=1; next }
```

これは `[transcript-archive]  # 説明` のようにヘッダー行末に親切コメントを付けると**セクション自体を「無効」として扱う**（サイレントに `enable=false` 相当）。

**対策**: 現状の Behavior.toml では該当しないため実害はないが、コード側コメントに「セクションヘッダ行にコメントを付けないこと」の注記を残しておく。将来ヘッダにコメントを追加する誰かへの防波堤。

### 罠4: jq の `//` 演算子は空文字列を素通しする

```bash
TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "unknown"')
```

これは JSON の `trigger` が `null` または欠損なら `"unknown"` にフォールバックするが、**空文字列 `""` は truthy として素通す**。sed フォールバック側と挙動が食い違う。

**対策**: jq 抽出後に bash 側で明示チェック:

```bash
TRIGGER=$(echo "$INPUT" | jq -r '.trigger // empty')
[ -n "$TRIGGER" ] || TRIGGER="unknown"
```

`// empty` に変えることで空文字列と null/欠損を同じ「空」として扱い、bash の `-n` チェックで統一する。

### 罠5: ファイル名構成要素のサニタイズ不足

trigger / session_id / スラグを**そのまま**ファイル名に連結すると、値に `/` `..` が混ざったときにパストラバーサル可能性が生じる。ハーネス由来の値を「信頼された入力」と割り切ることもできるが、フックは**手動テスト・偽装 stdin・将来の仕様変更**にも晒される。

**対策**: ホワイトリスト方式でサニタイズ:

```bash
sanitize_path_segment() {
  # 空入力は空のまま返す（呼び出し側で :- フォールバック）
  # `.` を許可しないのは `..` の意図的な排除
  printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64
}
```

**要点**: `.` を許可すると `..` が残る。ファイル拡張子は呼び出し側でリテラル連結する運用にすれば、値側にドットが必要なケースはなくなる。長さ上限（cut -c1-64）でファイル名膨張攻撃も緩和。

### 罠6: `date` は秒精度で命名衝突を起こす

```bash
DEST_NAME="${TS}-${TRIGGER}-${SID}.jsonl"
```

`TS=$(date -u +"%Y%m%dT%H%M%SZ")` は秒精度。同一 session_id + 同一 trigger で同一 UTC 秒内に2回発火すると、`cp` が無条件上書きしてデータロス。

**対策**: 衝突時に連番サフィックスを付ける:

```bash
DEST_NAME="${BASE_NAME}.jsonl"
if [ -e "$DEST_DIR/$DEST_NAME" ]; then
  n=2
  while [ -e "$DEST_DIR/${BASE_NAME}-${n}.jsonl" ] && [ "$n" -lt 100 ]; do
    n=$((n + 1))
  done
  DEST_NAME="${BASE_NAME}-${n}.jsonl"
fi
```

`date +%N`（ナノ秒）は GNU date 拡張で macOS/BSD の date では動かないため使わない。連番方式は移植性が高い。

### 罠7: フォールバック経路のテスト不足

「jq が無ければ sed フォールバック」というコードを書いても、CI 環境で jq が常時使えるとフォールバック経路が**一度も実行されない**。code-review が明示的に指摘した。

**対策**: PATH を絞ったサブシェルでフォールバック経路を強制実行するテストを1つ入れる:

```bash
minimal_bin=$(mktemp -d)
for cmd in cat awk sed date mkdir cp ls basename dirname tr cut printf; do
  target=$(command -v "$cmd") && ln -sf "$target" "$minimal_bin/$cmd"
done
out=$(PATH="$minimal_bin" ... | bash "$HOOK")
```

`jq` を含めないことでフォールバックを踏ませられる。

### 罠8: macOS bash 3.2 の `set -uo pipefail` と `basename` の相互作用

Test 15（サニタイズ検証テスト）を書いた際、`fname=$(basename -- "$f")` の後の `case "$fname" in ...` で `fname: unbound variable` が出た。ロジック上は `fname` が必ず定義されるはずだが、macOS の bash 3.2 では set -u と command substitution の組み合わせで unbound を偽陽性で出すことがある。

**対策**: 該当テストブロックだけ `set +u ... set -u` で囲むか、`case` の代わりに `grep -q` を使う（stdin 経由なので変数展開の罠を避けられる）。ADDF 全体では bash 3.2 互換を優先しつつ、set -u は必要な範囲で使う。

## プロジェクトへの適用

- ADDF のフックで Behavior.toml を bash から読むケース（PreCompact / 将来の PostToolUse 等）で本知見を適用する
- lint 側（`.claude/addf/addfTools/lint-*.py`）は Python + tomllib を使うため本知見は不要 — Python の TOML パーサを使え
- 罠5（サニタイズ）はフックに限らず「ファイル名に外部値を連結する全ての場面」で適用可能

## 参照

- [Plan 0042: PreCompact トランスクリプトアーカイブ](../../plans-add/0042-precompact-transcript-archive.md) — 本知見の出自
- 関連 knowhow: [sync-lint-design.md](sync-lint-design.md) — Python 実行環境ガードの3類型（本知見は「Python を避ける」場面の補完）
- 関連 knowhow: [claude-code-hooks.md](claude-code-hooks.md) — フックの共通作法（set -e 非使用・exit 0・CLAUDE_PROJECT_DIR フォールバック）
