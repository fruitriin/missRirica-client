# PR 本文フォーマット規約

> PR 本文書式の**単一ソース**。addf-dev / addf-speculate 等のスキルはここを参照する
> （規約本文をスキル側へコピーしない — 同期ペアを増やさない）。
> オーナーレビューの入口を GitHub PR に揃えるための規約（出典: Plan 0035）。

## 必須セクション

### 1. 対象 Plan

PR 本文に「## 対象 Plan」セクションを必ず置き、紐づく計画ファイルへのリンクを記載する。
Plan に紐づかない PR（依存更新・typo 修正・緊急 hotfix 等）では
「対象 Plan: なし（理由を一言）」と明記する。

- リンクテキストは **「Plan <番号>: <計画タイトル（日本語）>」** とする（ファイル名やパスではなく）。
  Plan タイトルが長い場合は、意味が変わらない範囲で短縮してよい
- **リンクをバッククォートで囲まない**（コードスパン内の markdown リンクは plain text になり
  リンク化されない）
- **blob URL の選び方**（本規約の主目的は「PR レビュー時点での可読性」）:
  - PR オープン中は **head ブランチの blob URL** を使う（マージ前でも 404 にならない）:
    `https://github.com/<owner>/<repo>/blob/<headブランチ>/<planパス>`
    （main の blob URL は、Plan ファイルがその PR で追加・更新される場合マージ前は 404 になるため使わない）
  - ただし head ブランチ URL は**マージ後にブランチが削除されると死ぬ**。
    ブランチ削除運用のプロジェクトでは commit SHA 固定 URL を使う
  - head ブランチ名の確認: `git branch --show-current` または `gh pr view --json headRefName`

### 2. 計画の進捗位置

フェーズ・項目分割された Plan は、途中フェーズの PR がマージされた瞬間に「済み」に見え、
残フェーズの存在が視界から消えて完了と誤認される（部分完成の誤完了）。これを防ぐため
PR 本文に「## 計画の進捗位置」セクションを必ず置き、以下を記載する:

- **この PR が Plan のどのフェーズ / 項目か**
- **残フェーズ・残項目は何か**（「この PR で Plan は完了しない」ことをレビュー時に可視化する）

Plan 全体を完了させる PR では「残りなし（この PR で Plan 完了）」と明記する。

## 記載例

（初出の実例: PR #21 https://github.com/fruitriin/ADDF/pull/21 。
マージ済み PR の実例のため、リンクは head ブランチではなく main を参照している）

```markdown
## 対象 Plan

- [Plan 0033: ダウンストリーム実測バグの修正](https://github.com/fruitriin/ADDF/blob/main/.claude/addf/plans-add/0033-downstream-reported-fixes.md)

## 計画の進捗位置

- この PR: 項目1〜3（upstream/downstream 判定の統一・INDEX 選択・knowhow 追記）
- 残り: 項目4（PlanTemplate.md 新規追加）— この PR で Plan は完了しない
```

## Plan 相互リンク規約

PR からリンクされる Plan の側にも、関連が辿れるためのリンク規約を置く
（knowhow 記事の相互リンクと同じ双方向原則）:

- 派生・依存・分離などの関連は、Plan 冒頭の「## 関連 Plan」セクションに
  markdown リンクで記す（フリーテキストの言及で済ませない）
- **リンクは双方向を原則とする** — 片リンクは辿れない側で関連が失われる。
  関連 Plan を追記したら、相手側の Plan にも本 Plan へのリンクを追記する
- 新規 Plan の書式（「関連 Plan」セクションを含む）は
  `.claude/addf/templates/PlanTemplate.md` に従う
