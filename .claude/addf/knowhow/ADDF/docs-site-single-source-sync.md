---
title: ドキュメントサイト（VitePress）で単一ソースを保つ — ビルド時生成 + リンク書き換え
created: 2026-07-10
last_verified: 2026-07-10
depends_on:
  - scripts/sync-docs.mjs
  - .claude/addf/webManual/.vitepress/config.mts
  - .claude/addf/plans-add/0039-docs-website.md
status: active
---

# ドキュメントサイトで単一ソースを保つ

> 2026-07-17（v0.7.0 後・Plan 0039）: サイト置き場を `docs/` から `.claude/addf/webManual/` へ
> 移動した（`docs/` はダウンストリームプロジェクト自身のために空ける — オーナー判断）。
> 本文のパスは移動後のものに更新済み。 — ビルド時生成 + リンク書き換え

> 出典: Plan 0039 フェーズ2（VitePress サイト骨格）。`.claude/addf/guides/` の内容を
> VitePress サイトに載せる際、`.claude/addf/webManual/guide/*.md` を手動コピー（コミット対象）にするか
> ビルド時生成物（gitignore 対象）にするかの設計判断

## 発見した知見

- **手動コピーは二重管理になり ADDF の「単一ソース化」哲学（`sync-lint-design.md`）と衝突する**。
  代わりに `scripts/sync-docs.mjs` という薄いビルドスクリプトを用意し、`npm run docs:sync`
  （`docs:dev`/`docs:build` から自動的に前段実行）で `.claude/addf/guides/*.md` を
  `.claude/addf/webManual/guide/*.md` へその都度コピーする設計にした。`.claude/addf/webManual/guide/*.md` は `.gitignore` 対象の
  生成物であり、ソースは常に `.claude/addf/guides/` 側のみ
- **相対リンクはコピー元のディレクトリ深さを前提にしているため、単純コピーだとリンク切れになる**。
  例: `.claude/addf/guides/setup.md` 内の `../../../CONTRIBUTING.md` は元の場所からは正しいが、
  `.claude/addf/webManual/guide/setup.md` に配置すると同じ相対パスでは解決できない
- **リンク先を解決してから振り分ける**: リンクを `[text](path)` パターンで抽出し、
  `resolve(dirname(元ファイル), path)` で絶対パスに解決した上で、
  - 他のガイド（`.claude/addf/webManual/guide/` に同居する）を指す場合 → `.claude/addf/webManual/guide/` 内の相対パス（`./name.md`）に書き換え
  - それ以外（docs サイトに含まれないリポジトリファイル）を指す場合 → GitHub の blob URL
    （`https://github.com/<owner>/<repo>/blob/main/<path>`）に書き換え
  - 画像（`![alt](path)`）は blob（HTML ページ）ではなく raw
    （`https://raw.githubusercontent.com/<owner>/<repo>/main/<path>`）に書き換える必要がある
    （blob URL は画像として描画されない）
  - アンカー（`#section`）は解決対象から一旦切り離し、書き換え後のパスに戻す
    （`resolve()` に `#section` ごと渡すと末尾に付着して不正なパスになる）
- **`ignoreDeadLinks: false`（デフォルト）のまま運用するとリンク書き換えバグが即ビルド失敗として
  露呈する**。EnumaElish は `ignoreDeadLinks: true` にしていたが、ADDF 本体はあえて `false` の
  ままにして「デッドリンク検出をドリフト対策の一部として使う」方針にした（Plan 0039 の設計）。
  この方針のおかげで、初回実装時にリンク書き換え漏れ4件を `npm run docs:build` 失敗として
  即座に検出できた
- **軽量な回帰テストは vitepress のインストールなしで書ける**: `node scripts/sync-docs.mjs` を
  実行し、生成された `.claude/addf/webManual/guide/*.md` に `](../` のような未書き換けの上位相対リンクが
  残っていないかを `grep` するだけで、リンク書き換えロジックの主要な退行は検出できる
  （`.claude/addf/tests/tools/test-sync-docs-links.sh`）。フルビルド（vitepress dev サーバ起動・
  実際のデッドリンク検出）は `npm run docs:build` の手動実行に任せてよい

## プロジェクトへの適用

- 同様の「既存 Markdown 資産を VitePress 等の静的サイトジェネレータに載せたいが、原本は別の
  場所に置いたままにしたい」場面では、この「ビルド時コピー + リンク解決書き換え」パターンが
  再利用できる
- リンク書き換えスクリプトは正規表現1本の実装で済むが、エッジケース（アンカー・画像・
  コードブロック内の疑似リンク）を最初から想定して実装しないと、後から静かに壊れる
  （実際に code-review で「アンカー・画像は考慮されていない」と Warning 指摘を受けた）
- ダウンストリームには配布しない ADDF 本体固有の基盤（`package.json`・`scripts/`・`.claude/addf/webManual/`）を
  追加する場合、対応するテスト（`.claude/addf/tests/tools/`）は
  「該当ファイル・ツール（今回は `node`）が無ければ SKIP」で書く。`.claude/addf/tests/` 自体は
  ダウンストリームにも配布されるため、本体固有機能のテストがダウンストリームで誤 FAIL しない
  ようにする（`sync-lint-design.md` の「欠如 = SKIP」設計の応用）

## 注意点・制約

- GitHub blob URL 書き換えはブランチ名を `main` に固定している。デフォルトブランチ名が
  異なるダウンストリームで流用する場合は要調整
- 画像・アンカーは今回のガイド群には実例が無く、ロジックは実装したが実データでの検証はできて
  いない（`.claude/addf/tests/tools/test-sync-docs-links.sh` にも画像/アンカーのテストケースは
  未追加）。将来ガイドに画像やアンカー付きリンクが増えたら、その時点で実例ベースのテストを足す

## 関連ノウハウ

- [同期 lint の設計](sync-lint-design.md) — 単一ソース化・「欠如 = SKIP」設計思想の親knowhow
- [VitePress 埋め込みのエスケープ落とし穴](vitepress-embed-escape-pitfalls.md) — 同じ「ビルド時生成」パターンをローカルダッシュボード（Plan 0058）に適用した際の Vue コンパイル安全化の知見

## 参照

- `scripts/sync-docs.mjs` — 実装本体
- `.claude/addf/tests/tools/test-sync-docs-links.sh` — 軽量回帰テスト
- `.claude/addf/plans-add/0039-docs-website.md` — 本知見が生まれた Plan
