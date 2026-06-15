# MissRirica マルチバージョン対応実装計画書

## 概要
MissRiricaアプリケーションを拡張し、複数のMisskeyバージョン（v13、v2025.7.0、v2025.9.0など）のソースコードを保持し、アプリケーション内で動的に切り替え可能にする機能を実装する。

## 現状分析

### 現在の構造
- **単一バージョン**: 現在はMisskey v13ベースの単一バージョンのみ
- **ビルドプロセス**: Vite + Capacitorによる単一のビルドパイプライン
- **ソースコード**: `/src`ディレクトリに単一バージョンのソースが配置

### 技術スタック
- フロントエンド: Vue 3.2.47 + TypeScript 4.9.5
- ビルドツール: Vite 4.1.1
- モバイルフレームワーク: Capacitor 4.5.0
- パッケージマネージャー: npm

## アーキテクチャ設計

### 1. ディレクトリ構造

```
missRirica/
├── versions/                       # 各Misskeyバージョンのソースコード
│   ├── v13/
│   │   ├── src/                   # v13のソースコード
│   │   ├── package.json
│   │   └── vite.config.ts
│   ├── v2025.7.0/
│   │   ├── src/                   # v2025.7.0のソースコード
│   │   ├── package.json
│   │   └── vite.config.ts
│   └── v2025.9.0/
│       ├── src/                   # v2025.9.0のソースコード
│       ├── package.json
│       └── vite.config.ts
├── dist/                          # ビルド成果物
│   ├── v13/
│   ├── v2025.7.0/
│   └── v2025.9.0/
├── src/                           # バージョンセレクター（ランチャー）
│   ├── version-selector/          # バージョン選択UI
│   ├── version-manager/           # バージョン管理ロジック
│   └── app-shell/                 # アプリケーションシェル
├── shared/                        # 共通コンポーネント・ユーティリティ
│   ├── components/
│   ├── utils/
│   └── types/
└── capacitor/                     # Capacitorネイティブ統合
    └── plugins/
        └── version-switcher/      # バージョン切替プラグイン
```

### 2. バージョン管理システム

#### 2.1 バージョンマニフェスト
```typescript
// version-manifest.json
{
  "versions": [
    {
      "id": "v13",
      "displayName": "Misskey v13 (安定版)",
      "description": "従来の安定したバージョン",
      "releaseDate": "2023-01-01",
      "status": "stable",
      "entryPoint": "/dist/v13/index.html",
      "buildPath": "/versions/v13",
      "features": ["基本機能", "プッシュ通知", "テーマ"],
      "minApiVersion": "13.0.0",
      "maxApiVersion": "13.99.99"
    },
    {
      "id": "v2025.7.0",
      "displayName": "Misskey 2025.7.0",
      "description": "新機能搭載版",
      "releaseDate": "2025-07-01",
      "status": "beta",
      "entryPoint": "/dist/v2025.7.0/index.html",
      "buildPath": "/versions/v2025.7.0",
      "features": ["新UI", "高度な機能", "実験的機能"],
      "minApiVersion": "2025.7.0",
      "maxApiVersion": "2025.7.99"
    },
    {
      "id": "v2025.9.0",
      "displayName": "Misskey 2025.9.0",
      "description": "最新版",
      "releaseDate": "2025-09-01",
      "status": "experimental",
      "entryPoint": "/dist/v2025.9.0/index.html",
      "buildPath": "/versions/v2025.9.0",
      "features": ["最新機能", "開発版機能"],
      "minApiVersion": "2025.9.0",
      "maxApiVersion": "2025.9.99"
    }
  ],
  "defaultVersion": "v13"
}
```

#### 2.2 バージョン切替メカニズム

##### アプローチ1: iframe方式（シンプル）
```typescript
// src/version-manager/VersionLoader.ts
export class VersionLoader {
  private currentFrame: HTMLIFrameElement | null = null;

  async loadVersion(versionId: string): Promise<void> {
    const manifest = await this.getVersionManifest();
    const version = manifest.versions.find(v => v.id === versionId);

    if (!version) {
      throw new Error(`Version ${versionId} not found`);
    }

    // 既存のフレームを削除
    if (this.currentFrame) {
      this.currentFrame.remove();
    }

    // 新しいフレームを作成
    this.currentFrame = document.createElement('iframe');
    this.currentFrame.src = version.entryPoint;
    this.currentFrame.style.cssText = `
      position: fixed;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      border: none;
      z-index: 9999;
    `;

    document.body.appendChild(this.currentFrame);
  }
}
```

