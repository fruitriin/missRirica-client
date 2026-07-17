---
title: スキル設計パターン（Anthropic 社内知見ベース）
created: 2026-03-19
last_verified: 2026-07-06
depends_on: []
status: active
---

# スキル設計パターン（Anthropic 社内知見ベース）

> 出典: Thariq (Anthropic) "Lessons from Building Claude Code: How We Use Skills" (2026-03-18)
> https://x.com/trq212/status/2033949937936085378

## 発見した知見

### スキルはフォルダである

スキルは「マークダウンファイル」ではなく **フォルダ**。スクリプト・アセット・データ等を含められる。
ファイルシステム全体をコンテキストエンジニアリングと段階的開示（Progressive Disclosure）の手段として使う。

- 詳細な関数シグネチャ → `references/api.md` に分離
- 出力テンプレート → `assets/` に配置
- `references/`, `scripts/`, `examples/` フォルダで構成

### 9 つのスキルカテゴリ

| # | カテゴリ | 概要 | 例 |
|---|---|---|---|
| 1 | Library & API Reference | ライブラリ・CLI・SDK の正しい使い方 | billing-lib, frontend-design |
| 2 | Product Verification | コード出力の検証。Playwright/tmux 等と連携 | signup-flow-driver, checkout-verifier |
| 3 | Data Fetching & Analysis | データ・モニタリングスタックへの接続 | funnel-query, grafana |
| 4 | Business Process & Team Automation | 反復ワークフローの自動化 | standup-post, create-ticket |
| 5 | Code Scaffolding & Templates | フレームワークボイラープレート生成 | new-migration, create-app |
| 6 | Code Quality & Review | コード品質の強制・レビュー | adversarial-review, testing-practices |
| 7 | CI/CD & Deployment | フェッチ・プッシュ・デプロイ | babysit-pr, deploy-service |
| 8 | Runbooks | 症状→調査→レポートのワークフロー | oncall-runner, log-correlator |
| 9 | Infrastructure Operations | ルーチンメンテナンス・運用手順 | dependency-management, cost-investigation |

### スキル作成のベストプラクティス

1. **当たり前を書かない** — Claude が既に知っている情報は省く。Claude の「通常の思考」を変える情報に集中する
2. **Gotchas セクションを育てる** — スキル中で最も価値が高い。失敗パターンを蓄積して更新し続ける
3. **ファイルシステムで段階的開示** — 全情報をスキル本体に書かず、参照ファイルに分離して Claude に必要時に読ませる
4. **Claude をレールに乗せすぎない** — 指示が具体的すぎると柔軟性を失う。情報は与えるが適応の余地を残す
5. **セットアップを考慮する** — ユーザー固有の設定は `config.json` パターンで保存し、未設定時に質問する
6. **description フィールドはモデル向け** — セッション開始時にスキル一覧が作られ、description でトリガー判定される。要約ではなくトリガー条件を書く
7. **データを保存する** — ログファイル・JSON・SQLite 等でスキル内メモリを実現。`${CLAUDE_PLUGIN_DATA}` が安定した保存先
8. **スクリプトを同梱する** — Claude にコード生成ではなく合成（composition）に集中させる
9. **オンデマンドフック** — スキル呼び出し時のみ有効になるフック。常時有効にしたくないガードに有用（例: `/careful` で rm -rf をブロック）

### 配布方法

- **リポジトリチェックイン** (`.claude/skills/`) — 小規模チーム向け。チェックインするとモデルのコンテキストに加算される
- **プラグインマーケットプレイス** — スケール時に有効。ユーザーが選択インストール
- サンドボックスフォルダで試用 → トラクション獲得後にマーケットプレイスへ PR

### 計測

- PreToolUse フックでスキル使用をログし、人気度やトリガー不足を検出

## ADDF での応用

### カテゴリマッピング — ADDF の既存スキル・エージェント

