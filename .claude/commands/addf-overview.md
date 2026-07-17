---
name: addf-overview
description: |
  CLAUDE.md・スキル・フック・エージェントのエコシステムを網羅的に記録し、
  .claude/addf/project-overview/ に静的ドキュメントとして出力する。
  ドキュメントは「実装方法別」ではなく「概念システム別」に分類する。
  最後に実施したコミットハッシュを .lock として保持。
  コードの変更後や大規模スキル追加時に実行してドキュメントを最新化する。
user_invocable: true
---

# addf-overview — ADDF エコシステム概要生成

## 目的

このプロジェクト（AutomatonDevDrive Framework）の「Claude Code ハーネス全体像」を人間が読めるドキュメントとして記録する。
分類の軸は **「概念的な関連性・システム単位」** であり、「スキル/フック/エージェント」という実装種別では分けない。

例: 品質ゲートシステムは addf-code-review-agent・addf-security-review-agent・addf-lint・addf-dev の品質ゲートフェーズをまとめて1ファイルに記録する。
これらは別々の実装（エージェント/スキル）だが、「品質保証」という機能で繋がっている。

## このプロジェクトの特性

**ADDF は AI コーディングエージェントのためのリポジトリ構成フレームワークである。**

- 個人エージェントのハーネスではなく、**配布されるフレームワーク**。下流プロジェクトに導入して使う
- SOUL.md や personas.toml は持たない。ペルソナではなくプロセスを定義する
- 三本柱: **計画駆動** (Plan-driven)・**ノウハウ蓄積** (Knowhow)・**品質ゲート** (Quality Gate)
- Claude Code ファーストパーティ + Codex 部分対応 + その他エージェント基本対応
- スキル・エージェント・フックはすべて `addf-` 接頭辞を持つ
- `.claude/addf/plans-add/` は ADDF 自身の開発計画、`.claude/addf/plans/` は下流プロジェクトの計画置き場
- addf-lock.json + addf-migrate によるバージョン管理・マイグレーション機構を持つ

## 出力先

すべて `.claude/addf/project-overview/` に作成する（`~/.claude` 配下には書かない）。
既存ファイルは上書き。

```
.claude/addf/project-overview/
├── INDEX.md               エントリポイント・ファイル一覧・最終更新日
├── claude-md-deps.md      CLAUDE.md とその依存・Boot Sequence
├── phase-flows.md         フェーズ/ステップ進行のあるスキルを自動検出して全掲載
├── interactions.md        システム間相互作用アスキーアート
├── system-*.md            概念システムごとのドキュメント（Step 3 で探索的に決定）
└── .lock                  最終実施時のコミットハッシュ（1行）
```

## モード選択

引数でモードを切り替える:

- **`/addf-overview`** (引数なし) → **full モード**。毎回ゼロベースで全要素をスキャンし、概念システムを探索的に発見する
- **`/addf-overview patch`** → **patch モード**。.lock のコミットハッシュから git diff を取り、変更があったシステムだけ再生成する

**どちらを使うかの判断基準:**
- スキル/フック/エージェントが**追加・削除**された → **full**（概念の境界が動く可能性）
- 既存ファイルの**中身だけ変わった** → **patch**（分類は変わらない）
- 迷ったら **full**

---

## patch モード手順

### P1: .lock を読み、差分を取得

```bash
LOCK_HASH=$(cut -d'|' -f1 .claude/addf/project-overview/.lock)
git diff --name-only "$LOCK_HASH"..HEAD
```

### P2: 変更ファイルを概念システムにマッピング

以下のルールで、どの system-*.md が影響を受けるか判定する。
マッピングテーブルは `.claude/commands/addf-overview.exp.md` の最新分類結果に基づいて判断する。

**`.exp.md` が存在しない場合** → patch モードは使用不可。「`.claude/commands/addf-overview.exp.md` が見つかりません。full モードで実行してください」と警告し、処理を停止する。
**新しいファイルがマッピングできない場合** → full モードで実行すること。実行者に警告を出す。

### P3: 影響するシステムだけ再生成

該当する system-*.md を更新する。interactions.md と phase-flows.md は更新しない。

### P4: 経験の記録 + .lock 更新 + 完了報告

---

## full モード手順

### Step 0: 前回の経験を読む

`.claude/commands/addf-overview.exp.md` が存在すれば Read する。
前回の実行で発見された「分類の迷い」「新概念の提案」「次回への申し送り」が記録されている。
今回の分類判断に活かせ。存在しなければスキップ（初回実行）。

### Step 1: 全データ収集（できる限り並列）

**A. プロジェクト構造**
- `CLAUDE.md` 全文
- `CLAUDE.repo.md`（存在すれば — 下流プロジェクト用テンプレート）
- `AGENTS.md` 全文
- `.claude/settings.json` と `.claude/settings.local.json`（※ settings.local.json は機密設定を含む可能性があるため、docs/ への内容出力禁止。フック定義の有無確認のみ）

**B. スキル全件**
- `.claude/commands/addf-*.md` を Glob で列挙し、**全ファイルを全文 Read**
- `.exp.md` は対応するスキルとペアとして記録

