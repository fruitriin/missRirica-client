---
title: 権限要求パターンと settings ファイルの使い分け
created: 2026-03-19
last_verified: 2026-07-14
depends_on: []
status: active
---

# 権限要求パターンと settings ファイルの使い分け

## 発見した知見

### 3つの権限パターン

| パターン | 内容 | 例 |
|---|---|---|
| **アップストリーム** | ADDF フレームワーク開発・メンテナンスに必要な権限 | `sed`（大規模リネーム）、`find`（.gitignore 外探索）、`swiftc`（ツールビルド） |
| **ダウンストリーム** | プロジェクト固有の開発に必要な権限 | プロジェクトのビルドコマンド、テストランナー、デプロイツール |
| **汎用** | どのプロジェクトでも共通して必要な権限 | `git` 操作、ファイル操作（`cp`, `mv`, `rm`, `mkdir`, `ls`）、`chmod` |

### 2つのプロジェクト種別 × 配置先

#### ADDF 開発プロジェクト（このリポジトリ = フレームワーク本体）

| パターン | 配置先 | 理由 |
|---|---|---|
| アップストリーム | `settings.local.json` | ADDF 開発固有の権限。ダウンストリームに持ち込ませない |
| ダウンストリーム | `settings.json` | テンプレートとしてダウンストリームに配布される |
| 汎用 | `settings.json` | 全プロジェクトで共通、コミット対象 |

**ポイント**: このリポジトリの `settings.json` はダウンストリームの初期テンプレートになる。ADDF 開発でしか使わない `sed`, `find`, `swiftc` 等は `settings.local.json` に入れるべき。

#### ADDF 利用プロジェクト（ダウンストリーム）

| パターン | 配置先 | 理由 |
|---|---|---|
| アップストリーム | `settings.json` | ADDF フレームワーク機能（スキル・エージェント・フック）の実行に必要。全開発者で共有 |
| ダウンストリーム | `settings.json` | プロジェクト固有のビルド・テスト権限。全開発者で共有 |
| マシンローカル | `settings.local.json` | 個人の開発環境固有の権限（IDE 連携、個人ツール等） |

## プロジェクトへの適用

### 現在の settings.json の問題点

現在の `settings.json` にはアップストリーム権限（`sed`, `find`, `swiftc`, `git rev-parse`）が混在している。ダウンストリームプロジェクトがこのテンプレートをクローンすると、不要な権限が含まれてしまう。

### あるべき姿

**settings.json**（コミット対象、ダウンストリームのテンプレート）:
```json
{
  "permissions": {
    "allow": [
      "Read", "Edit", "Write", "Glob", "Grep",
      "Agent", "Skill", "LSP", "ToolSearch",
      "TaskCreate", "TaskGet", "TaskList", "TaskOutput", "TaskStop", "TaskUpdate",
      "TeamCreate", "TeamDelete", "SendMessage",
      "Bash(cp *)", "Bash(mkdir *)", "Bash(ls *)", "Bash(tail *)", "Bash(cd *)",
      "Bash(git status *)", "Bash(git diff *)", "Bash(git log *)",
      "Bash(git add *)", "Bash(git commit *)", "Bash(git rm *)",
      "Bash(git ls-files *)", "Bash(git branch *)", "Bash(git worktree *)",
      "Bash(git checkout *)", "Bash(git show *)", "Bash(git merge *)", "Bash(git stash *)",
      "Bash(bash .claude/addf/tests/run-all.sh *)",
      "Bash(uv run --python 3.11 .claude/addf/addfTools/lint *)"
    ],
    "ask": [
      "Bash(git push *)",
      "Bash(git reset --hard *)",
      "Bash(git clean *)"
    ]
  }
}
```

**settings.local.json**（ADDF 開発プロジェクトのみ、gitignore 対象）:
```json
{
  "permissions": {
    "allow": [
      "Bash(sed *)",
      "Bash(find *)",
      "Bash(git rev-parse *)",
      "Bash(bash .claude/addf/addfTools/build.sh *)",
      "Bash(swiftc *)"
    ]
  }
}
```

## 権限フォーマットの技術仕様（公式ドキュメント準拠）

> 出典: https://code.claude.com/docs/ja/permissions

### 評価順序

**deny → ask → allow** の順で評価される。最初にマッチしたルールが優先されるため、**deny は常に勝つ**。

### 設定ファイルの優先順位

1. **管理設定**（オーバーライド不可）
2. **CLI 引数**（一時的なセッションオーバーライド）
3. **`settings.local.json`**（ローカルプロジェクト設定）
4. **`settings.json`**（共有プロジェクト設定）
5. **`~/.claude/settings.json`**（ユーザー設定）

**重要**: いずれかのレベルで deny されたツールは、他のレベルで allow できない。

