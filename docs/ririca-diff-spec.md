# Ririca 差分仕様書 — v1.5.3 から抽出した「本家に対する本質的差分」

MissRirica 1.5.3（このリポジトリの `origin/main`、Misskey v13.6.1〜v13.11.3 断面ベース）が
本家 `packages/frontend/src` に加えていた変更の完全な棚卸し。
出典は `origin/main:mypatch.patch`（50ファイル・3,269行。ただし約1/3は prettier ノイズで実質差分なし）。

2.0 ではこのコードを機械的に移植しない。**この文書を仕様書として、各ユニットを
現在の misskey/develop に対する機能ブランチとして再実装する。**

## 差分の根本原理

本家 frontend は「`window.location.origin` = 接続先インスタンス」を前提とする。
MissRirica は「アプリの配信元（Capacitor WebView）≠ インスタンス。接続先はログイン時に決まり、
アカウント切替で変わる」。1.5 の本質的差分のほぼすべてが、この前提の破壊箇所リストである。

### 2.0 での攻略法（v13 時代との違い）

現在の develop では本家自身が半分解決している:

- backend が HTML に `<meta property="instance_url">` を注入し、
  `packages/frontend-shared/js/config.ts` がそれを読んで `host` / `url` を導出する（実装済み）
- 残る固定点は同ファイルの `apiUrl` / `wsOrigin` の2定数（`window.location.origin` 固定）のみ

よって 2.0 の設計は:

1. シェルがアプリ起動**前**に、選択中インスタンスの URL を `instance_url` メタとして DOM に注入
2. fork 側パッチは「`apiUrl` / `wsOrigin` を `address`（=メタ）由来にする」2行+α のみ
3. インスタンス／アカウント切替はリロード方式。config は静的定数のままでよい

これにより 1.5 で最も痛かった「config.ts を `$i` 依存にする」逆転（config→account の循環依存で
os.ts / stream.ts の改造が芋づる式に必要になった元凶）が不要になる。

## ユニット別仕様

### U1: instance-origin-decouple（接続先の動的化）

v1.5 での該当差分:

| v13 ファイル | 変更内容 |
|---|---|
| `config.ts` | host/hostname/url/apiUrl を `$i.instanceUrl` から算出。wsUrl・updateLocale 削除 |
| `os.ts` | api/apiGet を `new Misskey.api.APIClient({origin: $i?.instanceUrl})` 生成に変更 |
| `stream.ts` | stream を「$i がある時だけ `$i.instanceUrl` に接続」に変更（未ログイン時 null） |
| `components/MkMention.vue` | avatar URL を `${$i.instanceUrl}/avatar/...` に |
| `pages/about.vue` | version をインスタンスごとに localStorage から取得 |

2.0 での実装方針: 上記の大半は**メタ注入方式で消滅**する。fork 側に残るのは
`frontend-shared/js/config.ts` の apiUrl/wsOrigin の2行と、未ログイン時に stream/api を
生成しない起動ガード。**upstream PR 候補**（フロントエンド分離配信の自然な延長）。

### U2: standalone-frontend（シェルから読める静的ビルド）

v1.5 での該当差分:

| 項目 | 変更内容 |
|---|---|
| `i18n.ts` + `src/locales/` | サーバー配信 locale を廃し、全言語 JSON を直 import してバンドル。Ririca 独自文言（`ririca.*`）をオーバレイ（`script/createLocal.sh`） |
| `src/assets/` | client-assets を同梱し vite alias で解決 |
| `init.ts` | ServiceWorker 登録の解除、`vite/modulepreload-polyfill` 削除 |
| `scripts/emoji-base.ts` | Twemoji/FluentEmoji を外部 URL に（要再検討: インスタンス相対でよいか） |

2.0 での実装方針: vite の base/asset 設定、SW 登録スキップ、locale 同梱を1ブランチに。
locale の Ririca 文言オーバレイ（ja/en/ko）は 1.x の `createLocal.sh` の仕組みを現代化して流用。

### U3: token-signin（ログイン導線）

v1.5 での該当差分:

