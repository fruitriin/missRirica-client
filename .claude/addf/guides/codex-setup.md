# Codex で ADDF を使う

OpenAI Codex CLI で AutomatonDevDrive Framework を利用するためのガイド。

## 互換性サマリ

| ADDF 機能 | Codex での利用 | 備考 |
|---|---|---|
| 計画駆動開発 | そのまま使える | Markdown ベース、エージェント非依存 |
| ノウハウ蓄積 | そのまま使える | `.claude/addf/knowhow/` は plain Markdown |
| 進捗管理 | そのまま使える | `.claude/addf/Progress.md` を手動で運用 |
| ブートシーケンス | `AGENTS.md` 経由 | 本リポジトリに同梱済み |
| スキル（`/addf-*`） | 手動移植が必要 | 下記「スキルの移植」参照 |
| Hooks | 限定的 | ターンカウンター等は利用不可 |
| 品質ゲート自動化 | 手動実行 | エージェント並列起動は手動で代替 |
| GUI テスト | 利用不可 | Codex sandbox では macOS GUI 不可 |

## セットアップ

### 1. AGENTS.md の認識

本リポジトリには `AGENTS.md` が含まれており、Codex は自動的にこれを読み込みます。
追加設定なしでブートシーケンスが機能します。

### 2. CLAUDE.md の読み込み（推奨）

ADDF の詳細な開発プロセスは `CLAUDE.md` に定義されています。
Codex にも `CLAUDE.md` を読ませるには、`~/.codex/config.toml` に以下を追加:

```toml
project_doc_fallback_filenames = ["CLAUDE.md"]
```

これにより、`AGENTS.md` が存在しないディレクトリでは `CLAUDE.md` がフォールバックとして読み込まれます。
`AGENTS.md` と `CLAUDE.md` が同一ディレクトリにある場合、`AGENTS.md` が優先されます（Codex は各ディレクトリから最大1ファイルを読む）。

### 3. Codex の権限設定

ADDF の開発フローでは `git commit`、ファイル編集、テスト実行が必要です。
推奨設定:

```toml
approval_policy = "on-request"
sandbox_mode = "workspace-write"
```

## スキルの移植

ADDF のスキル（`.claude/commands/addf-*.md`）は Claude Code の Skills 形式で書かれています。
Codex で同等の機能を使うには、`.agents/skills/` に SKILL.md 形式で配置します。

### 形式の違い

**Claude Code（`.claude/commands/addf-knowhow.md`）:**
```yaml
---
name: addf-knowhow
description: 実装知見を .claude/addf/knowhow/ に記録する
user_invocable: true
---
# 手順
...
```

**Codex（`.agents/skills/addf-knowhow/SKILL.md`）:**
```yaml
---
name: addf-knowhow
description: 実装知見を .claude/addf/knowhow/ に記録する
---
# 手順
...
```

主な違い:
- ディレクトリ: `.claude/commands/` → `.agents/skills/<name>/`
- ファイル名: `<name>.md` → `SKILL.md`（ディレクトリ名がスキル名）
- frontmatter: `user_invocable` は Codex では不要（Codex は暗黙トリガーがデフォルト）
- `context: fork` は Codex では `agents/openai.yaml` で設定

### 移植が有効なスキル

| スキル | 移植推奨度 | 理由 |
|---|---|---|
| `addf-knowhow` | 高 | Markdown 操作のみ、エージェント非依存 |
| `addf-knowhow-index` | 高 | 同上 |
| `addf-dev` | 高 | 計画駆動の中核、Markdown ベース |
| `addf-lint` | 中 | Python スクリプト依存あり |
| `addf-migrate` | 中 | git 操作中心、移植可能 |
| `addf-gui-test` | 不可 | macOS Swift ツール依存 |
| `addf-permission-audit` | 不可 | Claude Code settings.json 専用 |

## デュアルエージェント運用

Claude Code と Codex を同じプロジェクトで併用する場合:

### symlink 戦略

```bash
# AGENTS.md を CLAUDE.md へのシンボリックリンクにする場合
# （ADDF ではリポジトリに AGENTS.md を同梱しているため不要）
ln -s CLAUDE.md AGENTS.md
```

**注意**: ADDF は `AGENTS.md` と `CLAUDE.md` を別ファイルとして提供しています。
`AGENTS.md` は Codex 向けの簡潔なブートシーケンス、`CLAUDE.md` はフル機能の開発プロセス定義です。

### project_doc_fallback_filenames 戦略（推奨）

```toml
# ~/.codex/config.toml
project_doc_fallback_filenames = ["CLAUDE.md"]
```

この設定で Codex は `AGENTS.md`（簡潔版）と `CLAUDE.md`（詳細版）の両方を読みます。
`CLAUDE.md` の `@` メンション（`@CLAUDE.repo.md` 等）は Codex では展開されないため、
参照先ファイルの内容は Codex が必要に応じて直接読みに行きます。

### ワークフローの使い分け

| タスク | 推奨エージェント | 理由 |
|---|---|---|
| 計画作成・レビュー | どちらでも | Markdown 操作のみ |
| 実装 | どちらでも | コード生成は両方得意 |
| 品質ゲート | Claude Code | エージェント並列実行、Hooks |
| GUI テスト | Claude Code | macOS ツール依存 |
| セキュリティレビュー | どちらでも | コード分析は両方可能 |

## 制限事項

1. **`@` メンション展開**: `CLAUDE.md` の `@CLAUDE.repo.md` 等は Codex では自動展開されない。Codex は必要時にファイルを直接読む
2. **Hooks**: ターンカウンター、セッション開始時のリセットは Codex では動作しない
3. **経験ファイル（`.exp.md`）**: Claude Code のスキル実行時に自動参照される仕組みは Codex にはない。手動で参照を指示する必要がある
4. **settings.json の権限管理**: Codex は `config.toml` の `approval_policy` で管理。粒度が異なる
