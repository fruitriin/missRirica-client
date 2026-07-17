---
title: Claude Code Hooks の適用方法
created: 2026-03-18
last_verified: 2026-06-11
depends_on: []
status: active
---

# Claude Code Hooks の適用方法

## 発見した知見

### Hooks とは
Claude Code のライフサイクル内の特定ポイントで自動実行されるユーザー定義ハンドラー。
シェルコマンド（`command`）、HTTP エンドポイント（`http`）、LLM プロンプト（`prompt`）、サブエージェント（`agent`）の4種類がある。

### フックイベント一覧

| イベント | 発火タイミング | マッチャー対象 | ブロッキング可 |
|---|---|---|---|
| `SessionStart` | セッション開始・再開時 | `startup`, `resume`, `clear`, `compact` | — |
| `UserPromptSubmit` | プロンプト送信時（Claude 処理前） | なし（常に発火） | exit 2 でプロンプト拒否 |
| `PreToolUse` | ツール呼び出し前 | ツール名（`Bash`, `Edit\|Write` 等） | exit 2 or JSON deny でブロック |
| `PostToolUse` | ツール呼び出し成功後 | ツール名 | — |
| `PostToolUseFailure` | ツール呼び出し失敗後 | ツール名 | — |
| `PermissionRequest` | 権限ダイアログ表示時 | ツール名 | JSON で allow/deny |
| `Stop` | Claude の応答完了時 | なし（常に発火） | — |
| `SubagentStart` / `SubagentStop` | サブエージェント開始・終了 | エージェントタイプ | — |
| `TaskCompleted` | タスク完了マーク時 | なし（常に発火） | — |
| `WorktreeCreate` / `WorktreeRemove` | worktree 作成・削除 | なし（常に発火） | — |
| `InstructionsLoaded` | CLAUDE.md / rules 読み込み時 | なし（常に発火） | — |
| `PreCompact` / `PostCompact` | コンテキスト圧縮前後 | `manual`, `auto` | — |
| `SessionEnd` | セッション終了 | 終了理由 | — |
| `Notification` | 通知送信時 | 通知タイプ | — |
| `ConfigChange` | 設定ファイル変更時 | 設定ソース | — |

### exit コードによるフロー制御

```
exit 0  → 成功。stdout の JSON を解析して処理を継続
exit 2  → ブロッキングエラー。stderr が Claude にフィードバックされる
         PreToolUse: ツール呼び出しをブロック
         UserPromptSubmit: プロンプトを拒否
その他   → 非ブロッキングエラー。stderr は verbose モードで表示、実行は継続
```

### JSON 出力による制御（exit 0 + stdout）

PreToolUse の場合:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Destructive command blocked by hook"
  }
}
```

PermissionRequest の場合:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "permissionDecision": "allow"
  }
}
```

### 設定ファイルの場所とスコープ

| 場所 | スコープ | 共有 |
|---|---|---|
| `~/.claude/settings.json` | 全プロジェクト | マシンローカル |
| `.claude/settings.json` | プロジェクト | コミット可能 |
| `.claude/settings.local.json` | プロジェクト | gitignore |
| スキル/エージェント frontmatter | コンポーネント有効時のみ | コンポーネント定義内 |

### マッチャーパターン
- 正規表現文字列。`"Bash"`, `"Edit|Write"`, `"mcp__.*"` 等
- `"*"` または省略で全てにマッチ
- MCP ツールは `mcp__<server>__<tool>` 形式

### stdin で受け取る共通入力フィールド
```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/project/root",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": { "command": "npm test" }
}
```

### スキル/エージェントの frontmatter でのフック定義

```yaml
---
name: secure-operations
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/security-check.sh"
---
```

コンポーネントのライフサイクルにスコープされ、完了時に自動クリーンアップされる。

### 環境変数
- `$CLAUDE_PROJECT_DIR` — プロジェクトルート
- `${CLAUDE_PLUGIN_ROOT}` — プラグインルート
- `$CLAUDE_CODE_REMOTE` — リモート環境で `"true"`

## フックからのコンテキスト使用量計測（Plan 0023 で実証）

- UserPromptSubmit フックの stdin JSON に `transcript_path` が含まれる。フック入力
  そのものにはモデル名・コンテキスト使用量は**含まれない**が、transcript JSONL の
  `type: "assistant"` エントリの `message.usage` から実測できる:
  `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` ≈ 現在の使用量
- 罠1: サブエージェントの応答が `isSidechain: true` で混ざる。メインチェーンのみ採用する
- 罠2: `message.model` にはウィンドウ variant が載らない（`claude-fable-5[1m]`
  セッションでも素の `claude-fable-5`）。200k/1M の判別はフックからは不可能なので、
  「フックは実測値＋設定表の目安を注入し、variant を知っているモデル自身が判断する」分担にする
- 罠3: 残量に言及する固定文言（「コンテキストが大きくなっています」等）は根拠のない
  状態断言になり、モデルの早期切り上げを誘発しうる（Fable 5 ガイドの警告）。
  注入は観測事実のみ＋「切り上げ指示ではない」の安心文を添える
- 大きい transcript は末尾チャンク（2MB 程度）だけ読み、先頭の不完全な行を捨てる。
  取得不能（transcript 不在・圧縮直後・パース失敗）は静かに exit 0（誤発火より無発火）
- 実装: `.claude/addf/addfTools/context-reminder.py`（`turn-reminder.sh` から stdin 中継。
  stdin の TTY 判定で手動実行・旧テストとの互換を保つ）

## プロジェクトへの適用

### ADD フレームワークでの活用パターン

**1. PostToolUse: 自動 Lint/フォーマット**
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/auto-lint.sh"
          }
        ]
      }
    ]
  }
}
```

**2. PreToolUse: 破壊的コマンドのブロック**
```bash
#!/bin/bash
command=$(jq -r '.tool_input.command' < /dev/stdin)
if [[ "$command" == rm* ]]; then
  echo "Blocked: rm commands not allowed" >&2
  exit 2
fi
exit 0
```

**3. Stop: セッション終了時のナレッジ抽出**
セッション完了時に knowhow の自動抽出候補を表示

**4. WorktreeCreate: .claude ディレクトリのコピー**
worktree 作成時に `.claude` ディレクトリを自動コピー（CLAUDE.md の並列実装方針に対応）

**5. スキル frontmatter: スキル固有の検証**
品質ゲート系スキルに PreToolUse フックを組み込み、スキル実行時のみ特定の検証を追加

## 注意点・制約

- フックは設定ファイルの**スナップショット**で動作する。セッション中のファイル編集は即時反映されない（`/hooks` メニューでレビューが必要）
- exit 2 のブロッキングは PreToolUse と UserPromptSubmit でのみ意味がある
- `async: true` でバックグラウンド実行可能だが、ブロッキング制御はできない
- `once: true` でセッション中1回だけ実行（スキルのみ、エージェントでは不可）
- timeout デフォルト: コマンド 600秒、プロンプト 30秒、エージェント 60秒

## 参照

- [Claude Code Hooks リファレンス](https://code.claude.com/docs/ja/hooks)
- [ワークフローをフックで自動化する](https://code.claude.com/docs/ja/hooks-guide)
- Everything Claude Code の hooks/ ディレクトリ
- 関連 knowhow: [pretooluse-block-with-rationale.md](pretooluse-block-with-rationale.md) — 根拠提示型ブロックの設計パターン
- 関連 knowhow: [context-and-transcript.md](context-and-transcript.md) — トランスクリプト JSONL の構造・resume との非対称双方向性・能動 compaction の限界
