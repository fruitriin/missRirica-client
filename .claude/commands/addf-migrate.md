---
name: addf-migrate
description: |
  ADDF フレームワークを最新版にアップグレードする。.claude/addf/lock.json のバージョンと
  最新版の差分を算出し、安全にマイグレーションする。
  ADDF のアップデート・バージョンアップ・マイグレーションを行いたいときに使う。
user_invocable: true
---

# ADDF マイグレーション

ADDF フレームワークを最新版（またはターゲットバージョン）にアップグレードする。

## 引数

- **引数なし**: 最新版にアップグレード
- `$ARGUMENTS`: ターゲットのコミットハッシュまたはタグを指定

## 前提条件

- `.claude/addf/lock.json` が存在すること。無ければ**旧位置フォールバック**として
  `.claude/addf-lock.json`（v0.6.0 未満の配布位置）を探し、あればそれを正として読む <!-- residual-path: allow -->
  （Phase 2.5 のディレクトリ大移行で新位置へ移動される）。どちらにも存在しない場合は2分岐:
  - ADDF 由来ファイル（`.claude/commands/addf-*.md` 等）も存在しない → エラー終了し `/addf-init` を案内する
  - ADDF 由来ファイルが存在する（= lock 未生成の**部分導入**プロジェクト。手縫い導入・旧版の部分コピー） → 「lock がありませんが ADDF ファイルを検出しました。初期正規化モードで走りますか？」と提案する <!-- human-judgment -->。承認されたら `/addf-init` の「部分導入からの正規化」手順に合流する: 最新版をクローンし、既存の ADDF 由来ファイルは最新版で上書き（安全一括上書きと個別確認必須の2群に分けて扱う — 存在≠所有）・プロジェクト固有ファイル（`*.exp.md`・`Progress.md`・`CLAUDE.repo.md` 等）は保護・完了時に `.claude/addf/lock.json` を生成する。手順の実体は `addf-init.md`（外部起動導入＋読み替え）を参照する — ここには重複記述しない
- ワーキングツリーがクリーンであること（未コミットの変更があれば中断して案内する）

## マイグレーション手順

### Phase 1: 状態確認

1. `.claude/addf/lock.json`（無ければ旧位置 `.claude/addf-lock.json` — 「前提条件」の <!-- residual-path: allow -->
   旧位置フォールバック）を読み、現在の `ref`（`vX.Y.Z` タグ名）と `version` を記録する
   - **旧形式の後方互換**: `ref` がなく `commit` フィールドがある lock（v0.3.0 以前の形式）は、`v<version>` タグを起点として扱う（記録されたハッシュはリリースプロセスの都合で実在しない場合があるため、タグを正とする）
2. `git status` でワーキングツリーがクリーンか確認する
   - クリーンでなければ: 「未コミットの変更があります。コミットまたはスタッシュしてから再実行してください」と案内して終了
3. ロックファイルの `repository` フィールドから ADDF リポジトリの URL を取得し検証する:
   - `https://` スキームであることを確認する（`file://`, `ssh://`, `git://` は拒否）: `grep -q '^https://' <<<"<repository-url>"`
   - デフォルト URL（`https://github.com/fruitriin/ADDF.git`）と異なる場合は警告を表示
   - URL をユーザーに表示して確認 <!-- human-judgment -->

### Phase 2: 最新版の取得

4. 一時ディレクトリを作成する:
   ```bash
   mktemp -d
   ```
5. ADDF リポジトリを一時ディレクトリにクローンする:
   ```bash
   git clone --depth 1 <repository-url> <tmp-dir>/addf-latest
   ```
   ターゲット指定時:
   ```bash
   git clone <repository-url> <tmp-dir>/addf-latest
   git -C <tmp-dir>/addf-latest checkout <target>
   ```
6. 最新版のコミットハッシュを記録する:
   ```bash
   git -C <tmp-dir>/addf-latest rev-parse HEAD
   ```

### Phase 2.4: 手順書自身の自己点検（「2.4」は後続のフェーズ番号を壊さないための枝番）

