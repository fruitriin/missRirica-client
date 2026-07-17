---
title: PreToolUse ブロックフックの設計パターン — 根拠提示型ガード
created: 2026-03-19
last_verified: 2026-07-06
depends_on: []
status: active
---

# PreToolUse ブロックフックの設計パターン — 根拠提示型ガード

## 発見した知見

### パターン概要

PreToolUse フックでツール呼び出しをブロックする際、**事実（何がダメか）ではなく根拠（なぜダメか）を reason に含める**ことで、エージェントが自律的に代替手段を選択できるようになる。

### 具体例: `/tmp/` 使用のブロック

マシングローバルの `/tmp/` を使うと、カレントディレクトリより上位のパスへのアクセスとなり、Claude Code の権限要求ダイアログが発生する。プロジェクトルートの `tmp/` を使えばこの問題を回避できる。

**実装例** (`check-tmp.py`):
```python
"""PreToolUse hook: block writes to system temp directory."""
import sys, json, re

event = json.load(sys.stdin)
tool = event.get("tool_name", "")
input_data = event.get("tool_input", {})

# .md ファイルはポリシー記述自体が言及するため除外
file_path = input_data.get("file_path", "")
if file_path.endswith(".md"):
    print(json.dumps({"decision": "approve"}))
    sys.exit(0)

text = ""
if tool == "Bash":
    text = input_data.get("command", "")
elif tool == "Write":
    text = input_data.get("file_path", "") + " " + input_data.get("content", "")
elif tool == "Edit":
    text = input_data.get("file_path", "") + " " + input_data.get("new_string", "")

# パターンを動的構築（hook 自身がブロックされるのを防ぐ）
sys_tmp = "/" + "tmp" + "/"
temp_dir_fn = "std::env::temp_" + "dir"

if re.search(r"(?<![./a-zA-Z0-9_-])" + re.escape(sys_tmp), text) or temp_dir_fn in text:
    msg = (
        "マシングローバルの " + sys_tmp + " を使わないでください。"
        + "プロジェクトルート直下の tmp/ に書き出してください。"
        + "CLAUDE.local.md「一時ファイル方針」を参照。"
    )
    print(json.dumps({"decision": "block", "reason": msg}))
else:
    print(json.dumps({"decision": "approve"}))
```

**設計上のポイント:**
- `.md` ファイルは除外（ポリシー記述自体が `/tmp/` を言及するため）
- 検出パターンを文字列結合で動的構築（フック自身のソースがブロック対象にならないよう）
- `decision: "block"` + `reason` で JSON 応答（exit 2 の stderr ではなく exit 0 + JSON）

### `CLAUDE_CODE_TMPDIR` 環境変数

Claude Code v2.1.4 以降で導入された環境変数。Claude Code 内部が使う一時ディレクトリのパスを上書きできる。

```bash
export CLAUDE_CODE_TMPDIR=/path/to/custom/tmp
```

- 未設定時はシステムデフォルト（`/tmp`）を使用
- コンテナ環境・権限制約環境・セキュリティポリシーで `/tmp` が使えない場合に有用
- ただしこれは **Claude Code 内部** の一時ファイルの話であり、エージェントがコード内で生成する一時ファイルとは別。エージェントの一時ファイル生成は PreToolUse フックでガードする必要がある

### 根拠提示型ブロックのパターン

| 要素 | 事実提示（非推奨） | 根拠提示（推奨） |
|---|---|---|
| reason の内容 | `/tmp/ は使用禁止です` | `カレントより上のディレクトリアクセスで権限要求が発生するため、プロジェクトルートの tmp/ を使ってください` |
| エージェントの反応 | 何をすべきか分からず再試行・質問 | 代替手段を自律的に選択できる |

### 横展開可能なガードパターン

同じ「根拠提示型 PreToolUse ブロック」パターンは以下のユースケースに横展開できる:

