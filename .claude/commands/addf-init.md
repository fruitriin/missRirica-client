---
name: addf-init
description: |
  ADDF プロジェクトの初期セットアップまたは構造検証を行う。
  新規プロジェクトで ADDF を導入するとき、またはプロジェクト構造の整合性を確認したいときに使う。
  引数なしで初期化、`check` で構造検証。
user_invocable: true
---

# ADDF Init — プロジェクト初期化 & 構造検証

## 外部からの起動（既存プロジェクトへの導入）

このスキルが WebFetch 経由で取得された場合、または tmp ディレクトリ内のクローンから読まれている場合:

1. **URL の検証とクローン**:
   - ユーザーが提供した URL、またはデフォルト `https://github.com/fruitriin/ADDF.git`
   - `https://` スキームのみ許可。`file://`, `ssh://`, `git://` は拒否して案内する
   - URL をユーザーに表示して確認: 「以下の URL からクローンします: <url>。続行しますか？」
   ```bash
   mktemp -d
   git clone --depth 1 <url> <tmp>/addf-source
   ```
2. 現在のワーキングディレクトリ（ユーザーのプロジェクト）を **導入先** とする
3. プロジェクト種別は **「ADDF 利用プロジェクト」（ダウンストリーム）に固定** する
4. **既存ファイルからプロジェクト情報を自動取得する**（対話ステップの省略）:
   - `README.md` からプロジェクト名・目的を読み取る
   - 既存の `CLAUDE.md` があればその内容を読み取り、後で `CLAUDE.repo.md` に退避する
   - `package.json`, `Cargo.toml`, `pyproject.toml` 等があればビルド・テストコマンドを推定する
   - 推定結果をユーザーに確認する（対話ではなく確認のみ） <!-- human-judgment -->
5. 以下の init モードの Phase 1 から続行する。Phase 3 のファイルコピー元は `<tmp>/addf-source`

---

## 部分導入からの正規化

lock ファイル（`.claude/addf/lock.json`。旧配布の位置は `.claude/addf-lock.json`）が無いまま <!-- residual-path: allow -->
ADDF 由来ファイル（`.claude/commands/addf-*.md` 等）の一部が
存在するプロジェクト（手縫い導入・旧版の部分コピー）を、正規の導入状態に揃えるモード。
`/addf-migrate` は lock 不在かつ部分導入を検出したとき、このモードを提案して誘導する。

> 本節で参照するカテゴリ1〜3 の定義は、後述の init モード「Phase 3: ファイルコピー & マージ」を参照。

上記「外部からの起動」の手順（URL 検証とクローン → init モード Phase 1〜4）に合流し、
以下だけ読み替える:

- **カテゴリ1（ADDF 由来ファイル）は既存でも最新版（クローン元）で上書きする** —
  通常 init の「既存ファイルは上書きしない」原則の例外。ただし**存在≠所有**
  （ファイル名の一致は ADDF 由来の証明にならない）のため、2群に分けて扱う:
  - **安全一括上書き** — `addf-` プレフィックスや専用ディレクトリで ADDF 所有と識別できるもの:
    `.claude/commands/addf-*.md`・`.claude/agents/addf-*.md`・`.claude/addf/knowhow/ADDF/`・
    `.claude/addf/addfTools/`・`.claude/addf/tests/`・`.claude/addf/templates/`。
    一覧を提示してまとめて承認を得る <!-- human-judgment -->
  - **個別確認必須** — プレフィックス識別が効かない、または設定値・プロジェクト独自ファイルの可能性があるもの:
    - `.claude/hooks/*.sh` — 既存との diff を提示し、1ファイルずつ承認を得る <!-- human-judgment -->
    - `AGENTS.md` — ADDF ブートシーケンス見出しの有無で所有を確認する:
      `grep -q '^## Boot Sequence' AGENTS.md`。見出しが無ければ
      プロジェクト独自の同名無関係ファイルとみなし、上書きしない（実例あり — 存在≠所有）
    - `.claude/addf/Behavior.toml` — 上書きではなく、既存の `enable` 値等の設定値を
      保持して最新版の構造にマージする
  - 上書き前の差分確認は、既存ファイルごとに以下を実行して裏付ける。
    **差分が非空のファイルは安全一括上書きの群から外し、個別確認に回す**
    （差分ゼロの上書きだけを一括承認の対象にする）:
    ```bash
    git diff --no-index <既存ファイル> <tmp>/addf-source/<同パス>
    ```
- 最新版（クローン元）に存在しない ADDF 由来ファイル（リネーム前の旧名残留等）は
  削除を提案する <!-- human-judgment -->
