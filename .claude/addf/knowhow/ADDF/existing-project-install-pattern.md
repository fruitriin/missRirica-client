---
title: 既存プロジェクトへの ADDF 導入パターン
created: 2026-03-21
last_verified: 2026-07-06
depends_on: []
status: active
---

# 既存プロジェクトへの ADDF 導入パターン

## 発見した知見

### 鶏と卵問題の解決

ADDF のスキル（`addf-init.md`）は `.claude/commands/` に配置されるが、既存プロジェクトにはこのファイルが存在しない。スキルがないのにスキルを実行できない。

**解決策: ブートストラッププロンプト + raw URL**

1. README にコピペ用プロンプトを記載
2. Claude が `raw.githubusercontent.com` 経由で `addf-init.md` を WebFetch
3. スキルの「外部起動セクション」を読み、ADDF リポジトリを tmp にクローン
4. tmp のファイル群を参照しながらプロジェクトにセットアップ

**重要**: GitHub の通常の Markdown プレビューは WebFetch で取得できない。raw URL（`raw.githubusercontent.com`）に誘導する必要がある。

### CLAUDE.md 退避戦略

既存プロジェクトに CLAUDE.md がある場合、ADDF の CLAUDE.md に置き換える必要がある。既存の指示は `CLAUDE.repo.md` に退避する。

1. 既存の `CLAUDE.md` と `AGENTS.md`（あれば）の両方を読む
2. 重複を統合し、プロジェクト固有の指示として `CLAUDE.repo.md` に退避
3. ADDF の `CLAUDE.md` テンプレートで置き換え（`@CLAUDE.repo.md` で退避先を自動参照）
4. 退避した `CLAUDE.repo.md` を `CLAUDE.repo.example.md` と比較して構造的不足をチェック
5. 不足があれば対話的に補完

### フレームワーク導入時の信頼モデル

ADDF はプラグインマーケットプレイスの「1スキルをインストール」とは根本的に異なる。CLAUDE.md でエージェントの振る舞い全体を支配し、hooks で任意コマンドを実行し、settings.json で権限を変更する。

導入前に以下を明示表示してユーザーの承認を得る必要がある:
- **hooks**: どのイベントで何が実行されるか
- **権限変更**: allow/ask に何が追加されるか
- **CLAUDE.md**: ブートシーケンスがどう変わるか

### 干渉チェックの3カテゴリ

| カテゴリ | 処理 | 例 |
|---|---|---|
| 無条件コピー | `addf-` プレフィックス／専用ディレクトリで衝突リスクなし。ただし `*.addf.md` は**コピーしない**（ADDF 本体専用サフィックス — 存在ベース判定を汚染するため） | commands/addf-*.md, agents/addf-*.md, hooks/, .claude/addf/knowhow/ADDF/, .claude/addf/guides/, addfTools/, tests/, templates/, optional/ |
| インテリジェントマージ | 既存を保持しつつ ADDF エントリを追加 | settings.json, .gitignore（マーカーブロックはクローン元をそのままコピー — 列挙を持たない）, CLAUDE.md |
| プロジェクト固有生成 | ダウンストリーム体裁で新規作成 | CLAUDE.repo.md, TODO.md, Progress.md, addf-lock.json |

### .gitignore マーカーブロック

ADDF エントリを `# --- ADDF Framework ---` で囲むことで:
- `/addf-migrate` が ADDF エントリを自動更新できる
- ユーザーが ADDF エントリを識別しやすい
- プロジェクト固有のエントリと衝突しない

## プロジェクトへの適用

### 外部起動の判定

`addf-init.md` の Phase 1 で以下の4分岐を行う:
1. `addf-lock.json` あり → 導入済み
2. `addf-*.md` あり but lock なし → **Template 経由の新規プロジェクト** または **部分導入プロジェクト**
   （手縫い導入・旧版の部分コピー）。どちらかをユーザーに確認する。部分導入なら
   スキル冒頭の「部分導入からの正規化」モードに合流する（既存 ADDF 由来ファイルは
   最新版で上書き、プロジェクト固有ファイルは保護、完了時に lock 生成 → 以後は
   `/addf-migrate` の系譜に載る）
