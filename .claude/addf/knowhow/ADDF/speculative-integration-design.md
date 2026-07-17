---
title: 投機 feature の squash 統合設計 — 副作用を worktree に閉じ込める
created: 2026-07-03
last_verified: 2026-07-03
depends_on:
  - .claude/addf/addfTools/speculate-integrate.py
  - .claude/addf/tests/tools/test-speculate-integrate.sh
  - .claude/commands/addf-speculate.md
status: active
---

# 投機 feature の squash 統合設計 — 副作用を worktree に閉じ込める

> 出典: worktree 投機開発の integration 統合フェーズ。複数の speculative/ ブランチを
> 使い捨ての統合ブランチに squash マージし、動作確認を一括するスクリプトの設計判断

## 発見した知見

### 破壊的 git 操作は専用 worktree の中だけに置く

squash 統合には巻き戻し（`reset --hard` + `clean -fd`）や作り直し（`worktree remove --force`・
`branch -D`）が伴う。これらを**専用 worktree（base リポジトリの隣に生成）の中だけ**で行い、
メインの作業ツリーに一切触れない構造にすると、スクリプトのどこで失敗してもユーザーの
作業状態を壊さない。使い捨て空間を最初に確保してから危険な操作を始めるのが正道。

- 置き先パスに **git 管理外のディレクトリが既に存在したら ERROR で止まる**（勝手に消さない）。
  `git worktree remove` は git 管理下の worktree にしか効かないので、この判定は remove の失敗で兼ねられる
- dirty な既存 worktree を作り直すときは WARNING を出してから破棄する（使い捨て設計は維持しつつ
  「知らせる」— silent に捨てない）

### `git commit` の非0を「差分なし」と解釈しない — 理由を先に判定する

squash マージ後の commit が失敗する理由は「差分がない」だけではない（pre-commit フックの拒否等）。
非0 を一律 empty 扱いにすると、**実変更がフック拒否で握り潰されたのに「差分なし」と偽って報告する**
（レビュー High で検出）。順序を入れ替えて解決する:

1. `git diff --cached --quiet` で先に「本当に差分なし」を判定 → empty（正常系の報告）
2. 差分があるのに commit 非0 → `commit_failed` として **ERROR**（exit 1）で報告

一般化: サブプロセスの失敗を単一の理由に還元してよいのは、その理由を事前チェックで排除した後だけ。
「エラーコードの解釈」より「状態の事前判定」が安全。

### 使い捨てブランチは「毎回作り直し」がリカバリを兼ねる

integration ブランチ・worktree を実行のたびに base から再生成する設計にすると、
「衝突 feature を外して再実行」「前回の中途半端な状態からの復旧」がすべて同じコードパスになり、
部分的な状態修復のロジックが不要になる。再生成可能なものに増分更新を実装しない。
ただし名前に日付を含める場合、**当日以外の古いブランチは再生成で消えない**ため、
蓄積の掃除は別途（clean 手順）に明示的に割り当てること。

### fake リポジトリのテストで commit フックを使うと「commit 失敗」を注入できる

`printf '#!/bin/sh\nexit 1\n' > .git/hooks/pre-commit` で任意の commit 失敗を再現できる
（worktree は hooks をメイン `.git/hooks` と共有するため、worktree 内の commit にも効く）。
tomllib の PYTHONPATH シムと同系の「環境起因の失敗を決定的に注入する」テスト手法。

### 不可逆な削除の設計 — 「警告は出すが止めない」を許さない

reconcile（掃除）フェーズのペルソナ並列レビューで、削除系に共通する欠陥パターンが3件とも
Critical として検出された（全て実測再現）。教訓:

- **独立試行の羅列にしない**: worktree→ローカル→origin の削除を独立に試行すると、ローカルが
  失敗（lock・メイン作業ツリーで checkout 中）しても origin だけ消え、エフェメラル環境の
  安全網が真っ先に失われる。後段の削除は前段の成功をゲート条件にする（`local_gone` フラグ）
- **削除を守るのが文字列比較だけ、にしない**: 日付名ブランチの「過去」判定は、未来日付の注入で
  当日分が消える・日付またぎで作成直後が消える。未来日付は ERROR、判定に1日の猶予を置く
- **不可逆操作だけは「検出=スクリプト/解釈=エージェント」の例外にする**: 削除の根拠
  （Worktrees.md の「昇格済み/放棄」記載）をスクリプトが読んで突合し、記載が無ければ削除前に
  一括 ERROR（部分削除後の中断より、何も消さない方が安全）。エージェントの善意をコードで検証する
- **フラグ名は操作の実態で命名する**: `--promote` は「昇格を実行する」と誤読される（実態は削除専用）。
  `--delete` に改名。誤読が破壊につながる名前は早期に直す（未コミットのうちなら改名はタダ）

## プロジェクトへの適用

- `/addf-speculate` 手順6（統合）・7（Stage 2）・8（Dashboard 書き分け）の基盤
- key=value 出力（`integrated=` / `conflicted=` / `missing=` / `empty=` / `commit_failed=`）＋
  exit 3値で、解釈と記録（Worktrees.md / Dashboard）はエージェントに委ねる
  （検出=スクリプト / 解釈=エージェント — [sync-lint-design.md](sync-lint-design.md) の原則）

## 注意点・制約

- スクリプトは `[speculation].enable` を再チェックしない（新規投機のゲートは speculate-guard.py の責務。
  統合は既存ブランチへの明示操作）
- 衝突の解消はスクリプトの外 — 自明な衝突は feature ブランチ側で解消して再実行する
  （昇格対象のブランチが常に自己完結する、という上位設計に従う）

## 関連ノウハウ

- [sync-lint-design.md](sync-lint-design.md) — exit 3値・欠如=SKIP・ドリフト注入テストの原則
- [worktree-dotdir-copy.md](worktree-dotdir-copy.md) — feature worktree への .claude 複製の罠
  （integration worktree では複製不要 — 実装の場ではないため）
- [optional-skill-optin.md](optional-skill-optin.md) — 「silent に捨てない」報告設計の前例
