---
title: オプトイン式スキルの退避＋有効化コピー設計
created: 2026-07-02
last_verified: 2026-07-02
depends_on:
  - .claude/addf/addfTools/sync-optional-skills.py
  - .claude/addf/tests/tools/test-optional-skills.sh
  - .claude/addf/guides/gui-test-setup.md
status: active
---

# オプトイン式スキルの退避＋有効化コピー設計

> 出典: GUI テスト環境マトリクス計画 フェーズ1。環境依存のスキル（GUI テスト等）を「能力レベル」でオプトインにする

## 発見した知見

### 設定オプトインだけでは足りない — スキル定義自体を発見パスから退避する

`Behavior.toml` の enable フラグだけだと、無効でもスキル定義がコンテキストに載り続け、
エージェントが「試みて失敗する」余地が残る。原本を `.claude/addf/optional/` に置き、有効時のみ
発見パス（`.claude/commands/` / `.claude/agents/`）へコピーで実体化すると、無効時は
**能力として存在しない**状態になる。

### 3原則と実装の要点

1. **原本が真実源**（コミット対象は原本のみ）
2. **有効化コピーは使い捨て**（gitignore 済み・再生成可能）
3. **改変されたコピーは削除も上書きもしない**（直接編集か原本更新か区別できないため WARNING で人間に委ねる）

- **シンボリックリンクではなくコピー**: Windows のリンクは Developer Mode / core.symlinks 依存。クローンで壊れる
- **同期の入口はスキルに置かない**: 退避対象のスキル自身を入口にすると鶏卵になる。スクリプト＋ガイド文書が入口
- **enable の型検証**: TOML で `enable = "false"`（文字列）は `bool()` で True になり意図と正反対に配置される。ERROR にする
- **孤児検出**: 原本のリネーム・削除で発見パスに取り残されたコピーは、原本列挙ベースの検査から永久に不可視。
  gitignore ADDF ブロックの列挙と突き合わせて「原本なきコピー」を検出する（列挙の陳腐化検査と相互に補完）

### レビューで検出された同型穴: 「参照では実行されない」再び

migrate 手順に「同期の再実行を案内」と**注記**したが、番号付き実行ステップにしていなかった
（rule-placement-execution-guarantee の教訓と同型。2レビューエージェントが独立指摘）。
新しい運用コマンドを導入したら、それを実行させる**番号付きステップ**を実行主体が読む手順書に置くこと。
ガイド文書（agents.md 等）の「ファイルが常在する」前提の記述も、オプトイン化と同時に洗い出して直す。

## 関連ノウハウ

- [sync-lint-design.md](sync-lint-design.md) — SKIP 設計・列挙の陳腐化・ドリフト注入テスト
- [rule-placement-execution-guarantee.md](rule-placement-execution-guarantee.md) — 参照では実行されない
- [checklist-backing-lint.md](checklist-backing-lint.md) — 手順書の裏付け要求。migrate 追加ステップはコードブロック付き
- [skill-design-patterns.md](skill-design-patterns.md) — スキル配布のもうひとつの選択肢として本知見を引用する側（マーケットプレイスに載せない小規模チーム向け）
- [speculative-integration-design.md](speculative-integration-design.md) — 「silent に捨てない」報告設計の前例として本知見を引用する側
- [worktree-dotdir-copy.md](worktree-dotdir-copy.md) — 「成功して見える失敗」を型検証で殺す同系の設計として本知見を引用する側
