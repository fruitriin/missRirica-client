# CLAUDE.repo.md

MissRirica 2.0 — Misskey 用 iOS/Android クライアントのリブート。
このリポジトリは薄い Capacitor シェル + 司令塔（計画・ドキュメント・統合スクリプト）。
Misskey 本体への差分は別リポジトリ [misskey4ririca](https://github.com/fruitriin/misskey4ririca) の
`ririca/*` 機能ブランチとして管理する（MISTEMS 式・rebase 前提）。

# プロジェクト種別

このリポジトリは **ADDF 利用プロジェクト** です。

# 正典ドキュメント（タスク着手前に読む）

- [README.md](README.md) — アーキテクチャと設計原則3箇条
- [docs/ririca-diff-spec.md](docs/ririca-diff-spec.md) — 本家 Misskey に対する差分の仕様書（U1〜U6）。機能ブランチ実装の正
- [docs/branch-history.md](docs/branch-history.md) — 1.x 系の教訓。設計判断に迷ったらここに戻る

# 2つのリポジトリの役割分担（最重要規約）

- **misskey4ririca**（fork 側）: 差分は「汎用の拡張ポイント」に限定。Capacitor・OneSignal・
  デバイス固有コードを入れない。フォーマットを本家から変えない（prettier 差分の混入禁止）。
  機能ブランチは upstream/develop に対して rebase 可能な状態を維持し、
  意味のあるコミットに圧縮しておく
- **missRirica-client**（このリポジトリ）: ネイティブ実装・ランチャ UI・統合スクリプト・計画

fork 側での作業もこのリポジトリの Plan として管理する（worktree 越しに実施）。

## コミットログ規約

日本語で書く。形式:

```
[領域] 変更内容の要約

詳細説明（必要な場合）
```

領域の例: `[docs]` `[shell]` `[script]` `[fork]`（misskey4ririca 側作業の記録）`[addf]`

## テスト

シェルのビルドチェーンは Phase 1 で整備予定。整備後にここへビルド・Lint・テストコマンドを記載する。
それまでの品質ゲート Stage 1 は「変更したドキュメント・スクリプトの整合確認」で代替する。

## 既知の制約（~/.claude/my-environment.md も参照）

- fork 側の重い操作（rebase・統合）は submodule `misskey/` または worktree で行う
- 旧ブランチ（origin/main = 1.5.3 実体、origin/skykid ほか）は仕様書の出典。削除しない