**C. エージェント全件**
- `.claude/agents/addf-*.md` を全件 Read

**D. フック全件**
- `.claude/hooks/*.sh` を全件 Read

**E. 主要ファイル・ディレクトリの確認**
- `CONTRIBUTING.md` — 存在確認と内容確認
- `TODO.md` — 存在確認と内容確認
- `.claude/addf/Progress.md`, `.claude/addf/Feedback.md` — 存在確認
- `.claude/addf/lock.json` — バージョン情報
- `.claude/addf/Behavior.toml` — 行動設定
- `.claude/addf/plans/`, `.claude/addf/plans-add/` — ls（件数と命名パターン）
- `.claude/addf/knowhow/` — ls（INDEX.md の有無、knowhow ファイル数）
- `.claude/addf/guides/` — ls（ガイド一覧）
- `.claude/addf/templates/` — ls（テンプレート一覧）
- `.claude/addf/addfTools/` — 存在確認

**F. コミット情報**
- `git log -1 --pretty=format:"%H|%s|%ad" --date=short`

---

### Step 2: フェーズフロー自動検出

**全スキルファイル**（Step 1B で取得済み）を走査し、
以下のパターンのいずれかを含むスキルを「フェーズ進行あり」と判定する：

```
検出パターン（大文字小文字・全半角を問わず）:
- "Phase [0-9]"
- "Step [0-9]"
- "### フェーズ" / "### Phase"
- "### ステップ" / "### Step"
- "## フロー" / "## 手順"（番号付きフローを持つもの）
- "1. " に続く複数の手順番号（3ステップ以上の番号付きリスト）
```

**スキルを対象リストに加える・除くのは実行者が判断**。
リストを事前に決め打ちしない。毎回全スキャンで発見する。

---

### Step 3: 概念システムの探索的発見

全スキル・エージェント・フック・設定ファイルを読んだ上で、**帰納的に**概念システムを発見する。
事前に決まったシステム一覧をなぞるのではなく、実データからグルーピングを導出する。

**手順:**

1. **全要素をフラットに並べる** — スキル・エージェント・フック・設定ファイル・ディレクトリの一覧表を作る
2. **クラスタリング** — 以下の3つの問いで要素同士の近さを判断する:
   - そのスキル/エージェント/フックの「主目的」は何か？
   - 使わなくなったとき、どの機能が失われるか？
   - 他のどの要素と最も密接に連携しているか？
3. **名前をつける** — クラスタごとに `system-[名前].md` のファイル名と一言説明を決める
4. **前回との差分を確認** — `.exp.md` に記録された前回の分類と比較する。変わったなら理由を言語化する
5. **1つの要素が複数のシステムに関与する場合は両方に記載**してよい

**決め打ち禁止:**
- システムの数は固定しない
- 前回と同じ分類になるとは限らない
- 「前回の分類を追認する」だけで終わらせない。毎回ゼロベースで全要素を見直す

**前回の分類（参考として読むが、拘束力はない）:**

前回（.exp.md に記録がある場合はそちらを優先）の分類がなければ、以下を初期仮説として使え:
- **計画駆動** (planning) — TODO.md・.claude/addf/plans/・addf-dev の計画フェーズ
- **ノウハウ** (knowhow) — .claude/addf/knowhow/・addf-knowhow・addf-knowhow-index・addf-knowhow-filter・addf-knowhow-agent
- **品質ゲート** (quality) — addf-code-review-agent・addf-security-review-agent・addf-lint・addf-permission-audit
- **ライフサイクル** (lifecycle) — Boot Sequence・Progress・Feedback・フック群・addf-dev の全体フロー
- **配布・導入** (distribution) — addf-init・addf-migrate・addf-release・addf-lock.json・CLAUDE.repo
- **ツールチェーン** (toolchain) — addf-gui-test・addf-annotate-grid・addf-clip-image・addf-ui-test-agent・addfTools

これらが今も妥当かどうか、Step 1 で収集したデータから再検証すること。

**残余チェック:**
全要素を分類した後、どのシステムにも入らなかった要素がないか確認する。
- 残余1-2件 → 既存システムへの追加を検討
- 残余3件以上で共通概念あり → 新たな概念システムを提案

**各システムの記録すべき内容:**
- 構成要素（スキル / エージェント / フック / ファイルを問わず全リスト）
- 設計思想（なぜこの設計か。CLAUDE.md・CONTRIBUTING.md との対応）
- 主要フロー（典型的な使われ方・連携フロー）
- 下流プロジェクトでのカスタマイズポイント
- 関連するシステム（他のどのシステムと連携するか）

---

### Step 4: ドキュメント生成

#### INDEX.md