- プロジェクト固有ファイルは従来どおり保護する（`.claude/commands/*.exp.md`・
  `.claude/addf/Progress.md`・`.claude/addf/Feedback.md`・`CLAUDE.repo.md`・`TODO.md` 等。
  カテゴリ2 のマージ・カテゴリ3 の生成は既存があれば上書きしない）
- 完了時に `.claude/addf/lock.json` をクローン元の `ref` で生成する（カテゴリ3 と同じ手順）。
  以後のアップグレードは `/addf-migrate` が使える
- 正規化完了後に `/addf-plan-audit` の初回実行を案内する（部分導入で運用してきた
  プロジェクトこそ「完了扱いだが未完了タスクが残っている計画」を抱えている母集団のため）

---

## 引数

- **引数なし**: 初期セットアップ（init モード）
- `check`: 構造検証（check モード）

---

## init モード（引数なし）

### Phase 1: 状態確認

1. 既に ADDF 導入済みか判定する:
   - `.claude/addf/lock.json` が存在する → 「ADDF は導入済みです。`/addf-init check` で構造を検証できます」と案内して終了
   - `.claude/commands/addf-*.md` が存在するが lock ファイルがない（旧位置 `.claude/addf-lock.json` にもない）<!-- residual-path: allow --> → **Template 経由の新規プロジェクト**（ADDF ファイルは同梱済み、ロックファイルのみ未生成）または**部分導入プロジェクト**（過去に手動で ADDF ファイルの一部を導入した状態）。どちらかをユーザーに確認する <!-- human-judgment -->。Template 経由なら Phase 2 に進む。部分導入なら上記「部分導入からの正規化」に従う（既存ファイルが最新版と差分なしなら lock 再生成のみで完了する）
   - `CLAUDE.md` または `.claude/` が存在するが ADDF ファイルがない → **既存プロジェクト導入モード**。「既存プロジェクトに ADDF を導入します。続行しますか？」と確認を求める <!-- human-judgment -->
   - どちらも存在しない → 初期セットアップを開始

### Phase 2: セットアップ情報の収集

**外部起動（既存プロジェクト）の場合:**

2. 既存ファイルからプロジェクト情報を自動取得する（対話を最小化）:
   - `README.md` からプロジェクト名・目的を読み取る
   - 既存の `CLAUDE.md` からプロジェクト固有の指示を読み取る（後で `CLAUDE.repo.md` に退避）
   - `package.json`, `Cargo.toml`, `pyproject.toml` 等からビルド・テストコマンドを推定する
   - git の既存コミットログからコミット規約を推定する
   - 推定結果をユーザーに確認する（対話ではなく確認のみ） <!-- human-judgment -->
   - プロジェクト種別は「ADDF 利用プロジェクト」に固定

**Template 経由（新規プロジェクト）の場合:**

2. ユーザーに以下を質問する（未回答はデフォルト値を使用）:

   **必須:**
   - プロジェクト名（デフォルト: リポジトリ名）
   - プロジェクト種別: `ADDF 利用プロジェクト`（デフォルト） / `ADDF 開発プロジェクト`

   **任意:**
   - ビルドコマンド（例: `npm run build`）
   - Lint コマンド（例: `npm run lint`）
   - テストコマンド（例: `npm test`）
   - コミットログ規約（デフォルト: 日本語 `[領域] 変更内容の要約`）
   - ターゲットエージェント: `Claude Code`（デフォルト） / `Codex` / `両方`

### Phase 2.5: 干渉チェック（既存プロジェクトの場合）

3. 既存プロジェクトのファイル・ディレクトリ構造を検査し、ADDF ファイルとの干渉を報告する:

   ```
   ╔══════════════════════════════════════════════╗
   ║  ADDF 干渉チェック                            ║
   ╚══════════════════════════════════════════════╝

   ■ 競合なし（そのままコピー）
     .claude/commands/     — 存在しない（新規作成）
     .claude/agents/       — 存在しない（新規作成）

   ■ マージが必要
     .gitignore            — 既存あり → ADDF エントリを追加
     .claude/settings.json — 既存あり → hooks/permissions をマージ

   ■ 要確認
     CLAUDE.md             — 既存あり → ADDF ブートシーケンスを先頭に挿入
     CONTRIBUTING.md       — 既存あり → 上書き or スキップを選択

   ■ 新規作成
     TODO.md, CLAUDE.repo.md, .claude/addf/Progress.md, ...
   ```

   Template 経由の場合（ADDF ファイルが既に揃っている場合）はこの Phase をスキップ。

### Phase 2.7: 導入前レビュー（既存プロジェクトの場合）

