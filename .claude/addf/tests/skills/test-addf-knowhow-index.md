# テスト: addf-knowhow-index

## テスト 1: 引数なし — INDEX 読み込み

### 入力
```
/addf-knowhow-index
```

### 期待結果
- `.claude/addf/knowhow/INDEX.md` の内容が返される
- テーブル形式で knowhow ファイル一覧が表示される

---

## テスト 2: reindex — インデックス再構築

### 入力
```
/addf-knowhow-index reindex
```

### 期待結果
- `.claude/addf/knowhow/INDEX.md` が再生成される
- `.claude/addf/knowhow/` 内の全 `.md` ファイル（INDEX 系を除く）がインデックスに含まれる
- 各エントリにファイルパス・一行要約・キーワードが含まれる
