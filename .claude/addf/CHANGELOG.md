# ADDF Changelog

ADDF フレームワークの変更履歴。`/addf-migrate` 実行時に該当バージョン間のエントリを表示する。

## [0.7.0] - 2026-07-17

### 追加

- **ローカル HTML ダッシュボードとアンカーコメント・レビューループ（Plan 0058 フェーズA〜C）**:
  - `generate-dashboard.py` 新設: リポジトリ状態（TODO・Plan の FB フィールド・Questions・
    Progress・投機ブランチ・gh PR）から VitePress ダッシュボード3ページ
    （要フィードバック / 進行中タスク / 未実施の計画）＋プランビューア（全 Plan 本文）を生成。
    `npm run dashboard:dev` で閲覧（DS は `npx vitepress dev .claude/addf/dashboard`）
  - **アンカーコメント UI**（crit.md のプロトコル模倣）: ページ上の任意ブロックにホバー💬で
    コメント。GitHub PR レビュー型の draft モデル — 送信待ちスタックに積み「レビューを送信」で
    確定・確定分だけがエージェントの読み取り対象。anchor に対象ブロック原文を保持し
    再生成の行ズレに耐える。入力中テキストは localStorage にアンカー別マルチスロットで
    永続化（HMR リロード・パネル開閉で消えない）
  - コメント置き場 `.claude/addf/DashboardComments.json`（コミット対象の共有チャンネル）と
    **ブートシーケンス手順 1.7** 新設（CLAUDE.md / AGENTS.md / development-process.md）:
    エージェントが未解決コメントを読み、対応後に resolved 化。Question への回答相当は
    Questions.md へ転記（二重チャンネル回避）
  - crit（`~/.crit/reviews/`）の未解決コメントも「要フィードバック」ページに集約（二層接続）
  - Plan の owner_feedback / feedback_ask / feedback_since フィールドを PlanTemplate に追加
    （未完了 Plan 全件に遡及付与済み）
  - プランビューアの折りたたみ構文2系統: `::: details`（推奨）と `<details>/<summary>`
    パススルー（閉じ忘れはバランスチェックで全エスケープにフォールバック）。
    インラインコード内 `{{...}}` の Vue interpolation クラッシュも v-pre レンダラで解消
  - `addf-init` コピーリスト・`addf-migrate` 対象外リストに DashboardComments.json の
    補完手順を追加。テスト `test-generate-dashboard.sh` 新設（drift-injection 方式・18件）
- **ccchain オプトイン配布機構（Plan 0040 フェーズ1・2）**:
  - ADDF 本体に ccchain（EnumaElish）をドッグフーディング導入。`.ccchain.conf` を実運用
    コマンド群で調整（破壊的 git 操作の ask 化・読み取り系の allow 化）し
    PreToolUse(Bash) フックとして配線
  - `Behavior.toml` の `[ccchain]` オプトイン・`sync-ccchain.py`・`optional/ccchain/`
    テンプレート・`/addf-lint` セクション13・テスト23件を新設（フェーズ3〔ガイド・
    migrate 統合〕・フェーズ4〔配線統合〕は未着手）

### 修正

- **downstream テスト環境適合（Issue #30・#31・Plan 0059）**:
  - `test-template-sync.sh` の `make_sandbox()` を疑似コピー方式に変更 — `*.addf.md` が
    存在しない downstream でもサンドボックスが upstream シミュレータとして機能し、
    連鎖 FAIL しない（Issue #30）
  - `lint-template-sync.py` ペア6 の TODO テーブル解析を markdown リンク書式
    `[title](path)` とバックティック書式の両対応に（downstream で広く使われる
    リンク書式が「TODO 登録漏れ」誤 WARNING になっていた — Issue #31）
  - 動的アサーションの downstream 分岐を明示的に踏む回帰テストを追加
    （分岐カバレッジの構造的な穴を解消）。回帰テスト計24件追加
- **migrate-paths / lint-residual-paths の誤検知根本対処（Issue #33・Plan 0060）**:
  - `compile_pattern()` に lookbehind 境界を導入 — 外部 URL
    （例: supabase.com のドキュメント URL）や他プロジェクトの絶対パス言及を
    旧パス残存として誤検知しない。自リポジトリへの絶対パス残存は引き続き検出。
    rewrite が外部 URL を書き換えて壊す潜在バグも同時に解消（回帰テスト12件）