4. ADDF が追加する hooks、権限変更、CLAUDE.md への影響を明示表示する:

   ```
   ADDF はプロジェクトの開発プロセス全体を規定するフレームワークです。
   以下の変更が行われます:

   ■ Hooks（セッション中に自動実行されるコマンド）
     + SessionStart: reset-turn-count.sh → ターンカウンターリセット
     + SessionStart (compact): post-compact-recovery.sh → コンパクション後の復帰
     + UserPromptSubmit: turn-reminder.sh → ターンリマインダー
     + PreCompact: pre-compact-archive.sh → トランスクリプトアーカイブ（オプトイン）
     + PreToolUse (Skill): skill-usage-log.sh → スキル使用ログ
     + PreToolUse (Bash): destructive-git-guard.sh → 破壊的 git 操作の理由提示（Plan 0043 項目3）

   ■ 権限変更（settings.json）
     allow に追加: Read, Edit, Write, Agent, Skill, Bash(git *), ...
     ask に追加: Bash(git push *), Bash(git reset --hard *), Bash(git branch -D *),
                Bash(git checkout -- *), Bash(git restore .), Bash(git clean *)
     deny に追加: Bash(rm -rf /), Bash(chmod 777 /), Bash(dd if=* of=/dev/*),
                Bash(mkfs.*), Bash(shutdown *), Bash(reboot *), ...（極端な破壊操作 11 パターン・Plan 0043 項目1）

   ■ CLAUDE.md
     + ブートシーケンス（Feedback → TODO → Progress 自動読み込み）
     + 開発プロセス定義（計画駆動、品質ゲート）

   続行しますか？
   ```

   ユーザーが拒否した場合は中断し、一時ディレクトリを削除。

### Phase 3: ファイルコピー & マージ

ADDF ファイルの配置元を決定する:
- **外部起動**: `<tmp>/addf-source` からコピー
- **Template 経由**: ADDF ファイルは既にプロジェクト内に存在（コピー不要）
- **既存ファイルは上書きしない**（存在する場合はスキップして通知）

#### Phase 3 前置: バイナリ実物の preview（Plan 0043 項目2）

コピー実行の**前に**、配布バイナリの実物 preview をオーナーに提示する。
Plan 0031 の checksums 照合の**上流**として位置付ける — 照合は改竄検出、preview は
意図の確認。「不便のない範囲」の実装として、以下の最小構成で行う <!-- human-judgment -->:

1. `<tmp>/addf-source/.claude/addf/addfTools/checksums.sha256` を読み、記載された
   実行可能バイナリ（Swift ツール群 4本: annotate-grid / capture-window / clip-image /
   window-info）の SHA-256 と、`file`/`stat` によるサイズ・種別を1行ずつ表示する
2. ダウンストリームでは通常 **skip** で構わない（バイナリを利用する GUI テスト
   機能自体がオプトインのため）。オーナーに「preview 表示 / skip」の選択を提示する
3. skip を選ばれた場合は verify-checksums.sh を Phase 4（変更確認）の直前で1度実行し、
   改竄検出だけは残す（意図の確認は諦めるが、改竄検出は担保する）<!-- human-judgment -->
4. preview を選ばれた場合はハッシュ・サイズ・種別を表示 → オーナーが問題なしと
   判断したら続行、疑わしければ導入を中止する <!-- human-judgment -->

以下のカテゴリのファイル（バイナリ以外）は preview 対象外 — テキストなので addf-init 実行前後の `git diff` でオーナーが直接内容を確認できる。

#### カテゴリ1: 無条件コピー（外部起動の場合のみ）

**除外規則: `*.addf.md` に該当するファイルはコピーしない**（ADDF 本体専用。
`.addf.md` をダウンストリームに物理的に置くと、存在ベースの判定ロジックが
「ADDF 本体」と誤認する根源になる — 分離規約 / 存在≠所有）。

衝突リスクなし（`addf-` プレフィックスで識別可能）:
- `.claude/commands/addf-*.md` — スキル定義
- `.claude/agents/addf-*.md` — エージェント定義
- `.claude/addf/optional/` — オプトイン式スキル・エージェント・設定の原本（GUI テスト等は
  `sync-optional-skills.py apply`、ccchain（EnumaElish・構造的パーミッション制御）は
  `sync-ccchain.py apply` で有効化。いずれも `.claude/addf/addfTools/`）
