# MissRirica - 開発者ガイド

MissRiricaは、Misskeyソーシャルネットワークソフトウェア用のモバイルiOS/Androidクライアントで、CapacitorとVue 3で構築されています。モバイル特化の最適化とプッシュ通知サポートを備えた、Misskey Web（v13）とほぼ同じUIを提供します。

## プロジェクト概要

**タイプ**: ハイブリッドモバイルアプリ (Capacitor + Vue 3 + TypeScript)
**バージョン**: 1.5.3
**対象プラットフォーム**: iOSおよびAndroid
**ベース**: モバイル向け改修を施したMisskey v13クライアント

### 主な機能
- Misskey Web（v13）とほぼ同一のUI
- OneSignalによるプッシュ通知
- ネイティブモバイルアプリ体験
- 複数Misskeyインスタンスのサポート
- ダーク/ライトモード対応のテーマシステム

## よく使うコマンド

### 開発
```bash
# ライブリロード付き開発サーバー起動
npm run dev

# 型チェック
npm run lint

# ビルド済みアプリケーションのプレビュー
npm run preview
```

### ビルド
```bash
# 本番ビルド
npm run build

# 開発ビルド（デバッグ情報付き）
npm run devbuild
```

### モバイル開発
```bash
# XcodeでiOSプロジェクトを開く
npm run ios

# Android StudioでAndroidプロジェクトを開く
npm run android
```

## アーキテクチャ & 技術スタック

### コア技術
- **フロントエンド**: Vue 3.2.47 (Composition API)
- **ビルドツール**: Vite 4.1.1
- **言語**: TypeScript 4.9.5
- **モバイルフレームワーク**: Capacitor 4.5.0
- **UIコンポーネント**: カスタムVueコンポーネント
- **状態管理**: カスタムリアクティブストア (Pizzax)
- **ルーティング**: カスタムルーター (Nirax)
- **スタイリング**: CSSカスタムプロパティ付きSCSS

### 主要な依存関係
- **Misskey統合**: API通信用`misskey-js`
- **プッシュ通知**: OneSignal + Capacitorプッシュ通知
- **チャート**: Chart.jsと各種プラグイン
- **UI拡張**:
  - アニメーション用Canvas Confetti
  - 画像ギャラリー用PhotoSwipe
  - 画像編集用Cropper.js
  - 高度なアニメーション用GSAP
- **テキスト処理**:
  - MFM (Misskey Flavored Markdown) サポート
  - 絵文字レンダリング用Twemoji
  - シンタックスハイライト用Prism.js

### プロジェクト構造

```
src/
├── components/          # 再利用可能なVueコンポーネント
├── pages/              # ルートベースのページコンポーネント
├── ui/                 # UIレイアウトコンポーネント (universal, deck, classic, visitor)
├── directives/         # カスタムVueディレクティブ
├── themes/             # テーマ定義 (JSON5形式)
├── locales/            # 国際化ファイル
├── scripts/            # ユーティリティ関数とヘルパー
├── widgets/            # ダッシュボードウィジェット
├── filters/            # データ変換フィルター
├── types/              # TypeScript型定義
├── assets/             # 静的アセット
├── account.ts          # ユーザーアカウント管理
├── store.ts            # アプリケーション状態管理
├── router.ts           # アプリケーションルーティング
├── init.ts             # アプリケーション初期化
└── style.scss          # グローバルスタイル
```

### 設定ファイル

#### Capacitor設定
- `capacitor.config.dev.json` - ローカルサーバー付き開発設定
- `capacitor.config.prod.json` - 本番設定

#### ビルド設定
- `vite.config.ts` - カスタムエイリアス付きViteビルド設定
- `tsconfig.json` - TypeScript設定
- `vite.json5.ts` - テーマファイル用カスタムJSON5プラグイン

#### コード品質
- `.eslintrc.cjs` - Vue 3 + TypeScript用ESLint設定
- テスト設定は未検出（package.jsonにCypressが記載されているが未設定）

### 環境変数
```bash
VITE_SERVER_PATH=https://miss-ririca.herokuapp.com/
VITE_ONE_SIGNAL_APP_ID=26c23e85-1fc8-4115-8cf3-f81338427bf3
VITE_NOTIFICATION_TOKEN_ENDPOINT=https://miss-ririca.herokuapp.com/api/setToken
```

