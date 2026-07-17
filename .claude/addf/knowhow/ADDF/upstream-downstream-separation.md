---
title: アップストリーム / ダウンストリーム分離パターン
created: 2026-03-19
last_verified: 2026-06-10
depends_on: []
status: active
---

# アップストリーム / ダウンストリーム分離パターン

## 発見した知見

ADD フレームワーク（アップストリーム）のファイルと、フレームワークを利用するプロジェクト（ダウンストリーム）のファイルを分離する3つのパターンが存在する。

### パターン 1: `.addf.` サフィックス — ADDF 固有版
ダウンストリーム向けの汎用ファイルと、ADDF 開発向けの専用ファイルを並置する。

| ダウンストリーム | ADDF 開発 | 用途 |
|---|---|---|
| `ProgressTemplate.md` | `ProgressTemplate.addf.md` | 進捗テンプレート |
| `INDEX.md` | `INDEX.addf.md` | knowhow インデックス |

**使い分け**: ADDF 本体リポジトリでは `.addf.md` 版を使い、ダウンストリームでは無印版を使う。

### パターン 2: `ADDF/` サブディレクトリ — ADDF 由来コンテンツの隔離
ダウンストリームが自由に使えるディレクトリ内で、ADDF 由来のコンテンツをサブディレクトリに分離する。

| ダウンストリーム | ADDF 由来 |
|---|---|
| `.claude/addf/knowhow/*.md` | `.claude/addf/knowhow/ADDF/*.md` |
| `.claude/addf/plans/*.md` | `.claude/addf/plans-add/*.md` |

**使い分け**: ダウンストリームは `.claude/addf/knowhow/` 直下に自プロジェクトの knowhow を置く。ADDF 由来の knowhow は `ADDF/` 内にあり、混在しない。

### パターン 3: `addf-` プレフィックス — ADDF 由来コンポーネントの識別
スキル・エージェント・設定ファイルに `addf-` プレフィックスを付けて、プロジェクト固有のものと区別する。

| ADDF 由来 | プロジェクト固有 |
|---|---|
| `addf-knowhow.md` | `my-project-deploy.md` |
| `addf-code-review-agent.md` | `my-project-reviewer.md` |
| `addf-Behavior.toml` | （プロジェクト独自の設定） |

**使い分け**: ダウンストリームはプレフィックスなしでスキル・エージェントを追加する。`addf-` は触らない。

## プロジェクトへの適用

### 新しいファイルを追加するときの判断基準

```
Q: このファイルはダウンストリームでも使う？
├─ YES → 汎用版を作成（無印）
│   └─ ADDF 固有の拡張が必要？ → .addf.md 版も作成
├─ NO（ADDF フレームワーク開発専用）
│   ├─ knowhow → .claude/addf/knowhow/ADDF/ に配置
│   ├─ 計画 → .claude/addf/plans-add/ に配置
│   └─ スキル/エージェント → addf- プレフィックスで作成
└─ どちらでも使える共通知見 → .claude/addf/knowhow/ 直下に配置
```

### 現在の分離状況

| カテゴリ | ダウンストリーム | ADDF |
|---|---|---|
| 計画 | `.claude/addf/plans/` | `.claude/addf/plans-add/` |
| ノウハウ | `.claude/addf/knowhow/*.md` | `.claude/addf/knowhow/ADDF/*.md` |
| インデックス | `INDEX.md` | `INDEX.addf.md` |
| テンプレート | `ProgressTemplate.md` | `ProgressTemplate.addf.md` |
| スキル | プレフィックスなし | `addf-` プレフィックス |
| エージェント | プレフィックスなし | `addf-` プレフィックス |
| 設定 | `addf-Behavior.toml` | 同左（共用） |

## 注意点・制約

- `.addf.md` パターンは「同じ目的の2バージョン」なので、変更時は両方の同期を忘れないこと
- `ADDF/` サブディレクトリのファイルはダウンストリームでも参照可能（削除しない限り）
- `addf-` プレフィックスのスキルはダウンストリームから呼び出し可能（フレームワーク機能として提供）
- ダウンストリームが ADDF ファイルを上書き・変更しないよう、README やテンプレートで案内する
- **配布ファイルに ADDF 内部の計画番号を書かない**: エージェント定義・ガイド・テンプレート等のダウンストリーム配布ファイルで未実装機能に言及する場合、「Plan 0016 で導入予定」のような内部計画番号は使わず「将来バージョンで導入予定」のような汎用表現を使う。内部番号はダウンストリームユーザーに意味が通じず、`.claude/addf/plans-add/` は配布対象外のため参照もできない（Plan 0020 実装時に発見）

## 参照

- `CLAUDE.repo.example.md` の哲学セクション
- `.claude/addf/Feedback.md` の改善アクション（plans-add / INDEX.addf.md 運用）

## 関連ノウハウ

- [同期 lint の設計 — 検出はツール、解釈と修復はエージェント](sync-lint-design.md) — この分離規約を lint で機械的に守らせる設計と、ダウンストリーム配布時の SKIP 設計
- [既存プロジェクトへの導入パターン](existing-project-install-pattern.md) — `.addf.md` / `ADDF/` / `addf-` の3分離パターンを引用する側
