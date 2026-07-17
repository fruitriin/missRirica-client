# テスト: addf-annotate-grid

> 前提: このスキルはオプトイン式。`.claude/addf/Behavior.toml` で `[gui-test] enable = true` を設定し、
> `uv run --python 3.11 .claude/addf/addfTools/sync-optional-skills.py apply` で有効化コピーを配置してからテストすること
> （uv が無ければ `python3` で直接実行。Python 3.11+ が必要）。手順の詳細は `.claude/addf/guides/gui-test-setup.md` を参照。

## テスト 1: 引数なし — 使い方表示

### 入力
```
/addf-annotate-grid
```

### 期待結果
- 使い方（Usage）が表示される
- `--divide N` と `--every N` の2モードが説明される
- スタイルオプション（--line-color, --label-color 等）が説明される
