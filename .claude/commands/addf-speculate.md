---
name: addf-speculate
description: |
  アイドル時（着手可能なタスクがないとき）に、直交概念を git worktree で投機開発する。
  投機は speculative/ ブランチに隔離され、本流には自動マージされない。
  `addf-Behavior.toml` の `[speculation].enable = true` でオプトインした場合のみ動作する。
  /addf-dev がアイドルを検出したときに呼ばれるほか、手動で1サイクル実行してもよい。
user_invocable: true
---

# addf-speculate — アイドル時の worktree 投機開発（1サイクル）

TODO に着手可能なタスクがないとき、黙って止まる代わりに、独立した概念を worktree で投機開発して
オーナーがまとめてレビュー・取捨選択できる状態を作る。

**本書の見取り図**: 手順1〜10 が毎サイクルのメインフロー、それ以降のセクション
（clean サブコマンド・昇格手順・部分昇格と持ち越し・深化ブランチ）はイベント発生時に参照する付随手順。
手順1 には枝番のサブステップがある（1.5 モード確認・1.7 再構築と掃除・1.8 大改造の窓検出）。

## 手順

### 1. 発動ガード

```bash
uv run --python 3.11 .claude/addf/addfTools/speculate-guard.py
```

uv が無い環境では `python3` で直接実行する（Python 3.11+ が必要。旧い Python では tomllib 欠如の ERROR となり投機は開始できない — フェイルセーフ）。

- `enable=false`（exit 0）→ **何もせず終了**し、「投機は無効（オプトインは addf-Behavior.toml の
  `[speculation].enable`）」と報告する
- exit 1（型不正等の ERROR）→ 投機せず、エラー内容をオーナーに報告する
- exit 2（上限到達 WARNING）→ 新規投機はせず、`.claude/addf/Worktrees.md` に「上限で待機」を記録して終了する
- exit 0 かつ `enable=true` → 次へ（`slots` が今回起こせる worktree の残り枠）

### 1.5. モード確認（interactive のみ）

`CLAUDE.local.md` の `# ADDF モード`（`/addf-mode` が管理）を確認し、responsiveness が
`interactive` の場合は**投機開始前にオーナーへ一言確認する**（オーナーが目の前にいるため）。
`relaxed` / `unattended`（またはモード未設定）は確認なしで開始してよい。

### 1.7. 再構築と掃除（サイクル冒頭）

git を真実源として、`.claude/addf/Worktrees.md`（git から再構築可能なビュー）との整合を取る:

```bash
python3 .claude/addf/addfTools/speculate-reconcile.py
```

（tomllib 不要のためシステム python3 でそのまま動く。`rm -rf` された stale worktree の
`git worktree prune` も内部で実行される）

出力（key=value）と Worktrees.md を突合する。キーごとの見方:

| 出力キー | 見方と Worktrees.md への反映 |
|---|---|
| `branch=<b> worktree=… origin=… merged_hint=…` | speculative ブランチごとの機械的事実。表に行が無ければ**復元**（下記）。行があるのに実体が無ければ「放棄（実体なし）」等へ更新 |
| `speculative_worktree=<branch>:<path>` | 生きている投機 worktree。表のパス列と突合し、ずれていれば表を実体に合わせる |
| `integration_past=…` | **2日以上前**の integration（前日分までは日付またぎ対策の猶予で `integration_today=` 側に出る）。`clean` サブコマンドの冒頭で自動削除される |
| `detached_worktree=<path>` | どのブランチにも属さない worktree。どの走査にも乗らず放置すると永久残骸になる — 由来を確認し、不要なら `git worktree remove <path>` で外し、表に該当行があれば「放棄（実体なし）」等へ更新する |

- **git 実体があるのに Worktrees.md に記載がない**（`branch=` 行にあるのに表にない、
  またはファイル自体が失われた）→ **復元**: 状態「要再検証」で行を追加する。対象概念は
  ブランチ名 `speculative/<concept>` から推定し、最終更新は再構築時刻とする
  （テスト通過/失敗は git に残らないため次の Stage 1 で再判定する。再構築はメタデータの
  完全復元ではなく**投機を見失わないこと**の保証）。復元行の状態値は手順5の列挙の
  いずれかを使う（丸括弧は任意の注記 — 例「放棄（実体なし）」）。「対象概念（出典）」列が
  分からなければ「不明（再構築）」でよい
- **Worktrees.md に記載があるのに git 実体がない** → 掃除候補: 状態を「放棄（実体なし）」等に
  更新する（行を silent に消さない）
- `merged_hint=yes` は「main に取り込み済みの可能性」の**ヒント**にすぎない。squash マージは
  履歴が繋がらないためスクリプトでは確定できない — **正規フロー（squash 昇格）で main に
  取り込まれたブランチは恒常的に `merged_hint=no` のまま**になる（壊れているのではなく、
  履歴が繋がらないため検出できないだけ）。確定は Worktrees.md の「昇格済み」記録と
  突き合わせて判断する
- `integration_past=`（2日以上前）の integration ブランチが残っていれば、後述の
  `clean` サブコマンドで掃除する（または掃除をオーナーに案内する）

### 1.8. 大改造の窓検出（one-shot Plan の実施提案）