##### アプローチ2: WebView切替方式（高度）
```typescript
// capacitor/plugins/version-switcher/src/index.ts
import { WebPlugin } from '@capacitor/core';

export interface VersionSwitcherPlugin {
  switchVersion(options: { versionId: string }): Promise<void>;
  getCurrentVersion(): Promise<{ versionId: string }>;
  preloadVersion(options: { versionId: string }): Promise<void>;
}

export class VersionSwitcherWeb extends WebPlugin implements VersionSwitcherPlugin {
  async switchVersion(options: { versionId: string }): Promise<void> {
    // WebViewの内容を動的に変更
    const manifest = await this.loadManifest();
    const version = manifest.versions.find(v => v.id === options.versionId);

    if (version) {
      // Capacitor WebViewのソースを変更
      window.location.href = version.entryPoint;
    }
  }

  async getCurrentVersion(): Promise<{ versionId: string }> {
    const stored = localStorage.getItem('currentVersion');
    return { versionId: stored || 'v13' };
  }

  async preloadVersion(options: { versionId: string }): Promise<void> {
    // バックグラウンドでバージョンを事前ロード
    const link = document.createElement('link');
    link.rel = 'prefetch';
    link.href = `/dist/${options.versionId}/index.html`;
    document.head.appendChild(link);
  }
}
```

### 3. バージョンセレクターUI

```vue
<!-- src/version-selector/VersionSelector.vue -->
<template>
  <div class="version-selector">
    <h1>Misskeyバージョンを選択</h1>

    <div class="current-instance">
      <span>接続先: {{ currentInstance }}</span>
      <span>推奨バージョン: {{ recommendedVersion }}</span>
    </div>

    <div class="version-grid">
      <div
        v-for="version in availableVersions"
        :key="version.id"
        class="version-card"
        :class="{ recommended: version.id === recommendedVersion }"
        @click="selectVersion(version.id)"
      >
        <h3>{{ version.displayName }}</h3>
        <p>{{ version.description }}</p>
        <div class="version-status" :class="version.status">
          {{ getStatusLabel(version.status) }}
        </div>
        <ul class="features">
          <li v-for="feature in version.features" :key="feature">
            {{ feature }}
          </li>
        </ul>
        <button class="launch-btn">
          起動
        </button>
      </div>
    </div>

    <div class="settings">
      <label>
        <input type="checkbox" v-model="autoSelectVersion">
        サーバーバージョンに基づいて自動選択
      </label>
      <label>
        <input type="checkbox" v-model="rememberChoice">
        選択を記憶する
      </label>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import { VersionManager } from '../version-manager/VersionManager';
import { InstanceDetector } from '../utils/InstanceDetector';

const versionManager = new VersionManager();
const instanceDetector = new InstanceDetector();

const availableVersions = ref([]);
const currentInstance = ref('');
const recommendedVersion = ref('');
const autoSelectVersion = ref(true);
const rememberChoice = ref(true);

onMounted(async () => {
  // 利用可能なバージョンを読み込み
  availableVersions.value = await versionManager.getAvailableVersions();

  // 現在のインスタンス情報を取得
  const instanceInfo = await instanceDetector.detectCurrentInstance();
  currentInstance.value = instanceInfo.url;

  // サーバーバージョンに基づいて推奨バージョンを決定
  recommendedVersion.value = await versionManager.getRecommendedVersion(
    instanceInfo.version
  );

  // 自動選択が有効な場合
  if (autoSelectVersion.value) {
    await selectVersion(recommendedVersion.value);
  }
});

async function selectVersion(versionId: string) {
  if (rememberChoice.value) {
    localStorage.setItem('selectedVersion', versionId);
  }

  await versionManager.loadVersion(versionId);
}

function getStatusLabel(status: string): string {
  const labels = {
    stable: '安定版',
    beta: 'ベータ版',
    experimental: '実験版'
  };
  return labels[status] || status;
}
</script>
```

### 4. ビルドシステム

#### 4.1 マルチバージョンビルドスクリプト
```javascript
// scripts/build-all-versions.js
const { exec } = require('child_process');
const { promisify } = require('util');
const fs = require('fs-extra');
const path = require('path');

const execAsync = promisify(exec);

async function buildVersion(versionId) {
  console.log(`Building version: ${versionId}`);

  const versionPath = path.join(__dirname, '..', 'versions', versionId);
  const distPath = path.join(__dirname, '..', 'dist', versionId);

  // バージョンディレクトリに移動してビルド
  process.chdir(versionPath);

  // 依存関係をインストール
  await execAsync('npm install');

  // ビルド実行
  await execAsync('npm run build');

  // ビルド成果物を移動
  await fs.move(
    path.join(versionPath, 'dist'),
    distPath,
    { overwrite: true }
  );

  console.log(`Version ${versionId} built successfully`);
}

async function buildAllVersions() {
  const manifest = await fs.readJson(
    path.join(__dirname, '..', 'version-manifest.json')
  );

  for (const version of manifest.versions) {
    await buildVersion(version.id);
  }

  console.log('All versions built successfully');
}

buildAllVersions().catch(console.error);
```

