---
name: addf-gui-test
description: |
  GUI テストシナリオを実行する。docs/test-scenarios/ のシナリオファイルを読み、.claude/addf/addfTools/ のツールを使ってテストを実施する。
  UI の見た目や動作を視覚的に検証したいとき、スクリーンショットベースの回帰テストを行いたいときに使う。
user_invocable: true
---

# GUI テスト実行

## 引数
- `$ARGUMENTS`: シナリオ番号（例: "001"）またはシナリオファイル名。省略時は全シナリオを一覧表示。

## 手順

### 引数なしの場合
1. `docs/test-scenarios/` 内の全 `.md` ファイル（README.md 除く）を一覧表示する
2. 各ファイルの `# ` 見出しからシナリオ名を抽出して表示する

### シナリオ指定の場合
1. `docs/test-scenarios/` から該当するシナリオファイルを読む
2. `.claude/addf/Behavior.toml` を読み、プラットフォームを確認する:
   - `gui-test.enable` が `false` なら「GUI テストは無効です」と報告して終了
   - `gui-test.machine` の値でプラットフォーム固有ツールを選択:
     - `"mac"`: `.claude/addf/addfTools/` の macOS 向け Swift ツールを使用
     - `"linux"` / `"windows"`: 未実装。「このプラットフォームの GUI テストツールは未実装です」と報告して終了
3. シナリオの「前提条件」を確認する:
   - テストツールがビルド済みか確認（`.claude/addf/addfTools/window-info` の存在チェック）
   - 未ビルドなら `.claude/addf/addfTools/build.sh` を実行する
4. シナリオの「手順」に従ってテストを実行する:
   - アプリケーションの起動: シナリオに記載された起動コマンドを使用
   - 各ツールの呼び出し: `.claude/addf/addfTools/` のツールを使用
   - 一時ファイルは `tmp/` に書き出す（`/tmp/` は使用禁止）
5. 「期待結果」と実際の結果を比較する
6. 「クリーンアップ」を実行する
7. 結果を報告する（成功/失敗 + 詳細）

## 経験の活用
- 実行前に `addf-gui-test.exp.md` が存在すれば読み、過去の経験（権限問題の回避策、安定しないテストへの対処等）を考慮する
- 実行後、新たな教訓があれば `addf-gui-test.exp.md` に追記する

## 前提条件
- `docs/test-scenarios/` ディレクトリが存在すること（存在しない場合は「テストシナリオディレクトリが見つかりません。`docs/test-scenarios/` を作成してシナリオファイルを追加してください」と報告して終了）
- `.claude/addf/Behavior.toml` が存在すること

## 注意事項
- GUI テストはディスプレイ環境が必要
- Screen Recording / Accessibility 権限が必要な場合がある（`.claude/addf/addfTools/check-screen-recording.sh` で確認可能）
- 失敗した場合はスクリーンショットを `tmp/` に保存して報告する
- テスト対象プロセスは必ずクリーンアップで終了させる
