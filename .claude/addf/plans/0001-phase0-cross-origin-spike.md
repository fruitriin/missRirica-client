# Plan 0001: Phase 0 — クロスオリジン接続の検証スパイク

## 実装状況: 未着手

owner_feedback: 不要

> 出典: オーナー指示（2026-07-17、MissRirica 2.0 リブート計画の Phase 0）

## 関連 Plan

- [Plan 0002: Phase 1 — 土台の構築](0002-phase1-foundation.md) — 本 Plan の検証結果が前提

## 目的

MissRirica 2.0 の成立条件である「本家 frontend を origin ≠ インスタンスで動かせるか」を
最小コストで実証し、Go/No-Go を判定する。

## 現状の挙動

本家 misskey/develop の frontend は `<meta property="instance_url">` から `host`/`url` を
導出するが、`apiUrl`/`wsOrigin` は `window.location.origin` 固定
（`packages/frontend-shared/js/config.ts:14-15`）。配信元と異なるインスタンスへの
接続は想定されていない。詳細は [docs/ririca-diff-spec.md](../../../docs/ririca-diff-spec.md) の U1。

## 変更内容（項目・フェーズ）

### 項目1: 検証環境の準備

- **対象**: misskey4ririca の worktree（`ririca/instance-origin-decouple` 試作ブランチ）
- misskey/develop から frontend を単体ビルドし、静的サーバー（またはローカル vite）から配信する

### 項目2: 2行パッチ + メタ注入

- **対象**: `packages/frontend-shared/js/config.ts`
- `apiUrl` / `wsOrigin` を `address`（instance_url メタ）由来に変更
- 配信 HTML に `instance_url` メタを注入して任意インスタンスを指す

### 項目3: 実地検証（検証事項は diff-spec 末尾の Phase 0 リスト）

- クロスオリジン API 呼び出し（CORS・認証方式が bearer か body credential か）
- WebSocket ストリーミングのクロスオリジン接続
- トークンによるログイン → タイムライン表示まで到達するか
- 絵文字・アバター・メディアプロキシ・テーマ・locale など他の origin 前提の漏れを列挙

## 影響範囲

検証のみ。既存ブランチ・リポジトリへの恒久変更なし（試作ブランチは worktree 内）。

## テスト方針

ブラウザ（Playwright MCP 可）で実際にログイン→TL 表示を目視・スクリーンショット確認。
検証結果は本 Plan に追記し、判明した「origin 前提の漏れ」一覧を
docs/ririca-diff-spec.md に反映する。

## 破壊的変更の許容範囲

なし（読み取り検証のみ）

## 要オーナー確認

- CORS/WS が塞がれていた場合の代替方針（ネイティブ HTTP ブリッジ方式）への切替判断

## 完了条件

- [ ] 任意インスタンスへのトークンログイン → ホームタイムライン表示が成功、または不成立の技術的根拠を特定
- [ ] 検証結果（Go/No-Go と origin 前提の漏れ一覧）を docs/ririca-diff-spec.md に反映
- [ ] Go の場合: `ririca/instance-origin-decouple` の実装方針（upstream PR 化の可否含む）を確定 <!-- human-judgment -->

## AI 実装時間見積もり

1〜2セッション