> Issue #27: 旧版（v0.5.0 以前）の `addf-migrate.md` で `/addf-migrate` を開始してしまうと、
> Phase 2.5（v0.6.0 で新設されたディレクトリ大移行）を知らないまま Phase 3 以降に進んでしまう。
> この問題自体は「Phase 5 でスキルが新版に上書きされた後、もう一度実行する」という事後救済
> （`.claude/addf/CHANGELOG.md` の `[0.6.0]` エントリ参照）でしか解消できない —
> **旧版のファイルには本フェーズの指示自体が存在しないため、本フェーズはその旧版ユーザーを
> 事前救済できない**。本フェーズが実際に予防するのは、**本フェーズ自体を既に含む版で
> `/addf-migrate` を開始した後、さらに新しいバージョンが出ていた場合**の同種のドリフト
> （手順書自体が実行中に古くなる構造的リスク）に対する事前検知である。

6.05.（「6.05」は Phase 2 のステップ6と、Phase 2.5 専用の枝番 6.1〜6.10 の間に割り込む、
Phase 2.4 専用の枝番。6.1〜6.10 とは無関係）いま実行している（ローカルの）
`.claude/commands/addf-migrate.md` と、Phase 2 でクローンした
最新版の `<tmp-dir>/addf-latest/.claude/commands/addf-migrate.md` を比較する:
```bash
diff -q .claude/commands/addf-migrate.md <tmp-dir>/addf-latest/.claude/commands/addf-migrate.md 2>&1
```
   - **差分なし（exit 0）**: 実行中の手順書は最新版と同一のため、そのまま Phase 2.5 に進む
   - **差分あり（exit 1）**: 「実行中の `/addf-migrate` 手順書自体が古い版です。これ以降は新版
     （`<tmp-dir>/addf-latest/.claude/commands/addf-migrate.md`）の内容に読み替えて進めます」と
     明示的にユーザーに伝えた上で、以降の Phase（特に Phase 2.5 の発動判定）はクローンした
     最新版の記述に従う。この時点でのユーザーへの通知は情報提供のみで、確認待ちで停止する
     必要はない（Phase 2.5 の発動判定・Phase 4 の適用確認で改めて承認を取るため）
   - **比較対象が見つからない（exit 2・stderr にエラー）**: 最新版でファイル自体が改名・
     移動された可能性がある。`<tmp-dir>/addf-latest/.claude/commands/` の実際の構成を
     確認し、該当する後継ファイル（あれば）と比較し直すか、見つからなければこのステップは
     スキップして Phase 2.5 に進む <!-- human-judgment -->

### Phase 2.5: ディレクトリ大移行（v0.6.0 新構造・ワンショット）

（「2.5」は後続のフェーズ番号を壊さないための枝番。以降のステップ 6.1〜6.10 は
Phase 2 のステップ6とは独立した、このフェーズ専用の枝番）

> この Phase は**本ファイルの新版（v0.6.0 以降）を読んでいる場合のみ機能する**。
> 旧版（v0.5.0 以前）の addf-migrate.md で `/addf-migrate` を開始した場合、この Phase は
> 存在せず1周目ではディレクトリ移行されない — 復旧: Phase 5 のスキル上書きで本ファイルが
> 新版になった後、**もう一度 `/addf-migrate` を実行**すれば Phase 2.5 が発動する。

v0.6.0 で ADDF 管理ファイルの配置が全面的に変わった（docs/ の明け渡しと `.claude/addf/` への
集約 — 旧→新の全対応と背景は `.claude/addf/CHANGELOG.md` の [0.6.0] 移行ガイド参照）。
本フェーズは**構造の差分で発動する** — バージョン番号のハードコードではないため、
0.4.x 以前から v0.6.0 以降へ直行するバージョン跨ぎでも漏れず、移行済みプロジェクトでは
発動しない（Phase 6 のステップ 16.5 と同じ差分連動の型）。

発動した場合は**一発通し切り**を推奨する: 6.2〜6.7 を中断なしで通し切る（git mv と参照
書き換えの間で止まった main が最も危険なため。ADDF 本体は Plan 0037 でオーナー同席・
単一セッションで実施した）。途中で想定外が出たら粘らず 6.9 で巻き戻す。

