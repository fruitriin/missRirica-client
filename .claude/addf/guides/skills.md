# フレームワークスキル

ADDF が提供するスキル（`/コマンド名` で呼び出し）:

## ノウハウ管理

| スキル | 呼び出し | 説明 |
|---|---|---|
| **addf-knowhow** | `/addf-knowhow <トピック>` | 実装知見を `.claude/addf/knowhow/` に記録。既存ノウハウとの重複チェック・統合を自動で行う |
| **addf-knowhow-index** | `/addf-knowhow-index [reindex]` | knowhow インデックスを参照、または `reindex` で再構築 |
| **addf-knowhow-filter** | `/addf-knowhow-filter <plan-path>` | Plan に関連するノウハウだけをフィルタリングして返す |
| **addf-knowhow-revise** | `/addf-knowhow-revise` | 鮮度低下（🔴 stale / needs-review）したノウハウを再検証し、訂正・superseded 遷移を記録 |
| **addf-knowhow-network** | `/addf-knowhow-network` | ノウハウ同士を相互リンクで接続し、知見ベースを wiki として育てる |

## 開発ループ

| スキル | 呼び出し | 説明 |
|---|---|---|
| **addf-dev** | `/addf-dev` | TODO.md から未実施タスクを自律選択し、実装・品質検証・コミットまで完遂。繰り返すには `/loop 1h /addf-dev` |
| **addf-mode** | `/addf-mode [nervous\|unattended 等]` | 「迷ったときの作法（7割共有原則）」の3軸モードと unattended 情報伝達フラグを表示・切り替え |

## プロジェクト管理

| スキル | 呼び出し | 説明 |
|---|---|---|
| **addf-init** | `/addf-init [check]` | プロジェクトの初期セットアップ（引数なし）または構造検証（`check`） |
| **addf-migrate** | `/addf-migrate [target]` | ADDF フレームワークを最新版にアップグレード |
| **addf-lint** | `/addf-lint` | フレームワーク整合性チェック（JSON構文・権限・frontmatter・INDEX等） |
| **addf-release** | `/addf-release [minor]` | リリース（チェンジログ・バージョン採番・publish） |
| **addf-permission-audit** | `/addf-permission-audit` | 権限要求の分析・分類・settings ファイルへの追加提案 |
| **addf-overview** | `/addf-overview` | CLAUDE.md・スキル・フック・エージェントのエコシステム概要を `.claude/addf/project-overview/` に生成 |

## 経験管理

| スキル | 呼び出し | 説明 |
|---|---|---|
| **addf-experience** | `/addf-experience` | スキル経験ファイル（`.exp.md`）参照の自己整合性・書式健全性を検証 |

## GUI テスト（オプション）

GUI 関連スキルはオプトイン式です（原本は `.claude/addf/optional/`、有効化するまで発見パスに存在しません）。
`.claude/addf/Behavior.toml` で `enable = true` に設定し、
`uv run --python 3.11 .claude/addf/addfTools/sync-optional-skills.py apply` で有効化コピーを配置してください
（uv が無い場合は `python3` で直接実行。Python 3.11+ が必要。手順の詳細は `.claude/addf/guides/gui-test-setup.md`）。macOS のみ対応。

| スキル | 呼び出し | 説明 |
|---|---|---|
| **addf-gui-test** | `/addf-gui-test <シナリオ>` | `docs/test-scenarios/` のシナリオに基づき GUI テストを実行 |
| **addf-annotate-grid** | `/addf-annotate-grid <path>` | PNG 画像にグリッド線と座標ラベルを描画（LLM の座標認識用） |
| **addf-clip-image** | `/addf-clip-image <path>` | PNG 画像の指定領域を切り出し（注目領域の抽出用） |
