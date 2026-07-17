# 詳細セットアップ

> GitHub で **[Use this template](https://github.com/fruitriin/ADDF/generate)** からリポジトリを作成し、`/addf-init` を実行すれば以下の手順の大部分を自動化できます。
> 手動でセットアップしたい場合や、`/addf-init` が対応していない設定を行う場合はこのガイドを参照してください。

## プロジェクト固有ファイルの差し替え（手動セットアップ）

| ファイル | 操作 | 説明 |
|---|---|---|
| `README.md` | 差し替え | プロジェクト独自の説明に書き換え |
| `CLAUDE.repo.md` | 作成 | `CLAUDE.repo.example.md` を参考に作成し、コミットする（チーム共有のプロジェクト固有設定） |
| `CLAUDE.local.md` | 作成（任意） | `CLAUDE.local.example.md` を参考に、開発者個人の設定を記載 |
| `CONTRIBUTING.md` | 差し替え（任意） | 必要に応じてプロジェクトに合わせる |

## 設定ファイルの役割

| ファイル | 読み込み方式 | コミット |
|---|---|---|
| `CLAUDE.repo.md` | CLAUDE.md から `@` メンションで展開 | する |
| `CLAUDE.local.md` | Claude Code が自動読み込み | しない（`.gitignore`対象） |
| `.gitignore` | git 標準 | する |
| `.claudeignore` | Claude Code 標準 | する |

`.gitignore` 対象でも Claude Code はパス指定でアクセスできるため、「git 非追跡だが Claude には見せたいファイル」（`*.exp.md` 等）は `.gitignore` にだけ書きます。

## ディレクトリ構成

```
.
├── CLAUDE.md                    # ブートシーケンス・開発プロセス定義
├── CLAUDE.repo.example.md       # CLAUDE.repo.md のテンプレート
├── CLAUDE.local.example.md      # CLAUDE.local.md のテンプレート
├── AGENTS.md                    # Codex 向けブートシーケンス
├── TODO.md                      # タスクバックログ
├── CONTRIBUTING.md              # コントリビューションガイド
├── .claude/
│   ├── addf/                    # ADDF 占有名前空間（v0.6.0〜）
│   │   ├── lock.json            # ADDF バージョンロック
│   │   ├── Progress.md          # 現在のタスク進捗
│   │   ├── Feedback.md          # 問題記録・改善アクション
│   │   ├── Progresses/          # 完了タスクのアーカイブ
│   │   ├── templates/           # テンプレートファイル
│   │   ├── plans/               # 実装計画ファイル
│   │   ├── knowhow/             # 実装知見の蓄積
│   │   ├── guides/              # ガイドドキュメント
│   │   └── addfTools/           # lint・migrate・speculate 等のツール群（GUI テスト用 Swift バイナリ含む）
│   ├── commands/                # スキル定義（Claude Code 規約位置・不動）
│   ├── agents/                  # サブエージェント定義（同上）
│   └── hooks/                   # Claude Code Hooks（同上）
├── docs/                        # ADDF は使わない（GitHub Pages 等の一般用途に明け渡し）
└── .gitignore / .claudeignore
```

## 計画ファイルの作成

計画ファイルは簡素なメモや箇条書きから作成できます。たとえば:

```markdown
<!-- こんなメモを plan.md に書いて… -->
- README のスキルセクションが空
- 英語ドキュメントがない
- GUI テストが macOS 専用
```

これを Claude に渡す（`plan.md` とだけ入力する、チャットに箇条書きを貼る、等）だけで、AI が自動的にプロジェクトをレビューし、正式な計画ファイル群に分解して `.claude/addf/plans/` と `TODO.md` に投入します。

計画ファイルの書式は [CONTRIBUTING.md](../../../CONTRIBUTING.md) を参照してください。

## 実運用の参考

このリポジトリ自体が ADDF を使って開発されています:

- **`.claude/addf/plans-add/`** — ADDF 自身の開発計画。Plan の書き方・粒度の実例
- **`.claude/addf/knowhow/ADDF/`** — 開発で蓄積されたノウハウ
- **`.claude/settings.json`** — ダウンストリームテンプレートの実例
- **`.github/workflows/test.yml`** — CI 品質ゲート（run-all.sh + lint 一式）の実例。ダウンストリームには配布されないが、同じゲートを組みたい場合は雛形として参照できる。CI が落ちたらローカルで `/addf-lint`（lint 一式）または `bash .github/scripts/run-lint.sh <lintスクリプト>` で再現できる
- **`.claude/addf/Progresses/`** — 完了タスクのアーカイブ
- **`git log`** — コミットログ規約・品質ゲートの適用結果