- **README 日英にローカルダッシュボード機能を記載（Plan 0065）**
- **ダウンストリーム移行フィードバック回収（taskbar.fm・Issue #27〜#29・Plan 0055）**:
  - `addf-migrate.md` に Phase 2.4「手順書自身の自己点検」を新設。Phase 2 で最新版を
    クローンした直後、実行中のローカル `addf-migrate.md` と比較し、古い版のまま
    実行していないかを事前検知する（Issue #27）
  - `*.addf.md` 除外規則の説明を強化: `.addf.md` サフィックスは「ダウンストリームにも
    残してよい」という意味ではなく、`Release.addf.md` を含め例外なく ADDF 本体専用で
    あることを明記（Issue #28）
  - `test-binary-checksums.sh` Test 15・`test-template-sync.sh` Test 1 が、downstream
    宣言のダウンストリームプロジェクトで実行すると原理的に必ず FAIL していた固定
    アサーションを、実プロジェクトの宣言に応じた動的アサーションに修正（Issue #29）

## [0.6.2] - 2026-07-11

### セキュリティ

- **セキュリティ回収 一括対応**（Plan 0043 全4項目・「事後観測方式」の最小実装）:
  - **項目1 明示 deny ルール**: `.claude/settings.json` の `permissions` に `deny` セクションを新設。
    極端な破壊操作11パターン（`rm -rf /` / `rm -rf ~` / `chmod 777 /` / `dd if=* of=/dev/*` /
    `mkfs.*` / `shutdown *` / `reboot *` 等）のみ限定。実運用で追加が必要になれば Feedback で調整
  - **項目2 addf-init 実物 preview**: `addf-init.md` の Phase 3 前置ステップとして、
    Swift バイナリ4本（annotate-grid / capture-window / clip-image / window-info）の SHA-256 /
    サイズ / 種別を preview 表示 / skip 可能な仕組みを追加。skip 選択時も verify-checksums.sh
    で改竄検出は担保
  - **項目3 破壊的 git ガードフック**: `.claude/hooks/destructive-git-guard.sh` を新設し
    PreToolUse(Bash) に配線。5パターン（`git reset --hard` / `push --force*` / `clean -f*` /
    `branch -D` / `checkout -- .`）に理由メッセージを stderr で提示。ブロックは
    settings.json の ask ルールに委ね、フックは理由提示の分業設計。5パターン全てが ask に
    登録されるよう `Bash(git branch -D *)` / `Bash(git checkout -- *)` / `Bash(git restore .)` /
    `Bash(git restore -- *)` を ask に追加。13テスト全パス。
    ⚠️ 実効性の申し送り: PreToolUse フックの `exit 0 + stderr` がエージェントのコンテキストに
    実際に表示されるかは未検証。実効性が観測されない場合は JSON stdout の
    `permissionDecisionReason` 方式への切り替えを検討する（Suggestion 7 対応）
  - **項目4 @メンション解決のパストラバーサル耐性**: `.claude/addf/addfTools/lint-template-sync.py`
    の `_repo_declaration_lines` と `.claude/addf/addfTools/verify-checksums.sh` の
    `detect_repo_kind()` の両側で、`..` を含むパス・絶対パス・シンボリックリンク経由の
    脱出を silent に無視するガードを追加。ペア7 の同期契約で両側の整合を保つ

### 追加

- **CI 品質ゲート**（Plan 0030・一部完了）: GitHub Actions（ubuntu-latest）で
  `bash .claude/addf/tests/run-all.sh` と lint スクリプト一式を PR・push ごとに自動実行する
  ワークフローを新設。非 macOS 専用テストは明示 SKIP で計上。CI 実地検証済み（ERROR 注入・
  WARNING annotation 表示・SKIP 計上を確認）。branch protection の要否のみオーナー判断待ち
- **バイナリ検証可能性（チェックサム照合）**（Plan 0031）: コミット済み Mach-O バイナリ4種
  （window-info / capture-window / annotate-grid / clip-image）の改竄・取り違え・片側コミットを
  機械検出する `checksums.sha256` を `build.sh` に追加し、全 OS で実行可能な照合テストを
  `.claude/addf/tests/tools/` に新設（ビルド再現性そのものは保証しない設計判断込み）
- **PR 本文標準フォーマット・投機 feature 昇格の PR 経路**（Plan 0035）: `.claude/addf/guides/pr-format.md`
  を新設し、対象 Plan リンク・複数フェーズ計画の進捗位置欄を PR 本文の標準書式として定義。
  投機 feature（`speculative/*`）を main へ昇格する際の PR 経路も整備し、複数フェーズ計画の
  「部分完成の誤完了」を防ぐ運用を明文化