#### 4.2 package.jsonの更新
```json
{
  "scripts": {
    "dev": "vite --config vite.launcher.config.ts",
    "build:launcher": "vite build --config vite.launcher.config.ts",
    "build:versions": "node scripts/build-all-versions.js",
    "build:all": "npm run build:launcher && npm run build:versions",
    "sync:capacitor": "npx cap sync",
    "deploy": "npm run build:all && npm run sync:capacitor"
  }
}
```

### 5. 共通コンポーネント管理

#### 5.1 共有ライブラリ
```typescript
// shared/components/index.ts
export { default as MisskeyButton } from './MisskeyButton.vue';
export { default as MisskeyInput } from './MisskeyInput.vue';
export { default as NotificationHandler } from './NotificationHandler.vue';

// shared/utils/api-adapter.ts
export class ApiAdapter {
  constructor(private version: string) {}

  async callApi(endpoint: string, params: any) {
    // バージョンに応じてAPIコールを適応
    switch (this.version) {
      case 'v13':
        return this.callV13Api(endpoint, params);
      case 'v2025.7.0':
        return this.callV2025Api(endpoint, params);
      default:
        throw new Error(`Unsupported version: ${this.version}`);
    }
  }

  private async callV13Api(endpoint: string, params: any) {
    // v13 API呼び出しロジック
  }

  private async callV2025Api(endpoint: string, params: any) {
    // v2025 API呼び出しロジック
  }
}
```

### 6. データ永続化と設定管理

#### 6.1 バージョン間のデータ共有
```typescript
// src/version-manager/DataBridge.ts
export class DataBridge {
  private db: IDBDatabase;

  async initializeDatabase() {
    const request = indexedDB.open('MissRiricaShared', 1);

    request.onupgradeneeded = (event) => {
      const db = event.target.result;

      // アカウント情報（全バージョン共通）
      if (!db.objectStoreNames.contains('accounts')) {
        db.createObjectStore('accounts', { keyPath: 'id' });
      }

      // バージョン固有の設定
      if (!db.objectStoreNames.contains('versionSettings')) {
        db.createObjectStore('versionSettings', { keyPath: 'versionId' });
      }

      // キャッシュデータ
      if (!db.objectStoreNames.contains('cache')) {
        db.createObjectStore('cache', { keyPath: 'key' });
      }
    };

    this.db = await new Promise((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  async getSharedData(key: string) {
    const transaction = this.db.transaction(['cache'], 'readonly');
    const store = transaction.objectStore('cache');
    return store.get(key);
  }

  async setSharedData(key: string, value: any) {
    const transaction = this.db.transaction(['cache'], 'readwrite');
    const store = transaction.objectStore('cache');
    return store.put({ key, value, timestamp: Date.now() });
  }
}
```

### 7. 実装フェーズ

#### フェーズ1: 基盤構築（2週間）
1. ディレクトリ構造の再編成
2. バージョンマニフェストシステムの実装
3. 基本的なバージョンローダーの実装

#### フェーズ2: バージョン統合（3週間）
1. 各Misskeyバージョンのソースコード統合
2. バージョン固有の依存関係解決
3. ビルドシステムの構築

#### フェーズ3: UI実装（2週間）
1. バージョンセレクターUIの実装
2. 設定画面の実装
3. バージョン切替アニメーション

#### フェーズ4: 最適化（2週間）
1. バージョンの事前読み込み
2. キャッシュ戦略の実装
3. パフォーマンス最適化

#### フェーズ5: テストとデバッグ（2週間）
1. 各バージョンの動作確認
2. バージョン間の切替テスト
3. データ永続化のテスト

### 8. 技術的課題と解決策

#### 課題1: バンドルサイズの増大
**解決策**:
- 各バージョンを独立したチャンクとしてビルド
- 動的インポートによる遅延読み込み
- 共通ライブラリの外部化

#### 課題2: メモリ使用量
**解決策**:
- 非アクティブバージョンのアンロード
- WebWorkerを使用したバックグラウンド処理
- メモリリークの監視と自動クリーンアップ

#### 課題3: バージョン間の非互換性
**解決策**:
- APIアダプター層の実装
- バージョン固有のポリフィル
- 段階的な機能デグレード

### 9. セキュリティ考慮事項

1. **バージョン検証**: 各バージョンのハッシュ値検証
2. **サンドボックス化**: iframe/WebViewによる分離
3. **権限管理**: バージョンごとの権限制御
4. **通信の暗号化**: バージョン間通信の暗号化

### 10. 将来の拡張性

1. **プラグインシステム**: 各バージョンへのプラグイン追加
2. **カスタムバージョン**: ユーザー独自のバージョン追加
3. **A/Bテスト**: 複数バージョンの同時実行
4. **自動更新**: バージョンの自動更新機能

## まとめ

このマルチバージョン対応により、MissRiricaは：
- 複数のMisskeyバージョンを単一アプリで提供
- ユーザーが状況に応じて最適なバージョンを選択可能
- 新機能の段階的な展開とテストが可能
- 後方互換性を維持しながら最新機能を提供

実装には約11週間を要すると見込まれるが、段階的にリリース可能な設計となっている。