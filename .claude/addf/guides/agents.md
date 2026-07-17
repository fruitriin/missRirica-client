# 組み込みエージェント

品質ゲートやブートシーケンスで自動起動されるサブエージェント。
プロジェクトに合わせて **定義を変更・追加** できます。

## エージェント一覧

| エージェント | 用途 | 起動タイミング | カスタマイズ指針 |
|---|---|---|---|
| **addf-knowhow-agent** | Plan に関連するノウハウをフィルタリング | ブートシーケンス（タスク開始時） | — |
| **addf-code-review-agent** | コード品質・可読性のレビュー | タスク完了時の品質検証 | プロジェクトのコーディング規約を追記 |
| **addf-security-review-agent** | セキュリティ脆弱性の検査・報告 | タスク完了時（オプション） | 業界固有のセキュリティ基準を追記 |
| **addf-contribution-agent** | フレームワークへのコントリビューション候補検出 | タスク完了時の品質検証 | — |
| **addf-ui-test-agent** | スクリーンショットベースの UI 検証 | タスク完了時（オプション） | **プロジェクトの UI/UX 専門家として書き換える** |

## テスターエージェントはプロジェクトの専門家であるべき

エージェント定義は `.claude/agents/` に配置されています。特にテスター系エージェント（`addf-ui-test-agent`、`addf-security-review-agent`）は、プロジェクトのドメイン知識を持つ専門家として定義を書き換えることを強く推奨します。

**カスタマイズ例:**

| プロジェクト種別 | UI テストエージェントに追加すべき知識 | セキュリティエージェントに追加すべき知識 |
|---|---|---|
| EC サイト | 決済フロー・カート操作・商品表示の検証手順 | PCI DSS 準拠チェック |
| iOS Native | iOS シミュレータでの自動テスト・`xcrun simctl` 操作・画面サイズ別検証 | Keychain 利用・App Transport Security |
| SaaS ダッシュボード | グラフ描画・フィルタ操作・レスポンシブ対応 | 多テナント分離・認証フロー |
| Web API | API レスポンス検証・エンドポイント網羅テスト | 認証・認可・レート制限・入力バリデーション |

### 定義の書き換え方

`addf-ui-test-agent` はオプトイン式で、**原本は `.claude/addf/optional/agents/addf-ui-test-agent.md`** にあります
（`gui-test.enable = true` + `sync-optional-skills.py apply` で `.claude/agents/` に有効化コピーが
配置されます。詳細は `.claude/addf/guides/gui-test-setup.md`）。

1. 原本 `.claude/addf/optional/agents/addf-ui-test-agent.md` を開く（有効化コピーを直接編集しない —
   コピーは使い捨てで、原本との差分は同期時に WARNING になる）
2. プロジェクト固有のテスト基準・ドメイン知識を追記する
3. `addf-` プレフィックスはそのまま保持する（ADDF マイグレーション対象として管理されるため）
4. `uv run --python 3.11 .claude/addf/addfTools/sync-optional-skills.py apply` で有効化コピーに反映する
   （uv が無い場合は `python3` で直接実行。Python 3.11+ が必要）

### 新しいエージェントの追加

プロジェクト固有のエージェントを追加する場合は、`addf-` プレフィックスなしで `.claude/agents/` に配置します:

```
.claude/agents/
├── addf-code-review-agent.md     # ADDF 組み込み（マイグレーション対象）
├── addf-ui-test-agent.md         # GUI テスト有効時のみ存在（原本: .claude/addf/optional/agents/）
├── my-api-test-agent.md          # プロジェクト固有（マイグレーション対象外）
└── my-e2e-test-agent.md          # プロジェクト固有（マイグレーション対象外）
```

## 視点ずらしレビュー（ペルソナ並列）

レビューエージェントは実装者と同じモデルを使うため、**盲点も共有しがち**です。
`addf-code-review-agent` はペルソナ（視点）を指定して起動でき、複数ペルソナの並列実行で盲点をずらせます。

| ペルソナ | 視点 |
|---|---|
| `skeptic` | 実装者の前提・暗黙の仮定を疑う |
| `attacker` | 壊す目的で読む（境界値・想定外入力・並行アクセス）。コードロジックの穴専門 — システムレベルのセキュリティ基準は `addf-security-review-agent` と分業 |
| `newcomer` | 初見で意図が読み取れない箇所を指摘 |
| `maintainer` | 半年後の保守者として依存の罠・テストの抜けを指摘 |
| `domain-skeptic` | Plan と実装の乖離・要件の読み違えを検出 |

### 発動条件 — 常設しない

ペルソナ並列はコストがかかるため、通常タスクでは単体レビューを使います。

| 状況 | 体制 |
|---|---|
| 通常タスク完了時 | 単体（ペルソナなし） |
| マイルストーン・リリース直前 | 3体並列（skeptic + attacker + newcomer） |
| Plan が `mode: critical` を宣言 | 5体並列 |
| unattended（不在）モードでの自走（`/addf-mode unattended`） | 3体並列 |

ユーザーの監督が弱まるほどレビューを厚くする、という設計です。

### 起動方法

Agent ツールのプロンプトにペルソナを指定します:

```
Agent(addf-code-review-agent): 「ペルソナ: attacker。直近の git diff をレビューしてください」
```

集約ルール（重複排除・コンセンサス補正）は `.claude/agents/addf-code-review-agent.md` に記載されています。

## 品質ゲートでの使用

タスク完了時、以下の順序で品質検証が実行されます:

1. ビルド・Lint・テスト（失敗時は実装に差し戻し）
2. コードレビュー（`addf-code-review-agent`）
3. コントリビューション検出（`addf-contribution-agent`）

`addf-security-review-agent` と `addf-ui-test-agent` はオプションです。

> **品質ゲート拡張（オプション）**: Stage 1/Stage 2 の2段階構成で並列実行する拡張モードもあります。
> 詳細は `CLAUDE.repo.example.md` の「品質ゲート拡張」セクションを参照してください。