- **`addf-plan-audit` スキル新設**（Plan 0036）: 「完了扱いだが未完了タスクが残っている計画」
  （埋没）を構造検査・意味的パターン・TODO 突合の3層で掘り起こす棚卸しスキルを追加。
  `/addf-migrate` のワンショット案内にも統合
- **投機適性の判定基準・大改造の窓検出**（Plan 0038）: タスクの投機適性を3区分で判定する基準を
  `/addf-dev` の選定手順に組み込み、不適合タスクの Plan 化フォールバック導線と、
  大改造（in-flight 在庫ゼロ等）の窓を検出して選択肢を提示する仕組みを追加
- **コンテキスト枯渇時のループ継続教義**（Plan 0041・フェーズ1・2 完了）: 「コンテキスト残量が
  少ないことを理由にループを止めない」教義を `addf-dev.md` と `ProgressTemplate.addf.md`
  （同期ペア）双方に配線。auto-compact 発動点の実測（`compactMetadata.preTokens`）に基づき、
  残量少時は復帰容易性の高いタスクを優先する運びを追加。実地検証（/loop 自走での継続観測）は
  別サイクルで実施予定
- **委譲禁止事項の単一ソース `DelegationRules.md`**（Plan 0046）:
  `Agent` tool 経由でサブエージェント（worktree 実装等）に委譲するときの共通禁止事項を
  `.claude/addf/templates/DelegationRules.md` に単一ソース化した（Progress.md 境界・git 操作・
  単一ソース尊重・スコープ・ノウハウ記録の5項目）。委譲時は `@DelegationRules.md` で参照する。
  ダウンストリームは末尾の「プロジェクト固有ルール」節に追記できる（addf-migrate は共通禁止事項
  のみ更新）。あわせて `lint-template-sync.py` ペア1 の検査境界（`## 運用ルール` 節のみ・
  `## タスク` 以降は同期対象外）を docstring に明文化し、`test-template-sync.sh` に境界検証テスト
  （Test 4b: タスク欄変更で誤検知しない）を追加
- **PreCompact トランスクリプトアーカイブ**（Plan 0042・オプトイン）: compaction 直前の
  トランスクリプト JSONL を `~/.claude/addf-transcript-archive/<プロジェクトスラグ>/`
  にコピーする PreCompact フックを新設。`.claude/addf/Behavior.toml` の
  `[transcript-archive] enable = true` で有効化する（デフォルト無効）。
  復元手順は `.claude/addf/knowhow/ADDF/transcript-archive-restore.md`
- **変更ルート判断表**（Plan 0047）: 新規変更・フォローアップに対して
  「dev 直行 / オーナー問い合わせ / speculate 方式」を変更の性質で選ぶ判断表を
  `.claude/addf/guides/speculative-development.md` に新設。speculate の用途拡張
  （オーナー判断待ち案件の隔離実行）も明記。`/addf-dev` `/addf-speculate` から参照
- **モデル配分ポリシー**（Plan 0049）: 役割ごとに異なる Claude モデルを使い分ける運用を
  仕組み化した。`addf-implementer` エージェントを新設し実装作業を専任分離、
  `.claude/addf/guides/model-allocation.md` ガイド新設、`CLAUDE.repo.example.md` に
  モデル配分ポリシーのプレースホルダ節を追加（プロジェクトごとの評価・割り当て表を記入する運用）
- **ドキュメントサイト骨格**（Plan 0039 フェーズ2）: VitePress によるドキュメントサイトの骨格を
  追加（フェーズ1の `addf-doc-review-agent` 逆輸入は既存リリース済み）。フェーズ3
  （GitHub Pages 公開）はオーナーによる有効化操作待ちのため未実施
- **`.gitignore` 旧位置グロブパターンの非対称検知**（Plan 0052・Issue #26 実測回収）:
  `lint-residual-paths.py` に、`.gitignore` のグロブパターンが移行後の旧位置にはマッチするが
  新位置にはマッチしない非対称（リテラル文字列一致では検出できない）を WARNING で検出する
  機能を追加。`addf-migrate.md` の Phase 2.5 に「GUI 系バイナリは再ビルド後 timeout 付きで
  実際に実行して確認する」注記、ディレクトリ丸ごと移動の混在確認対象への `guides` 追加、
  apply 後の `.gitignore` 旧位置パターン見直し注記を追加
- **README スキルテーブル網羅性 lint（ペア8）**（Plan 0053）: `lint-template-sync.py` に、
  `.claude/commands/addf-*.md`（`*.exp.md` を除く）が README.md / README.en.md のスキル一覧に
  掲載されているかを検査する `check_pair8()` を新設。新設スキルが README のドキュメント公開から
  漏れる再発を防ぐ（upstream 限定・downstream は独自 README のため SKIP）

