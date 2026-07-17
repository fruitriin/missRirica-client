# Plan 0003: プッシュ通知の設計（検討スタブ）

## 実装状況: 未着手

## 分かっていること

- v1.5 は OneSignal + 自前サーバー（heroku、停止済み）で `{misskey_token, device_id, instance_url}` を登録していた
- v2 試作には Supabase Edge Function を push endpoint にする `sw/register` 呼び出しサンプルが残っている（`origin/v2-master:src/pages/index.vue`）
- 現行 Misskey は WebPush（ServiceWorker）が成熟しており、`sw/register` API でエンドポイント登録できる
- 2.0 の設計原則では fork 側に OneSignal を入れず、`ririca/push-hooks`（購読情報をシェルに渡す汎用フック）+ シェル側実装 + 中継サーバー（riin-service に新設想定）の3点構成
- 詳細は [docs/ririca-diff-spec.md](../../../docs/ririca-diff-spec.md) の U5

## 未解決の問い

- 中継方式: (a) Misskey の WebPush をサーバーで受けて APNs/FCM に変換して中継 (b) OneSignal 等の SaaS 続投 (c) ネイティブトークンを `sw/register` に直接載せる変則
- riin-service に載せるか、独立した小サービスにするか
- 既存アプリ（ストア公開中の 1.5.3）のユーザーの通知移行

## 着手のトリガー

- Plan 0002 完了（シェルの構造とブリッジ規約が固まった）時点で標準テンプレートに書き直して着手判断