### ルール構文

| 形式 | 効果 |
|---|---|
| `Read` | ツールのすべての使用をマッチ |
| `Bash(npm run build)` | 正確なコマンドをマッチ |
| `Bash(npm run test *)` | `npm run test` で始まるコマンドをマッチ |
| `Bash(git * main)` | 中間ワイルドカード（`git checkout main` 等） |

### ワイルドカードの注意点

- **`:*` は非推奨（レガシー構文）**。`Bash(git status *)` ではなく **`Bash(git status *)`**（スペース+アスタリスク）を使う
- `*` の前のスペースは単語境界を強制: `Bash(ls *)` は `ls -la` にマッチするが `lsof` にはマッチしない
- `Bash(ls*)` はスペースなしのため `ls -la` と `lsof` の両方にマッチ
- シェルオペレータ（`&&` 等）は認識される: `Bash(safe-cmd *)` は `safe-cmd && other-cmd` にマッチしない

### 組み込みツールの許可

ツール名だけで許可:
```json
"allow": ["Read", "Edit", "Write", "Glob", "Grep", "Agent", "Skill", "LSP", "ToolSearch"]
```

タスク管理・チーム管理系も同様: `TaskCreate`, `TaskUpdate`, `TeamCreate`, `SendMessage` 等。

### Read/Edit のパスパターン（gitignore 仕様準拠）

| パターン | 意味 |
|---|---|
| `//path` | ファイルシステムルートからの絶対パス |
| `~/path` | ホームディレクトリからのパス |
| `/path` | プロジェクトルートからの相対パス |
| `path` / `./path` | 現在のディレクトリからの相対パス |

`*` は単一ディレクトリ内、`**` は再帰マッチ。

### MCP ツールの許可

- `mcp__server` — サーバーの全ツール
- `mcp__server__tool` — 特定ツール

### Agent（サブエージェント）の許可

- `Agent(Explore)`, `Agent(Plan)`, `Agent(my-custom-agent)`

### スキルと権限のスコープ

**スキルは権限をネストしない**。`Skill(addf-lint)` を allow に入れてもスキル起動の許可のみ。スキル内部で呼ばれる `Bash(uv run ...)` 等の各ツール呼び出しは個別に権限チェックされる。

### コマンド許可の限定テクニック

`python3` を全面許可すると権限が強すぎる場合、実行スクリプトをディレクトリに集約して限定:
```json
"Bash(uv run --python 3.11 .claude/addf/addfTools/lint *)"
```

### PreToolUse フックによる権限拡張

フックは権限システムの**前**に実行される。フック出力でツール呼び出しを承認または拒否できる。

### 破壊的操作のテンプレート除外方針

テンプレート（`settings.json`、ダウンストリームに配布）に含めるかどうかは
「**破壊が主目的か副作用か**」で分類する（完全に一貫はしない実務的境界）:

| 分類 | 例 | 配置 | 理由 |
|---|---|---|---|
| 作成が主・上書きは副作用 | `cp`, `mkdir`, `mktemp`, `git clone` | `settings.json` | 通常は新規ファイル作成。上書きはワイルドカード指定時の副作用 |
| 元状態を消す・変えるのが主目的 | `mv`, `rm`, `chmod` | `settings.local.json` | 副作用ではなく破壊が動作の主眼 |
| 元に戻せない | `git push`, `git reset --hard`, `git clean` | `settings.json` の `ask` | 遠隔状態やインデックスに不可逆な影響 |

- `cp` は「上書きしうる」点で完全に無害ではないが、通常運用（`cp src/foo dst/foo`）で
  副作用リスクは低い。ワイルドカード + 既存ディレクトリ書き換えの組み合わせでのみ問題化する
- 「上書き副作用も禁止したい」プロジェクトは `settings.json` の `ask` に `Bash(cp * /*)` 等を
  追加するか、`deny` で特定パス（`Bash(cp * ./src/**)`）を明示する — が、テンプレートには含めない
  （運用ノイズが増える vs 実害率のトレードオフ。**深追い設計の Plan 化余地あり**）
- 慣れた開発者は自分の責任で `settings.local.json` に `mv`/`rm`/`chmod` を `allow` として追加する
  （本リポジトリの `settings.local.json` はまさにこの形）
- これにより、ダウンストリームの新規プロジェクトがデフォルトで**破壊主目的の操作は不許可**の
  安全な状態で始まる

### gh コマンドの read/write 分離

`gh` のサブコマンドは参照系と更新系で権限レベルを分ける:

**allow（参照系）**:
- `gh repo view`, `gh repo list`, `gh repo clone`
- `gh issue list`, `gh issue view`, `gh issue status`
- `gh pr list`, `gh pr view`, `gh pr status`, `gh pr diff`, `gh pr checks`, `gh pr checkout`