6.1. **発動判定**: ターゲットが新構造で、ローカルが未移行のときだけ 6.2 以降を実施する:
    ```bash
    # 判定パス .claude/addf は paths.toml の [meta].new_root と手動同期（変更時は両方直す）
    if [ -f <tmp-dir>/addf-latest/.claude/addf/addfTools/paths.toml ] && [ ! -d .claude/addf ]; then
      echo "MIGRATION-REQUIRED: Phase 2.5 を実施する"
    else
      echo "SKIP: Phase 2.5 は不要（Phase 3 へ進む）"
    fi
    ```
    **セカンダリチェック（部分適用の検出）**: `.claude/addf` が存在しても、旧位置
    （`.claude/addfTools`・`docs/plans` 等）にファイルが残る場合は以前の移行の**部分適用** <!-- residual-path: allow -->
    （apply/rewrite の途中失敗）の可能性がある。上の判定が SKIP でも、次で MOVE が
    1件以上出るなら Phase 2.5 を実施する（ツールが未導入なら 6.2 の手順で導入してから実行する）:
    ```bash
    TOOL=.claude/addf/addfTools/migrate-paths.py
    [ -f "$TOOL" ] || TOOL=.claude/addfTools/migrate-paths.py  # residual-path: allow（旧位置フォールバック）
    uv run --python 3.11 "$TOOL" check | grep '^MOVE' || echo "MOVE なし（部分適用ではない）"
    ```

6.2. **道具の導入**: 移行前のプロジェクトには移行ツールがまだ無いため、クローンした最新版から
    取得し、単独コミットする（作業ツリーを clean に保つ — apply は dirty を拒否する）:
    ```bash
    mkdir -p .claude/addfTools  # residual-path: allow（旧位置への意図的な配置）
    cp <tmp-dir>/addf-latest/.claude/addf/addfTools/migrate-paths.py \
       <tmp-dir>/addf-latest/.claude/addf/addfTools/lint-residual-paths.py \
       <tmp-dir>/addf-latest/.claude/addf/addfTools/paths.toml \
       .claude/addfTools/  # residual-path: allow
    git add .claude/addfTools && git commit -m "[移行] v0.6.0 ディレクトリ移行ツールを導入"  # residual-path: allow
    ```
    （ツールは旧位置 `.claude/addfTools/` に置く — paths.toml は旧位置をフォールバック探索し、 <!-- residual-path: allow -->
    apply がツール自身も新位置へ移動する。コピー先に同名ファイルが既にある場合は
    プロジェクト独自ファイルの可能性があるため、上書きせず先に別の場所へ退避する）

6.3. **プリフライト（check・読み取り専用）**: 移動計画・移動先の衝突・旧パス参照の全数と、
    rewrite の射程外候補の警告を確認する:
    ```bash
    uv run --python 3.11 .claude/addfTools/migrate-paths.py check  # residual-path: allow
    ```
    （uv が無ければ `python3 .claude/addfTools/migrate-paths.py check`。Python 3.11+ が必要） <!-- residual-path: allow -->
    - exit 1（ブロッカーあり）の場合は表示に従って解消してから再実行する
    - **存在≠所有**: docs/ は ADDF 管理サブディレクトリ（plans / plans-add / knowhow / guides /
      project-overview）単位でのみ移動する。docs/ 直下のプロジェクト固有ファイル
      （GitHub Pages コンテンツ等）は移動リストに現れず、ツールは一切触れない —
      check の移動リストにプロジェクト固有ファイルが**含まれていない**ことを目視確認する <!-- human-judgment -->
    - **ディレクトリ丸ごと移動の混在確認**: `.claude/addfTools`・`.claude/templates`・`.claude/tests`・ <!-- residual-path: allow -->
      `.claude/optional`・**`docs/guides`** は**ディレクトリ単位で丸ごと** `.claude/addf/` 占有空間へ <!-- residual-path: allow -->
      移動される（存在≠所有の識別はディレクトリ移動には効かない）。`docs/guides` は上記の <!-- residual-path: allow -->
      「存在≠所有」（plans/plans-add/knowhow/project-overview のサブディレクトリ単位判定）とは
      扱いが異なる点に注意 — guides はサブディレクトリ分割がなく丸ごと移動されるため、
      templates/tests と同じ「ファイル単位の混在確認」が必要（サブディレクトリ単位判定は効かない）。
      プロジェクト独自ファイルが混在していると占有空間に引き込まれ、**将来の migrate（Phase 5
      「その他のファイル」の addfTools・tests・guides 上書き）で消えうる**。クローン元との差分で
      独自ファイルの有無を確認し、あれば移行前に別の場所（`.claude/` 直下・`docs/` 直下や
      `scripts/` 等の占有空間外）へ退避する <!-- human-judgment -->:
      ```bash
      for d in addfTools templates tests optional; do
        diff -rq ".claude/$d" "<tmp-dir>/addf-latest/.claude/addf/$d" 2>/dev/null | grep '^Only in \.claude/'
      done
      diff -rq "docs/guides" "<tmp-dir>/addf-latest/.claude/addf/guides" 2>/dev/null | grep '^Only in docs/guides'  # residual-path: allow
      ```
      （`Only in .claude/<dir>` / `Only in docs/guides` の行 = クローン元に無いローカル固有ファイル。 <!-- residual-path: allow -->
      ADDF 由来の経験ファイル等ではなくプロジェクト独自のものが出たら退避する）
    - check の出力をユーザーに提示し、大移行の実施承認を得る <!-- human-judgment -->

