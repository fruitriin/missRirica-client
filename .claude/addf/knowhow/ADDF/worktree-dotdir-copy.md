---
title: worktree への .claude 複製 — cp -r の「既存ディレクトリへの入れ子」罠
created: 2026-07-03
last_verified: 2026-07-03
depends_on:
  - .claude/commands/addf-speculate.md
status: active
---

# worktree への .claude 複製 — cp -r の「既存ディレクトリへの入れ子」罠

> 出典: 投機開発スキル（addf-speculate）フェーズ1 のコードレビュー（Critical 指摘）

## 発見した知見

### `cp -r src dst` は dst が既存ディレクトリだと「中に」コピーする

`.claude/` は git 管理下のファイルを含むため、`git worktree add` の時点で新 worktree 側に
`.claude/` が**既に存在する**。この状態で

```bash
cp -r .claude ../wt/.claude     # ❌ ../wt/.claude/.claude/ という入れ子ができるだけ
```

とすると、cp は「既存ディレクトリの中に同名ディレクトリを作る」動作をし、マージされない。
**エラーが出ず成功して見える**のが悪質で、複製したつもりのエージェントは `.exp.md` 等の
gitignore 対象ファイルを失った状態で作業を始めてしまう。正しくは:

```bash
cp -r .claude/. ../wt/.claude/  # ✅ 送り元末尾の /. で「中身をマージ」の意味になる
```

### venv / node_modules は relocatable でない — コピーせず再構築する

`.claude` 配下に MCP サーバー等の依存（`.venv` / `node_modules` / `__pycache__`）を持つ構成では、
複製がそれらを一緒にコピーしてしまう。しかし venv は作成時の**絶対パス**を埋め込む
（shebang・`pyvenv.cfg`・activate スクリプト）ため relocatable でなく、**コピーは成功して見えるが
壊れている**（該当構成では投機サイクルごとに必発 — ダウンストリーム Issue #18 で実測）。
node_modules も同様にパス・シンボリックリンク前提が崩れうる。

複製時に除外し、必要になったら worktree 側で再構築する:

```bash
cp -r .claude/. <dst>/.claude/
# .venv / node_modules / __pycache__ 等は relocatable でないため除外する（コピー先で再構築）
find <dst>/.claude \( -name .venv -o -name venv -o -name node_modules -o -name __pycache__ \) \( -type d -o -type l \) -prune -exec rm -rf {} +
# git 追跡下のファイルまで消えた場合（依存をあえてコミットしている構成）は復元する
git -C <dst> checkout -- .claude 2>/dev/null || true
```

再構築は `uv sync` / `bun install` 等、依存のマニフェストから行う（マニフェストは git 管理下または
複製対象のため worktree 側に届いている）。壊れたコピーを持ち込むより、無い状態から作り直す方が安全。

補足:

- **除外リストは代表3種＋`venv`（ドットなし）**にすぎない。`.tox` 等、プロジェクト固有の
  依存ディレクトリがあれば除外リストに追記する（シンボリックリンク経由の venv もあるため
  `-type l` も対象に含めている）
- **除去は名前ベース**のため、依存を git 追跡下にあえてコミットしている構成では追跡ファイルまで
  消える。3行目の `git checkout -- .claude` がそれを worktree のブランチから復元する
  （追跡ファイルが無ければ何もしない安全弁。省略しないこと）

### worktree 複製の目的は「gitignore 対象ファイルの補完」

git 管理下のファイルは worktree add が持っていくので、複製で運ぶ必要があるのは
`.exp.md`（経験）・状態ファイル等の gitignore 対象だけ。「複製済みか」の確認は
git 管理下ファイルの存在では判定できない（worktree add 由来と区別がつかない）。
gitignore 対象の代表ファイル（例: `*.exp.md`）の有無で確認する。

### 検証は「成功して見える失敗」を再現してから直す

この罠は fake リポジトリで両形式を実行し、`<dst>/.claude/.claude` の有無と
`.exp.md` の到達を確認して確定した。手順書のシェルコマンドも、レビュー・修正時に
サンドボックスで実地再現するとすり抜けを防げる。

## 関連ノウハウ

- [オプトイン式スキルの退避＋有効化コピー設計](optional-skill-optin.md) — 「成功して見える失敗」を型検証で殺す同系の設計
- [同期 lint の設計](sync-lint-design.md) — サンドボックス再現テストの作法
- [投機統合の設計](speculative-integration-design.md) — feature worktree への .claude 複製の罠を本知見から引用する側（integration worktree では複製不要という補足も含む）