| 項目 | 変更内容 |
|---|---|
| `components/MkSignin.vue` | パスワード/TOTP/WebAuthn を廃し「インスタンス選択 + アクセストークン直入力」に置換 |
| `src/miauth.ts`（新規） | MiAuth フロー（authUrl / getToken）の独自実装 |
| `pages/welcome.vue` ほか | エントランスを Ririca 用に置換（利用規約チェック・言語選択） |

2.0 での実装方針: ログイン前 UI はシェル側（fork 外）に置けないか最初に検討する。
1.7 が実証した「未ログイン時はランチャ画面だけ表示し、アプリ本体を起動しない」方式なら
MkSignin の置換自体が不要になる可能性がある。MiAuth を第一候補、トークン直入力をフォールバックに。

### U4: multi-account（インスタンス横断のアカウント管理）

v1.5 での該当差分:

| 項目 | 変更内容 |
|---|---|
| `account.ts` | 全メソッドに instanceUrl を追加。アカウントを instanceUrl 付きで IndexedDB 永続化 |
| `pages/settings/accounts.vue` | 各アカウントを対応インスタンスの APIClient で解決 |
| `components/MkMenu.vue` | ユーザーメニューに host 表示 |
| `theme-store.ts` / `pizzax.ts` | サーバーレジストリ同期を無効化（インスタンス間で共有できないため） |

2.0 での実装方針: アカウント一覧（instanceUrl + token）の管理はシェル側で持ち、
切替＝メタ注入し直してリロード。fork 側はレジストリ同期の無効化（または
インスタンスごとの分離）のみ。v2-master に localStorage スキーマの叩き台あり
（`usersStorage.users: Record<UserId,{url,accessToken}>` + `mainUserId`）。

### U5: native-hooks + push（ネイティブ統合）

v1.5 での該当差分（**2.0 ではこの方式を採らない**）:

| 項目 | 変更内容 |
|---|---|
| `init.ts` | Capacitor Device/App を直 import、async ブートストラップ化、Android backButton、OneSignal 登録、通知トークンを自前サーバーに POST |
| `scripts/theme.ts` | applyTheme 末尾で iOS StatusBar のスタイル連動 |
| `pages/timeline.vue` | カメラ権限リクエスト |

2.0 での実装方針: fork 側には `window.__ririca` ブリッジ規約の**汎用フックだけ**を追加
（例: テーマ適用後フック、起動完了フック、push 購読フック）。Capacitor・OneSignal・
権限まわりの実装はすべてシェル側。push の中継サーバーは riin-service に新設
（v1.5 は heroku、v2 試作は Supabase Edge Function だった）。

### U6: mobile-ui（UI 小改修群）

v1.5 での該当差分（各々独立・小規模）:

- `ui/_common_/common.vue`: StreamIndicator・ローディングバー抑制
- `components/MkDonation.vue`: 寄付誘導 → MissRirica の使い方リンクに差替
- `pages/settings/index.vue`: Email 未設定警告の削除
- `ui/visitor/b.vue`: GitHub リンクを Misskey/MissRirica の2択ポップアップに
- 実績アイコン・バッジ色の変更、`$i?.policies?.` のオプショナル化 ほか

2.0 での実装方針: 1本の `ririca/mobile-ui` ブランチにまとめる。個々は現物を見て取捨選択。

## v1.5 差分のうち捨てるもの

- prettier 由来のフォーマット差分（`mypatch.patch` の約1/3）— 本家フォーマットに完全準拠する。
  **フォーマットを本家から変えないことが squash/rebase 運用の最重要規約**
- `.orig` / `.rej` のマージ残骸
- `scripts/sound.ts` の Web Audio 化 — 本家がサウンド機構を刷新済みのため現物確認してから判断
- `scripts/upload.ts` の blueimp-load-image 化 — 同上
- plan.md の複数クライアントバージョン同梱構想 — 2.0 のスコープ外

## 検証事項（Phase 0）

1. 任意インスタンスへのクロスオリジン API 呼び出し（CORS、認証方式が bearer か body credential か）
2. WebSocket（ストリーミング）のクロスオリジン接続
3. `instance_url` メタ注入 + apiUrl/wsOrigin 2行パッチだけで TL 表示まで到達するか
4. 絵文字・アバター・メディアプロキシ・テーマ・locale など、他に origin 前提が漏れている箇所の洗い出し
5. Capacitor WebView の origin（`capacitor://localhost`）で Secure Context 前提の API が動くか