6.4. **apply（git mv）→ 単独コミット**: backup ref（`refs/backup/pre-0037-migration`）が
    自動作成され、git mv が一括実行される。**git mv だけをコミットする**（参照書き換えと
    混ぜない — revert 一発で戻せる原子性）:
    ```bash
    uv run --python 3.11 .claude/addfTools/migrate-paths.py apply  # residual-path: allow
    git add -A && git commit -m "[移行] v0.6.0 ディレクトリ大移行 (1/2): git mv"
    ```
    **`.gitignore` 旧位置パターンの見直し**: `.gitignore` に旧位置ベースの独自パターン
    （例: `.claude/Progress.md`）がある場合、git mv 後は新位置（`.claude/addf/Progress.md`）に <!-- residual-path: allow -->
    パターンがマッチせず意図せず追跡対象になりうる（ダウンストリーム実測で Progress.md・
    Dashboard.md・Worktrees.md・ProgressTemplate.md が該当）。`git status` で新規追跡ファイルが
    無いか確認し、あれば `.gitignore` のパターンを新位置に合わせて更新する <!-- human-judgment -->

6.5. **rewrite（参照書き換え）→ 別コミット**: apply でツール自身も移動済みのため、
    **新位置**のコマンドラインで実行する（旧位置のコピペは No such file になる。
    apply の完了メッセージにも新位置のコマンドが表示される）:
    ```bash
    uv run --python 3.11 .claude/addf/addfTools/migrate-paths.py rewrite
    git add -A && git commit -m "[移行] v0.6.0 ディレクトリ大移行 (2/2): 参照書き換え"
    ```

6.6. **残存参照ゼロの確認（完了ゲート）**: 旧パス参照の残存を検査する。ERROR が出たら
    移行は未完了（apply / rewrite の部分適用の可能性もある — check で状態を確認する）:
    ```bash
    uv run --python 3.11 .claude/addf/addfTools/lint-residual-paths.py
    ```
    exit 2 は docs/ への逆流検出の WARNING（移行直後の一発実施では通常発生しない。
    恒久検査として再実行したときに docs/ へ ADDF ファイルが再侵入した場合のシグナル）

6.7. **プロジェクト自身のビルド・テストを実行する**: lint ゼロだけでは完了にしない。
    `.claude/addf/tests/run-all.sh` が存在しないプロジェクト（部分導入・軽量導入）では
    下のコマンドをスキップし、プロジェクト固有のビルド・テストのみ実行する。
    rewrite は「フルパス文字列のリテラル出現」しか書き換えられないため、以下の
    **射程外4類型**はここで初めて露見する（ADDF 本体の移行実測では、移行直後に
    テスト 19 スイート中 18 が失敗し、原因は全てこの類型だった）:
    ```bash
    bash .claude/addf/tests/run-all.sh   # ＋ CLAUDE.repo.md 記載のプロジェクト固有のビルド・Lint・テスト
    ```
    失敗したら以下を疑って修正し、再実行する（修正は追加コミットでよい）:
    1. **相対階層参照**: `SCRIPT_DIR/../../..` 等 — ディレクトリが深くなり全てのルート算出がずれる
    2. **分割断片**: `os.path.join(dir, '.claude', 'addf-Behavior.toml')` 等の組み立てパス。
       コンパイル済みバイナリ内の断片はソース修正＋再ビルド＋checksums 更新まで必要。
       **GUI 系バイナリ（window-info・capture-window 等）を含む場合は特に注意する**: disabled
       判定（`gui-test.enable = false`）が旧パス参照で失敗すると、実際の GUI 情報取得処理に
       フォールバックし**画面収録権限ダイアログ待ちで無期限にハングしうる**（ダウンストリーム
       実測で9時間ハングした実績あり — 詳細は `map-driven-migration-tool.md` 参照）。ソース修正・
       再ビルド・checksums 更新に加えて、**timeout 付きで実際に実行して確認する**こと（disabled
       状態のはずが実処理に落ちていないかは実行時間でしか判別できない） <!-- human-judgment -->
    3. **書き込み先の親 mkdir**: テストのサンドボックス構築等で、書き込みパスだけ書き換わり
       `mkdir -p` / `cp` の準備側が旧構造のまま残る
    4. **Markdown 相対リンク**: `../../` 等 — ファイル自身の階層が変わるとリンク先がずれる
       （テストにかからず、レンダリング時にしか壊れない）

