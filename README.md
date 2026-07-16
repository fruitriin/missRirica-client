# MissRirica 2.0

MissRirica は Misskey 用の iOS/Android クライアントです。

- iOS: https://apps.apple.com/app/missririca/id1659214999
- Android: https://play.google.com/store/apps/details?id=space.riinswork.missririca

2.0 は、Misskey v13 ベースだった 1.x 系を **misskey/develop 最新に追従できる構造**で作り直すリブートです。

## アーキテクチャ

MissRirica 2.0 は2つのリポジトリで構成されます。

```
misskey-ririca（仮称・standalone リポジトリ）
├── ririca/instance-origin-decouple   ← rebase 前提の機能ブランチ群（資産）
├── ririca/standalone-frontend
├── ririca/token-signin
├── ririca/native-hooks
├── ririca/push-hooks
├── ririca/mobile-ui
└── ririca-main                       ← 統合スクリプトで misskey/develop から再生成（使い捨て）

missRirica-client（このリポジトリ）
├── src/            ← 薄い Capacitor シェル（ランチャ・ネイティブブリッジ）
├── misskey/        ← submodule → misskey-ririca @ ririca-main
└── script/ririca-統合.sh
```

### 設計原則

1. **差分はパッチファイルではなく「rebase 可能な機能ブランチ」で持つ。**
   1ブランチ = 1つの意味。細かい fix や前進後退は rebase で意味のあるコミットに圧縮する。
   統合ブランチ `ririca-main` はいつでもスクリプトで再生成できる使い捨て。
   （[MISTEMS](https://github.com/fruitriin/misskey/tree/mistems-readme) と同じ戦略。コンフリクト解消は git rerere に記憶させる）
2. **fork 側の差分は「汎用の拡張ポイント」に限定する。**
   Capacitor・OneSignal・デバイス固有コードは fork に入れず、このリポジトリのシェル側に置く。
   fork 側は `window.__ririca` ブリッジ規約のような小さなフックだけを持ち、rebase で守る面積を最小にする。
3. **本家の origin=インスタンス前提を最小差分で外す。**
   本家は既に `<meta property="instance_url">` から接続先を導出する仕組みを持つ
   （`packages/frontend-shared/js/config.ts`）。残る固定点は `apiUrl` / `wsOrigin` の2行のみで、
   シェルが起動時にメタタグを注入すれば、本家コードはほぼ無改造で任意インスタンスを向く。
   アカウント／インスタンス切替はリロード方式（1.x と同じ）。

### なぜこの形か

1.x 系の歴史（詳細は [docs/branch-history.md](docs/branch-history.md)）:

- 1.6: 差分ディレクトリ+diffテキスト → 手順が暗黙化して破綻
- 1.5/dev-1.6-3: 本家フルコピー+パッチファイル → リリースには至ったが本家追従が毎回大手術
- 1.7: fork submodule + 薄いランチャ → 方式として最も筋が良かった（v13.6.1→v13.11.3 を1コミットで追従）
- v2 系: フルスクラッチ → UI 再実装の量で2度頓挫

2.0 は「1.7 の構造」に「MISTEMS のブランチ運用」を組み合わせたもの。

## 移植する差分の仕様

1.5.3（`origin/main` ブランチ、`mypatch.patch`）から抽出した本質的差分の仕様書:
[docs/ririca-diff-spec.md](docs/ririca-diff-spec.md)

## 開発フェーズ

| Phase | 内容 | 状態 |
|---|---|---|
| 0 | 検証スパイク: メタ注入+2行パッチでクロスオリジンログインが通るか（CORS/WS/認証） | 未着手 |
| 1 | 土台: 機能ブランチ群・統合スクリプト・Capacitor 7 シェル | 進行中（このスキャフォールド） |
| 2 | コア: standalone-frontend / token-signin / マルチアカウント | 未着手 |
| 3 | ネイティブ統合: native-hooks / push（riin-service 連携） | 未着手 |
| 4 | 磨き: mobile-ui / i18n / 実機確認 | 未着手 |
| 5 | リリース: CI・ストア審査 | 未着手 |

## Donation（寄付）

- 日本語で寄付: https://ofuse.me/fruitriin/letter
- Donation in English: https://ko-fi.com/fruitriin
- Patron: https://www.patreon.com/user/membership?u=79852147