- `.claude/hooks/*.sh` — フック
- `.claude/addf/templates/` — テンプレート（ディレクトリ丸ごと。個別ファイル名は列挙しない — 列挙は本体側のテンプレート追加に追従できず腐るため。除外規則により `ProgressTemplate.addf.md` 等の `*.addf.md` はコピーしない）
- `.claude/addf/addfTools/` — ツール群
- `.claude/addf/tests/` — テストスイート
- `.claude/addf/Behavior.toml`
- `.claude/addf/CHANGELOG.md`（`Release.addf.md` は除外規則によりコピーしない）
- `.claude/addf/Questions.example.md`, `.claude/addf/Dashboard.example.md` — CLAUDE.md が書式参照するため必須
- `CLAUDE.repo.example.md`, `CLAUDE.local.example.md`
- `AGENTS.md`
- `.claudeignore`
- `.claude/addf/knowhow/ADDF/`（`INDEX.addf.md` は除外規則によりコピーしない。ダウンストリームの knowhow インデックスは `.claude/addf/knowhow/INDEX.md` に一本化する）
- `.claude/addf/guides/`

#### カテゴリ2: インテリジェントマージ

- **`.claude/settings.json`**: 既存あり → ADDF の hooks と permissions をユニオン追加（既存を削除しない）。結果をユーザーに表示して確認 <!-- human-judgment -->。既存なし → ADDF テンプレートをコピー
- **`.gitignore`**: ADDF エントリをマーカーブロック付きで追加する。
  ブロックの内容は **ADDF リポジトリ（クローン元）の `.gitignore` マーカーブロックをそのままコピーする**（ここに列挙を持たない — リスト陳腐化の防止）。外部起動の場合のコピー元は `<tmp>/addf-source/.gitignore`:
  ```
  # --- ADDF Framework (do not remove) ---
  （クローン元 .gitignore の同ブロック内容）
  # --- /ADDF Framework ---
  ```
- **`CLAUDE.md`**: 既存なし → ADDF テンプレートをコピー。既存あり → 以下の手順で退避・補完する:
  1. 既存の `CLAUDE.md` と `AGENTS.md`（存在すれば）の両方を読み、プロジェクト固有の指示を把握する。重複する内容は統合し、最適な形で `CLAUDE.repo.md` に退避する（どちらのファイルに何が書かれているかは現場判断で整理）
  2. ADDF の `CLAUDE.md` テンプレートで置き換える（`@CLAUDE.repo.md` で退避先を自動参照）
  3. 退避した `CLAUDE.repo.md` を `CLAUDE.repo.example.md` と比較し、構造的不足をチェック:
     - プロジェクト種別セクション（「ADDF 利用プロジェクト」宣言）があるか
     - テストセクション（ビルド・Lint・テストコマンド）があるか
     - コミットログ規約があるか
  4. 不足があればユーザーに対話的に補完を求め、`CLAUDE.repo.md` に追記する
- **`CONTRIBUTING.md`**: 既存があればユーザーに確認（上書き / スキップ） <!-- human-judgment -->

#### カテゴリ3: プロジェクト固有ファイル（ダウンストリーム体裁で生成）

- **`CLAUDE.repo.md`** — `CLAUDE.repo.example.md` をベースに「ADDF 利用プロジェクト」として生成
  - 種別宣言行は `CLAUDE.repo.example.md` の該当行を**一字一句そのままコピーする**
    （`このリポジトリは **ADDF 利用プロジェクト** です。` — 太字マーカー含む。
    パラフレーズしない — lint-template-sync の種別判定がこの書式（太字込みの厳密一致）に依存する）
  - プロジェクト名、ビルド・Lint・テストコマンド、コミットログ規約を反映
- **`CLAUDE.local.md`** — テンプレートからコピー
- **`.claude/addf/lock.json`** — ADDF クローン元の `ref` で生成
  - `ref` にはクローン元の lock の `ref`（`vX.Y.Z` タグ名）をそのまま記録する。クローン元の lock が旧形式（`commit` フィールド）の場合は `v<version>` タグ名に読み替える
  - `git remote get-url origin` でリポジトリ URL を取得（取得できない場合はユーザーに入力を求める）
  - このファイルは `/addf-migrate` がバージョン差分を算出する際のアンカーとして使用される
- **`TODO.md`** — 初期テンプレート
- **`.claude/addf/plans/`** — ディレクトリ作成
- **`.claude/addf/knowhow/INDEX.md`** — インデックス初期化
- **`.claude/addf/Progress.md`** — `.claude/addf/templates/ProgressTemplate.md` から生成（`ProgressTemplate.addf.md` は ADDF 本体用のため使わない）
- **`.claude/addf/Feedback.md`** — 初期テンプレート
- **`.claude/addf/Questions.md`** — `Questions.example.md` の書式説明を残して未回答・回答済みを空で生成（非同期質問箱。ブートシーケンス 1.5 が参照）
- **`.claude/addf/DashboardComments.json`** — `{"comments": []}` で空生成（HTML ダッシュボードのアンカーコメント置き場。ブートシーケンス 1.7 が参照。`generate-dashboard.py` 実行時にも無ければ自動生成される）