6.8. **射程外の手動確認**: rewrite 完了メッセージの案内（と check の射程外候補警告）に従い、
    テストで露見しない残りを点検する <!-- human-judgment -->:
    - git 追跡外ファイル（`.claude/settings.local.json` の許可ルール等）に残る旧パス
    - Markdown 相対リンクの解決（上記類型4 — 全 Markdown を一度リンクチェックする。
      例: `grep -rn '](\.\./' --include='*.md' .` で相対リンクを列挙して目視する）
    - 上記4類型のうちテストにかからなかったもの
    - 移動先 `.claude/addf/` 配下に、元々のプロジェクト独自ファイルが混入していないか
      （6.3 の混在確認の再点検 — 混入したまま残すと将来の migrate の上書きで消えうる） <!-- human-judgment -->

6.9. **失敗時の巻き戻し**: 途中で想定外が出たら粘らず backup ref へ戻す（「直しながら進む」
    より、巻き戻して原因を解消してからの再実行を優先する — main に中途半端な状態を残さない）:
    ```bash
    git reset --hard refs/backup/pre-0037-migration
    ```
    （backup ref は 6.2 の道具導入コミットを含む「git mv 直前」を指す）

6.10. 本フェーズ完了後、Phase 3 以降は新構造のパスで続行する（本書のパス表記はすべて新構造）

### Phase 3: 差分算出

7. 現在のロックファイルの `ref`（タグ）と最新版の間で、ADDF 管理ファイルの差分をリストアップする

**マイグレーション対象ファイル**（除外規則: `*.addf.md` に該当するファイルは**例外なく**対象外 — ADDF 本体専用で
ダウンストリームには一切配布されない。`.addf.md` サフィックスは「除外規則の判定パターン」という意味しか持たず、
「ダウンストリームでも保持してよい」という意味ではない（`Release.addf.md` を含む）。
旧バージョンの配布で残っている `*.addf.md`（例: `ProgressTemplate.addf.md`、`INDEX.addf.md`、`Release.addf.md`）が
あれば削除を提案する）:
- `.claude/commands/addf-*.md` — スキル定義
- `.claude/agents/addf-*.md` — エージェント定義
- `.claude/addf/optional/` — オプトイン式スキル・エージェント・設定の原本（適用後に
  `sync-optional-skills.py`・`sync-ccchain.py` の再実行を案内）
- `.claude/hooks/` — フック
- `.claude/addf/templates/` — テンプレート
- `.claude/addf/addfTools/` — ツール群
- `.claude/addf/tests/` — テストスイート
- `.claude/settings.json` — 共有権限設定（マージ — Phase 5 参照）
- `CLAUDE.md` — ブートシーケンス（マージ注意）
- `AGENTS.md` — Codex 向けブートシーケンス（上書き）
- `CONTRIBUTING.md` — コントリビューションガイド
- `.claudeignore` — Claude 除外設定
- `.claude/addf/CHANGELOG.md` — 変更履歴（`Release.addf.md` は除外規則により対象外）
- `.claude/addf/guides/` — ADDF ガイドドキュメント
- `.claude/addf/knowhow/ADDF/` — ADDF ノウハウ

**マイグレーション対象外（スキップ）:**
- `.claude/addf/Progress.md` — プロジェクト固有の進捗
- `.claude/addf/DashboardComments.json` — プロジェクト固有のアンカーコメント（内容は保持。
  ただし**ファイル自体が存在しない場合は `{"comments": []}` で生成する** — ブートシーケンス
  1.7 が参照する新設ファイルのため、既存導入プロジェクトのアップグレードではここで補完する。
  `generate-dashboard.py` 実行時にも自動生成されるが、ダッシュボードを使わないプロジェクトは
  その経路を通らない）
