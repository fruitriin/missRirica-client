---
name: addf-annotate-grid
description: |
  PNG 画像にグリッド線と座標ラベルを描画する。LLM による画像判定の前に座標系を確立するために使う。
  スクリーンショットや UI 画像の特定領域を座標で指定したいとき、画像内の要素位置を正確に伝えたいときに使う。
user_invocable: true
---

# グリッドアノテーション

## 引数
- `$ARGUMENTS`: `<画像パス> [出力パス] [options]`
  - 例: `tmp/capture.png --divide 8`
  - 例: `tmp/capture.png tmp/grid.png --every 100 --font-size 10`
  - 省略時: 使い方を表示する

## 手順

### 引数なしの場合
以下の使い方を表示する:

```
annotate-grid <input-png> <output-png> --divide N
annotate-grid <input-png> <output-png> --every N

モード（いずれか1つ必須）:
  --divide N   縦横を N 等分（例: --divide 4 → 4×4 = 16 セル）
  --every N    N ピクセルごとに線を引く

スタイルオプション（任意）:
  --line-color  RRGGBBAA   グリッド線色 (default: FF000080)
  --label-color RRGGBBAA   ラベル文字色 (default: FFFF00FF)
  --label-bg    RRGGBBAA   ラベル背景色 (default: 00000080)
  --font-size   N          ラベルフォントサイズ pt (default: 12)

ラベル形式:
  --divide: 各セル左上に "col,row"（0-origin、左上が 0,0）
  --every:  各垂直線の上端に "x=N"、各水平線の左端に "y=N"

Exit: 0=成功, 1=エラー
```

### 引数ありの場合

1. `.claude/addf/addfTools/annotate-grid` がビルド済みか確認する
   - 未ビルドなら `cd .claude/addf/addfTools && ./build.sh` を実行する

2. 入力ファイルが存在するか確認する
   - 存在しない場合、`tmp/` 内の最新の PNG を候補として提示する

3. 出力パスを決定する:
   - 引数に出力パスが含まれていれば使用する
   - 含まれていない場合は `tmp/annotated-<入力ファイル名>` を自動設定する
     - 例: 入力が `tmp/capture.png` → 出力 `tmp/annotated-capture.png`

4. コマンドを組み立てて実行する:
   ```bash
   ./.claude/addf/addfTools/annotate-grid <input> <output> <options>
   ```

5. 結果を報告する:
   - 出力ファイルパスとサイズ（px）を表示する
   - 出力画像を Read ツールで表示する
   - 次のステップとして案内する:
     ```
     注目セルが確認できたら:
       --grid-cell col row N でクリップ: /addf-clip-image
       --rect x y w h でクリップ: /addf-clip-image
     ```

## 経験の活用
- 実行前に `addf-annotate-grid.exp.md` が存在すれば読み、過去の経験（最適なオプション選択、よくあるエラー等）を考慮する
- 実行後、新たな教訓があれば `addf-annotate-grid.exp.md` に追記する

## 注意事項
- 出力先は `tmp/` を使う（`/tmp/` は使用禁止）
- `--divide 0` / `--every 0` はエラーになる（1 以上が必要）
- 大きな画像（Retina @2x キャプチャ等）では `--font-size 20` 程度に調整する
