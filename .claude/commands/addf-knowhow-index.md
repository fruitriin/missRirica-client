---
name: addf-knowhow-index
description: |
  .claude/addf/knowhow/ のインデックスを参照して「何を知っているか」を把握する。reindex 引数でインデックスを再構築する。
  ADD フレームワーク本体では INDEX.addf.md、ダウンストリームプロジェクトでは INDEX.md を使用する。
  プロジェクトの知見ベースを確認したいとき、ノウハウの追加・削除後にインデックスを更新したいときに使う。
context: fork
user_invocable: true
---

# Knowhow インデックス

## インデックスファイルの選択

- ADDF 開発プロジェクト（フレームワーク本体）では `.claude/addf/knowhow/INDEX.addf.md` を使用する
- ADDF 利用プロジェクト（ダウンストリーム）では `.claude/addf/knowhow/INDEX.md` を使用する
- 判定方法（`INDEX.addf.md` の**存在で判定しない** — 配布によりダウンストリームにも物理存在しうる。存在≠所有）:
  1. **一次根拠**: `CLAUDE.repo.md` のプロジェクト種別宣言を読む。「ADDF 開発プロジェクト」なら `INDEX.addf.md`、「ADDF 利用プロジェクト」なら `INDEX.md`（宣言が `@メンション` 先のファイルにある場合はそれを辿る。コードブロック内の書き換え例は宣言として扱わない）
  2. **フォールバック**（宣言が見つからない場合）: `.claude/addf/lock.json` が存在すればダウンストリームとして `INDEX.md` を使用する。それも無ければ ADDF 本体として `INDEX.addf.md` を使用する

## 引数
- **引数なし**: インデックスファイルを読み、内容をそのまま返す
- **`reindex`**: `.claude/addf/knowhow/` の全ファイルを読み込み、インデックスファイルを再構築する

## 目的

インデックスを読むだけで「knowhow として何を知っているか」を把握できる状態にする。
全ファイルを読まなくても、どのファイルにどんな知見があるかが分かる。

---

## 引数なしの場合

1. インデックスファイル（`INDEX.addf.md` または `INDEX.md`）を読む
2. 内容をそのまま返す

---

## `reindex` の場合

1. `.claude/addf/knowhow/` 内の全 `.md` ファイルを読む（`INDEX.md` 自体と `CLAUDE.md`（読み方の作法）は除く）
2. 各ファイルについて以下を抽出する:
   - **ファイルパス**
   - **一行要約**: そのファイルが扱う中心トピック（1文）
   - **キーワード**: 実装判断に影響する特徴的な用語（5〜15個）。API名、パターン名、制約名など具体的なものを優先する
   - **フロントマター**: `last_verified`・`status`・`depends_on` を解析する（フロントマターがないファイルは ❓ として報告し、追加を促す）
3. **鮮度を判定する**（`last_verified` から今日までの経過日数。**しきい値の定義箇所はここが唯一**。他ファイルは「stale（index 定義の基準）」として参照する）:
   - 🟢 fresh: 60日以内
   - 🟡 aging: 60〜180日
   - 🔴 stale: 180日超、`depends_on` に存在しないファイル・スキルが含まれる、または `status: needs-review`（日付にかかわらず 🔴）
4. インデックスファイルに以下の形式で書き出す:

```markdown
# Knowhow Index

> 自動生成。`/addf-knowhow-index reindex` で再生成できる。

| 鮮度 | ファイル | 要約 | キーワード |
|---|---|---|---|
| 🟢 YYYY-MM-DD | [example.md](example.md) | 例の知見 | keyword1, keyword2 |
| ... | ... | ... | ... |
```

   - `status: superseded` / `retired` のファイルは表の末尾に「📜 棚（superseded / retired）」セクションとして分離して載せる
5. ファイルをトピック領域ごとにグルーピングして並べる（領域はプロジェクトに応じて自動判定する）
6. **鮮度レポート**: 🔴 stale と `needs-review` のファイルがあれば一覧表示し、`/addf-knowhow-revise` での再検証を案内する（表示のみ。強制はしない）

## 経験の活用
- 実行前に `addf-knowhow-index.exp.md` が存在すれば読み、過去の経験（グルーピング判断、キーワード選定の改善等）を考慮する
- 実行後、新たな教訓があれば `addf-knowhow-index.exp.md` に追記する

## 注意

- キーワードは「検索で引っかかる」ことを重視する。抽象的な単語より具体的な API 名・パターン名を優先する
- 新しい knowhow が追加されたら `/addf-knowhow-index reindex` を実行してインデックスを更新する
