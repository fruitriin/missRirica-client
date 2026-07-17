---
title: CLAUDE.md の @FileName メンション展開
created: 2026-03-18
last_verified: 2026-07-06
depends_on: []
status: active
---

# CLAUDE.md の @FileName メンション展開

## 発見した知見
- CLAUDE.md 内で @FileName と書くと、そのファイルの内容がインラインに展開される
- クオートで囲む（`@FileName` やコードブロック内）と展開されず、リテラルとして扱われる
- CLAUDE.md から @展開で埋め込まれたファイル内の @メンションは、さらにネスト展開される（`CLAUDE.local.md` → `@CLAUDE.local.example.md` のパターンで確認済み）

## 運用判断基準

### @展開すべき場合（クオートなし）
- **ブートシーケンスで毎回読むべきファイル**: @TODO.md, @.claude/addf/Progress.md, @.claude/addf/Feedback.md — エージェントが手動で Read する手間を省き、セッション開始時に自動でコンテキストに載る
- **分割した設定ファイルの結合**: @CLAUDE.repo.md, @CLAUDE.local.example.md — CLAUDE.md を分割管理しつつ、実行時には1つのコンテキストとして統合する
- **経験的・蓄積的なファイル**: 内容が変化し、常に最新を参照すべきもの

### クオートすべき場合（展開しない）
- **パスをリテラルとして言及するとき**: 手順書の中で「`TODO.md` に追記する」のように操作対象として言及する場合
- **ファイル一覧の説明**: 「**`TODO.md`**: タスクバックログ」のように役割を説明する場合（内容の展開は別の箇所で行う）
- **コード例・テンプレート内**: スキル定義や knowhow 内で @FileName を文字列として書きたい場合

### 二重展開を避ける
- 同一ファイルを複数箇所で @展開するとコンテキストを無駄に消費する
- 展開は1箇所（ブートシーケンスなど最も重要な文脈）に集約し、他の箇所ではクオートで参照する

## 注意点・制約
- 展開はセッション開始時に行われる（CLAUDE.md 読み込み時）
- 展開対象はプロジェクト内のファイルパス
- ネスト展開が機能するため、`CLAUDE.local.md` → `@テンプレート` のような間接参照パターンが使える

## 参照
- CLAUDE.md のブートシーケンスで @TODO.md, @.claude/addf/Progress.md, @.claude/addf/Feedback.md を展開利用中
- CLAUDE.md から @CLAUDE.repo.md で分割設定を結合
- `CLAUDE.local.md` から @CLAUDE.local.example.md でテンプレートを展開
