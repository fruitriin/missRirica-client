# テスト: addf-knowhow

## テスト 1: 引数なし — 一覧表示

### 入力
```
/addf-knowhow
```

### 期待結果
- `.claude/addf/knowhow/` 内の `.md` ファイルが一覧表示される
- 各ファイルの `# ` 見出しからタイトルが抽出されている
- INDEX.md / INDEX.addf.md は表示されない、または区別されている

---

## テスト 2: トピック指定 — 新規作成

### 前提条件
- `.claude/addf/knowhow/test-topic.md` が存在しないこと

### 入力
```
/addf-knowhow テスト用トピック
```

### 期待結果
- `.claude/addf/knowhow/test-topic.md` が作成される
- ファイル構造が `## 発見した知見` / `## プロジェクトへの適用` / `## 注意点・制約` / `## 参照` を含む
- 自己ブラッシュアップ（Phase 3）が実行される

### クリーンアップ
- `.claude/addf/knowhow/test-topic.md` を削除する
