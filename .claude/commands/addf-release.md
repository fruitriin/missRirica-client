---
name: addf-release
description: |
  プロジェクトのリリースを実行する。チェンジログ作成・バージョン採番・publish 操作をパッケージ化。
  リリースしたいとき、バージョンを上げたいとき、チェンジログを更新したいときに使う。
  ADDF 本体（upstream）とダウンストリームプロジェクトで自動的に手順を切り替える。
user_invocable: true
---

# ADDF Release — リリース実行

## 引数

- `$ARGUMENTS`: バージョン指定（`major` / `minor` / `patch`）や `--dry-run` 等。リリース設定に渡す。

## 手順

### 1. プロジェクト種別の判定

`CLAUDE.repo.md`（または `CLAUDE.repo.example.md`）を読み、プロジェクト種別を判定する:
- 「**ADDF 開発プロジェクト**」を含む → **upstream**
- それ以外 → **downstream**

### 2. リリース手順の読み込み

種別に応じてリリース手順を決定する:

**upstream の場合:**
1. `.claude/addf/Release.addf.md` を読む（必須）
2. `addf-release.exp.md` が存在すれば読み、過去の経験を考慮する

**downstream の場合:**
1. `addf-release.exp.md` を読む（リリース戦略の定義元）
2. 存在しなければ、ユーザーに対話的にリリース戦略をヒアリングして `addf-release.exp.md` を新規作成する:
   - バージョニングを行うか（semver / calver / なし）
   - チェンジログを管理するか（CHANGELOG.md / GitHub Releases のみ / なし）
   - バージョン更新対象ファイル（package.json / Cargo.toml / pyproject.toml / 独自）
   - Publish 手順（npm publish / cargo publish / Docker / デプロイ / なし）
   - プレリリースチェック（ビルド / テスト / Lint）
   - 構造は `.claude/addf/Release.addf.md` を参考にしてよいが、プロジェクトの要件に合わせて作り直す

### 3. リリース手順の実行

読み込んだリリース手順（Release.addf.md または addf-release.exp.md）に記載された内容を上から順に実行する。

### 4. 経験の更新

実行後、新たな教訓があれば `addf-release.exp.md` に追記する。

## Gotchas

- **upstream リリースは ADDF 全体に影響する**: ダウンストリームの `/addf-migrate` はこのバージョンを参照する
- **`--dry-run` を推奨**: 初回リリース時は必ず dry-run で内容を確認すること
- **downstream の初回実行**: exp ファイルがないため対話的にリリース戦略を構築する。2回目以降は exp に蓄積された戦略に従う