```markdown
# ADDF エコシステム概要 — インデックス

> 生成日: YYYY-MM-DD | コミット: [8文字ハッシュ] [メッセージ]

AutomatonDevDrive Framework — AI コーディングエージェントのためのリポジトリ構成フレームワーク。
計画駆動・ノウハウ蓄積・品質ゲートの三本柱で、エージェントの自律的な開発を支える。

概念システム別に分類したドキュメント群。実装種別（スキル/エージェント/フック）では分けていない。

## 概念システム一覧

| ファイル | システム | 主な構成要素 |
|---|---|---|
| ... | ... | ... |

（Step 3 で探索的に決定した全システムを列挙）

## 補完ドキュメント

| ファイル | 内容 |
|---|---|
| [claude-md-deps.md](claude-md-deps.md) | CLAUDE.md 依存グラフ・Boot Sequence |
| [phase-flows.md](phase-flows.md) | フェーズ進行スキル一覧（自動検出） |
| [interactions.md](interactions.md) | システム間相互作用アスキーアート |

## 全要素カウント

- スキル: N本（うち .exp.md あり: N本）
- エージェント定義: N体
- フックスクリプト: N本
- ガイドドキュメント: N本（.claude/addf/guides/）
- 概念システム: N（Step 3 で探索的に決定）
```

---

各 `system-*.md` の冒頭テンプレート:

```markdown
# [システム名] — [一言説明]

> 概念単位の記録。実装がスキル/エージェント/フック/ファイルのどれであっても、
> 「[このシステムの機能]」に関わるものをまとめている。

## 構成要素

[スキル / エージェント / フック / ファイルを問わず、関連するものをすべてリスト]

## 設計思想

[なぜこの設計になっているか。CLAUDE.md・CONTRIBUTING.md との対応]

## 主要フロー

[このシステムの典型的な使われ方・連携フロー。アスキーアートで可。]

## 下流でのカスタマイズ

[下流プロジェクトがこのシステムをどうカスタマイズできるか]

## 関連するシステム

[他のどのシステムと連携するか]
```

---

#### phase-flows.md

```markdown
# フェーズ進行スキル一覧

> 毎回の実行時に全スキルをスキャンして自動生成。対象リストは決め打ちしない。
> 検出基準: Phase/Step 番号付き構造、または3ステップ以上の手順フローを持つスキル。
> 生成日: YYYY-MM-DD

## 検出結果: N本

[スキル名] — [1行説明]
[スキル名] — [1行説明]
...

---

## [スキル名]

[スキルの description]

[フェーズ・ステップ構造を抜粋。改変しない — スキル本文から直接引用]

---
```

---

#### interactions.md

概念システム間の相互作用をアスキーアートで表現。
Step 3 で決定したシステム群に基づいてその都度描く（決め打ちの図は置かない）。

**必須で描く図:**

1. **全システム関係図** — 探索的に発見した全システムがどう連携するか
2. **addf-dev の全フェーズフロー図** — 計画選択→knowhow 参照→実装→品質ゲート→コミットの流れ
3. **品質ゲートフロー図** — Stage 1（ビルド検証）→ Stage 2（並列レビュー）→ フィードバック集約

---

#### claude-md-deps.md

- CLAUDE.md の Boot Sequence を抽出（ブートシーケンスの各ステップと参照先）
- **CLAUDE.md と CLAUDE.repo.md の関係** — テンプレート（汎用）とプロジェクト固有設定の分離構造
- CLAUDE.md が参照する外部ファイルの依存グラフ（TODO.md, Progress.md, Feedback.md, CONTRIBUTING.md）
- settings.json のフック定義とトリガー条件

---

### Step 5: 経験の記録

`.claude/commands/addf-overview.exp.md` に今回の実行で得た知見を追記する。

**記録すべきもの:**
- **分類結果** — N個のシステムに分類（前回: M個）。変更があれば差分を記載
- **分類の判断で迷った要素** — どの要素をどのシステムに入れるか迷ったか、最終的にどう判断したか
- **前回からの変化** — 新しく増えた要素、消えた要素、システム境界が動いた箇所
- **次回への申し送り** — 次回実行時に注意すべきこと、検証したい仮説

**ファイル構造:**
ファイル先頭に `.claude/addf/templates/ExperienceTemplate.md` 準拠の固定セクション（うまくいったパターン / 注意すべき落とし穴 / 次回への改善点）を置き、その後に実行記録を時系列で追記する。

**実行記録のフォーマット:**
```markdown
## YYYY-MM-DD 実行記録

### 分類結果
- N個のシステムに分類（前回: M個）
- [変更があれば差分を記載]

### 判断メモ
- [迷った点、発見、改善点]

### 次回への申し送り
- [次回実行時に注意すべきこと]
```

新しい実行記録は**末尾に追記**する（過去の記録は消さない）。
**重要:** `.exp.md` は次回実行時の Step 0 で**必ず読む**。

---

### Step 6: .lock 更新

`.claude/addf/project-overview/.lock` に以下を書く：
```
HASH|COMMIT_MSG|DATE
```

Step 1F で取得した値を使用する。コミットメッセージにパイプ文字 `|` が含まれる場合は `-` に置換すること（patch モードの `cut -d'|'` が破損するため）。

---

### Step 7: 完了報告

- 生成ファイル一覧と行数
- 概念システムの数と名前（前回との差分があれば強調）
- フェーズ進行スキルとして検出した数・スキル名
- 前回 .lock との差分コミット数
- `.exp.md` に記録した主な知見（1-3行のサマリ）
