# DelegationRules — 委譲エージェントへの共通禁止事項テンプレート

> 委譲プロンプト（`Agent` tool 経由の worktree 実装等）の**共通禁止事項の単一ソース**。
> 委譲時は `@DelegationRules.md` でメンションして参照する。
> 汎用禁止事項は本ファイル、プロジェクト固有の追加ルールは末尾の「プロジェクト固有ルール」節に追記する。

## 共通禁止事項

### 1. Progress.md の境界（同期ペアの尊重）

- **`.claude/addf/Progress.md` の `## タスク` 以降**（現在のタスク・チェックリスト・日記）は
  **触らない**。ここは親エージェントが管理する進行中セクション
- **`.claude/addf/Progress.md` の `## 運用ルール` 節**は、テンプレート
  （`.claude/addf/templates/ProgressTemplate.addf.md`）と同期関係にある — テンプレを触るなら
  Progress.md 側の同じ節も**同一差分で更新してよい**（`lint-template-sync` ペア1 の要求どおり）
- 判断が難しい場合の指針:
  - 「タスク欄の何か」を触りたい → 親エージェントに委ねる。委譲側では触らない
  - 「運用ルール節と ProgressTemplate.addf.md を同じ差分で同期したい」→ 触ってよい。むしろ触らないと lint が落ちる

### 2. git 操作

- **`git commit` / `git push` / `git tag` を実行しない**。コミットの粒度・タイミングは親エージェントが判断する
- ステージング（`git add`）と `git status` / `git diff` の閲覧は必要に応じて可
- 破壊的操作（`git reset --hard` / `git clean -fd` / `git checkout .` 等）は禁止 — 未コミット変更を捨てる操作は親と合意してから

### 3. 単一ソースの尊重

- ADDF には**単一ソース化**されたテンプレート・ガイドが複数ある。委譲側でその**内容を複製・改変・別ファイル化しない**:
  - PR 本文: [`.claude/addf/guides/pr-format.md`](../guides/pr-format.md)
  - 変更ルート判断: [`.claude/addf/guides/speculative-development.md`](../guides/speculative-development.md) の「変更ルート判断」節
  - 運用ルール: `.claude/addf/templates/ProgressTemplate.addf.md`
  - one-shot 定義: [`.claude/addf/guides/speculative-development.md`](../guides/speculative-development.md)
  - 委譲禁止事項: 本ファイル
- テンプレを触るなら**その単一ソースの本文を編集**する。参照側で複製したり書き換えたりしない

### 4. スコープの尊重

- 委譲プロンプトで指定された**タスクスコープの範囲内**で作業する。範囲外の「ついでの改善」は
  Progress 運用ルール7（`ProgressTemplate.addf.md`）の「主題との関係」判定に従い、
  主題外なら別 Plan として起案するだけに留め、その場で修正しない
- 委譲側でスコープ外の変更が必要と判断したら、結果報告に「スコープ外だが関連する観察」として記述し、
  親エージェントが処遇を決める

### 5. ノウハウの記録

- 委譲タスクで発見した知見は結果報告に**必ず含める**（親エージェントが `/addf-knowhow` で記録する判断をする）
- 委譲側で直接 knowhow ファイルを新設・編集しない（親側の並行編集と衝突するため）

## プロジェクト固有ルール

<!-- 以下の節はダウンストリームプロジェクトが自由に追記する枠。
     addf-migrate はここより下は上書きしない（本体版の共通禁止事項のみ更新される）。
     追記例: 特定ディレクトリの触り方・独自の命名規約・機密取り扱い等 -->

（ダウンストリームでプロジェクト固有の禁止事項をここに追記してください）
