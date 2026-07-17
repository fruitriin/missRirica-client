# テスト: addf-init 外部起動（既存プロジェクトへの導入）

> 手動実行シナリオ。実際に WebFetch・git clone・ファイルマージを行うため、
> 使い捨てのダミープロジェクトで実施すること。

## 準備: ダミー既存プロジェクトの作成

```bash
box="$(mktemp -d)" && cd "$box"
git init
echo "# Sample App" > README.md
printf 'node_modules\ndist\n' > .gitignore
echo '{"name":"sample-app","scripts":{"build":"tsc","test":"vitest"}}' > package.json
printf '# CLAUDE.md\n\n- 返答は日本語で\n- テストは vitest を使う\n' > CLAUDE.md
mkdir -p .claude && echo '{"permissions":{"allow":["Read"]}}' > .claude/settings.json
git add -A && git commit -m "initial"
```

## テスト 1: 外部起動フロー全体

### 入力（README 記載のコピペプロンプト）
```
https://raw.githubusercontent.com/fruitriin/ADDF/main/.claude/commands/addf-init.md
を取得し、このプロジェクトに ADDF フレームワークを導入してください。
ADDF リポジトリ: https://github.com/fruitriin/ADDF
```

ローカル検証の場合はクローン元 URL を手元のリポジトリパスに読み替えてよい
（ただし `https://` 以外のスキームが拒否されることのテストを兼ねる場合は raw URL を使う）。

### 期待結果
- クローン前に URL がユーザーに提示され、確認を求められる
- 既存プロジェクト導入モードと判定される（`.claude/` と CLAUDE.md があり lock がない）
- プロジェクト情報が自動推定される（名前: sample-app、ビルド: tsc、テスト: vitest）
- 干渉チェック（Phase 2.5）が表示される: `.gitignore`・`.claude/settings.json`・`CLAUDE.md` がマージ対象として列挙される
- 導入前レビュー（Phase 2.7）で hooks・権限変更が明示され、承認を求められる

## テスト 2: マージ結果の検証

### 期待結果
- 既存 CLAUDE.md の内容（日本語返答・vitest）が `CLAUDE.repo.md` に退避されている
- `.gitignore` に ADDF マーカーブロックが追加され、既存エントリ（node_modules, dist）が保持されている。ブロック内容がクローン元 `.gitignore` のマーカーブロックと一致する
- `.claude/settings.json` の既存 allow（Read）が保持されたまま ADDF の hooks/permissions が追加されている
- `.claude/addf/Progress.md` が `ProgressTemplate.md`（無印版）由来である（`.addf.md` 版の「ADD フレームワークテスト」行を含まない）

## テスト 3: 参照切れがないこと

### 入力
```
/addf-init check
```

および:

```bash
python3 .claude/addf/addfTools/lint-template-sync.py
```

### 期待結果
- check: 必須ファイルが全て存在し、`@` メンションが全て解決可能
- lint: exit 0（ペア5により、CLAUDE.md が参照する `.claude/addf/Questions.example.md`・`.claude/addf/Dashboard.example.md` の存在＝コピー漏れがないことが裏付けられる）
- 一時ディレクトリ（tmp クローン）が削除されている

## 後片付け

```bash
rm -rf "$box"
```