## 主要なアーキテクチャパターン

### 1. ハイブリッドモバイルアーキテクチャ
- ネイティブプラットフォーム統合用Capacitor WebView使用
- モバイルビューポートに適応するレスポンシブデザイン
- iOSノッチ/Dynamic Island用セーフエリア処理
- プラットフォーム固有のCSSクラス（`ios`、`android`）

### 2. コンポーネントベースUI
- TypeScript付きモジュラーVue 3コンポーネント
- 再利用可能な動作のためのカスタムディレクティブシステム
- カスタマイズ可能なダッシュボード用ウィジェットシステム

### 3. マルチUIサポート
- **Universal**: デフォルトのレスポンシブモバイルUI
- **Classic**: 従来のMisskey Webレイアウト
- **Deck**: TweetDeckスタイルのカラムレイアウト
- **Visitor**: ログイン/登録インターフェース
- **Zen**: 最小限の集中モード

### 4. 状態管理
- カスタムリアクティブストア実装 (Pizzax)
- IndexedDB永続化付きアカウント管理
- リアルタイム切り替え付きテーマシステム
- オフライン機能用デバイスストレージ

### 5. 国際化
- Vue I18nによる多言語サポート
- デバイスからの動的言語検出
- 日付、数値のロケール固有フォーマット

### 6. プッシュ通知システム
- クロスプラットフォーム通知用OneSignal統合
- ターゲット通知用デバイスIDトラッキング
- バックグラウンド通知処理

## データベース & バックエンド

### クライアントサイドストレージ
- **IndexedDB**: アカウントデータ、オフラインキャッシュ
- **LocalStorage**: 設定、一時データ
- **デバイスストレージ**: Capacitor経由のネイティブモバイルストレージ

### バックエンド統合
- **Misskey API**: Misskeyサーバーインスタンスとの完全統合
- **WebSocketストリーミング**: MisskeyのストリーミングAPI経由のリアルタイム更新
- **プッシュサービス**: 通知トークン管理用カスタムバックエンド

## 開発ワークフロー

### セットアップ
1. リポジトリのクローン
2. 依存関係のインストール: `npm install`
3. `.env`で環境変数を設定
4. 開発サーバー起動: `npm run dev`

### モバイル開発
1. Webアセットのビルド: `npm run build`
2. ネイティブプラットフォームと同期: `npx cap sync`
3. ネイティブIDE開く: `npm run ios` または `npm run android`

### コード品質
- コードリンティング用ESLint
- Vue 3推奨プラクティス
- TypeScript strictモード有効
- コンポーネントComposition API推奨

## 重要な注意事項

### モバイル特化の改修
- プロジェクトはベースMisskeyコードにパッチを適用（`patch.diff`、`mypatch.patch`参照）
- iOS固有のセーフエリア処理
- タッチ最適化インタラクション
- モバイルビューポート最適化

### テーマシステム
- `src/themes/`内のJSON5ベースのテーマ定義
- 動的テーマ切り替え
- システム同期付きダーク/ライトモード
- カスタムCSSプロパティシステム

### パフォーマンス考慮事項
- ルートコンポーネントの遅延読み込み
- 画像最適化とキャッシング
- 大規模リスト用仮想スクロール
- 効率的な状態管理

### デプロイメント
- 開発と本番の両方のCapacitor設定をサポート
- 環境固有のビルドプロセス
- アプリストア展開準備完了（iOS App Store、Google Play）

## トラブルシューティング

### よくある問題
1. **ビルド失敗**: `npm run lint`でTypeScriptエラーを確認
2. **モバイルプレビュー**: Capacitor同期が最新であることを確認
3. **テーマ読み込み**: テーマファイルのJSON5構文を確認
4. **プッシュ通知**: OneSignal設定を確認

### 開発のヒント
- Web テスト用に`npm run dev`でブラウザ開発者ツールを使用
- モバイル固有機能用にネイティブデバイスデバッグを使用
- ネイティブプラグイン問題用にCapacitorログを確認
- API統合問題用にネットワークリクエストを監視

---

**注記**: このプロジェクトは、モバイルアプリ機能用の改修を施したMisskey v13クライアントコードをベースにしています。コアコンセプトとAPI詳細については、元のMisskeyドキュメントを参照してください。