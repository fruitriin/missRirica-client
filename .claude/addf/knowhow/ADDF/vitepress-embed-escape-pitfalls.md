---
title: 自由記述 Markdown を VitePress に埋め込むときの Vue コンパイル安全化
created: 2026-07-16
last_verified: 2026-07-16
depends_on:
  - .claude/addf/addfTools/generate-dashboard.py
  - .claude/addf/plans-add/0058-dashboard-html-review-ui.md
status: active
---

# 自由記述 Markdown を VitePress に埋め込むときの Vue コンパイル安全化

> 出典: Plan 0058（ローカルダッシュボード）。Plan 本文を VitePress のプランビューアに
> コピーしたところ Vue SFC コンパイルが落ち、レビュー3体がさらに2つの実クラッシュ
> 経路を実測再現した。

## 発見した知見

- **VitePress は md を Vue テンプレートとしてコンパイルするため、自由記述 md の
  裸のタグ様テキストで即死する**。`速報の<番号>` のような日本語タグだけでなく、
  `speculative/<concept>` のような**英字開始**のプレースホルダも
  `Element is missing end tag.` でビルドが落ちる（実測）。`{{ }}` も Vue 展開として
  解釈される。エスケープ方針は「HTML コメント（`<!--`）以外の `<` は全て `&lt;`、
  `{{` は `&#123;&#123;`」の全数エスケープが安全 — 「HTML タグに見えるものは残す」
  という選別は英字開始プレースホルダで必ず漏れる
- **インラインコード判定を「行内バッククォート split の偶奇」でやると、奇数個の
  バッククォートを含む行で残り全部がエスケープ免除になる**（code-review が
  vitepress build の実クラッシュまで再現）。CommonMark では閉じバッククォートが
  無ければコードスパンは成立しない（リテラル扱い）ので、正しくは**先読み
  マッチング**: 同じ連長の閉じデリミタが段落内に実在する場合のみスパン、
  無ければリテラル＝通常エスケープ続行。フェンス（``` / ~~~）も文字種・連長を
  区別しないと `` ``` `` 内の `~~~` で誤って閉じる
- **エスケープは「本文コピー」だけでは足りない — タイトル・状態注記・自由記述
  フィールド経由の挿入点が全て攻撃面**。Plan の H1 から抽出した title、
  feedback_ask、TODO 状態注記をページに f-string で挿入する全箇所が同じ危険を持つ。
  対応は挿入点ごとの個別対応ではなく **`sv()` のような共通ヘルパーに集約**し、
  「escape する経路としない経路の非対称」を構造的に無くす
- **エスケープ処理のテストは合成の敵対的入力（drift-injection）で書く**。実リポジトリに
  たまたま存在する危険文字列（今回なら Plan 0028 の `<concept>`）への grep に依存すると、
  (1) ダウンストリームでは対象が存在せず誤 FAIL、(2) 実コーパスが安全な間は
  リグレッションを検出できない、の両方で壊れる。テスト自身が mktemp サンドボックスに
  「裸タグ様テキスト・奇数バッククォート・タイトル内タグ」入りの合成 Plan を作って
  生成→検証する（`ADDF_DASHBOARD_ROOT` env でルート上書き）

## プロジェクトへの適用

- `generate-dashboard.py` の `esc_vue()` / `sv()` が実装本体。同種の
  「自由記述 md を VitePress・Vue 系 SSG に流し込む」機能を作るときはこの2つを流用する
- 公開ドキュメントサイト（Plan 0039 の `docs/`）は原本が管理された guides のため
  この問題が顕在化していないが、外部由来・エージェント自由記述の md を载せる場合は
  同じエスケープが必要になる

## 注意点・制約

- 全数エスケープは「原文の忠実表示」目的に最適化した選択。埋め込み先で意図的に
  生 HTML（チップ用 span 等）を使いたいページは、エスケープ前に生成側が挿入する
  （生成テンプレート側の HTML と、データ由来文字列のエスケープを分離する）
- 紛らわしい名前の共存に注意: `.claude/addf/Dashboard.md`（unattended 自走の
  差分まとめ・一時ファイル）と `.claude/addf/dashboard/`（本 knowhow の生成物
  ディレクトリ）は別物。Plan 0058 フェーズC で3つ目の
  `.claude/addf/DashboardComments.json`（アンカーコメント置き場・コミット対象）が
  加わった。grep・ドキュメント参照時に取り違えない

## フェーズC で追加された落とし穴（2026-07-16）

- **インラインコード内の `{{...}}` は「コードスパン不変」ポリシーでは守れない**。
  VitePress が v-pre を付けるのはフェンスコードのみで、インラインコードの
  `{{.go_template}}`（crit の Go template 変数の記述等）は SFC コンパイルで
  interpolation として解釈され `Error parsing JavaScript expression` でビルドが落ちる。
  対処はエスケープ側ではなくレンダラ側 — `markdown.config` で `code_inline` を
  `<code v-pre>` を出す実装に差し替える（`escapeHtml` 併用。原文忠実表示も保たれる）
- **生 HTML のパススルーを許すなら、タグバランスチェックとフォールバックをセットにする**。
  `<details>/<summary>` を許可した直後、閉じ忘れ1つで "Element is missing end tag" が
  ダッシュボード全体（全ページ・全プランビューア）を巻き込むことをレビューが実測した。
  `_collapse_tags_status()` のように開閉数を数え、不均衡なら全エスケープに戻して WARN を
  出す（安全側に倒しても「折りたたみにならず原文表示」なだけで壊れない）。
  この回帰テストのフィクスチャを書くとき、**本文中に閉じタグの文字列を「無い」と
  説明するために書くとカウンタが均衡してテストにならない**（自己言及の罠 —
  lint-residual-paths の Plan 0052 と同型）
- **VitePress の config `vite.server.port` は CLI の `--port` より優先される**。
  テスト・並行起動用に別ポートを使いたい場合は config 側を
  `Number(process.env.ADDF_DASHBOARD_PORT) || 5180` のように環境変数対応にする
- **生成物ディレクトリを rmtree + 全再生成すると、dev サーバー起動中の再生成が
  全ファイル HMR → ページリロードになり、ブラウザで入力中のテキストを消す**
  （オーナー実測）。対処は2段: (1) 生成を差分書き込みにする（既存内容と比較して
  変わったファイルだけ write。rmtree は dev サーバーの `.vitepress/cache` も
  巻き込むため廃止し、掃除は自分の管理領域〔トップ md・plans/*.md〕の個別 unlink に
  限定する）(2) 入力中テキストは localStorage に退避し、マウント時にパネルごと復元する
- **dev サーバーの `/api/*` ミドルウェアで read-modify-write するなら Promise キューで
  直列化する**。`await readReqBody()` を挟む素朴な実装は並行 POST で後勝ち上書きになり、
  ファイル全体を書き戻す設計ではコメント消失＝実害になる（レビュー中に stray な
  dev サーバーが2つ生き残っている実態も観測されており、並行書き込みは机上の懸念ではない）

## 関連ノウハウ

- [ドキュメントサイトで単一ソースを保つ](docs-site-single-source-sync.md) — ビルド時生成・「欠如 = SKIP」テスト設計の親パターン
- [同期 lint の設計](sync-lint-design.md) — 恒真式テストの罠・独立オラクル・動的アサーション化の教訓

## 参照

- `.claude/addf/addfTools/generate-dashboard.py` — 実装本体
- `.claude/addf/tests/tools/test-generate-dashboard.sh` — drift-injection テスト
- `.claude/addf/plans-add/0058-dashboard-html-review-ui.md` — 本知見が生まれた Plan
