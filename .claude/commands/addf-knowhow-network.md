---
name: addf-knowhow-network
description: |
  knowhow 記事同士を GitHub flavored markdown リンクで相互接続し、知見ベースを wiki として育てる。
  双方向リンクを担保し、superseded/retired には 📜 プレフィックスを付け、INDEX にハブサマリを追加する。
  ノウハウが増えて関連が見えにくくなったとき、revise 後の整合を取りたいときに使う。
user_invocable: true
---

# addf-knowhow-network — ノウハウの相互リンク wiki 化

ノウハウは単独で読まれるより、関連ノウハウへ辿れることで価値が増す。
記事同士を GFM リンクで結び、knowhow 全体をひとつの wiki として育てる。

## 手順

### 1. 関連性の抽出

1. `.claude/addf/knowhow/` の全 `.md` ファイル（INDEX と CLAUDE.md を除く）を読む
2. 各記事の概念・キーワード・依存対象（`depends_on`）を抽出する
3. 記事間の関連を推定する（同じスキルに言及 / 同じファイル群を扱う / 同じドメイン / 一方が他方の前提）

### 2. 関連ノウハウセクションの生成・更新

4. 各記事の末尾に `## 関連ノウハウ` セクションを生成・更新する:

```markdown
## 関連ノウハウ

- [モデル定義時の型整合パターン](./model-type-consistency.md) — 本記事と同じく zod に依存
- [📜 Superseded: 旧型変換ロジック](./old-type-coercion.md) — 本記事に引き継がれた先輩ノウハウ
- [📜 Retired: 初期検討メモ](./adoption-memo.md) — 採用判断完了で棚上げ
```

- リンクは相対パス。リンクテキストは記事の `title`
- `status: superseded` / `retired` の記事へは `📜 Superseded:` / `📜 Retired:` プレフィックスを付ける
- 関連の説明（— 以降）は1行で「なぜ関連するか」を書く

### 3. 双方向リンクの担保

5. A から B にリンクを張ったら、B からも A にリンクが存在することを確認し、なければ追加する
   - 例外: `retired` ファイルへのリンクは片方向でよい（retired 側からのリンク追加は不要。棚の中は更新しない）。superseded → 後継は双方向必須

### 4. ハブサマリ

6. `INDEX.addf.md`（ダウンストリームでは `INDEX.md`）の末尾に「## ハブノウハウ」セクションを追加・更新する:
   - 被リンク数の多い記事トップ3〜5を列挙する
   - ハブ記事は多くの知見の前提になっているため、revise の優先対象になる

### 5. 完了処理

7. 追加・更新したリンク数と、双方向性の欠落を修正した件数を報告する

## 運用フロー（3スキルの分業）

```
/addf-knowhow-index reindex   # 鮮度マークの更新（機械的）
/addf-knowhow-revise           # 古いノウハウを再検証・訂正（意味的）
/addf-knowhow-network          # 相互リンクを張り直し wiki 化（構造的）
```

それぞれ独立に実行できるが、`revise → network` の順で回すと整合性が高い。

## 経験の活用

- 実行前に `addf-knowhow-network.exp.md` が存在すれば読み、過去の経験を考慮する
- 実行後、新たな教訓があれば `addf-knowhow-network.exp.md` に追記する
