---
name: addf-permission-audit
description: |
  セッション中の権限要求を分析し、3パターン（アップストリーム/ダウンストリーム/汎用）に分類して適切な settings ファイルへの追加を提案する。
  権限ダイアログが頻繁に出るとき、settings.json を整理したいとき、新しいツールの権限配置先を判断したいときに使う。
user_invocable: true
---

# 権限要求の監査・分類

## 引数
- `$ARGUMENTS`: 省略可。`apply` を指定すると提案を自動適用する。

## 手順

### 1. ノウハウ読み込み
`.claude/addf/knowhow/ADDF/permission-settings-pattern.md` を読み、以下を把握する:
- 3パターン × 2プロジェクト種別の分類ルール
- 権限フォーマットの技術仕様（評価順序、ワイルドカード構文、`:*` 非推奨など）

### 2. プロジェクト種別の判定
`CLAUDE.repo.md`（または `CLAUDE.repo.example.md`）を読み、以下を判定する:
- **ADDF 開発プロジェクト**: `addf-development-project: true` またはそれに類する記述がある
- **ADDF 利用プロジェクト**: 上記がない（デフォルト）

### 3. 現在の権限設定を読み込み
- `.claude/settings.json` の `permissions.allow` / `permissions.ask` / `permissions.deny`
- `.claude/settings.local.json` の `permissions.allow` / `permissions.ask` / `permissions.deny`（存在すれば）
- `permissions.deny` の過不足（Plan 0043 の事後観測方式で段階調整する対象）も監査対象に含める

### 4. セッション中の権限要求を収集
セッションのトランスクリプトまたは直近の操作ログから、ユーザーが承認した権限要求を収集する。
収集できない場合は、`git diff` で settings ファイルの変更履歴から最近追加された権限を分析する。

### 5. 各権限を分類

| パターン | 判定基準 |
|---|---|
| **アップストリーム** | ADDF フレームワーク開発でのみ必要（sed での大規模リネーム、swiftc ビルド、addfTools 操作等） |
| **ダウンストリーム** | プロジェクト固有のビルド・テスト・デプロイに必要 |
| **汎用** | git 操作、ファイル操作など、どのプロジェクトでも共通して必要 |

### 6. 配置先を決定

#### ADDF 開発プロジェクトの場合
| パターン | 配置先 |
|---|---|
| アップストリーム | `settings.local.json` |
| ダウンストリーム | `settings.json` |
| 汎用 | `settings.json` |

#### ADDF 利用プロジェクトの場合
| パターン | 配置先 |
|---|---|
| アップストリーム | `settings.json` |
| ダウンストリーム | `settings.json` |
| マシンローカル | `settings.local.json` |

### 7. 出力

```
## プロジェクト種別: ADDF 開発プロジェクト / ADDF 利用プロジェクト

## 権限監査結果

### settings.json に追加すべき権限
| 権限 | パターン | 理由 |
|---|---|---|

### settings.local.json に追加すべき権限
| 権限 | パターン | 理由 |
|---|---|---|

### 既に正しく配置されている権限
（確認のみ）

### 配置先が不適切な権限（要移動）
| 権限 | 現在の場所 | 正しい場所 | 理由 |
|---|---|---|---|
```

### 8. 構文チェック
提案する権限エントリが公式仕様に準拠していることを確認する:
- `:*` 構文（非推奨）を使っていないか → ` *` に修正
- 既存の設定に `:*` が残っていれば移行を提案する

### 9. コントリビューションレビュー
`addf-contribution-agent` をレビュアーとして起動し、提案内容の分離パターン遵守を検証する:
- settings.json に入れるべきでない権限が混入していないか
- settings.local.json に入れるべき権限が settings.json に入っていないか

### 10. apply モード
`$ARGUMENTS` に `apply` が指定されている場合:
- 提案に基づいて `settings.json` / `settings.local.json` を自動編集する
- 編集後の内容を表示して確認を求める

### 11. ユーザー確認
**コミットしない**。変更内容をユーザーに提示し、正しいか確認を求める。
ユーザーが承認した場合のみコミットする。

## 経験の活用
- 実行前に `addf-permission-audit.exp.md` が存在すれば読み、過去の判断パターンを考慮する
- 実行後、新たな分類判断の教訓があれば `addf-permission-audit.exp.md` に追記する
