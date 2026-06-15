# 技術検証 - マルチバージョンViteアプリケーション

このプロジェクトは、3つの異なるViteアプリケーションと、それらを切り替えるためのバージョンスイッチャーアプリケーションで構成されています。

## プロジェクト構成

```
tech-verification/
├── app-v1/          # カウンターアプリ (v1.0.0)
├── app-v2/          # Todoリストアプリ (v2.0.0)
├── app-v3/          # 天気アプリ (v3.0.0)
├── version-switcher/ # バージョン切り替えアプリ
└── package.json     # ルートパッケージ (monorepo管理)
```

## アプリケーション詳細

### App V1 - カウンターアプリ
- シンプルなカウンター機能
- リセットボタン付き
- ポート: 5173

### App V2 - Todoリストアプリ
- Todo項目の追加・削除
- チェックボックスで完了管理
- ポート: 5174

### App V3 - 天気アプリ
- 都市選択
- ランダムな天気情報表示
- ポート: 5175

### Version Switcher
- 全アプリケーションのランチャー
- iframe内でアプリを表示
- ポート: 5176

## セットアップ

```bash
# 1. 全ての依存関係をインストール
npm run install:all

# 2. すべてのアプリを同時に起動
npm run dev:all

# または個別に起動
npm run dev:v1        # アプリv1のみ
npm run dev:v2        # アプリv2のみ
npm run dev:v3        # アプリv3のみ
npm run dev:switcher  # バージョンスイッチャーのみ
```

## ビルド

```bash
# すべてのアプリをビルド
npm run build:all

# または個別にビルド
npm run build:v1
npm run build:v2
npm run build:v3
npm run build:switcher
```

## 使い方

1. `npm run dev:all`で全アプリを起動
2. ブラウザで`http://localhost:5176`を開く
3. Version Switcherから各アプリを選択して起動

## 技術スタック

- Vite 7.1.5
- TypeScript
- Vanilla JavaScript (フレームワークなし)
- npm workspaces (monorepo管理)