### 変更

- **knowhow 鮮度の一括再検証**（Plan 0032）: INDEX.addf.md で 🟡 判定だった7件を
  `/addf-knowhow-revise` で再検証。3件（`permission-settings-pattern.md` の破壊性分類・
  `skill-design-patterns.md` の計測フック記述・`existing-project-install-pattern.md` の
  部分導入ケース）を訂正、他は 🟢 に復帰。新 knowhow `knowhow-obsolescence-patterns.md`
  （陳腐化しやすい3パターンと逃がし方）を追加
- **`addf-experience` のスコープ再定義**（Plan 0044）: `.exp.md` 運用方式の案A（現行の
  スキル本文と分離した方式）を実測に基づき正式採用し、`addf-experience` を
  「@メンション書式検証」から「経験参照の自己整合性・書式健全性検証」に再定義。
  テスト（`test-addf-experience.md`）・README・guides を新スコープに合わせて全面更新
- **worktree 隔離破りの防止策**（Plan 0051）: CLAUDE.md「並列実装方針」に、worktree 隔離下の
  エージェントが共有チェックアウト側を覗く際の `cd` 永続化リスク（Bash ツールの作業ディレクトリが
  呼び出し間で持続し、隔離を離脱したままコマンドが共有チェックアウト側で実行される事故）への
  注意事項を追記。knowhow の一方向リンク14件を解消し双方向化
- **フォローアップ切り出し粒度の再定義**（Plan 0047・ダウンストリーム影響あり）:
  Progress 運用ルール7「レビュー指摘・発見への対応」（旧「レビュー指摘への対応」）の判定軸を、
  クリティカル度から**「主題との関係」一次軸 + クリティカル度二次軸**に変更した。
  Plan の主題内は修正範囲が広くても同一 Plan で完遂、主題外は別 Plan に切り出す
  （切り出した Plan の優先度をクリティカル度で決める）。「フェーズ内先送り禁止」の
  安全性は主題外 Critical/High を TODO 優先度最上位＋次タスク即着手に置くことで維持。
  同期対象: `ProgressTemplate.addf.md` / `ProgressTemplate.md` / `Progress.md` /
  `guides/development-process.md`。**ダウンストリーム利用者向け**: `/addf-migrate`
  実行時に Progress 運用ルールが上書きされる。既存のカスタム運用ルールがある場合は
  マージを確認すること（addf-migrate Phase 4 のプレビューで差分が表示される）

### 修正

- **README ドキュメントテーブルの掲載漏れ**（Plan 0050）: README.md / README.en.md の
  「ドキュメント」テーブルに、既存だが未掲載だった `skills.md`・`model-allocation.md` への
  リンクを追加し、実際のガイド一覧（`.claude/addf/guides/`）との乖離を解消
- **GUI バイナリの disabled 判定失敗による無期限ハング**（Plan 0052・Issue #26 実測）:
  ダウンストリーム移行後、window-info 等の disabled 判定が旧パス参照で失敗すると画面収録権限
  ダイアログ待ちで無期限にハングする実害が確認された。`test-tools.sh` の呼び出しに `timeout`
  ガード（GNU coreutils 不在環境向けの手動 kill フォールバック付き）を追加。あわせて
  `test-binary-checksums.sh` Test 15 を `CLAUDE.repo.md`/`CLAUDE.repo.example.md` 不在の
  ダウンストリーム構成で SKIP にフォールバックするよう修正
- **CHANGELOG・README スキル一覧の記載漏れ**（Plan 0053）: Plan 0030・0031・0032・0035・0036・
  0038・0039・0041 の CHANGELOG 未記載を回収。README.md / README.en.md のスキル一覧に
  掲載漏れだった `addf-plan-audit`（Plan 0036 で新設）を追加

## [0.6.1] - 2026-07-07

### 変更

- Release.addf.md プレリリースチェック5に「overview full 負債の追跡」を追加 —
  patch で overview 鮮度を通した場合、full 推奨の申し送りが残るならリリース後タスクとして
  TODO に積む（full のトリガーはリリースではなく構造変更）

### 修正

- v0.6.0 のファイル改名（`ADDF-Release.addf.md` → `Release.addf.md`）の残存参照を統一 —
  addf-release / addf-lint / addf-migrate / addf-init のスキル本文4箇所、
  knowhow 2件（release-skill-separation / existing-project-install-pattern）、Feedback.md、
  project-overview 2箇所（歴史的記録である CHANGELOG・過去 Plan・Progress アーカイブは温存）

