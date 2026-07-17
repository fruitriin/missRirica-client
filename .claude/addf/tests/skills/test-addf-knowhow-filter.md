# テスト: addf-knowhow-filter

## テスト 1: Plan パス指定 — 関連 knowhow のフィルタリング

### 入力
```
/addf-knowhow-filter .claude/addf/plans-add/0004-gui-test-cross-platform.md
```

### 期待結果
- 関連する knowhow のパスと要約が返される
- 結果は Plan の内容に対して意味的に関連がある
- fork 実行される（メインコンテキストに結果のみ返る）
