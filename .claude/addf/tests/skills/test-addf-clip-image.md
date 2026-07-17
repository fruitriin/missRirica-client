# テスト: addf-clip-image

> 前提: このスキルはオプトイン式。`.claude/addf/Behavior.toml` で `[gui-test] enable = true` を設定し、
> `uv run --python 3.11 .claude/addf/addfTools/sync-optional-skills.py apply` で有効化コピーを配置してからテストすること
> （uv が無ければ `python3` で直接実行。Python 3.11+ が必要）。手順の詳細は `.claude/addf/guides/gui-test-setup.md` を参照。

## テスト 1: 引数なし — 使い方表示

### 入力
```
/addf-clip-image
```

### 期待結果
- 使い方（Usage）が表示される
- `--rect`, `--grid-cell`, `--grid-range` の3モードが説明される
- col/row が 0-origin であることが明記される
