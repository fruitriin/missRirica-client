---
name: addf-lint
description: |
  ADDF フレームワークの整合性をチェックする。settings.json 構文・hooks 実行権限/配線・
  スキル frontmatter・Behavior.toml・knowhow INDEX 整合/鮮度/双方向リンク・
  テンプレート同期・チェックリスト裏付け・オプショナルスキル同期・Plan 状態整合を検証する。
  品質ゲート前、CI、設定変更後に使う。
context: fork
user_invocable: true
---

# ADDF Lint — フレームワーク整合性チェック

以下のチェックを順番に実行し、結果をまとめて報告する。
全チェック通過時は `✓ All checks passed` を表示する。
問題がある場合は項目ごとに `✗` と詳細を表示する。

> **注**: 本スキルの lint コマンドは `uv run --python 3.11` を前提とする
> （PEP 723 のサードパーティ依存も自動解決される）。
> uv が無い環境では `python3` で直接実行できるが、tomllib を使う lint（セクション4・10）は
> Python 3.11+ が必要（旧い Python では SKIP 案内を出す）、Frontmatter チェック（セクション3）は
> `pip install pyyaml` が必要（無ければ SKIP 案内を出す）。
> SKIP は環境起因で検査できなかったことを示す（✗ = 問題検出ではない）。

## 1. JSON 構文チェック

```bash
uv run --python 3.11 .claude/addf/addfTools/lint-json.py
```

## 2. Hooks 実行権限チェック

`.claude/hooks/` 内の `*.sh` ファイルが実行権限を持っているか確認する:

```bash
uv run --python 3.11 .claude/addf/addfTools/lint-hooks-exec.py
```

exit code: 0 = 全て実行可能 / 2 = WARNING（実行権限なし。`chmod +x` で付与する）。
`.claude/hooks/` が無い場合は SKIP される。

## 3. スキル Frontmatter チェック

`.claude/commands/addf-*.md` の全ファイルについて frontmatter の存在と必須フィールド（name, description）を検証する。

```bash
uv run --python 3.11 .claude/addf/addfTools/lint-frontmatter.py
```

## 4. addf-Behavior.toml 構文チェック

```bash
uv run --python 3.11 .claude/addf/addfTools/lint-toml.py
```

## 5. Knowhow INDEX 整合性チェック

`.claude/addf/knowhow/INDEX.addf.md`（ADDF 本体の場合）または `.claude/addf/knowhow/INDEX.md`（ダウンストリームの場合）を対象に:
- INDEX に記載されているがファイルが存在しないエントリを検出
- `.claude/addf/knowhow/` 配下に存在するが INDEX に記載されていない `.md` ファイルを検出
- INDEX ファイル自身（INDEX.md, INDEX.addf.md）と `CLAUDE.md`（読み方の作法）は除外する

INDEX ファイルからリンクを抽出するには、テーブル行の `[パス](パス)` パターンをパースする。

## 6. テンプレート同期チェック

同期が必要な8つのファイルペアのドリフトを検出する:

| ペア | 検証内容 | 重要度 |
|---|---|---|
| 1. `.claude/addf/templates/ProgressTemplate.addf.md` ⇔ `.claude/addf/Progress.md` | 運用ルールのテキスト包含 | ERROR |
| 2. `.claude/addf/templates/ProgressTemplate.addf.md` ⇔ `.claude/addf/templates/ProgressTemplate.md` | 運用ルールの正規化比較（意図的差分はホワイトリスト済み） | WARNING |
| 3. `CLAUDE.md` ⇔ `AGENTS.md` | ブートシーケンス手順番号の対応 | WARNING |
| 4. `CLAUDE.md` ⇔ `.claude/addf/guides/development-process.md` | ブートシーケンス概要の手順番号の対応 | WARNING |
| 5. `CLAUDE.md` ⇔ `.claude/commands/addf-init.md` コピーリスト | 参照ファイルのカバレッジ（.gitignore ADDF ブロック含む） | WARNING |
| 6. TODO（`TODO.md` / `.claude/addf/plans-add/TODO.addf.md`）⇔ Plan の `## 実装状況:` ヘッダ | 状態の矛盾・参照切れ・登録漏れ・表記ゆれヘッダ（`## 状態:` 等）。ヘッダ無し Plan は対象外 | WARNING |
| 7. `.claude/addf/addfTools/verify-checksums.sh` ⇔ `.claude/addf/addfTools/lint-template-sync.py` | `detect_repo_kind()` Python⇔Bash 実装の同期契約文言の存在チェック（挙動比較は困難なため契約明示を機械保証） | WARNING |
| 8. `README.md` / `README.en.md` ⇔ `.claude/commands/addf-*.md`（`*.exp.md` 除く） | スキルテーブルへの掲載漏れ（新設スキルが README のドキュメント公開から漏れていないか）。upstream 限定（downstream は独自 README のため SKIP） | WARNING |

※ lint にペアを追加・変更したら、この表とスクリプト docstring も同時に更新する。

