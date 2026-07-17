---
name: addf-clip-image
description: |
  PNG 画像の指定領域を切り出す。annotate-grid で座標確認後、注目領域だけを LLM に渡す際に使う。
  画像の一部分だけを拡大して確認したいとき、特定の UI コンポーネントを切り出して検証したいときに使う。
user_invocable: true
---

# 画像クリップ

## 引数
- `$ARGUMENTS`: `<画像パス> [出力パス] [options]`
  - 例: `tmp/capture.png --grid-cell 3 2 8`
  - 例: `tmp/capture.png tmp/clip.png --rect 100 200 400 300`
  - 例: `tmp/capture.png --grid-range 2 1 4 3 8`
  - 省略時: 使い方を表示する

## 手順

### 引数なしの場合
以下の使い方を表示する:

```
clip-image <input-png> <output-png> --rect x y width height
clip-image <input-png> <output-png> --grid-cell col row N
clip-image <input-png> <output-png> --grid-range col1 row1 col2 row2 N

クリップ領域（いずれか1つ必須）:
  --rect x y width height              ピクセル座標で矩形指定（左上原点）
  --grid-cell col row N                annotate-grid --divide N と同じ分割で1セル切り出す
  --grid-range col1 row1 col2 row2 N   (col1,row1) から (col2,row2) までの範囲を切り出す
                                        col, row は 0-origin（左上が 0,0）

Exit: 0=成功, 1=エラー
```

### 引数ありの場合

1. `.claude/addf/addfTools/clip-image` がビルド済みか確認する
   - 未ビルドなら `cd .claude/addf/addfTools && ./build.sh` を実行する

2. 入力ファイルが存在するか確認する
   - 存在しない場合、`tmp/` 内の最新の PNG を候補として提示する

3. 出力パスを決定する:
   - 引数に出力パスが含まれていれば使用する
   - 含まれていない場合は `tmp/clip-<入力ファイル名>` を自動設定する
     - 例: 入力が `tmp/capture.png` → 出力 `tmp/clip-capture.png`

4. コマンドを組み立てて実行する:
   ```bash
   ./.claude/addf/addfTools/clip-image <input> <output> <options>
   ```

5. 結果を報告する:
   - 出力ファイルパスと切り出しサイズ（px）を表示する
   - 出力画像を Read ツールで表示する

## 典型的な連携フロー

```
1. /addf-gui-test でスクリーンショット撮影 → tmp/capture.png
2. /addf-annotate-grid tmp/capture.png --divide 8
   → tmp/annotated-capture.png で座標系を確認
3. 注目セルが (3,2) だと判明
4. /addf-clip-image tmp/capture.png --grid-cell 3 2 8
   → tmp/clip-capture.png（注目領域のみ、OCR やテキスト検証に最適）
```

## 経験の活用
- 実行前に `addf-clip-image.exp.md` が存在すれば読み、過去の経験を考慮する
- 実行後、新たな教訓があれば `addf-clip-image.exp.md` に追記する

## コツ
- **切り出すのは元画像（annotated じゃない方）から。** グリッド線入りの画像を clip すると線がノイズになる。annotated で座標を確認して、clip は元画像に対して実行する
- **`--grid-range` が一番使いやすい。** `--divide 8` で細かくグリッド → `--grid-range col1 row1 col2 row2 8` で注目エリアを範囲指定。rect のピクセル座標計算が不要になる
- **clip → さらに annotate-grid → clip の再帰もあり。** 大きな画像を段階的に絞り込める。ただし2段階目までが実用的
- **広い画像はノイズが多い。** 全体を見ると関係ない要素が邪魔になり、対象を見失いやすい。clip で注目領域だけを切り出し、対象物に集中して検査する
- **対象物が見つからないときは走査する。** grid で分割 → 各セルを clip → 個別に注視、を繰り返して画像全体を網羅的に走査するテクニックが有効

## 注意事項
- 出力先は `tmp/` を使う（`/tmp/` は使用禁止）
- `--grid-cell` の col/row は 0-origin かつ N 未満でなければならない
- `--grid-range` の col1 <= col2、row1 <= row2 でなければならない
- `--rect` の座標は画像の左上原点（y は下向き増加）