### ドキュメント

- project-overview を v0.6.0 世代へ full 再生成（7概念システム維持・phase-flows に
  addf-plan-audit を初掲載・interactions に CI / doc-review / 止まらない教義 / migrate Phase 2.5 を反映）

## [0.6.0] - 2026-07-06

> **⚠️ このバージョンへの移行は、必ず最新版の addf-migrate.md（Phase 2.5 入り）で実行すること。**
> 旧版（v0.5.0 以前）の addf-migrate.md はローカル保存のまま実行されるため、ディレクトリ
> 大移行（Phase 2.5）を知らない。**旧版スキルで `/addf-migrate` を開始してしまった場合**:
> Phase 5 のスキル上書きで addf-migrate.md が新版になった後、**もう一度 `/addf-migrate` を
> 実行**すれば Phase 2.5 が発動する（1周目ではディレクトリ移行されない）。また、旧版の
> Phase 3/4 は新旧構造の差分を「削除」と誤認しうるが、**削除の物理実行はしないこと**。

### 破壊的変更 — ディレクトリ大集約（Plan 0037）

ADDF 管理ファイルの配置を全面変更した。`docs/` を明け渡し（ダウンストリームが GitHub Pages 等の
一般用途に使えるように）、ADDF 由来ファイルを `.claude/addf/` 名前空間に集約した。
旧→新の全対応は `.claude/addf/addfTools/paths.toml`（単一ソース — migrate の移動処理・
残存 lint・テストが全て参照する）が保持する。主な移動:

- `docs/plans` → `.claude/addf/plans`（同様に `plans-add` / `knowhow` / `guides` / <!-- residual-path: allow -->
  `project-overview`。docs/ 直下の ADDF 管理外ファイル — Pages コンテンツ等 — には
  一切触れない: 存在≠所有）
- `.claude/templates` → `.claude/addf/templates`（同様に `tests` / `optional` / `Progresses` / <!-- residual-path: allow -->
  `addfTools`）
- リネームを伴う移動（`.claude/addf/` 内は占有空間のため `addf-` プレフィックスを外す）:
  - `.claude/addf-Behavior.toml` → `.claude/addf/Behavior.toml` <!-- residual-path: allow -->
  - `.claude/addf-lock.json` → `.claude/addf/lock.json`（旧位置は `/addf-migrate` が <!-- residual-path: allow -->
    フォールバック検出する）
  - `.claude/ADDF-CHANGELOG.md` → `.claude/addf/CHANGELOG.md`（本ファイル） <!-- residual-path: allow -->
  - `.claude/ADDF-Release.addf.md` → `.claude/addf/Release.addf.md`（`.addf.md` サフィックスは <!-- residual-path: allow -->
    配布除外規則の判定パターンのため維持 — ADDF 本体専用でダウンストリームには一切配布されない。
    「維持」はこのファイル自体が今後もダウンストリームに残ってよいという意味ではない）
  - `.claude/Progress.md`・`Feedback.md`・`Questions.md`・`Questions.example.md`・ <!-- residual-path: allow -->
    `Dashboard.example.md`・`Dashboard.md`・`Worktrees.md` → `.claude/addf/` 直下へ
- 移動しないもの: `.claude/commands`・`agents`・`hooks`・`skills`・`settings*.json`
  （Claude Code が読み込み位置を規定 — 従来どおり `addf-` プレフィックスで分離）と、
  ルートのエントリポイント（`CLAUDE.md`・`TODO.md`・`AGENTS.md`・`CLAUDE.repo.md` 等）
- 旧パスへの symlink 等の後方互換スタブは置かない。残存参照は lint が即時 ERROR で知らせる
  （「静かに壊れる」より「うるさく直させる」）

### 移行ガイド

`/addf-migrate` を実行すると Phase 2.5（構造差分で発動 — 0.4.x 以前からの直行アップグレード
でも漏れない）が本手順を案内する。手動で行う場合の要約:

1. 作業ツリーを clean にする（dirty なら開始しない）
2. 最新版クローンから移行ツール3点（`migrate-paths.py`・`lint-residual-paths.py`・
   `paths.toml`）を旧位置 `.claude/addfTools/` へコピーしてコミットする <!-- residual-path: allow -->
   （移行前のプロジェクトには道具がまだ無い）
3. `uv run --python 3.11 .claude/addfTools/migrate-paths.py check` で移動計画・旧パス参照数・ <!-- residual-path: allow -->
   rewrite 射程外の候補を確認する（uv が無ければ python3（3.11+）で直接実行）
