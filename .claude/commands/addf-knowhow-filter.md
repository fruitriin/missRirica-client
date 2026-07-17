---
name: addf-knowhow-filter
description: |
  Plan ファイルの内容を受け取り、.claude/addf/knowhow/ から関連するノウハウのパスと要約だけを返す。ブートシーケンスだけでなく開発中いつでも利用してよい。
  タスク開始時に関連ノウハウを把握したいとき、実装中に参考になる知見を探したいときに使う。
context: fork
user_invocable: true
---

# Knowhow フィルタリング

Plan の内容に基づいて、`.claude/addf/knowhow/` 内のノウハウファイルから関連するものだけを選別して返す。

## 引数
- `$ARGUMENTS`: Plan ファイルのパス（例: `.claude/addf/plans/phase6.1-mouse-scroll.md`）

## 手順

1. `$ARGUMENTS` で指定された Plan ファイルを読む
2. `.claude/addf/knowhow/` 内の全 `.md` ファイル（`INDEX.md` と `CLAUDE.md` を除く）を読む
3. Plan の実装に **必要または有用** なノウハウを判定する
4. 以下の形式で結果を返す:

```
## 関連ノウハウ

### .claude/addf/knowhow/xxx.md
要約: （1〜2文で内容を要約）
関連理由: （Plan のどの部分に関係するか）

### .claude/addf/knowhow/yyy.md
要約: ...
関連理由: ...
```

5. 関連するノウハウがない場合は「関連するノウハウはありません」と返す

## 経験の活用
- 実行前に `addf-knowhow-filter.exp.md` が存在すれば読み、過去のフィルタリング精度に関する経験を考慮する
- 実行後、新たな教訓（見落とし・過剰マッチ等）があれば `addf-knowhow-filter.exp.md` に追記する

## 読むときの作法
- **タイトルで中身を推測しない**: 重要性が低いと確認できるまで、タイトルやキーワードからの推測で判定を済ませない
- **本文を確認する**: 本文には推測ではなく事実と経験の積み重ねがある。採用も棄却も、判断の根拠は本文に求める

## 判定基準
- Plan で扱う技術領域に直接関係するか
- Plan の実装で注意すべきハマりポイントが記載されているか
- Plan のアーキテクチャ判断に影響する知見があるか