3. `CLAUDE.md` or `.claude/` あり → 既存プロジェクト導入モード
4. 何もなし → 新規セットアップ

外部起動（WebFetch 経由）の場合は必ず「ADDF 利用プロジェクト」（ダウンストリーム）として扱う。

### `*.addf.md` の除外原則（存在≠所有）

無条件コピーのカテゴリでも、**`*.addf.md` サフィックスのファイルはコピーしない**。
理由: `.addf.md` は「ADDF 本体専用ファイル」を示すサフィックスであり、ダウンストリームに
物理配置すると「存在ベースの upstream/downstream 判定ロジック」が「ADDF 本体」と誤認する
根源になる（存在≠所有 の原則）。

具体的な除外対象例:
- `ProgressTemplate.addf.md`（テンプレート）
- `Release.addf.md`（リリース手順）
- `INDEX.addf.md`（knowhow インデックス — ダウンストリームは `INDEX.md` に一本化）

判定ロジック側では、CLAUDE.repo.md の種別宣言＋`addf-lock.json` の明示シグナルで
所有を判断する（詳細は [sync-lint-design.md](sync-lint-design.md) の「存在≠所有」）。

### 既存ファイルからの情報自動取得

既存プロジェクトの場合、対話ステップを最小化できる:
- `README.md` からプロジェクト名・目的
- `package.json` / `Cargo.toml` 等からビルド・テストコマンド
- git コミットログからコミット規約
- 推定結果を確認するだけで対話完了

## 注意点・制約

- WebFetch は GitHub の Markdown プレビュー（`github.com/.../blob/...`）を取得できない。`raw.githubusercontent.com` を使うこと
- 外部起動時の URL は `https://` のみ許可。`file://`, `ssh://`, `git://` は悪意あるリポジトリのリスクがある
- `CLAUDE.md` → `CLAUDE.repo.md` の退避時、既存の `@` メンション構文は ADDF の展開ルールと互換性があるか確認が必要
- ADDF はリポジトリ構成フレームワークであり、アプリケーションフレームワークを含まない。ただし、アプリケーションフレームワークが独自の CLAUDE.md / AGENTS.md を提供し始めた場合は干渉する可能性がある

## 参照

- `.claude/commands/addf-init.md` — 外部起動セクション、部分導入からの正規化、Phase 2.5 干渉チェック、Phase 2.7 導入前レビュー
- `.claude/addf/plans-add/0015-existing-project-install.md` — 設計計画
- `.claude/addf/knowhow/ADDF/upstream-downstream-separation.md` — 分離パターンの全体像

## 関連ノウハウ

- [アップストリーム/ダウンストリーム分離パターン](upstream-downstream-separation.md) — `.addf.md` / `ADDF/` / `addf-` の3分離パターン
- [同期 lint の設計](sync-lint-design.md) — 「存在≠所有」の判定ロジック、部分導入プロジェクトの検出との関係

## 訂正履歴

### 2026-07-06
- 外部起動の判定に「部分導入プロジェクト」ケースを追記
  （根拠: 現行 `.claude/commands/addf-init.md` の Phase 1 分岐 2 が「Template 経由 または 部分導入」に拡張されており、
  スキル冒頭に「部分導入からの正規化」モードが独立節として存在する）
- 無条件コピーカテゴリに「`*.addf.md` を除外する」原則を追記
  （根拠: 現行 `addf-init.md` の Phase 3 カテゴリ1 に「除外規則: `*.addf.md` に該当するファイルはコピーしない」が明記。
  存在≠所有 の分離規約に対応）
- 干渉チェック3カテゴリの例示リストを現状追従（.claude/addf/knowhow/ADDF/, .claude/addf/guides/, optional/, tests/ 等を追加）