投機在庫がゼロになった瞬間は、大改造（one-shot Plan — 定義の単一ソースは
`.claude/addf/guides/speculative-development.md`「one-shot（一発通し切り）」）の事前清算条件が
自然に満たされている**窓**である。次の投機を始める**前に**、窓が開いていないかを判定する:

1. **在庫ゼロの判定**: 手順 1.7 の reconcile check の出力で以下の機械シグナルが**すべて**
   成り立つこと（判定はスクリプト出力に一本化する — Worktrees.md の目視列挙はしない）:
   - `speculative_worktree=` 行が1行もなく、`local_speculative=`（空）、かつ
     （`remote=origin` なら）`remote_speculative=`（空）
   - `pending_count=0`（Worktrees.md の Pending 在庫もゼロ）
   - `active_count=0`（Worktrees.md の進行中状態 — 開発中・テスト通過・テスト失敗・衝突・
     統合済み・要再検証・上限で待機 — の行もゼロ。採否判断待ち・持ち越しを含む在庫の全部が
     清算済みであること）
2. **one-shot マーカー付き未着手 Plan の存在確認**:

   ```bash
   # Plan 本文のマーカー行（行頭）を探す（ディレクトリ不在・グロブ不一致に依存しない書き方）
   grep -rl '^execution_style: one-shot' --include='*.md' .claude/addf/plans .claude/addf/plans-add 2>/dev/null
   # TODO の状態注記（未着手 × one-shot）からも拾う（マーカー導入前の既存 Plan 対応）
   grep -hE '未着手.*one-shot|one-shot.*未着手' TODO.md .claude/addf/plans-add/TODO.addf.md 2>/dev/null
   ```

   grep のヒットは**候補**にすぎない（TODO の状態注記は転記ミス・文言の偶然一致で
   偽陽性になりうる）。候補ごとに以下を確認して初めて確定する:
   - ヒット行のバッククォート内の Plan ファイルパスを開き、`execution_style: one-shot` 行
     （行頭）が実在することを確認する — 実在して初めて one-shot Plan と確定する
     （1本目の grep で Plan 本文から直接ヒットした場合はこの確認を兼ねる）
   - 該当 Plan の TODO 上の状態が「未着手」であることを確認する
3. 1・2 の両方が成り立てば**窓が開いている**。次の投機を始める前にオーナーへ選択を提示する:
   - `interactive`: AskUserQuestion で「今が窓です。<Plan 名> を実施しますか / 投機を続けますか」を聞き、応答を待つ
   - `relaxed` / `unattended`: `.claude/addf/Questions.md` に同じ質問を置き、**応答待ちの間はこの
     サイクルの新規投機を開始しない**（手順2以降に進まず終了する — 投機を再開すると窓が閉じ、
     次の窓がいつ来るか分からなくなるため、窓を保って待つ）。窓保持カウンタは
     セッションをまたいで数え続けるため Questions.md 上に永続化する
     （「サイクル」の単位 = **/addf-speculate の呼び出し1回**）。読み書きのプロトコル:
     1. まず Questions.md を grep し、**同一 Plan 名**の未回答の窓エントリを探す
     2. あれば、そのエントリの「窓保持カウント: N」行を読み取り、N+1 に**同一エントリを
        書き換える**（新規エントリを増やさない — 窓1つにつきエントリは常に1つ）
     3. 無ければ「窓保持カウント: 1」行を含む窓エントリを新規作成する
     4. 書き換え後の N が **3 以上**なら窓の保持を解除して投機を再開してよい（自走を
        無期限に止めない）。再開したことと理由を Dashboard（unattended 時。無ければ
        Progress.md の日記）に記録する。Questions.md のエントリは**未回答のまま残す**
        （窓は閉じても質問自体は有効 — オーナーの Answer で改めて実施判断できる）
     5. 「窓保持カウント」行が無い・数値としてパース不能なら、安全側 = N=1 として
        行を書き直す（保持を最初から数え直す — 壊れたカウントで早期解除しない）
4. **one-shot Plan の実施は常にオーナーの明示応答が起点**（このセッションでの直接指示・
   AskUserQuestion への回答・Questions.md の Answer のいずれか）。窓の検出は提案までであり、
   **無応答・経過時間を承認とみなして自動着手することを禁止する**
   <!-- human-judgment: one-shot Plan の実施判断はオーナーのみが行う。エージェントは窓の検出と提案まで -->

### 2. 投機対象の選定

選定元の優先順位:

1. 既存の計画ファイルに記録済みの軽微な残課題（Low/Info 等。分解済み・独立性が高く・低リスク）
2. `.claude/addf/Questions.md` の未回答質問の最有力解釈による投機
3. オーナー常設リクエスト（TODO 末尾等）から導出できる独立作業

上記に加え、**採否判断待ちの有望な投機の深化**（子投機）も選定対象にできる
（親が integration 検証（手順7 Stage 2）を通過済みであることが最低条件。詳細は後述）。
判断の目安・命名・制約は後述「深化ブランチ（投機の系譜）」を参照。

ルール:

- **選定禁止**: オーナー指示待ちと明示された項目は投機対象にしない。**新規概念の発明は最終手段**
- **直交性の基準は「衝突ゼロ」ではなく「衝突してもエージェントが悩まず解決できる粒度か」**。
  触るファイル集合の重なりは目安であり、自明に解決できる衝突（独立セクションへの追記同士など）なら
  ナーバスにならず投機してよい。解決に悩むレベルの衝突が予想される組み合わせだけ避ける