| ADDF コンポーネント | カテゴリ | 備考 |
|---|---|---|
| `.claude/addf/knowhow/` + `addf-knowhow` | 1. Library & API Reference | **ライブラリ知識がそのままノウハウとして実装されている**。Anthropic の「Library & API Reference」スキルが SDK の使い方を教えるのと同じ役割を、ADDF はプロジェクト固有の知見ファイル群で果たす |
| `addf-gui-test` + `addf-ui-test-agent` | 2. Product Verification | `.claude/addf/addfTools/` にスクリプト群を同梱する構成は記事の推奨パターンそのもの |
| `addf-knowhow-filter` | 3. Data Fetching & Analysis | knowhow を Plan に応じてフィルタリングして返す — データフェッチの内部版 |
| `addf-dev` | 4. Business Process | TODO.md → Plan 選択 → 実装の反復ワークフロー自動化 |
| `.claude/addf/templates/` + Progress.md | 5. Code Scaffolding & Templates | ProgressTemplate からタスク進捗ファイルを生成するパターン |
| `addf-code-review-agent` + `addf-security-review-agent` | 6. Code Quality & Review | 品質ゲートの Stage 2 で並列実行するレビューエージェント群 |
| `addf-contribution-agent` | 7. CI/CD & Deployment | アップストリームへのコントリビューション検出 — デプロイではないが「コード配布」の自動化 |
| `addf-permission-audit` | 9. Infrastructure Operations | 権限設定の監査・分類・提案 |

### ADDF が既に実現しているパターン

| Anthropic の推奨 | ADDF での実装 |
|---|---|
| **Gotchas セクションを育てる** | **経験ファイル (.exp.md)** が同じ役割。スキル実行ごとに失敗パターンを蓄積し次回に活かす |
| **ファイルシステムで段階的開示** | `addf-knowhow-filter` がコンテキスト制御を担う。全 knowhow を読み込まず、Plan に関連するものだけをメインコンテキストに返す |
| **スクリプトを同梱する** | `.claude/addf/addfTools/` に Swift/Shell スクリプトを配置し、スキルから呼び出す（annotate-grid, clip-image, capture-window 等） |
| **オンデマンドフック** | `.claude/hooks/` の turn-reminder.sh / reset-turn-count.sh。セッション中に常駐するフック |
| **データを保存する** | `.claude/addf/Progress.md` がセッション横断の作業状態を保持。`.claude/addf/Feedback.md` がプロセス改善の蓄積 |
| **description はトリガー条件** | ADDF スキルの frontmatter で実装済み（例: `addf-knowhow-index` の「reindex 引数でインデックスを再構築」） |

### ADDF 固有の発展 — 記事にないパターン

- **knowhow = Library Reference の汎用化**: Anthropic は個別ライブラリごとにスキルを作るが、ADDF は `.claude/addf/knowhow/` という統一的なナレッジベースと `addf-knowhow-index` によるインデックスで、任意のトピックを動的に参照する仕組みを持つ。スキル数の爆発を防ぐアプローチ
- **エージェント分離**: 記事はスキル（commands）中心だが、ADDF はエージェント（`.claude/agents/`）をスキルと分離して定義。レビュー・テスト等の自律的なタスクはエージェントに委ね、ユーザー対話型の手順はスキルに残す
- **アップストリーム/ダウンストリーム分離**: `addf-` プレフィックスと `.addf.md` サフィックスで、フレームワーク由来とプロジェクト固有を区別。記事のマーケットプレイス配布とは異なるが、同じ「共有可能性」の課題を解決している
- **自己推進ループ**: `/loop` + `/addf-dev` による TODO.md 駆動の自律開発は、記事の `babysit-pr` や `standup-post` の発展形。単一タスク自動化を超えて、タスクバックログ全体の自動推進を実現

### 改善の余地

