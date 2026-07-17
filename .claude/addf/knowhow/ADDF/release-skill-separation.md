---
title: リリーススキルの責務分割パターン
created: 2026-03-21
last_verified: 2026-07-06
depends_on: []
status: active
---

# リリーススキルの責務分割パターン

## 発見した知見

### スキル = ルーター、設定ファイル = 手順定義

リリース操作はプロジェクトごとに戦略が大きく異なる（バージョニングの有無、チェンジログ戦略、publish 方法）。汎用フェーズをスキルに固定するとダウンストリームに不要な制約を押し付ける。

**正しい責務分割:**

| レイヤー | 責務 | 例 |
|---|---|---|
| スキル（`addf-release.md`） | 種別判定 → 設定/exp 読み込み → 実行 → 経験更新 | ルーターのみ |
| upstream 設定（`Release.addf.md`） | ADDF 固有のリリース手順 | プレチェック、lock 更新、gh release |
| downstream 経験（`addf-release.exp.md`） | プロジェクト固有のリリース戦略 | npm publish、App Store 提出 |
| テンプレート（`templates/Release.md`） | exp 初回作成の参考例 | npm / iOS / Web の3パターン |

### 3回のブラッシュアップで到達した設計

1. **初回**: スキルに汎用 Phase 2-7 を定義 + ADDF 固有セクション → 責務が混在
2. **2回目**: 汎用 Phase をスキルに、ADDF 固有を設定ファイルに → ダウンストリームに汎用 Phase を押し付ける問題
3. **最終**: スキルはルーターのみ、全手順を設定ファイル/exp に委譲 → プロジェクト完全自由

### 経験ファイル（exp）による戦略定義

ダウンストリームのリリース戦略は完全にプロジェクト依存。テンプレートを押し付けるのではなく:
- 初回実行時に対話的にヒアリング → `addf-release.exp.md` を生成
- 2回目以降は exp に蓄積された戦略に従う
- 構造は `Release.addf.md` を参考にしてよいが、作り直してもよい

## プロジェクトへの適用

### upstream/downstream 自動判定

`CLAUDE.repo.md` の「プロジェクト種別」セクションを読んで判定:
- 「ADDF 開発プロジェクト」→ `Release.addf.md` を読む
- それ以外 → `addf-release.exp.md` を読む

### 新スキル設計時の指針

プロジェクトごとに戦略が異なる操作（リリース、デプロイ、テスト等）は:
1. スキルはルーターに徹する
2. 手順は設定ファイル or exp に委譲する
3. テンプレートは参考例として提供する

## 注意点・制約

- exp ファイルは `.gitignore` 対象のため、チーム共有には `.claude/Release.md`（コミット対象）を使う方法もあるが、現設計では exp に統一
- upstream リリースは全ダウンストリームに影響する。`--dry-run` を初回は必ず実行すること

## 参照

- `.claude/commands/addf-release.md` — スキル定義（ルーター）
- `.claude/addf/Release.addf.md` — upstream リリース手順
- `.claude/addf/templates/Release.md` — exp 作成の参考例（npm / iOS / Web）