#### 投機適性の判定（除外基準）

候補として浮かんだ概念ごとに、直交性に加えて「投機に向くか」を判定する:

> **変更ルート判断との適用順序**: 本節（投機適性3区分）は「speculate 方式を選んだ後に投機で
> できるか」を見る軸。その手前で「そもそも speculate 方式を選ぶべきか（dev 直行 or オーナー
> 問い合わせ or speculate）」を変更の性質で判断する軸がある — 詳細は
> [`.claude/addf/guides/speculative-development.md`](../addf/guides/speculative-development.md)
> 「変更ルート判断」節。GUI 変更や「見せないと判断できないもの」は speculate 方式を選び、
> 続いて本節の適性判定にかける。従来のアイドル時投機に加えて**判断待ち案件の隔離実行**の
> 用途で speculative/ ブランチを使う場合も、選定はここに合流する。

| 区分 | 特徴 | 例 |
|---|---|---|
| 投機向き | 直交・局所的・失敗を捨てられる・本流と衝突しにくい | 注記追加、独立スキルの試作、lint 1本 |
| 投機不向き | 全域に触れる・参照の一貫性が必要・並走ブランチを全滅させる | ディレクトリ構成の全面再編、一括リネーム、テンプレート同期ペアの変更 |
| 投機禁止 | 不可逆・オーナー判断が本質 | リリース、削除系、外部公開 |

- 判定は**特徴ベース**で行い、数値スコアの固定式にしない（直交性の見積もりと同様、
  最終判断は人間とタスクとシチュエーションに応じてケースバイケースでよい —
  CLAUDE.md「迷ったときの作法（7割共有原則）」の思想と整合）
- **迷ったら不向き側（Plan 化フォールバック）に倒す**のをデフォルトとする
  （投機は「失敗を捨てられること」が前提 — 区分に迷うこと自体が捨てられなさのシグナル）
- **判定理由を1行残す**: 投機する概念は `.claude/addf/Worktrees.md` の表の下に
  `> 適性判定: YYYY-MM-DD <concept> — 向き（<根拠にした特徴>）` を追記する
  （unattended で Dashboard を書く場合は「気になった点」への記載でもよい）。
  「不向き/禁止」と判定した概念は、下記フォールバックの記録がこの1行を兼ねる

#### 不適合（不向き/禁止）のフォールバック — 捨てずに Plan 化する

「不向き/禁止」に該当した概念は投機しない。ただし**概念そのものは捨てず、正規ルート
（/addf-dev の通常タスク）へ流す**:

1. Plan 草案を `.claude/addf/plans/`（ADDF 本体では `.claude/addf/plans-add/`）に起こし、TODO に登録する
   （書式: `.claude/addf/templates/PlanTemplate.md`。詰め切れなければ検討スタブ variant でよい）
2. 大改造級（ディレクトリ構成の全面再編など全域に触れるもの）は、Plan の実装状況ヘッダ直後に行頭で
   `execution_style: one-shot` マーカーを付けて起案する（一発通し切り — 意味と実施様式の
   単一ソースは `.claude/addf/guides/speculative-development.md`「one-shot」、書き方は PlanTemplate 参照）。
   TODO の状態注記にも「one-shot」を併記する（手順 1.8 の窓検出が TODO からも拾えるように）
3. **silent に捨てない**: 「投機不適合のため Plan 化した（概念名・区分・理由の一行）」を
   Dashboard「気になった点」（unattended 時）と Progress.md の日記に記録する

### 委譲時の禁止事項

`Agent` tool でサブエージェント（worktree 実装等）に委譲するときは、共通禁止事項テンプレート [`@.claude/addf/templates/DelegationRules.md`](../addf/templates/DelegationRules.md) をプロンプトに含める。特に **Progress.md の境界**（タスク欄不可侵・運用ルール節は同期対象として更新可）は本ルールで単一ソース化されている — 委譲側で個別に指定しない。

### 3. worktree の起動

対象概念ごとに（`slots` の範囲内で）:

```bash
git worktree add ../<repo名>-spec-<concept> -b speculative/<concept>
cp -r .claude/. ../<repo名>-spec-<concept>/.claude/
# .venv / node_modules / __pycache__ 等は relocatable でないため除外する（コピー先で再構築）
find ../<repo名>-spec-<concept>/.claude \( -name .venv -o -name venv -o -name node_modules -o -name __pycache__ \) \( -type d -o -type l \) -prune -exec rm -rf {} +
# git 追跡下のファイルまで消えた場合（依存をあえてコミットしている構成）は復元する
git -C ../<repo名>-spec-<concept> checkout -- .claude 2>/dev/null || true
```

- **`.claude` の複製は必須**。`.exp.md`（経験ファイル）等の .gitignore 対象ファイルは worktree に
  自動複製されないため、複製を欠くと投機側が経験・設定を失った状態で作業することになる
- **コピー元は必ず `.claude/.`（末尾 `/.`）と書くこと**。worktree 側には git 管理下の `.claude/` が
  既に存在するため、`cp -r .claude <dst>/.claude` と書くと既存ディレクトリの**中に**入れ子
  （`<dst>/.claude/.claude/`）を作るだけでマージされず、複製が成功したように見えて失敗する
