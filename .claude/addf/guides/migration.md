# ADDF バージョンアップ

## `/addf-migrate` でアップグレード

```
/addf-migrate
```

このコマンドで ADDF フレームワークを最新版にアップグレードできます。

### 動作の流れ

1. `.claude/addf/lock.json` から現在のバージョンを読む
2. ADDF 本体リポジトリの最新版を取得
3. 差分を算出し、変更のプレビューを表示
4. .claude/addf/CHANGELOG.md から該当バージョン間の変更履歴を表示
5. ユーザーの確認後、変更を適用
6. ロックファイルを更新

### マイグレーション対象

| 対象 | マージ戦略 |
|---|---|
| スキル・エージェント定義（`addf-*`） | ADDF 側を優先（上書き） |
| Hooks・テンプレート・テスト | ADDF 側を優先 |
| `settings.json` | ダウンストリームの追加エントリを保持しつつマージ |
| `CLAUDE.md` | テンプレート部分を更新、プロジェクト固有追記は保持 |
| `AGENTS.md` | 上書き |

### マイグレーション対象外

- `.claude/addf/Progress.md`, `.claude/addf/Feedback.md` — プロジェクト固有
- `*.exp.md` — ローカル経験ファイル
- `CLAUDE.repo.md`, `CLAUDE.local.md` — プロジェクト固有設定
- `TODO.md`, `.claude/addf/plans/` — プロジェクトのタスク管理

### ターゲット指定

特定のバージョンにアップグレードする場合:

```
/addf-migrate <commit-hash-or-tag>
```

## 手動アップグレード

`/addf-migrate` を使わずに手動でアップグレードする場合:

1. ADDF リポジトリの最新版をクローン
2. `.claude/commands/addf-*.md` と `.claude/agents/addf-*.md` を上書きコピー
3. `.claude/hooks/` と `.claude/addf/templates/` を上書きコピー
4. `.claude/settings.json` の diff を確認し、手動でマージ
5. `.claude/addf/lock.json` を新しいコミットハッシュで更新