- `.claude/addf/Feedback.md` — プロジェクト固有の記録
- `.claude/addf/Progresses/` — 完了タスクアーカイブ
- `.claude/commands/*.exp.md` — ローカル経験ファイル
- `.claude/settings.local.json` — ローカル設定
- `.claude/addf/lock.json` — 自身（最後に更新）
- `CLAUDE.repo.md`, `CLAUDE.local.md` — プロジェクト固有設定
- `TODO.md`, `.claude/addf/plans/` — プロジェクトのタスク管理
- `.claude/addf/knowhow/*.md`（ADDF/ 以外） — プロジェクトのノウハウ
- `README.md`, `README.en.md` — プロジェクトの説明
- `.gitignore` — プロジェクトの除外設定。ただし ADDF マーカーブロック（`# --- ADDF Framework` 〜 `# --- /ADDF Framework`）**のみ**はステップ 14.6 でクローン元の同ブロックによる置換を提案する。ブロック外に変更がある場合は従来どおり手動マージを案内

7.5. **旧配布 `*.addf.md` の残留検出**（「7.5」は後続の番号参照を壊さないための枝番）:
旧バージョンの配布でダウンストリームに残っている `*.addf.md` を検出する:
```bash
find . -name '*.addf.md' -not -path './.git/*'
```
検出されたファイルは ADDF 本体専用の残留物のため、Phase 4 の「削除推奨」カテゴリで削除を提案する
（ADDF 本体で実行された場合は `*.addf.md` が正当に存在するが、そもそも本体では
`/addf-migrate` の前提となる `.claude/addf/lock.json` の向き先が自身であり通常実行しない）

### Phase 4: 変更の確認

8. 変更をカテゴリ別にユーザーに表示する:

```
╔══════════════════════════════════════════╗
║  ADDF Migration Preview                 ║
║  Current: v0.1.0 (ref: v0.1.0)          ║
║  Target:  v0.2.0 (def5678)              ║
╚══════════════════════════════════════════╝

■ 新規追加 (3)
  + .claude/commands/addf-new-skill.md
  + .claude/agents/addf-new-agent.md
  + .claude/addf/knowhow/ADDF/new-pattern.md

■ 更新 (5)
  ~ .claude/commands/addf-lint.md
  ~ .claude/hooks/turn-reminder.sh
  ~ .claude/addf/templates/ProgressTemplate.md
  ~ CLAUDE.md
  ~ CONTRIBUTING.md

■ 削除 (1)
  - .claude/commands/addf-deprecated.md

■ 削除推奨（旧配布残留ファイル） (2)
  - .claude/addf/templates/ProgressTemplate.addf.md
  - .claude/addf/knowhow/INDEX.addf.md

■ 要手動マージ (1)
  ! .gitignore (変更あり — 手動確認推奨)

■ スキップ (対象外)
  ○ .claude/addf/Progress.md, .claude/addf/Feedback.md, *.exp.md ...
```

9. 最新版の `.claude/addf/CHANGELOG.md` から、現在のバージョンからターゲットバージョンまでのエントリを抽出して表示する:
    ```
    ■ Changelog (v0.1.0 → v0.2.0)
      [0.2.0] - 2026-04-15
        追加: /addf-init スキル
        変更: CLAUDE.md ブートシーケンス改善
      [0.1.1] - 2026-04-01
        修正: addf-lint の INDEX 整合性チェック
    ```

10. ユーザーに確認を求める: 「このマイグレーションを適用しますか？」 <!-- human-judgment -->

### Phase 5: 適用

11. **`settings.json` のマージ**:
    - 最新版の `settings.json` を読む
    - 現在の `settings.json` を読む
    - ADDF 由来のエントリ（hooks、addf 関連権限）を最新版で更新する
    - ダウンストリームが独自に追加したエントリは保持する
    - マージ結果をユーザーに表示して確認を求める <!-- human-judgment -->

12. **スキル・エージェント・テンプレートの適用**:
    - ADDF 側を優先して上書きする
    - `addf-` プレフィックスのファイルのみ対象（プロジェクト固有のスキルは保護）
    - スキルのリネームが含まれる場合（旧名が削除され新名が追加される）、対応する `.exp.md` が存在すれば手動リネームを案内する:
      ```
      ! .claude/commands/addf-dev-loop.exp.md
        → .claude/commands/addf-dev.exp.md にリネームを推奨（経験を引き継ぐため）
      ```

