# Release — addf-release.exp.md 作成ガイド

> `/addf-release` を初めて実行すると、プロジェクトのリリース戦略をヒアリングして
> `addf-release.exp.md` を作成します。このファイルはその際の参考例です。
> `.claude/addf/Release.addf.md`（upstream 用）も構造の参考になります。

---

## 例 1: npm パッケージ

```markdown
# addf-release 経験メモ

## リリース戦略
- バージョニング: semver
- チェンジログ: CHANGELOG.md（Keep a Changelog 形式）

## プレリリースチェック
1. `npm run build` が通ること
2. `npm test` が全て通過すること
3. `npm run lint` がエラーなしであること

## バージョン更新対象ファイル
| ファイル | 更新内容 |
|---|---|
| `package.json` | `version` フィールドを更新 |
| `package-lock.json` | `npm install` で自動更新 |
| `CHANGELOG.md` | 新バージョンのエントリを先頭に追加 |

## Publish 手順
1. リリースコミットを作成: `[リリース] vX.Y.Z`
2. タグを作成: `git tag vX.Y.Z`
3. push: `git push && git push --tags`
4. `npm publish`

## リリース後
- npmjs.com でパッケージが公開されたことを確認
```

---

## 例 2: iOS App（App Store）

```markdown
# addf-release 経験メモ

## リリース戦略
- バージョニング: semver（Marketing Version） + ビルド番号（CURRENT_PROJECT_VERSION）
- チェンジログ: App Store Connect の「新機能」欄に直接記載。リポジトリには CHANGELOG.md も管理

## プレリリースチェック
1. `xcodebuild test` が全て通過すること
2. `swiftlint` がエラーなしであること
3. Provisioning Profile / 証明書の有効期限を確認
4. TODO.md に未完了の Critical タスクがないこと

## バージョン更新対象ファイル
| ファイル | 更新内容 |
|---|---|
| `*.xcodeproj` / `*.xcconfig` | `MARKETING_VERSION` と `CURRENT_PROJECT_VERSION` を更新 |
| `CHANGELOG.md` | 新バージョンのエントリを先頭に追加 |

## Publish 手順
1. リリースコミットを作成: `[リリース] vX.Y.Z (Build N)`
2. タグを作成: `git tag vX.Y.Z`
3. push: `git push && git push --tags`
4. Archive: `xcodebuild archive -scheme MyApp -archivePath build/MyApp.xcarchive`
5. Export: `xcodebuild -exportArchive -archivePath build/MyApp.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build/`
6. App Store Connect にアップロード: `xcrun altool --upload-app -f build/MyApp.ipa -t ios -u "$APPLE_ID"`
   - または Transporter.app / `xcrun notarytool` を使用
7. App Store Connect でビルドを選択し、審査に提出

## リリース後
- App Store Connect で審査状況を確認
- 審査通過後、段階的リリース（Phased Release）の設定を確認
- TestFlight のテスターに先行配布した場合、フィードバックを確認

## 注意すべき落とし穴
- ビルド番号は単調増加が必要。同じバージョンでリジェクトされた場合、ビルド番号だけ上げて再提出
- 審査リジェクト時のメタデータ修正は App Store Connect 上で直接行う（コード変更不要の場合）
- スクリーンショットの更新忘れに注意（新機能追加時）
```

---

## 例 3: Web サービス（バージョンなし）

```markdown
# addf-release 経験メモ

## リリース戦略
- バージョニング: なし（デプロイ日時で管理）
- チェンジログ: GitHub Releases のみ（自動生成）

## プレリリースチェック
1. `npm run build` が通ること
2. `npm test` が全て通過すること
3. ステージング環境で動作確認済みであること

## Publish 手順
1. main ブランチにマージ
2. CI/CD が自動デプロイ（GitHub Actions → Vercel / AWS）
3. `gh release create --generate-notes` でリリースノートを自動生成

## リリース後
- 本番環境の動作確認
- エラーモニタリング（Sentry 等）で異常がないか確認
- ロールバック手順: `git revert` → main に push → 自動デプロイ
```
