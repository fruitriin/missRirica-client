# RiricaCore - MissRiricaの核心差分ドキュメント

MissRiricaはMisskey v13をベースとしたモバイル専用クライアントです。このドキュメントはMisskeyからMissRiricaを作るために加えられた主要な変更点、特にログインとアカウント管理を中心とした差分をまとめたものです。

## 1. 基本アーキテクチャの変更

### 1.1 Capacitorによるハイブリッドアプリ化
- **変更箇所**: プロジェクト全体
- **目的**: WebベースのMisskeyをiOS/Androidネイティブアプリとして動作させる
- **主要ファイル**:
  - `capacitor.config.dev.json` - 開発環境設定（ローカルサーバー接続）
  - `capacitor.config.prod.json` - 本番環境設定
  - `src/init.ts` - Capacitorプラグインの初期化処理

### 1.2 モバイルUI対応
- **変更箇所**: `src/ui/` ディレクトリ全体
- **主要変更**:
  - レスポンシブデザインの強化
  - タッチ操作の最適化
  - セーフエリア対応（iOS notch/Dynamic Island）
  - プラットフォーム固有のCSS class（`ios`, `android`）の追加

## 2. ログイン・認証システムの差分

### 2.1 アカウント管理の拡張（`src/account.ts`）

#### 主要な変更点:
1. **マルチアカウント対応の強化**
   ```typescript
   export async function addAccount(id: Account["id"], token: Account["token"], instanceUrl: string)
   export async function removeAccount(id: Account["id"])
   export async function getAccounts(): Promise<{ id: Account["id"]; token: Account["token"]; instanceUrl: string }[]>
   ```
   - IndexedDBを使用したアカウント情報の永続化
   - 複数インスタンス間でのアカウント切り替え機能

2. **instanceUrlの管理**
   - 各アカウントに `instanceUrl` を紐付け
   - 異なるMisskeyインスタンス間でのアカウント管理

3. **アカウント切り替えUI**
   ```typescript
   export async function openAccountMenu(opts: {...}, ev: MouseEvent)
   ```
   - ポップアップメニューでのアカウント選択
   - 新規アカウント追加機能の統合

### 2.2 認証フローの改善

#### MiAuth対応（`src/miauth.ts`）
- Misskey標準のMiAuth認証システムの実装
- OAuth-likeな認証フローの提供
```typescript
export class MiAuth {
  public authUrl(): string
  public async getToken(): Promise<string>
}
```

#### 認証ページの最適化（`src/pages/auth.vue`）
- モバイルでの認証体験の最適化
- `MkSignin` コンポーネントとの統合
- コールバックURL処理の改善

### 2.3 ログイン状態の永続化

#### LocalStorageからIndexedDBへの移行
```typescript
// 古いLocalStorageからIndexedDBへの移行処理
import { set } from "@/scripts/idb-proxy";
{
  const accounts = miLocalStorage.getItem("accounts");
  if (accounts) {
    set("accounts", JSON.parse(accounts));
    miLocalStorage.removeItem("accounts");
  }
}
```

## 3. モバイル固有の機能追加

### 3.1 プッシュ通知システム（`src/init.ts:629-661`）

#### OneSignalとの統合
```typescript
OneSignal.setAppId(import.meta.env.VITE_ONE_SIGNAL_APP_ID);
const deviceId = await Device.getId();
OneSignal.setExternalUserId(deviceId.uuid);
```

#### 通知トークン管理
- バックエンドサーバーとの通信による通知設定
- デバイスIDとMisskeyトークンの紐付け
- インスタンス固有の通知設定

### 3.2 デバイス情報の取得と活用
```typescript
import { Device } from "@capacitor/device";
export let storedDeviceInfo: Object;

const res = await Device.getInfo();
```
- プラットフォーム検出（iOS/Android/Web）
- 言語設定の自動検出
- デバイス固有の最適化

### 3.3 ネイティブアプリ機能
```typescript
App.addListener("backButton", (canGoBack) => {
  if (canGoBack) {
    history.back();
  } else {
    App.exitApp();
  }
});
```
- ハードウェアバックボタン対応
- アプリのライフサイクル管理

## 4. UI/UXの差分

### 4.1 ビューポート最適化
```typescript
// タッチデバイス用のビューポート設定
if (["smartphone", "tablet"].includes(deviceKind)) {
  const viewport = document.getElementsByName("viewport").item(0);
  viewport.setAttribute("content",
    `${viewport.getAttribute("content")}, minimum-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover`
  );
}
```

### 4.2 テーマシステムの拡張
- モバイル向けダークモード対応
- セーフエリアを考慮したスタイリング
- プラットフォーム固有のテーマ調整

## 5. 設定・環境管理

### 5.1 環境変数の追加
```bash
VITE_ONE_SIGNAL_APP_ID=26c23e85-1fc8-4115-8cf3-f81338427bf3
VITE_NOTIFICATION_TOKEN_ENDPOINT=https://miss-ririca.herokuapp.com/api/setToken
```

### 5.2 ビルド設定
- 開発用と本番用のCapacitor設定分離
- モバイルビルド用のNPMスクリプト追加

## 6. パッチファイルによる変更管理

### 6.1 変更ファイルの管理
- `patch.diff` - 元のMisskey v13からの差分
- `mypatch.patch` - 追加の修正パッチ
- 約50ファイル以上にわたる変更の体系的管理

### 6.2 主要な変更カテゴリ
1. **アカウント管理系**: `src/account.ts`, `src/pages/settings/accounts.vue`
2. **UI/UX系**: `src/components/` 配下の各コンポーネント
3. **初期化系**: `src/init.ts`, `src/config.ts`
4. **ページ系**: `src/pages/` 配下の各ページコンポーネント

## 7. 重要な技術的判断

### 7.1 なぜCapacitorを選択したか
- Webベースの既存Misskeyコードの最大限の再利用
- クロスプラットフォーム対応
- ネイティブ機能へのアクセス（プッシュ通知、デバイス情報等）

### 7.2 アカウント管理の設計思想
- 複数インスタンス対応の重要性
- オフライン時のアカウント情報保持
- セキュアなトークン管理

### 7.3 モバイル最適化の方針
- タッチファーストなUI設計
- ネイティブアプリライクな操作感
- バッテリー消費の最適化

## 8. 今後の開発指針

### 8.1 メンテナンス方針
- 上流のMisskey変更への追従
- パッチファイルベースの変更管理
- モバイル固有機能の継続的改善

### 8.2 拡張可能性
- 他のMisskeyフォーク（Firefish等）への対応可能性
- 追加のネイティブ機能の統合
- パフォーマンス最適化の余地

---

このドキュメントは、MissRiricaがMisskey v13をどのようにモバイルアプリ化したかの核心的な差分を示しています。特にログイン・アカウント管理周りの変更は、モバイルアプリとしての利便性とセキュリティを両立させるための重要な改良点となっています。