**Codex 対応**（ターゲットが Codex または両方の場合）:
- `AGENTS.md` がリポジトリに存在することを確認する（ADDF 同梱済み）: `test -f AGENTS.md`
- Codex 設定案内を表示

### Phase 4: 完了

5. 生成結果をレポートする:
    ```
    ╔══════════════════════════════════════╗
    ║  ADDF Setup Complete                 ║
    ╚══════════════════════════════════════╝

    コピー: 35 ファイル
    マージ: .gitignore, .claude/settings.json, CLAUDE.md
    生成:   CLAUDE.repo.md, TODO.md, Progress.md, ...
    スキップ: CONTRIBUTING.md（既存保持）

    次のステップ:
    1. CLAUDE.repo.md を確認・カスタマイズしてください
    2. .claude/addf/plans/ に計画ファイルを作成してください
    3. `/addf-dev` で開発を開始できます
    ```

6. 一時ディレクトリを削除する（外部起動の場合）

---

## check モード（`/addf-init check`）

<!-- checklist-lint: skip-section（このセクションはチェックの実装そのもの。手作業チェックのスクリプト化は残課題バックログ参照） -->

読み取り専用で副作用なし。プロジェクト構造の整合性を検証する。

### チェック項目

1. **必須ファイルの存在確認**:
   - `CLAUDE.md` — ブートシーケンス定義
   - `CLAUDE.repo.md` — プロジェクト固有設定
   - `TODO.md` — タスクバックログ
   - `.claude/addf/Progress.md` — 進捗管理
   - `.claude/addf/Feedback.md` — フィードバック記録
   - `.claude/addf/Questions.md` — 非同期質問箱（無ければ WARNING、`Questions.example.md` から生成を案内）
   - `.claude/addf/lock.json` — バージョンロック
   - `.claude/settings.json` — 権限設定

2. **`CLAUDE.md` の `@` メンション解決**:
   - `CLAUDE.md` 内の `@ファイル名` パターンを抽出
   - 各参照先ファイルが実在するか確認
   - 解決できない参照があれば WARNING

3. **`TODO.md` と `.claude/addf/plans/` の整合性**:
   - TODO に記載された計画ファイルが `.claude/addf/plans/` に存在するか
   - `.claude/addf/plans/` にあるが TODO に未記載のファイルがないか

4. **`.claude/addf/lock.json` の妥当性**:
   - JSON として valid か
   - `version`, `ref`, `repository` フィールドが存在するか
   - `ref` が `v<version>` 形式のタグ名か（形式チェックのみ、リモート確認は行わない）
   - 旧形式（`ref` の代わりに `commit`）は WARNING とし、`/addf-migrate` 実行時に新形式へ移行される旨を案内する

5. **AGENTS.md の存在**（情報レベル）:
   - 存在すれば OK、なければ INFO（Codex 非対応として通知）

6. **Hooks 配線**:
   - `.claude/hooks/*.sh` が `settings.json` の hooks セクションに配線されているかを検査する
     （ファイルが存在しても配線がなければ実行されない — 手縫い導入で漏れやすい）:
     ```bash
     uv run --python 3.11 .claude/addf/addfTools/lint-hooks-wiring.py
     ```
     tomllib 不要のため uv が無ければ `python3` 直接実行でよい。
   - 未配線フックは WARNING（意図的に外している可能性があるため）。詳細は `/addf-lint` セクション11（Hooks 配線チェック）を参照

### レポート形式

```
╔══════════════════════════════════════╗
║  ADDF Structure Check                ║
╚══════════════════════════════════════╝

1. 必須ファイル        ✓ 7/7 存在
2. @ メンション解決    ✓ 全て解決可能
3. TODO ↔ plans 整合   ✓ 一致
4. addf/lock.json      ✓ 有効
5. AGENTS.md           ✓ 存在（Codex 対応）
6. Hooks 配線          ✓ 全配線済み

結果: ✓ All checks passed
```

問題がある場合は `✗` と詳細・修正提案を表示する。

---

## 再生性（Idempotency）

- init モード: 既存ファイルは上書きしない（スキップして通知）
- check モード: 読み取り専用、副作用なし
- 何度実行しても安全

## 経験の活用
- 実行前に `addf-init.exp.md` が存在すれば読み、過去の経験を考慮する
- 実行後、新たな教訓があれば `addf-init.exp.md` に追記する