4. `uv run --python 3.11 .claude/addfTools/migrate-paths.py apply` → **git mv だけを <!-- residual-path: allow -->
   単独コミット**（backup ref `refs/backup/pre-0037-migration` が自動作成される）
5. **新位置**の `uv run --python 3.11 .claude/addf/addfTools/migrate-paths.py rewrite` →
   参照書き換えを別コミット（ツール自身も移動済みのため旧パスのコピペは不可）
6. `uv run --python 3.11 .claude/addf/addfTools/lint-residual-paths.py` で残存ゼロを確認する
   （ERROR = 移行未完了）
7. プロジェクト自身のビルド・テストを実行する。失敗したら **rewrite 射程外の4類型**
   （相対階層参照 / `os.path.join` 等の分割断片 / 書き込み先の親 mkdir / Markdown 相対リンク）
   を疑う — ADDF 本体の移行実測では 19 スイート中 18 の失敗が全てこの類型だった。
   git 追跡外ファイル（`settings.local.json` の許可ルール等）とコンパイル済みバイナリ内の
   パス断片も rewrite の対象外のため手動確認する
8. 失敗時の巻き戻し: `git reset --hard refs/backup/pre-0037-migration`

### 追加
- `migrate-paths.py` — paths.toml 駆動の移行ツール（check / apply / rewrite の3モード）。
  apply と rewrite の dirty 拒否でコミット分離を構造的に強制・backup ref の既存上書き拒否・
  symlink 除外・境界チェック付き置換（`docs/plans` が `docs/plans-add` に誤マッチしない）。 <!-- residual-path: allow -->
  check は rewrite 射程外の候補（相対階層参照・パス断片・相対リンク）も警告する
- `lint-residual-paths.py` — 旧パス残存の完了ゲート（ERROR ゼロになるまで移行を完了扱い
  しない）＋移行後の docs/ 逆流 WARNING（移行前のリポジトリでは明示 SKIP）
- `paths.toml` — 旧→新パスマップの単一ソース（コピーリスト類の手書きドリフトの構造的排除）
- `test-migrate-paths.sh` — 71 アサーション（独自 knowhow・Pages コンテンツを持つ合成
  プロジェクトでのダウンストリーム移行シミュレーション・ドリフト注入・攻撃再現テスト込み）
- 行単位の除外マーカー `residual-path: allow` — 移行手順書・移行ガイドの正当な旧パス
  言及行を行単位で除外する（ファイル丸ごとの除外による lint 盲点を排除）
- rewrite 完了メッセージに書き換え対象外（追跡外ファイル・パス断片・相対リンク・バイナリ）の
  手動確認案内

### 変更
- `/addf-migrate` に Phase 2.5（ディレクトリ大移行のワンショット手順）と lock 旧位置
  （`.claude/addf-lock.json`）のフォールバック検出を追加 <!-- residual-path: allow -->

## [0.5.0] - 2026-07-05

### 追加
- 投機開発の再構築・掃除・昇格運用（Plan 0028 フェーズ3完結）
  - `speculate-reconcile.py` — check（worktree prune＋走査＋merged_hint）/ clean（`--delete` 明示指定制。Worktrees.md の「昇格済み/放棄」記載との突合を削除前に強制、過去日付 integration の自動掃除、dirty worktree 既定拒否）
  - 昇格手順（`speculative/<concept>` → main の squash マージ。オーナーの明示応答必須・無応答を承認とみなすこと禁止）
  - テスト `test-speculate-reconcile.sh` 17本・72アサーション
- 投機運用ガイド `.claude/addf/guides/speculative-development.md` — 2層モデル・オプトイン・ライフサイクル・昇格の定義・clean 原則の概観
- `lint-hooks-wiring.py` — settings.json のフック配線と実ファイルの突合（境界チェック付き。addf-lint セクション11・addf-init check 項目6）
- addf-migrate の部分導入正規化モード — lock 不在＋ADDF ファイル有りの構成で「安全一括上書き / 個別確認必須」の2分割手順を提案
- プレリリースチェックに項目4（README 和英の新機能反映確認）・項目5（project-overview の鮮度確認）を追加
- project-overview に「投機開発」を独立の概念システムとして追加（6→7 システム）