**ask（更新系）**:
- `gh issue create`, `gh issue comment`, `gh issue close`, `gh issue edit`
- `gh pr create`, `gh pr comment`, `gh pr merge`, `gh pr close`, `gh pr edit`, `gh pr review`
- `gh repo create`, `gh repo edit`, `gh repo delete`, `gh repo fork`

`gh api` は GET/POST の区別が引数順序に依存し、プレフィックスマッチでは GET に限定できない（`-f` パラメータ付与で自動 POST 化、`--method` の位置が不定）。公式ドキュメントも「引数を制約するパターンは脆弱」と警告している。allow/ask どちらにも入れず都度確認（デフォルト動作）が妥当。

### settings.json と settings.local.json の役割分担まとめ

**settings.json（テンプレート）** — 破壊主目的でない安全な操作:
- 組み込みツール（Read, Edit, Write, Glob, Grep, Agent, Skill, LSP, ToolSearch, TaskCreate/Update/List/Get/Output/Stop, TeamCreate/Delete, SendMessage）
- `Bash(* --help)`, `Bash(* --help *)`, `Bash(* --version)`
- ファイル操作（作成主目的）: `cp`, `mkdir`, `mktemp`, `ls`, `tail`, `cd`, `which`（mv/rm/chmod は除外）
- git 参照系 + commit/add + `git clone`, `git -C *`（push は ask）
- gh 参照系: `view`, `list`, `status`, `diff`, `checks`, `checkout`, `clone`
- フレームワークツール: `bash .claude/addf/tests/run-all.sh *`, `uv run --python 3.11 .claude/addf/addfTools/lint *`

> 実際の一覧はドリフトするため、正は `.claude/settings.json` を参照する。上記は「テンプレートに何を入れる／入れないか」の**基準**の例示。

**settings.local.json（パワーユーザー向け）** — 自己責任で許可:
- 破壊主目的のファイル操作: `mv`, `rm`, `chmod`
- ADDF 開発ツール: `sed`, `find`, `swiftc`, `addfTools/build.sh`, `git rev-parse`
- gh 更新系: `create`, `comment`, `close`, `edit`, `merge`, `review`, `fork`, `gh release`
- `uv run:*`（Python スクリプトの汎用実行）
- `gh api` は含めない（都度確認）

## 注意点・制約

- `settings.local.json` は `.gitignore` 対象なのでコミットされない
- いずれかのレベルで deny されたら、他のレベルで allow できない
- 新しい権限を追加するときは「これはどのパターンか？」を判断してから配置先を決める
- `ask` に入れるべき破壊的操作（push, reset --hard, clean）はどちらのプロジェクト種別でも共通
- **`:*` 構文は非推奨** — 既存の設定を ` *`（スペース+アスタリスク）に移行すべき

## 参照

- https://code.claude.com/docs/ja/permissions — 公式ドキュメント
- `.claude/settings.json` — プロジェクト共有設定
- `.claude/settings.local.json` — ローカル設定
- `.claude/addf/knowhow/ADDF/upstream-downstream-separation.md` — 分離パターンの全体像

## 関連ノウハウ

- [ccchain-dogfooding-phase1.md](ccchain-dogfooding-phase1.md) — ccchain は Claude Code の
  permission システムとは独立した別レイヤーで動作する。settings.json/settings.local.json の
  権限配置パターン（本記事）との責務分担を検討する際に参照する

## 訂正履歴

### 2026-07-06
- 「破壊的操作のテンプレート除外方針」の基準を「破壊が主目的か副作用か」に整理した
  → 従来は「破壊的な副作用を持つため mv/rm/chmod を除外」としながら、`cp *` も上書きしうる（副作用）
  ことに触れておらず、cp 許可・mv/rm/chmod 除外の基準が不統一だった（Plan 0026 レビュー指摘）。
  分類を明示し、「上書き副作用まで禁止したい場合の追加設計」は本記事の外に Plan 化余地として明記
  （根拠: 現行 `.claude/settings.json` は `Bash(cp *)` を allow、`.claude/settings.local.json` は
  `mv`/`rm`/`chmod` を allow に置いており、両者の境界は本記事の新しい基準と整合する）
- 例示 settings.json の一覧を現状に追従（`Bash(* --help)` / `Bash(* --help *)` / `Bash(* --version)`
  ・`Bash(git clone *)` / `Bash(git -C *)` / `Bash(mktemp *)` / `Bash(which *)`・
  gh 参照系サブコマンド群を追記）。settings.local.json 側にも `uv run:*` / `gh release *` を反映
  （根拠: 現行 `.claude/settings.json` / `.claude/settings.local.json`）
