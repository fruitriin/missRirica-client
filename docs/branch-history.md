# 1.x 系ブランチの歴史 — 本家追従方式の変遷と教訓

2.0 の設計判断の根拠となる、過去ブランチの考古学メモ。
（2026-07 に全ブランチを分析した結果の要約。詳細な差分棚卸しは [ririca-diff-spec.md](ririca-diff-spec.md)）

## 各ブランチの正体

| ブランチ | 期間 | 方式 | 結末 |
|---|---|---|---|
| `origin/1.6` | 2022-11〜2023-01 | submodule + 差分ディレクトリ `RiricaV13/` + `patchsV13.txt`（12.8万行 diff メモ） | ビルド前の手作業オーバレイコピーが暗黙前提で clone しても動かず、試作止まり |
| `origin/dev/1.6-3` | 2023-01〜02 | `src/` に本家フルコピー + `createPatch.sh` で `mypatch.patch` 自動生成 | ビルド可能になり **1.5.3 リリースの実体**に。ただし本家追従は毎回大手術（migrate/wip/retry の連打） |
| `origin/main` | 〜2023-02-20 | dev/1.6-3 と同型 | **リリース版 1.5.3 の最終断面**。`mypatch.patch` は dev/1.6-3・skykid と同一。src の差は MkSignin.vue の fix login 1件のみ |
| `origin/1.7` | 2023-05（2日間） | 本家を fork（misskey4ririca、現在は削除済み）して submodule 化。本体は semantic-ui 製ランチャ4ファイルのみ | v13.6.1→v13.11.3 を1コミットで追従。**方式として最も筋が良い**。CORS/pnpm/CI の立ち上げトラブルの末に停止 |
| `origin/v2/alpha` | 2023-05 | fork submodule を pnpm workspace で抱え、ラッパーから本家 frontend をランタイム注入 | file:// 環境との整合が取れず "fix?" 連打で停止 |
| `origin/v2-master` | 2023-07〜10 | Nuxt + misskey-js 直叩きのフルスクラッチ | ログイン+プレースホルダー画面で停止。「Misskey UI 全再実装は一人では割に合わない」の実証 |
| `origin/something-new` | 〜2023-10 | 旧 1.x 系派生（v2 系ではない） | ビルド調整のみ |
| `origin/skykid` | 2026-06 | dev/1.6-3 系 + ドキュメント整備（CLAUDE.md, RiricaCore.md, plan.md） | 復活準備。コードは未変更 |

## 教訓（2.0 の設計原則の出どころ）

1. **パッチファイルの再適用は本家の進化に勝てない**（dev/1.6-3 の migrate 連打）
   → 差分は rebase 可能な機能ブランチで持つ
2. **差分の置き場所は外へ**：リポジトリ内オーバレイ(1.6) → src 直書き(1.5) → 外部 fork(1.7) と
   段階的に外へ押し出した歴史そのものが答え。2.0 は 1.7 構造 + MISTEMS ブランチ運用
3. **フルスクラッチは2度死んだ**（v2/alpha, v2-master）→ 本家 UI をそのまま使う路線を堅持
4. **ネイティブ依存を frontend に直接埋めると差分が肥大する**（1.5 の init.ts）
   → fork 側は汎用フックのみ、実装はシェル側
5. **言語ファイルの部分オーバレイ（createLocal.sh）は成功パターン** → 2.0 でも流用
6. **フォーマッタを本家から変えない** — mypatch.patch の約1/3が prettier ノイズだった

## 旧ブランチの扱い

すべて削除せず保存する。特に `origin/main`（1.5.3 実体）と `origin/skykid`（ドキュメント）は
2.0 の仕様書の出典。v2-master の localStorage マルチアカウントスキーマと
Supabase push サンプル（`pages/index.vue` の registerNotification）は設計の参考資産。