13. **CLAUDE.md のマージ**:
    - ADDF テンプレート部分（ブートシーケンス等）を更新する
    - プロジェクト固有の追記部分は保持する
    - 自動マージが困難な場合は diff を表示して手動マージを案内する

14. **その他のファイル**:
    - hooks、addfTools、templates、tests、optional、guides は上書き。ただし**上書きは ADDF
      由来ファイルのみ** — ADDF のファイルリスト（クローン側の同ディレクトリ内容）に
      存在しないファイルはプロジェクト独自ファイルの可能性があるため削除・上書きしない
      （Phase 2.5 のディレクトリ丸ごと移動で独自ファイルが `.claude/addf/` に混在した場合の保護）
    - .claude/addf/knowhow/ADDF/ は上書き（ADDF 由来のノウハウのみ）

14.5. **オプショナルスキルの同期**（「14.5」は後続の番号参照を壊さないための枝番）:
    `.claude/addf/optional/` に変更（追加・更新・リネーム）が含まれる場合、有効化コピーを追従させる:
    ```bash
    uv run --python 3.11 .claude/addf/addfTools/sync-optional-skills.py apply
    uv run --python 3.11 .claude/addf/addfTools/sync-ccchain.py apply
    ```
    uv が無い環境では `python3` で直接実行する（Python 3.11+ が必要。旧い Python では ERROR 案内が出る）。
    `addf-Behavior.toml` の `[gui-test] enable` / `[ccchain] enable` にそれぞれ従って配置/撤去される。
    改変された有効化コピー（GUI スキル）は削除・上書きされず WARNING になるため、表示に従って
    原本へ取り込んでから再実行する。`.ccchain.conf` はプロジェクトが自由にチューニングする前提の
    ため、原本との差分があっても上書きされない（sync-optional-skills.py と異なる挙動）

14.6. **`.gitignore` の ADDF マーカーブロックの更新**（「14.6」は後続の番号参照を壊さないための枝番）:
    `.gitignore` のうち ADDF マーカーブロック（`# --- ADDF Framework (do not remove) ---` 行〜
    `# --- /ADDF Framework ---` 行）**のみ**、クローン元の同ブロックで置換を提案する。
    **ブロック外のプロジェクト固有記述には触れない** — ブロック外に差分がある場合は従来どおり
    手動マージを案内する。

    **置換前の必須検査**: 終了マーカーが欠落・重複していると範囲指定が EOF まで飲み込み、
    ブロック外のプロジェクト固有記述（秘密情報の除外設定を含みうる）を破壊する。以下を
    **すべて**満たすことを確認し、1つでも満たさなければ**置換せず手動マージへフォールバックする**:
    ```bash
    # (1) 開始マーカーがちょうど1つ（出力が 1 でなければ中止）
    grep -c '^# --- ADDF Framework (do not remove) ---$' .gitignore
    # (2) 終了マーカーがちょうど1つ（出力が 1 でなければ中止）
    grep -c '^# --- /ADDF Framework ---$' .gitignore
    # (3) 開始マーカーの行番号 < 終了マーカーの行番号（逆順なら中止）
    grep -n -e '^# --- ADDF Framework (do not remove) ---$' -e '^# --- /ADDF Framework ---$' .gitignore
    ```
    検査を通過したら、双方のブロックを抽出して差分を確認する（差分がなければこのステップはスキップ。
    範囲指定はマーカー行の**全文一致**で行う — 前方一致では類似行を誤って拾いうる）:
    ```bash
    sed -n '/^# --- ADDF Framework (do not remove) ---$/,/^# --- \/ADDF Framework ---$/p' .gitignore > <tmp-dir>/gitignore-block-current
    sed -n '/^# --- ADDF Framework (do not remove) ---$/,/^# --- \/ADDF Framework ---$/p' <tmp-dir>/addf-latest/.gitignore > <tmp-dir>/gitignore-block-latest
    diff -u <tmp-dir>/gitignore-block-current <tmp-dir>/gitignore-block-latest
    ```
    差分があればユーザーに提示し、承認を得てから現在の `.gitignore` のブロック部分を最新版の
    ブロックで置換する。**ブロック内にダウンストリーム独自の追記があった場合、その行は diff に
    「消える行」として現れる — 消える行が本当に ADDF 由来か必ず目視確認し、独自追記が含まれる
    場合はブロック外への退避を案内する**（`.gitignore` にマーカーブロック自体が無い場合は
    追記を提案する） <!-- human-judgment -->