- **段階的開示の深化**: 現在の ADDF スキルは単一 .md ファイル。`references/` や `examples/` フォルダを設けてコンテキスト消費を削減できる
- **description の見直し**: 現行スキルの description を「いつトリガーすべきか」の観点で再点検する価値がある
- ~~**計測フックの導入**: PreToolUse フックでスキル使用頻度をログし、改善の優先度判断に使う~~ → **実装済み**（`.claude/hooks/skill-usage-log.sh` を `PreToolUse: Skill` で配線・2026-07-06 確認）

### ADDF 独自パターンの発展（Anthropic 記事にない）

Anthropic 記事の 9 カテゴリ・段階的開示・Gotchas 育成に加え、ADDF は運用実績から
以下のパターンを確立している。詳細は個別 knowhow を参照:

- **検出＝スクリプト・解釈＝エージェント**: 決定的な検出は Python/Shell に任せ、意味的な
  解釈と修復はエージェント側で行う。ドリフト検出（`lint-template-sync.py`）や
  裏付け検査（`lint-checklist.py`）で採用。詳細は [sync-lint-design.md](sync-lint-design.md)
- **exit code の3値化**: `0=OK` / `1=WARNING` / `2=ERROR` を統一し、run-all 側で
  責務（ERROR で失敗にする／WARNING は通す）を機械化する。詳細は [sync-lint-design.md](sync-lint-design.md)
- **同期契約の lint 化**: 「同期しろ」を意思で守るのではなくペア（ソース↔ミラー）を
  lint で機械的に検出する。ペア1〜7 の運用実績あり。詳細は [sync-lint-design.md](sync-lint-design.md) / [checklist-backing-lint.md](checklist-backing-lint.md)
- **オプトイン式スキル**: 常用しないスキルは `.claude/addf/optional/` に退避し、
  `enable = true` で有効化コピーを作る。詳細は [optional-skill-optin.md](optional-skill-optin.md)

## 注意点・制約

- この知見は Anthropic 社内での数百スキル運用から得られたもの。小規模プロジェクトでは全てが適用可能とは限らない
- `${CLAUDE_PLUGIN_DATA}` はプラグインシステム前提の変数。リポジトリチェックイン型スキルでは利用できない場合がある
- スキル間の依存管理は未成熟 — 名前参照でモデルが呼び出すのみ
- ADDF は commands/ ベースを採用。skills/ フォルダベースだと動作はするが `/` スラッシュコマンドとして認識されない。skills/ はマーケットプレイス（プラグイン）用の仕組みであり、リポジトリチェックイン型のスキルは commands/ が適切

## 参照

- 元記事: https://x.com/trq212/article/2033949937936085378
- 元ツイート: https://x.com/trq212/status/2033949937936085378
- Claude Code Skills 公式ドキュメント: https://code.claude.com/docs/en/skills
- Agent Skills コース (Skilljar): https://anthropic.skilljar.com/introduction-to-agent-skills

## 関連ノウハウ

- [同期 lint の設計 — 検出はツール、解釈と修復はエージェント](sync-lint-design.md) — addfTools へのスクリプト同梱構成の実例（lint-template-sync.py）・exit3値・SKIP 設計
- [手順書チェックリストの裏付け lint](checklist-backing-lint.md) — 検出＝スクリプト・解釈＝エージェントの応用例。責めないトーン設計
- [オプトイン式スキルの退避＋有効化コピー設計](optional-skill-optin.md) — スキル配布のもうひとつの選択肢（マーケットプレイスに載せない小規模チーム向け）

## 訂正履歴

### 2026-07-06
- 「改善の余地: 計測フックの導入」を実装済みに修正
  （根拠: `.claude/settings.json` の `PreToolUse: Skill` に `.claude/hooks/skill-usage-log.sh` が配線されている）
- ADDF 独自パターンとして「検出＝スクリプト・解釈＝エージェント」「exit 3値」「同期契約の lint 化」
  「オプトイン式スキル」を追記（根拠: それぞれ knowhow として独立している運用実績）
