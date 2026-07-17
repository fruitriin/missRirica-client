---
title: チェックリスト裏付け lint — 手順書に「通り得ない確認項目」を持たせない
created: 2026-07-02
last_verified: 2026-07-02
depends_on:
  - .claude/addf/addfTools/lint-checklist.py
  - .claude/addf/tests/tools/test-checklist-lint.sh
  - .claude/addf/Release.addf.md
status: active
---

# チェックリスト裏付け lint — 手順書に「通り得ない確認項目」を持たせない

> 出典: Plan 0027。addf-lock に「構造上パス不可能な確認項目」が2リリース連続で残り続けた教訓の機械化

## 発見した知見

### 手順書の「確認」ステップは A型/B型に分類し、必ず裏付けを持たせる

- **A型（機械検証可能な事実の主張）**: exit code で判定できる実行チェック（コードブロック・インラインコマンド）を添える。アサーションが**書けない**と気づいた瞬間が設計不良の発見であり、その項目は書けた場合でも初回実行の FAIL で露見する
- **B型（人間・エージェントの判断）**: `<!-- human-judgment -->` マーカーで「これは機械化しない判断である」ことを明示する

どちらの裏付けもない「確認」項目は努力目標に堕ちて theater 化する。最悪ケースは「TODO に存在しない属性（Critical）の不在を確認せよ」のような**述語が未定義で構造上判定不能**な項目 — 通らないまま「確認した」ことにされ続け、手順書がエージェントを静かに嘘つきにする。検出は `lint-checklist.py`（/addf-lint セクション9、WARNING のみ）。

### トーン設計: WARNING は「手順書側の点検」であってエージェントの糾弾ではない

lint の出力文言は「A型なら実行コマンドを添える / B型ならマーカーを付ける / 書けない項目は設計を見直す」と**手順書の直し方**だけを語る。「確認漏れ」「嘘」という語彙を使わない（Feedback.md オーナーフィードバック「責めない・強制しない・温度を保つ」）。

### Markdown のステップ抽出で踏んだ落とし穴（レビューで検出された実バグ2件）

1. **「〜こと」の行末アンカー**: `こと[。）)]?\s*$` だけだと「〜こと — 補足説明:」のように説明が続く自然な文が候補から漏れる。ダッシュ・コロン・読点の後続も候補にする
2. **リスト項目のブロック境界**: 「次の同レベル項目 or 見出し」だけで区切ると、リスト直後の引用・平文（`> 補足...`）が最後の項目のブロックに飲み込まれ、無関係な解説文中のコマンドが裏付けとして誤計上される。「項目のインデント以下に戻った平文・引用」でも打ち切る

どちらも**「lint 自身が検出対象の項目を見落とす」= メタ lint が自分の存在理由を検査できない**という、Plan 0027 が糾弾した問題と同型の穴だった。lint を書いたら、その lint が生まれるきっかけになった当のケースを**裏付けを剥がした状態で必ず再現テストする**（sync-lint-design の「ドリフト注入 TDD」と同じ作法）。

### 同期ペアを増やさない迂回: ホワイトリストという選択肢

ProgressTemplate 系にマーカーを足すと同期ペア1/2（Progress.md / ProgressTemplate.md への同時反映）が連鎖する。テンプレートがプロジェクト非依存でコマンドをインライン化できない項目は、lint 側の**理由付き WHITELIST** で除外する方が変更の波及が小さい。ホワイトリストには必ず理由を書く（無言の除外は将来の自分に「なぜ？」を残す）。

## 関連ノウハウ

- [sync-lint-design.md](sync-lint-design.md) — 検出はツール・解釈はエージェント、SKIP 設計、ドリフト注入テスト。本 lint はこの設計の直系
- [plan-status-drift-check.md](plan-status-drift-check.md) — 信用ベース運用と「責めない」WARNING の先例
- [rule-placement-execution-guarantee.md](rule-placement-execution-guarantee.md) — 参照では実行されない。実行チェックのインライン展開は実行保証の手段
- [optional-skill-optin.md](optional-skill-optin.md) — 手順書の裏付け要求を引用する側。migrate 追加ステップのコードブロック添付例
- [skill-design-patterns.md](skill-design-patterns.md) — 検出＝スクリプト・解釈＝エージェントの応用例として本 lint を引用する側。責めないトーン設計
- [plan-refinement-pattern.md](plan-refinement-pattern.md) — 完了条件の A型/B型分離の根拠として本 lint を引用する側