### Phase 6: 完了

15. `.claude/addf/lock.json` を更新する（旧形式の `commit` フィールドがあれば `ref` に置き換える）:
    ```json
    {
      "version": "<new-version>",
      "ref": "v<new-version>",
      "updated_at": "<today>",
      "repository": "<repository-url>"
    }
    ```
    ターゲットがタグではなくコミットハッシュ指定だった場合は、`ref` にそのハッシュを記録する

16. 一時ディレクトリを削除する:
    ```bash
    rm -rf <tmp-dir>
    ```

16.5. **バージョン差分連動のワンショット手順**（「16.5」は後続の番号参照を壊さないための枝番）:
    Phase 4 の差分プレビューで「新規追加」に `.claude/commands/addf-plan-audit.md` が
    含まれていた場合（= 本スキルを初めて含むバージョンを跨いだ更新）、マイグレーション
    完了後に `/addf-plan-audit` を1回実行し、過去 Plan の「完了扱いだが未完了タスクが
    残っている計画」を掘り起こす。手順の実体はスキル本体を参照する（ここには
    埋め込まない — 二重実装＝同期ペアの温床を避ける）。差分にスキルが現れたときだけ
    案内されるため「マイグレーションのたびに実施」にはならない。ただし一回きりの
    厳密な保証ではない — ローカル削除等で本スキルが再度「新規追加」に現れた場合は
    再案内される。実施済みならその旨を答えてスキップしてよい。検出結果への処置は
    オーナー判断 <!-- human-judgment -->

17. 完了レポートを表示する:
    ```
    ✓ ADDF マイグレーション完了
      v0.1.0 → v0.2.0 (ref: v0.2.0)
      適用: 新規 3, 更新 5, 削除 1
      手動確認: .gitignore

    次のステップ:
    1. 変更内容を確認してください (git diff)
    2. 問題なければコミットしてください
    3. 手動マージが必要なファイルを確認してください
    4. /addf-lint で整合を確認してください（オプショナルスキル同期はセクション10、
       ccchain 同期はセクション13）
    ```

## Gotchas

<!-- checklist-lint: skip-section（設計判断の解説。チェックリストではない） -->

- **`rm -rf` の権限**: Phase 6 の一時ディレクトリ削除に `rm -rf` を使用する。`settings.json` のテンプレートには破壊的操作を含めない方針のため、この操作で権限確認が発生する。これは意図的な設計であり、ユーザーが一時ディレクトリの削除を明示的に承認する
- **CLAUDE.md のマージ**: CLAUDE.md はダウンストリームが追記している可能性がある。ADDF のテンプレート部分（ブートシーケンス等）のみ更新し、`@CLAUDE.repo.md` 行以降のプロジェクト固有部分は保持する。自動判定が困難な場合（構造が大幅に変更されている等）は diff を表示して手動マージを案内する
- **リポジトリ URL**: `.claude/addf/lock.json` の `repository` フィールドが正確であることが前提。URL が変更された場合は手動で `.claude/addf/lock.json` を更新する必要がある

## エラーケース

<!-- checklist-lint: skip-section（エラー時の対応表。チェックリストではない） -->

- `.claude/addf/lock.json`（旧: `.claude/addf-lock.json`）が存在しない → ADDF 由来ファイルも無ければ「ロックファイルが見つかりません。`/addf-init` でプロジェクトを初期化してください」。ADDF 由来ファイルがあれば部分導入とみなし、初期正規化モードを提案する（「前提条件」参照） <!-- residual-path: allow -->
- ワーキングツリーが汚れている → 中断して案内
- リポジトリのクローンに失敗 → ネットワーク確認を案内
- ロックファイルの `ref` が ADDF リポジトリに存在しない → 浅いクローンを完全クローンに切り替えて再試行。それでも見つからなければ `v<version>` タグにフォールバックする（旧形式 lock の実在しないハッシュ対策）

## 経験の活用
- 実行前に `addf-migrate.exp.md` が存在すれば読み、過去の経験を考慮する
- 実行後、新たな教訓があれば `addf-migrate.exp.md` に追記する