- **`.venv` / `venv` / `node_modules` / `__pycache__` は複製後に必ず除去すること**（上記の `find`。
  シンボリックリンクの場合も対象）。venv は作成時の絶対パスを埋め込むため relocatable でなく、
  **コピーしても壊れている**（MCP サーバー等の依存を `.claude` 配下に持つ構成では毎サイクル必発 —
  Issue #18）。壊れたコピーを残すより、除外して worktree 側で再構築する方が安全
- **`find` の後の `git checkout -- .claude` を省略しないこと**。除去は名前ベースのため、依存を
  あえて git 追跡下にコミットしている構成では追跡ファイルまで消える — checkout が worktree の
  ブランチから復元する（該当ファイルが無ければ何もしない）
- worktree 隔離下は判断閾値を1段下げてよい（失敗を捨てられるため。CLAUDE.md「迷ったときの作法」）

### 4. 実装と Stage 1

`.claude` 配下に MCP サーバー等の依存を持つ構成では、**Stage 1 の前に必ず再構築**
（`uv sync` / `bun install` 等）を実行する（手順3の複製は venv 等を除外している。
マニフェストは git 管理下または複製対象のため worktree 側に届いている）。

各 worktree 内で対象概念を実装し、**Stage 1（ビルド・Lint・テスト）を worktree 内で実行**する。

- テスト通過 → 状態「テスト通過」
- テスト失敗 → 一度は原因分析・修正を試み、それでも失敗するなら状態「テスト失敗」で打ち切る
  （投機は使い捨て。深追いしない）

### 5. Worktrees.md への記録

`.claude/addf/Worktrees.md`（.gitignore 対象の実行時状態ファイル）に全投機を記録する。
**打ち切った投機も silent に消さず記録する**。

書式:

```markdown
# Worktrees（投機の進行状態）

| worktree パス | ブランチ | 対象概念（出典） | 状態 | 最終更新 |
|---|---|---|---|---|
| ../repo-spec-foo | speculative/foo | <出典と一行説明> | テスト通過 | YYYY-MM-DD HH:MM |
```

状態: `開発中` / `テスト通過` / `テスト失敗` / `衝突` / `統合済み` / `放棄` / `昇格済み` / `上限で待機` / `要再検証` / `Pending`

- 「上限で待機」と「Pending」は似て非なる状態のため混同しないこと:
  - **上限で待機** = **開始前のキュー**。スロット上限で今サイクルは worktree を起こせなかった投機
    （まだ何も作られていない）
  - **Pending** = **持ち越しの保留**。着手済みだが数サイクル直らず「いつかやる」に落としたもの
    （ブランチと PR は既に存在する — 後述「部分昇格と持ち越し」参照）
- 「**採否判断待ち**」は状態値ではなく、「統合済み＋origin push 済みで、オーナーの採否判断を
  待っている」状況の**通称**（Dashboard の見出し等で使う。表の状態列には書かない）
- 深化ブランチ（`speculative/<concept>--deep-<sub>`）は「対象概念（出典）」列に親を明記する
  （例: `深化（親: speculative/<concept>）`）。親の採否に運命連帯するため、親子が表から
  辿れることが清算の前提になる（後述「深化ブランチ（投機の系譜）」参照）

### 6. integration 統合（テスト通過の feature が1件以上あるとき）

テスト通過の feature（今サイクルの新規と、前サイクルから採否判断待ちで繰り越したものの両方）を
1本の integration ブランチに squash 統合し、動作確認を一括する:

```bash
uv run --python 3.11 .claude/addf/addfTools/speculate-integrate.py speculative/<concept1> speculative/<concept2> ...
# uv が無ければ python3 で直接実行（Python 3.11+ が必要）
```

（tomllib 不要のためシステム python3（3.6+）でそのまま動く。uv 不要）

`--base` は省略時、origin の default branch を自動検出する（remote なし・未設定なら NOTE を出して
`main` フォールバック。検出名のローカルブランチが無ければ `origin/<name>` を起点にする）。
スクリプトは `integration/loop-<日付>` ブランチを base から**作り直し**（使い捨て・再生成可能）、
専用 worktree（`../<リポジトリ名>-integration`）の中だけで統合する。メインの作業ツリーには触れない。
なお integration worktree への `.claude` 複製は**不要**（feature worktree と違い実装作業の場ではなく、
Stage 2 の実行主体はメインツリー側のエージェントで、テスト一式も git 管理下にあるため）。

- exit 1（ERROR: base 不在・worktree の置き先が塞がっている・commit フック拒否等）→ 統合を中断し、
  エラー内容をオーナーに報告する（`commit_failed=` は差分の握り潰しを防ぐための ERROR — empty と混同しない）
- exit 0 / 2 → 以下の出力（key=value）を解釈して Worktrees.md へ反映する:

- `integrated=` — 統合成功。状態「統合済み」にして Stage 2 へ
- `conflicted=` — squash 時に衝突した feature（スクリプトが巻き戻し済み）。直交性の基準で判断する:
  - **悩まず解決できる衝突**（独立セクションへの追記同士など）→ `speculative/<concept>` ブランチ側で
    base を取り込んで解消し（昇格対象のブランチが常に自己完結するように、解消は必ず feature 側に置く）、
    スクリプトを再実行する
  - **解決に悩むレベルの衝突** → 状態「衝突」で integration から外し、残りでスクリプトを再実行する
    （integration は作り直しが正道）。silent に捨てず、Dashboard の「気になった点」で報告する
