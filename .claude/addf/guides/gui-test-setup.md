# GUI テスト セットアップガイド

## 概要

ADD フレームワークの GUI テスト機能は、スクリーンショット撮影・グリッドアノテーション・画像クリップを使った視覚的な UI 検証を提供します。

現在 **macOS のみ** 対応しています。

## 前提条件

- macOS 15 以降（ScreenCaptureKit 使用）
- Swift コンパイラ（Xcode Command Line Tools）
- Screen Recording 権限

## セットアップ手順

### 1. プラットフォーム設定とスキルの有効化

GUI 関連スキル（`addf-gui-test` / `addf-annotate-grid` / `addf-clip-image` /
`addf-ui-test-agent`）は**オプトイン式**です。原本は `.claude/addf/optional/` に退避されており、
有効化するまで発見パスに存在しません（GUI の無い環境でコンテキストを消費せず、
エージェントが GUI テストを試みることもありません）。

`.claude/addf/Behavior.toml` を編集:

```toml
[gui-test]
enable = true
machine = "mac"
```

続けて同期スクリプトでスキルの有効化コピーを配置:

```bash
uv run --python 3.11 .claude/addf/addfTools/sync-optional-skills.py apply
```

uv が無い環境では `python3` で直接実行できます（Python 3.11+ が必要。旧い Python では実行できない旨の案内が出ます）。

無効に戻すときは `enable = false` にして同コマンドを再実行します（配置と撤去の両方を担います。
有効化コピーを直接編集していた場合は削除されず WARNING になります — 変更は
`.claude/addf/optional/` の原本に対して行ってください）。整合チェックは `/addf-lint` セクション10。

### 2. ツールのビルド

```bash
cd .claude/addf/addfTools
bash build.sh
```

以下の4つのバイナリがビルドされます:
- `window-info` — ウィンドウ一覧・位置・サイズを JSON 出力
- `capture-window` — 指定ウィンドウのスクリーンショット撮影
- `annotate-grid` — PNG 画像にグリッド線と座標ラベルを描画
- `clip-image` — PNG 画像の指定領域を切り出し

`build.sh` は完了時に `checksums.sha256` も再生成します。toolchain（Xcode / swiftc バージョン）が
配布時と異なると生成されるハッシュも異なりますが、これは正常です（Plan 0031 実測: 同一環境内でのみ
決定的。環境間の再現は保証しません）。差分をコミットに含めるかは各プロジェクトの運用判断です。

バイナリと `checksums.sha256` の照合は手動でも実行できます（GUI テストの動作前確認やトラブル
シューティング用）:

```bash
bash .claude/addf/addfTools/verify-checksums.sh
```

### 3. Screen Recording 権限の確認

```bash
bash .claude/addf/addfTools/check-screen-recording.sh
```

権限がない場合は、macOS のシステム設定から付与してください:
- **システム設定** → **プライバシーとセキュリティ** → **画面収録** → ターミナルアプリを追加

## 使い方

### スキルから呼び出し

```
/addf-gui-test <シナリオ番号>
```

テストシナリオは `docs/test-scenarios/` に配置します。

### 個別ツールの直接使用

```bash
# ウィンドウ情報を取得
.claude/addf/addfTools/window-info <プロセス名>

# スクリーンショットを撮影
.claude/addf/addfTools/capture-window <プロセス名> tmp/capture.png

# グリッドアノテーション
.claude/addf/addfTools/annotate-grid tmp/capture.png tmp/annotated.png

# 画像クリップ
.claude/addf/addfTools/clip-image tmp/annotated.png tmp/clip.png --rect 100,200,300,400
```

## プラットフォーム対応状況

| プラットフォーム | `machine` 値 | 状態 |
|---|---|---|
| macOS | `"mac"` | 対応済み（Swift/ScreenCaptureKit） |
| Linux | `"linux"` | 未実装 |
| Windows | `"windows"` | 未実装 |

Linux/Windows の GUI テストツール実装はコントリビューションを歓迎します。
`addf-gui-test.md` スキルのプラットフォーム判定ロジックは実装済みのため、プラットフォーム固有ツールを `.claude/addf/addfTools/` に追加するだけで対応できます。

## トラブルシューティング

### ビルドに失敗する
- Xcode Command Line Tools がインストールされているか確認: `xcode-select --install`
- macOS 15 以降が必要です

### Screen Recording 権限エラー
- `check-screen-recording.sh` を実行して権限を確認
- ターミナルアプリに Screen Recording 権限が付与されているか確認

### `gui-test.enable = false` と表示される
- `.claude/addf/Behavior.toml` の `enable` を `true` に変更してください