```bash
uv run --python 3.11 .claude/addf/addfTools/lint-template-sync.py
```

exit code: 0 = 全一致 / 1 = ERROR / 2 = WARNING のみ。
upstream/downstream の判定は明示シグナルで行う（一次根拠: `CLAUDE.repo.md` の種別宣言 / フォールバック: `.claude/addf/lock.json` の存在。ファイルの存在では判定しない — 存在≠所有）。ダウンストリームではペア1は `ProgressTemplate.md` を正として比較し（`.addf.md` 版が物理存在しても比較しない）、ペア2・ペア3は SKIP される（独自 `AGENTS.md` の誤報防止）。その他のペアも対象ファイルが存在しなければ SKIP される。
WARNING には git log による最終更新日ヒントが併記される。**どちらを正として同期するかはエージェントが文脈で判断する**（通常は新しい側が正だが、誤編集の巻き戻しもありうる）。修正後は再実行して確認する。

## 7. Knowhow 鮮度チェック

`.claude/addf/knowhow/` 配下の各 `.md` ファイル（INDEX と CLAUDE.md を除く）について:
- フロントマター（`last_verified`・`status`）の有無を確認。なければ WARNING
- 🔴 stale のファイル（しきい値・判定基準は `addf-knowhow-index.md` の定義に従う）を列挙し、`/addf-knowhow-revise` を案内する
- `depends_on` に存在しないファイル・スキルが含まれていれば WARNING

鮮度低下は WARNING 止まり（エラーにしない）。再検証の判断はエージェント・オーナーに委ねる。

## 8. Knowhow 双方向リンクチェック

`.claude/addf/knowhow/` 配下の各 knowhow の「## 関連ノウハウ」セクションのリンクについて:
- リンク先ファイルが存在するか確認。なければ WARNING
- A→B のリンクに対し B→A が存在するか確認。欠落していれば INFO として列挙し、`/addf-knowhow-network` を案内する
- 「## 関連ノウハウ」セクション自体がないファイルはチェック対象外（ネットワーク化は任意）

## 9. チェックリスト裏付け検査

手順書（`Release.addf.md` / `addf-init.md` / `addf-migrate.md` / `addf-plan-audit.md` /
`ProgressTemplate` 系）の
「確認/検証」ステップに裏付け（実行可能チェックまたは `<!-- human-judgment -->` マーカー）が
あるかを点検する:

```bash
uv run --python 3.11 .claude/addf/addfTools/lint-checklist.py
```

exit code: 0 = 裏付けあり / 2 = WARNING（ERROR 級はこの lint には無い）。
WARNING はエージェントの確認漏れではなく**手順書側の点検**: A型（機械検証可能）なら
実行コマンドを添え、B型（人間判断）ならマーカーを付け、アサーションが書けない項目は
構造上通らない可能性があるので手順書の設計を見直す。
チェックの実装そのもの・解説文のセクションは `<!-- checklist-lint: skip-section -->` で除外できる。
対象ファイルが無い場合（ダウンストリーム）は SKIP される。

## 10. オプショナルスキル同期チェック

`.claude/addf/optional/`（オプトイン式スキル・エージェントの原本）と発見パスの有効化コピーが
`addf-Behavior.toml` の `[gui-test] enable` と整合しているかを検査する:

```bash
uv run --python 3.11 .claude/addf/addfTools/sync-optional-skills.py
```

exit code: 0 = 整合 / 1 = ERROR（`enable` が真偽値でない等の設定不正） /
2 = WARNING（未配置・撤去漏れ・原本との差分・gitignore 列挙漏れ・原本を失った孤児コピー）。
解消は `sync-optional-skills.py apply`（原本と異なる有効化コピーは apply でも削除・上書きされない —
直接編集は原本に対して行う）。`.claude/addf/optional/` または Behavior.toml が無い場合、
Behavior.toml が構文エラーの場合（セクション4の責務）は SKIP される。

## 11. Hooks 配線チェック

`.claude/hooks/*.sh` の各ファイルが `settings.json` の hooks セクションに配線されているかを
突合する（セクション2の実行権限チェックと対: 権限があっても配線がなければ実行されない）:

```bash
uv run --python 3.11 .claude/addf/addfTools/lint-hooks-wiring.py
```

exit code: 0 = 全配線済み / 2 = WARNING（未配線フックあり。ダウンストリームが意図的に
外している可能性があるため ERROR にしない）。tomllib 不要のためシステム python3 でも動く。
突合は境界チェック付き（`count.sh` が `reset-turn-count.sh` の配線にマッチする
部分文字列誤判定を防ぐ）。`settings.local.json` のみでの配線は有効だが OK と区別して
`NOTE: <hook> は settings.local.json 経由（他環境・CI には適用されない）` が出る（exit 0 のまま）。
フックのコメントヘッダに `# hooks-wiring: indirect` を置くと検査対象外（NOTE 表示。
他スクリプト経由の間接参照用エスケープハッチ）。配線例は ADDF リポジトリの
`.claude/settings.json`（https://github.com/fruitriin/ADDF/blob/main/.claude/settings.json）を参照。
`settings.json` 不在、`.claude/hooks/*.sh` 不在、settings.json が不正 JSON の場合
（セクション1の責務）、settings.json が読めない場合（OSError）は SKIP される。