- `missing=` — ブランチが存在しない（Worktrees.md の記載と git 実体のずれ）。記録を突き合わせて訂正する
- `empty=` — base との差分が無い（既に本流へ取り込み済み等）。状態を確認して「昇格済み」等に訂正する

### 7. Stage 2 — integration 一括ゲート

integration worktree の中で一括の動作確認とレビューを行う（コストの大きい Stage 2 を N 回→1回に償却する）:

1. **相互作用テスト**: integration worktree 内でプロジェクトのテスト一式（Stage 1 と同じコマンド）を実行する。
   単体では通過した feature も、組み合わせて壊れることがある
   - 失敗したら原因 feature を特定し（feature を外して再統合すると二分探索できる）、
     該当 feature を状態「衝突」で外して integration を作り直す
2. **一括レビュー**: `addf-code-review-agent` を**ペルソナ並列（視点ずらしレビュー）**で起動する。
   起動前に `.claude/agents/addf-code-review-agent.md` を読み、ペルソナ定義と集約ルールに従うこと。
   レビュー対象は `git diff main...integration/loop-<日付>` の全差分
3. 指摘は **feature 単位に帰属**させて Worktrees.md に記録する。Critical/High は該当 feature の
   worktree で修正して Stage 1 からやり直す（ただし投機は使い捨て — 深追いするより
   状態「テスト失敗」で打ち切ってよい）

レビューまで終えたら integration worktree は削除してよい（`git worktree remove ../<リポジトリ名>-integration`）。
integration **ブランチ**は使い捨てのため origin へ push しない（次サイクルで作り直す）。

### 8. Dashboard への書き分け

unattended 自走（`dashboard_report: true`）では `.claude/addf/Dashboard.md`（書式: `.claude/addf/Dashboard.example.md`）に
結果を書き分ける。基準は「オーナーの採否判断の対象かどうか」:

- **「投機ブランチ（採否判断待ち）」**: integration の動作確認（手順7「Stage 2」）まで通過した feature のみ。
  前サイクルからの判断待ちも繰り越し再掲する
- **「気になった点」**: テスト失敗・衝突・上限待機。採否判断の対象ではないが、知らせる価値のある観察
  （silent に捨てない）

### 9. ブランチの退避（エフェメラル環境対策）

サイクル末に、各 `speculative/<concept>` ブランチを origin へ push する:

```bash
if git remote get-url origin >/dev/null 2>&1; then
  git push -u origin speculative/<concept>
else
  echo "SKIP: remote なし（ローカル環境）"
fi
```

- remote が無い環境では SKIP してよい（欠如 = SKIP）。remote があるのに push が失敗した場合
  （認証・reject・ネットワーク断）は SKIP 扱いにせず、失敗として報告する
- コンテナ実行（Claude Code on the Web 等）ではセッション終了で worktree もローカルブランチも
  失われるため、**push が投機を残す唯一の手段**。省略しないこと
- push したブランチから PR を作成する場合は、本文を `.claude/addf/guides/pr-format.md` の規約に従って書く

### 10. 完了処理

呼び出し元（/addf-dev）の完了処理に合流し、**Progress.md の日記に「投機サイクルを実行した
（対象概念・結果の一行）」を記録してコミットする**。Worktrees.md は gitignore だが、
サイクルが回った事実はこの日記経由でコミット履歴に残る。

cron / `/loop` 等から /addf-dev を**経由せず単独実行**された場合は、Progress.md の日記への記録と
コミットのみ行えばよい（品質検証〜アーカイブを含むフルの完了処理は /addf-dev 経由時に呼び出し元が担う）。
**呼び出し文脈が不明な場合も、日記への記録とコミットは最低限実施する**（サイクルが回った事実を
コミット履歴に残すことが投機の追跡可能性の下限）。

投機の採否はオーナーの判断（Dashboard / PR レビュー等）。**エージェントが speculative/ ブランチを
本流へ自動マージする経路は存在しない**。

## サブコマンド: clean（`/addf-speculate clean`）

**掃除の原則: integration の過去分は常に自動削除・speculative ブランチは明示指定制。**
`clean` は実行の冒頭で、**2日以上前**の `integration/loop-*` ブランチとその worktree を
自動削除する（当日・前日分は日付またぎ対策の猶予で残る。integration は使い捨てのため
記録との突合は不要。残したい場合のみ `--keep-integrations` でオプトアウトする）。

オーナーが今すぐ片付けたいとき、またはサイクル冒頭（手順 1.7「再構築と掃除」）で
`integration_past=` を検出したときの明示的な掃除手順:

1. 状態を走査する:

   ```bash
   python3 .claude/addf/addfTools/speculate-reconcile.py
   ```

2. `.claude/addf/Worktrees.md` で状態が「昇格済み」「放棄」のブランチを確認する
   （スクリプトの `merged_hint` はヒントにすぎない — 削除の根拠は Worktrees.md の記録に置く）