### 変更
- upstream/downstream 判定を暗黙推定から明示シグナルに統一（Plan 0033）
- worktree への `.claude` 複製を3行構成に — venv/node_modules/__pycache__ の除外（symlink 含む）と追跡ファイル復元（Issue #18）
- `speculate-integrate.py` の `--base` を origin default branch 自動検出に（検出不能時は main フォールバック＋NOTE 可視化）（Issue #20）
- addf-migrate 14.6 の .gitignore ADDF ブロック置換をマーカー数検査付きに（不成立は手動マージへフォールバック）（Issue #20）
- run-all.sh に「必須ランタイム不在を SKIP=成功にしない」ガイドラインを追加
- addf-dev に Stage 構成の読み替え指針（独自フェーズ構成・単線構成プロジェクト対応）
- README（和・英）に addf-speculate と投機開発ガイドを掲載
- project-overview の GUI テスト記述をオプトイン前提に統一（Plan 0029 残課題 L1 解消）
- 投機の同時 worktree 上限（`max_worktrees`）の推奨値を 3→7 に変更

### 修正
- 投機 worktree の venv 破損バグ — `.claude` 複製時に venv/シンボリックリンクを持ち込まない（Issue #18・ダウンストリーム実測報告）
- default branch が main でないダウンストリームでの integration 誤 base — 自動検出化により解消（Issue #20）
- lint-template-sync のダウンストリーム構成（addf-lock.json あり・独自 AGENTS.md あり）での誤検知（Plan 0033）

## [0.4.0] - 2026-07-03

### 追加
- worktree 投機開発（`/addf-speculate`）— アイドル時に直交概念を `speculative/` ブランチで投機し、integration ブランチで一括動作確認する2層モデル（Plan 0028 フェーズ1・2）
  - `speculate-guard.py` — `[speculation]` enable・上限の発動ガード（オプトイン式・デフォルト無効）
  - `speculate-integrate.py` — integration ブランチへの squash 統合。衝突 feature のスキップ報告・commit フック拒否の検出（`commit_failed`）・メイン作業ツリー不可侵
  - Stage 2 一括ゲート（integration 上の相互作用テスト＋ペルソナ並列レビュー）と Dashboard 書き分け
- オプショナルスキルのオプトイン機構 — GUI スキル一式を `.claude/addf/optional/` に退避し、`[gui-test] enable` + `sync-optional-skills.py apply` で有効化コピーを配置（Plan 0029 フェーズ1）
- チェックリスト裏付け lint（`lint-checklist.py`）— 手順書の「確認」項目に実行チェックか human-judgment マーカーの裏付けを要求（Plan 0027）
- 旧 Python 環境ガード — tomllib（Python 3.11+）・PEP 723 依存（pyyaml）を使うスクリプトに責務別 import ガード（lint = SKIP / 実行前ゲート = フェイルセーフ ERROR / 変更系 = ERROR）
- 再現テスト群 — `test-lint-toml` / `test-lint-frontmatter` / `test-speculate-guard` / `test-speculate-integrate` / `test-optional-skills`（PYTHONPATH シム・commit フック注入によるドリフト注入 TDD）

### 変更
- Python スクリプトの呼び出しを `uv run --python 3.11` に統一し、uv 不在環境向けの `python3` 直接実行フォールバック注記を手順書（addf-lint / addf-migrate / addf-speculate / .claude/addf/guides）に併記
- GUI テストシナリオ（test-addf-clip-image / test-addf-annotate-grid）にオプトイン前提の注記を追加
- 非 macOS 環境ではバイナリ実行テストを SKIP（Plan 0029）

### 修正
- macOS システム python3（3.9）で tomllib 依存スクリプトが未捕捉の Traceback で落ちる罠を修正
- `lint-frontmatter.py` の pyyaml 欠如時の未捕捉クラッシュを SKIP ガード化（ペルソナ並列レビューの3者独立指摘による検出）

## [0.3.0] - 2026-06-29