## 12. Plan 状態整合チェック（誤完了防止）

`.claude/addf/plans-add/`・`.claude/addf/plans/` の Plan ファイルについて、`## 実装状況:` ヘッダが
「完了」で始まるのに完了条件セクションに未チェック `- [ ]` が残っている矛盾
（フェーズ分割 Plan の途中マージで「済み」に見える誤完了）を検出する:

```bash
uv run --python 3.11 .claude/addf/addfTools/lint-plan-status.py
```

exit code: 0 = OK / 1 = ERROR / 2 = WARNING（表記ゆれ状態ヘッダ。ERROR 優先）。
チェックボックスは GFM タスクリスト全形式（`-`・`*`・`+`・番号付き `1.` / `1)`）を検出する。
「一部完了」「未着手」等の中間状態ヘッダとヘッダ無しの旧 Plan は正当な対象外。
ただし表記ゆれ状態ヘッダ（`## 状態:`・`## ステータス:`・`## 進捗:`・レベル違いの
`### 実装状況:`・コロン無しの `## 実装状況 完了` 等）を持ちチェックボックスを含む Plan は
無言スキップにせず WARNING で「`## 実装状況:` への統一」を促す（セクション6ペア6の
表記ゆれ検出と同旨）。完了条件がチェックボックス形式でない旧書式 Plan は SKIP される
（明示出力・件数計上・ファイル名列挙。チェックボックス化は強制しない）。
コードフェンス（```・~~~・4連以上のバッククォート）内のチェックボックス例示は無視される。
完了条件セクションの見出しは「完了条件」を**含む**もの（`### フェーズA: 完了条件` 等）を
拾うが、含まない見出しのセクションは検出不能（スクリプト docstring の制約参照）。
ERROR が出たら**ヘッダとチェックボックスのどちらが実態かを確認して直す**
（残作業があるならヘッダを「一部完了（残り: …）」へ / 実施済みならチェックを付ける。
lint を通すために完了状態を機械的に書き換えない）。
セクション6のペア6（TODO ⇔ ヘッダ）が「ヘッダが実態を語っている」前提で動くのに対し、
本チェックはその手前（ヘッダ ⇔ 完了条件の実態）を担う。stdlib のみのため
システム python3 でも動く。対象ディレクトリが無い場合は SKIP、検査対象 0 件の場合は
`NOTE: 検査対象 0 件 — リポジトリルートで実行しているか確認` が出る（いずれも exit 0）。

## 13. ccchain 同期チェック

`addf-Behavior.toml` の `[ccchain] enable` と、プロジェクトルートの `.ccchain.conf`・
`.claude/settings.json` の PreToolUse(Bash) フックエントリが整合しているかを検査する
（Plan 0040 フェーズ2・オプトイン配布機構。ccchain は EnumaElish 由来の外部ツールで、
パイプ・チェーン・サブシェル・`-exec` の中身まで含めた構造的コマンド判定を行う）:

```bash
uv run --python 3.11 .claude/addf/addfTools/sync-ccchain.py
```

exit code: 0 = OK / 1 = ERROR（`enable` が真偽値でない・`settings.json` が壊れている等） /
2 = WARNING（未配置・未配線・残存・バイナリ不在）。解消は `sync-ccchain.py apply`。
`.ccchain.conf` は初回配置後は書き換え可能な前提のため、sync-optional-skills.py と異なり
原本との差分があっても上書きしない（プロジェクト固有のルールチューニングを保護する）。
`.claude/addf/optional/ccchain/` または Behavior.toml が無い場合、Behavior.toml が
構文エラーの場合（セクション4の責務）は SKIP される。バイナリ不在は Claude Code の動作を
妨げない WARNING に留める（フェイルセーフ側＝素通しの設計。詳細:
`.claude/addf/knowhow/ADDF/ccchain-dogfooding-phase1.md`）。

## 結果報告

全チェックの結果を以下の形式でまとめる:

```
╔══════════════════════════════════════╗
║  ADDF Lint Results                   ║
╚══════════════════════════════════════╝

1. JSON 構文          ✓ / ✗
2. Hooks 実行権限     ✓ / ✗
3. Frontmatter        ✓ / ✗
4. Behavior.toml      ✓ / ✗
5. INDEX 整合性       ✓ / ✗
6. テンプレート同期   ✓ / ⚠ / ✗
7. Knowhow 鮮度       ✓ / ⚠
8. Knowhow リンク     ✓ / ⚠
9. チェックリスト裏付け ✓ / ⚠
10. オプショナルスキル同期 ✓ / ⚠
11. Hooks 配線         ✓ / ⚠
12. Plan 状態整合      ✓ / ⚠ / ✗
13. ccchain 同期       ✓ / ⚠ / ✗
```