3. 確定済みブランチを明示指定して削除する:

   ```bash
   python3 .claude/addf/addfTools/speculate-reconcile.py clean --delete speculative/<concept> [--delete ...]
   ```

   - `--delete` は**削除専用**であり、main への統合（昇格）は一切しない（昇格は後述の
     「昇格手順」で行う — オーナー承認必須）
   - スクリプトは削除前に `.claude/addf/Worktrees.md` の記録と突合し、対象の状態が「昇格済み」
     「放棄」でなければ**何も消さずに ERROR で中断する**（記録なし・ファイルなしも同様。
     不可逆な削除だけは記録との突合をスクリプトが強制する — 「検出=スクリプト/解釈=エージェント」
     の意図的な例外。突合を承知でスキップするなら `--force-delete`）
   - 指定ブランチは worktree（あれば）→ ローカルブランチ → origin 側（remote があれば。
     無ければ SKIP）の順で削除される。**ローカル側の削除が完了しなかった場合、origin 側には
     触れない**（`kept=origin:<branch>` で報告される。退避先の origin が最後まで残るように、
     ローカルの失敗を解消してから再実行する）
   - **未コミット変更のある worktree は既定で削除拒否**（`kept=` + WARNING。`--delete` 対象・
     過去 integration とも）。破棄してよいと確認できたときのみ `--force-delete` を付ける
   - **判断待ちブランチは保護される**: `--delete` 指定のない speculative ブランチは消えない
     （`kept=` で報告される）。ブランチを残して worktree ディレクトリだけ外したいときは
     `--prune-worktrees` を付ける（未コミット変更のある worktree は外さず WARNING になる）。
     ただし `--prune-worktrees` は指定外の**全て**の speculative worktree を一括で外す —
     1件だけ外したいときは `git worktree remove <パス>` を使う
4. `removed=` / `kept=` の出力を Worktrees.md に反映する: 削除したブランチの行を落とす
   （履歴を残したい場合は状態「掃除済み」の注記に更新する）。exit 2 なら内容をオーナーに
   報告する — `WARNING:` は実害系（削除失敗・dirty 破棄・origin 保護）、`NOTE:` は
   指定ミス系（speculative/ 以外の指定・指定ブランチ不在）

## 昇格手順（オーナー承認必須）

`speculative/<concept>` を main へ取り込む手順。**昇格 = `speculative/<concept>` → `main`**
（integration は検証の場であって昇格の経路に入らない — 定義とライフサイクル図は
`.claude/addf/guides/speculative-development.md` を参照）。
**エージェントが自動昇格する経路は作らない** — この手順は必ずオーナーの明示承認から始まる。

**エージェントは、オーナーの明示的な応答（このセッションでの直接指示、AskUserQuestion への
回答、または GitHub 上での PR マージ）なしに main への取り込み（squash マージの実行）を
してはならない。PR の作成は昇格ではなく提案の一形態である。Dashboard 掲載・PR オープンからの
経過時間や無応答を承認とみなすことを禁止する。**

### 承認チャネル（モード連動）

承認の形は2経路。どちらを基本形にするかはループのモード（responsiveness — `/addf-mode`）に従う:

- `interactive`: **セッション内のプロンプト指示**が自然（オーナーが目の前にいるため。
  AskUserQuestion での確認も可）→ 経路A
- `relaxed` / `unattended`: **PR を作って待つ**のが基本形 → 経路B。オーナーは GitHub 上の
  マージでも、次セッションのプロンプト指示でもよい（どちらも明示応答として等価）

### 経路A: プロンプト指示（ローカル squash マージ）

（ステップ番号は手順1〜10 との衝突を避けるため `A-1` 形式で振る）

1. **[A-1]** オーナーが Dashboard / Worktrees.md / open PR の採否判断待ち一覧から昇格する feature を選び、承認する
   <!-- human-judgment: 昇格の承認はオーナーのみが行う。エージェントは提案までにとどめる -->
2. **[A-2]** integration で衝突解消が入った feature は、その解消を `speculative/<concept>` ブランチ側に
   反映してから昇格する（昇格対象のブランチが常に自己完結する — integration のコミットは
   検証の場の産物であり、履歴の源にしない）
3. **[A-3]** main 上で squash マージしてコミットする:

   ```bash
   git checkout main
   git merge --squash speculative/<concept>
   git commit   # プロジェクトのコミットログ規約に従って要約を書く
   ```

4. **[A-4]** 昇格後テストとして、プロジェクトの Stage 1（ビルド・Lint・テスト）と同じコマンドを main 上で
   実行する。失敗したら squash コミットを revert し、原因を feature ブランチ側で直してから
   再昇格する（main に壊れた状態を残さない）
5. **[A-5]** `.claude/addf/Worktrees.md` の該当行を状態「昇格済み」に更新する
6. **[A-6]** **深化ブランチがある場合はここで順序制約を守る**: `clean --delete` の**前に**子の
   繰り上げ rebase を済ませるか、親の分岐点 SHA を Worktrees.md の子の行に記録する
   （「深化ブランチ」節の「繰り上げ rebase」参照 — 親削除後は起点が取得できなくなる）
7. **[A-7]** `/addf-speculate clean`（`clean --delete speculative/<concept>`）で後始末する
   （worktree・ローカルブランチ・origin 側の残骸が消える。スクリプトは A-5 で
   記録した「昇格済み」と突合してから削除する — 記録の更新を飛ばすと ERROR になる）
8. **[A-8]** 持ち越し中の feature があれば状態「要再検証」に落とす（「部分昇格と持ち越し」参照）

### 経路B: PR 経路（GitHub マージ）

エージェントの仕事は **PR を作成して提示するまで**。**マージはオーナーが GitHub 上で行う、
もしくはオーナーからのプロンプト指示で行う**（プロンプト指示された場合は経路A の A-2 以降に
合流する）。

