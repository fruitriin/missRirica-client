# Plan 0002: Phase 1 — 土台の構築（機能ブランチ群・統合スクリプト・Capacitor シェル）

## 実装状況: 未着手

owner_feedback: 不要

> 出典: オーナー指示（2026-07-17、MissRirica 2.0 リブート計画の Phase 1）

## 関連 Plan

- [Plan 0001: Phase 0 — クロスオリジン接続の検証スパイク](0001-phase0-cross-origin-spike.md) — 本 Plan は Phase 0 の Go 判定が前提
- [Plan 0003: プッシュ通知の設計（検討スタブ）](0003-push-notification-design.md) — シェルの構造が固まったら着手判断

## 目的

2.0 の開発が回り始める最小の土台を作る:
misskey4ririca の機能ブランチ群の初期実体、統合スクリプトの実働、Capacitor シェルの起動。

## 現状の挙動

- misskey4ririca には develop / ririca-main（= develop のコピー）のみ存在し、機能ブランチは未作成
- このリポジトリの `2.0` ブランチはドキュメントとスクリプト雛形のみで、ビルド可能なシェルがない
- `script/ririca-統合.sh` は雛形（実行未検証）

## 変更内容（項目・フェーズ）

### 項目1: 機能ブランチの初期実体（misskey4ririca 側）

- **対象**: `ririca/instance-origin-decouple`（Phase 0 の成果を清書）、`ririca/standalone-frontend`
- 各ブランチは upstream/develop 起点、意味のあるコミットに圧縮した状態で push

### 項目2: 統合スクリプトの実働確認

- **対象**: `script/ririca-統合.sh`
- 存在する機能ブランチのみで ririca-main を再生成できるようにし（未作成ブランチはスキップ可能に）、
  実行して ririca-main を更新

### 項目3: Capacitor シェル

- **対象**: このリポジトリの `src/`・`package.json`・`capacitor.config.*`・submodule `misskey/`
- submodule 追加（misskey4ririca @ ririca-main、リモート構成: origin=misskey4ririca, upstream=misskey-dev/misskey）
- Capacitor 7 で iOS/Android プロジェクトを生成
- ランチャ（インスタンス URL + トークン入力 → `instance_url` メタ注入 → frontend 起動）の最小実装
- ビルド・Lint コマンドを整備し CLAUDE.repo.md の「テスト」節を更新

## 影響範囲

このリポジトリの `2.0` ブランチ全体、misskey4ririca のブランチ構成。
旧ブランチ（main, skykid 等）には触れない。

## テスト方針

- `ririca-統合.sh` の実行で ririca-main が再生成されること
- シミュレータ（iOS または Android）でシェルが起動し、Phase 0 と同等のログイン→TL 表示が
  WebView 内で再現できること（Capacitor WebView origin での CORS/Secure Context 再検証を含む）

## 破壊的変更の許容範囲

`2.0` ブランチ内は自由。他ブランチ・misskey4ririca の develop は変更しない。

## 要オーナー確認

- デフォルトブランチを `2.0` に切り替えるタイミング
- アプリ ID・署名まわり（既存ストアアプリの継続 or 新規）

## 完了条件

- [ ] `ririca-統合.sh` が実行可能で、ririca-main が機能ブランチから再生成される
- [ ] シミュレータでシェルが起動し、任意インスタンスにログインして TL が表示される <!-- human-judgment -->
- [ ] CLAUDE.repo.md にビルド・テストコマンドが記載されている

## AI 実装時間見積もり

2〜3セッション