1. **`cd` の上方向ディレクトリ突き抜け防止** — プロジェクトルートより上に `cd` しようとする操作をブロックし、「プロジェクトルート外へのアクセスは権限要求を引き起こすため、プロジェクト内で完結してください」と根拠を提示
2. **特定ブランチへの直接 push 防止** — `git push origin main` をブロックし、「PR 経由でマージしてください。理由: レビュープロセスの担保」と根拠を提示
3. **機密ファイルの読み取り防止** — `.env` や credentials ファイルへのアクセスをブロックし、「環境変数経由で取得してください。理由: シークレットのコンテキスト混入防止」と根拠を提示
4. **大容量ファイルの Write 防止** — 巨大なバイナリやログの書き出しをブロックし、「ストリーミング処理に切り替えてください。理由: メモリ消費の抑制」と根拠を提示
5. **Bash での sed/awk による置換防止** — BulkEdit 失敗後に `sed` や `awk` にフォールバックする Bash コマンドをブロックし、「sed は正規表現ベースで意図しない置換が起きうるため、Edit ツールの exact match を使ってください。BulkEdit が失敗した場合は個別の Edit 呼び出しに分割してください」と根拠を提示。組み込みツールより劣る手段への退行を防ぐパターン

> **アイデア: `addfReplace` ツール** — 正規表現インターフェースを意図的に省いたリテラル一括置換ツール。Edit は1箇所の exact match、sed は正規表現で強力すぎるという隙間を埋める。BulkEdit 失敗時の安全なフォールバック先として `addfReplace file.txt 'old' 'new'` や `--pairs replacements.json` で複数ペア一括置換を想定。正規表現を持たないことがこのツールの価値なので `--regex` フラグを追加しないこと。

## プロジェクトへの適用

### CLAUDE.local.md に記載する一時ファイル方針テンプレート

```markdown
## 一時ファイル方針

一時ファイルはシステムの `/tmp/` を使わず、プロジェクトルートの `tmp/` に書き出すこと。

- テスト生成物、スクリプト出力、デバッグ用ダンプ等すべてここに置く
- `/tmp/` や `std::env::temp_dir()` は使用禁止
- PreToolUse hook で自動検出・ブロックする
```

### settings.json への登録

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/check-tmp.py\""
          }
        ]
      }
    ]
  }
}
```

## 注意点・制約

- フックの reason は Claude のコンテキストに注入されるため、**簡潔かつ行動可能**な内容にする（長い説明は不要）
- ブロックパターンの文字列をフック自身のソースコードに直書きすると、フックの Edit/Write 時に自己ブロックする。文字列結合で動的構築するか、`.md` 拡張子を除外する
- `decision: "block"` は exit 0 + JSON stdout で返す方法と、exit 2 + stderr で返す方法がある。JSON 方式のほうが構造化されており推奨
- PreToolUse フックは全ツール呼び出しに対して実行されるため、パフォーマンスに注意。マッチャーで対象ツールを絞ること
- **ブロックせず理由だけ添えるパターン（未検証・要実機確認）**: 「ブロックはしないが permission ダイアログの前後で参照される根拠メッセージを添えたい」場合、exit 0 + stderr の実効性は不確実（`claude-code-hooks.md` の exit コード表では stderr が Claude にフィードバックされるのは exit 2 の場合のみと明記）。実効性が観測されない場合は JSON stdout の `hookSpecificOutput.permissionDecisionReason` を返して `permissionDecision` を省略する方式に切り替える。Plan 0043 の `destructive-git-guard.sh` はこの未検証パターンで実装されており、実効性の観測結果が集まったら本節を更新する

## 参照

- 実装例: SDIT プロジェクトの `.claude/hooks/check-tmp.py`
- 関連 knowhow: [claude-code-hooks.md](claude-code-hooks.md) — フック全般の知見
- [CLAUDE_CODE_TMPDIR に関する Issue](https://github.com/anthropics/claude-code/issues/18679)
- [Claude Code Hooks リファレンス](https://code.claude.com/docs/ja/hooks)