**前提ゲート**: PR を作成できるのは **Stage 2（手順7 integration 一括ゲート）を通過した
feature のみ**（手順8 の「投機ブランチ（採否判断待ち）」Dashboard 掲載条件と同じ）。
未通過の feature から PR を作らない。

（ステップ番号は `B-1` 形式で振る）

1. **[B-1]** 手順9 で push 済みの `speculative/<concept>` から PR を作成する:

   ```bash
   gh pr create --base main --head speculative/<concept> --body-file <本文ファイル>
   ```

   PR 本文は `.claude/addf/guides/pr-format.md` の規約に従い、投機 PR では加えて以下を記載する:
   - **投機の出典**（Worktrees.md「対象概念（出典）」の内容 — どこから生まれた投機か）
   - **integration 検証の結果**（Stage 2 の通過状況・レビュー指摘と対応の要約）
   - 深化ブランチがある場合は「**深化ブランチあり**: `speculative/<concept>--deep-<sub>`」の注記
     （親を蹴ると深化も消えることが、採否判断の材料としてオーナーに見える）
2. **[B-2]** `.claude/addf/Worktrees.md` の該当行に PR 番号を注記する（状態は変えない — PR 作成は
   提案であって昇格ではない）。記載先は「**対象概念（出典）**」列 — 深化の親記録と同じ方式
   （例: `…（PR #21）`）
3. **[B-3]** オーナーのマージを**待つ**（無応答を承認とみなさない — 冒頭の禁止事項）

#### PR マージ後の後始末

squash マージは履歴が繋がらないため、reconcile check（手順 1.7）の `merged_hint` は
**恒常的に `no` のまま**になる（既知の制約 — 壊れているのではなく検出できないだけ）。
マージの確定は次のトリガーで行う:

- **トリガー**: 次セッションのブートシーケンス、または reconcile check（手順 1.7）と
  同じタイミングで Worktrees.md を確認し、PR 番号注記のある行を見たとき
  （スクリプトは PR 番号を parse しない — 確認するのはエージェント自身）、
  `gh pr view <番号> --json state,mergedAt` で MERGED を確認して確定する
  （`merged_hint=yes` が出た場合もヒントにすぎない — 確定は PR 状態と Worktrees.md の記録で行う）

確定後の後始末（ステップ番号は `後-1` 形式で振る）:

1. **[後-1]** ローカル main を追随させる（`git checkout main && git pull`）。squash マージのため
   ローカルの `speculative/<concept>` は main と履歴が繋がらないまま残るが、それが正常
   （このずれを理由にブランチを作り直したり main へ再マージしたりしない）
2. **[後-2]** `.claude/addf/Worktrees.md` の該当行を状態「昇格済み」に更新する
3. **[後-3]** **深化ブランチがある場合**: 後-4 の `clean --delete` の**前に**、子の繰り上げ
   rebase（「深化ブランチ」節の「繰り上げ rebase」）を済ませる。すぐに rebase しない場合は、
   親の分岐点 SHA（`git merge-base speculative/<concept> speculative/<concept>--deep-<sub>` の
   結果）を Worktrees.md の**子の行に記録**してから次へ進む（親削除後は merge-base が取れず、
   繰り上げ rebase の起点が失われる）
4. **[後-4]** `clean --delete speculative/<concept>` で残骸（worktree・ローカルブランチ）を消す。
   GitHub の「マージ後ブランチ削除」で origin 側が既に消えていても問題ない —
   削除の根拠は origin の有無ではなく **Worktrees.md の「昇格済み」記載との突合**であり、
   origin に無ければ origin 側の削除が対象外になるだけでローカル残骸は消える
   （worktree・ローカル・origin のどこにも実体が無ければ NOTE で報告される）
5. **[後-5]** 持ち越し中の feature があれば状態「要再検証」に落とす（次の「部分昇格と持ち越し」）

## 部分昇格と持ち越し

N 本の投機のうち通った分だけ先に本流へ入れ、残りは次サイクルで直す。integration ごと
all-or-nothing にマージしない — **1本の不備が他を人質に取らない**。

- **要再検証**: 本流に昇格があったら（部分昇格・通常タスクのマージとも）、持ち越し中の
  feature は状態「要再検証」に落とす（base が動いたため過去の検証結果が古い）
- **次サイクルの再検証**: 新しい main に rebase し、`git push --force-with-lease` で
  speculative ブランチを更新してから Stage 1 から再検証する。open PR がある場合は
  **同じ PR がそのまま更新され**、持ち越しの文脈（レビューコメント等）が保たれる

### 滞留の出口 — Pending（いつかやる）

数サイクル経っても直らない持ち越し feature は、「放棄」ではなく状態「**Pending**」に落とす:

- Pending はアクティブな投機スロットを**占有しない**（スロットの実体は speculative worktree 数 —
  speculate-guard の計上。worktree を外せば計上から外れ、新しい投機を妨げない）
- Pending の worktree は削除してよい（**ブランチと PR は残す** — 再開時に worktree を作り直す）。
  **Pending 1件だけ**外すなら `git worktree remove <パス>` を使う。`clean --prune-worktrees` は
  `--delete` 指定外の**全て**の speculative worktree を dirty 保護つきで一括で外す
  （**Pending 専用ではない** — 開発中・テスト通過の worktree も外れる。未コミット変更のあるものは
  git が保護する）