### 追加
- 「迷ったときの作法（7割共有原則）」— 3軸（信頼性・応答性・完成イメージ確度）でエージェントの進む/止まる/問うを制御（Plan 0016）
- 代替わり日記（Progress 日記）— compaction・resume・loop 継続での「小さな代替わり」に備える引き継ぎ書式（Plan 0017）
- knowhow ライフサイクル管理 — 鮮度タグ・`/addf-knowhow-revise`・`/addf-knowhow-network` による知見の経年管理（Plan 0018）
- 分かれ道の目印（`.exp.md` 🔀セクション）— 差し戻し・やり直しの経験を道標として記録（Plan 0019）
- 視点ずらしレビュー（ペルソナ並列）— `addf-code-review-agent` に5つのペルソナを追加し、マイルストーン時に並列起動（Plan 0020）
- テンプレート同期 lint（`lint-template-sync.py`）— 6ペアの同期チェックを自動化（Plan 0021, 0022, 0024）
- turn-reminder の関心事分離 — ターンカウンターとコンテキスト量リマインダーを独立スクリプトに分割（Plan 0023）
- 実測ベース能動コンパクション促し — `context-reminder.py` でトークン量を実測し、閾値超過時に促す（Plan 0023）
- `/addf-overview` スキル — エコシステム概要の提供
- コンパクション復帰フック — コンパクション後のブートシーケンス再開を自動化
- プロジェクト初回の骨格プランニングフロー — ブートシーケンス Step 4 でヒアリング→計画生成を自動化
- `CLAUDE.repo.md` 自動生成 — 骨格プランニング時にプロジェクト固有設定を生成
- ノウハウ記録の3観点（コーディング・品質ゲート・タスク総括）を ProgressTemplate に明文化
- `.claude/addf/Questions.md` — 非同期質問箱（relaxed/unattended モード用）
- `.claude/addf/Dashboard.md` — unattended 自走時の差分まとめ

### 変更
- リポジトリ URL を `fruitriin/ADDF` に変更（Plan 0025）
- README にロゴバナーを追加
- 代替わり日記の「同僚」表現を「同僚でもあり、寝て起きたあとの自分でもある」に改善

### 修正
- `addf-init` コピーリストの鮮度回復と同期 lint ペア5の追加（Plan 0022）
- Questions.md の運用フロー整備

## [0.2.0] - 2026-03-21

### 追加
- `/addf-init` スキル — プロジェクト初期セットアップ・構造検証・既存プロジェクトへの導入
- `/addf-release` スキル — リリース自動化（upstream/downstream 自動判定）
- `/addf-migrate` にスキルリネーム時の `.exp.md` 手動リネーム案内を追加
- `ADDF-Release.addf.md` — ADDF 本体のリリース手順定義
- `AGENTS.md` — Codex 向けブートシーケンス
- `.claude/addf/guides/codex-setup.md` — Codex ユーザー向けセットアップガイド
- 経験ファイルテンプレート（`ExperienceTemplate.md`）と主要3スキルの初期経験
- スキル使用計測フック（`skill-usage-log.sh` / PreToolUse）
- `.claude/addf/guides/` にドキュメント分離（setup, skills, agents, development-process, migration）
- 既存プロジェクトへの ADDF 導入（WebFetch → tmp クローン → 干渉チェック → 導入前レビュー）
- `.gitignore` マーカーブロック形式（`addf-migrate` での自動更新対応）

### 変更
- `/addf-dev-loop` → `/addf-dev` にリネーム（1タスク実施が基本、`/loop` で繰り返し）
- 全スキルの description にトリガー条件（「〜のとき使う」）を追加
- README をリポジトリ構成フレームワークとして再構成（対応エージェント表、既存プロジェクト導入手順）
- `addf-lint` の frontmatter チェックで `.exp.md` を除外

### 修正
- `addf-migrate` の対象リストに `settings.json`, `AGENTS.md`, `ADDF-Release.addf.md`, `.claude/addf/guides/` を追加
- `skill-usage-log.sh` の JSONL インジェクション対策（jq でエントリ全体を生成）
- `addf-init` / `addf-migrate` に URL 検証ステップを追加（`https://` のみ許可）

## [0.1.0] - 2026-03-20

### 追加
- `addf-lock.json` — バージョン追跡用ロックファイル
- `/addf-migrate` スキル — ADDF のアップグレードを安全に実行する6フェーズのマイグレーション
- `ADDF-CHANGELOG.md` — フレームワーク変更履歴（本ファイル）
- `settings.json` に `git clone`, `git -C`, `mktemp` 権限を追加

### 初期リリース内容
- ブートシーケンス（CLAUDE.md）による自動コンテキスト読み込み
- ノウハウ管理（`/addf-knowhow`, `/addf-knowhow-index`, `/addf-knowhow-filter`）
- 自律開発（`/addf-dev`、旧 `/addf-dev-loop`）
- 品質ゲート（`addf-code-review-agent`, `addf-security-review-agent`, `addf-contribution-agent`）
- GUI テスト（`/addf-gui-test`, `/addf-annotate-grid`, `/addf-clip-image`）— macOS オプション
- 経験ファイル検証（`/addf-experience`）
- フレームワーク整合性チェック（`/addf-lint`）
- 権限監査（`/addf-permission-audit`）
- ターンカウンターフック（SessionStart / UserPromptSubmit）
