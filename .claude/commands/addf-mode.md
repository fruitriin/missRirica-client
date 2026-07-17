---
name: addf-mode
description: |
  「迷ったときの作法（7割共有原則）」の3軸モードと unattended 情報伝達フラグを切り替える。
  引数なしで現在のモード表示。例: `/addf-mode nervous`、`/addf-mode unattended --notify`。
  オーナーの状況（目の前にいる/不在）や信頼度に合わせてエージェントの判断閾値を調整したいときに使う。
user_invocable: true
---

# addf-mode — 判断モード切替

CLAUDE.md「迷ったときの作法（7割共有原則）」の3軸モードを宣言・確認する。

## モード状態の保存先

`CLAUDE.local.md` の `# ADDF モード` セクションに保存する。
CLAUDE.local.md は .gitignore 対象かつ毎セッション自動読込のため、新しいブートステップなしで全セッションに行き渡る。

```markdown
# ADDF モード

trust: normal            # nervous(5割) | normal(7割) | full(9割)
responsiveness: relaxed  # interactive | relaxed | unattended
image_clarity: balanced  # specific(-1段) | balanced(±0) | vague(+1段)
dashboard_report: true   # unattended 時: 次セッション冒頭で Dashboard.md を表示
uncertainty_notify: false # unattended 時: 閾値割れ・投機分岐・障害時に外部通知
```

## 手順

### 引数なしの場合

1. `CLAUDE.local.md` の `# ADDF モード` セクションを読み、現在のモードを表示する
2. セクションが無ければ「デフォルト（trust: normal × responsiveness: relaxed）」と表示する

### 引数ありの場合

1. 引数を解釈する:
   - `nervous` / `normal` / `full` → trust 軸
   - `interactive` / `relaxed` / `unattended` → responsiveness 軸
   - `specific` / `balanced` / `vague` → image_clarity 軸
   - `--notify` / `--no-notify` → uncertainty_notify フラグ
   - `--dashboard` / `--no-dashboard` → dashboard_report フラグ
2. `CLAUDE.local.md` の `# ADDF モード` セクションを更新する（無ければ作成。他のセクションは触らない）
3. 変更後のモード一覧と、それが判断に与える影響（閾値と閾値割れ時の挙動）を一行で要約して表示する

### Plan 単位の宣言が優先

Plan のフロントマター（`trust:` / `responsiveness:` 等）が宣言されている場合、そのタスク中は Plan 側が優先される。
`/addf-mode` の設定はセッション全体のデフォルトとして機能する。

## 経験の活用

- 実行前に `addf-mode.exp.md` が存在すれば読み、過去の経験を考慮する
- 実行後、新たな教訓があれば `addf-mode.exp.md` に追記する