- Pending 在庫は **5本まで**を許容する。6本以上になったら Dashboard（unattended 時）/
  `.claude/addf/Questions.md` でオーナーに整理（再開 or 放棄）を提案する。件数は reconcile check
  （手順 1.7）の `pending_count=` が機械的に報告する（Worktrees.md の状態「Pending」行数 —
  手順 1.8 の在庫ゼロ判定もこの値を参照する）

## 深化ブランチ（投機の系譜）

採否判断待ちの投機が有望なとき、その成果を前提にさらに発展させる**子投機（深化ブランチ）**を
作ってよい（親の採否確定を待たずに、有望な方向を先行探索する経路）。

- **命名**: 親 `speculative/<concept>` に対し **`speculative/<concept>--deep-<sub>`**。
  区切り `--deep-` で親子を機械的に判別できる（`<concept>` / `<sub>` 自体に `--deep-` を
  含めないこと）
- **起動**: 子は親ブランチを起点に worktree を切る（手順3の `git worktree add` の末尾に
  起点 `speculative/<concept>` を渡す）。例（親 `speculative/foo` から子 `--deep-bar` を切る）:

  ```bash
  git worktree add ../<repo名>-spec-foo--deep-bar -b speculative/foo--deep-bar speculative/foo
  ```

  `.claude` の複製と除外は手順3と同じ。**Stage 1（手順4）も通常投機と同様に実行する**
- **深化を選んでよい目安**（判断が迷わないためのガイド。固定式にしない）:
  1. 親が integration 検証（手順7 Stage 2）を通過している
  2. オーナーの好反応シグナル（PR コメント・Dashboard への反応）がある、または親の成果が
     次の展開の前提として明確に活きる
  3. 未着手の直交概念より深化の期待値が高いと見積もれる
- **系譜の運命連帯**:
  - 親が放棄 → **深化も放棄**（親の前提が消えるため）。**親の行を「放棄」に更新したら、同時に
    子の行も状態「放棄」に更新する**（経路A の A-5 と同粒度の明示アクション。Worktrees.md の
    親子記録で連鎖を追う）
  - 親が昇格 → 深化は新 main に**繰り上げ rebase**（下記）して**独立した投機に繰り上がる**。
    以後は通常の投機として扱う（`git push --force-with-lease` で PR も引き継がれる —
    「部分昇格と持ち越し」と同じ運用）
- **繰り上げ rebase（親が昇格したとき）**: 素の `git rebase main` は使えない — 親は squash
  昇格のため履歴が繋がらず、さらに integration の衝突解消は feature（親）側に反映される
  既存ルールにより、親の最終状態と子の分岐点の乖離は常態であるため、親由来のコミットで
  コンフリクトする。子の実装差分だけを新 main に載せ替える `--onto` を使う:

  ```bash
  # 親の分岐点 SHA を取得する（親ブランチが必要 — 下記の順序制約どおり親の削除前に実行する）
  parent_base=$(git merge-base speculative/<concept> speculative/<concept>--deep-<sub>)
  git rebase --onto main "$parent_base" speculative/<concept>--deep-<sub>
  git push --force-with-lease origin speculative/<concept>--deep-<sub>
  ```

  - コンフリクトしたら、**子の実装差分だけ**を新 main 上に再適用する（親由来の内容は
    main 側＝昇格済みの姿を正とする）。解決に悩むレベルなら深追いせず状態「衝突」で報告する
  - **順序制約**: 深化（子）がいる親を `clean --delete` する**前に**、(1) 子の繰り上げ rebase を
    済ませる、または (2) 親の分岐点 SHA（上記 merge-base の結果）を Worktrees.md の
    **子の行に記録**する。親を先に削除すると merge-base が取れなくなり、`--onto` の起点が
    失われる（経路A の A-6・後始末の 後-3 が同じ制約を指す）
- **制約**:
  - 深化も通常の投機スロットを**1つ消費する**（無料の枠にしない）
  - 深さは**2世代（親＋深化）まで**を目安とする — 親が未採択のうちに孫を作ると清算が複雑化する
  - Worktrees.md に**親子関係を記録**する（手順5の「対象概念（出典）」列 — 例
    `深化（親: speculative/<concept>）`）
  - 親の PR に「**深化ブランチあり**」を注記する（経路B の B-1 — 親を蹴ると深化も
    消えることが採否判断の材料としてオーナーに見える）

## 現バージョンの範囲

このスキルは投機サイクルの全段階を提供する: 発動ガード→再構築と掃除（手順 1.7）→
大改造の窓検出（手順 1.8）→選定（投機適性の判定・不適合の Plan 化フォールバック込み）→
worktree 起動→Stage 1→integration 統合→Stage 2→Dashboard 書き分け→push、および
`clean` サブコマンド・昇格手順（プロンプト指示 / PR の2経路）・部分昇格と持ち越し
（要再検証・Pending）・深化ブランチ。
昇格（`speculative/<concept>` → main）は**常にオーナー承認必須**であり、
エージェントが本流へ自動マージする経路は存在しない。

## 経験の活用

- 実行前に `addf-speculate.exp.md` が存在すれば読み、過去の経験（選定判断・直交性の見積もり精度等）を考慮する
- 実行後、新たな教訓があれば `addf-speculate.exp.md` に追記する
