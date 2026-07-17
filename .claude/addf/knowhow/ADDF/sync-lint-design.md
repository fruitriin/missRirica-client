---
title: 同期 lint の設計 — 検出はツール、解釈と修復はエージェント
created: 2026-06-10
last_verified: 2026-07-14
depends_on:
  - .claude/addf/addfTools/lint-template-sync.py
  - .claude/addf/tests/tools/test-template-sync.sh
  - .claude/addf/tests/tools/test-binary-checksums.sh
  - .claude/addf/addfTools/verify-checksums.sh
  - .claude/commands/addf-init.md
  - .claude/commands/addf-migrate.md
  - .claude/commands/addf-knowhow-index.md
  - .claude/addf/addfTools/sync-optional-skills.py
  - .claude/addf/addfTools/speculate-guard.py
  - .claude/addf/addfTools/lint-toml.py
status: active
---

# 同期 lint の設計 — 検出はツール、解釈と修復はエージェント

> 出典: Plan 0021（addf-lint テンプレート同期チェック）。同期忘れが3度再発した教訓の自動化

## 発見した知見

### 「意思で覚える」が3度敗北したら機械化する

同期が必要なファイルペア（CLAUDE.md ⇔ AGENTS.md 等）の手動同期は、Feedback.md に改善アクションとして記録しても3度再発した。チェック自体をエージェントの注意力（意思）に委ねると「忘れる・読み飛ばす・今回は大丈夫と判断する」という同じ失敗モードを lint の中に持ち込む。役割分担の原則:

- **検出 = 決定的スクリプト**: 忘れない・揺らがない・CI に乗る
- **解釈と修復 = エージェント**: どちらを正として同期するかは文脈判断（通常は新しい側が正だが、誤編集の巻き戻しもありうる）

スクリプトは WARNING に `git log -1 --format=%cs` の最終更新日ヒントを併記し、エージェントの判断材料を渡す。

### 構造比較より「正規化テキスト比較」— 実際のドリフトは内容差分

計画段階では「ステップ番号・見出しの構造対応」の検証を想定していたが、過去3度のドリフト（Plan 0016/0017/0019）は全て**既存ステップ内のサブ項目・文言の差分**であり、番号比較では捕捉できない。採用した方式:

1. 比較対象セクションを抽出（`## 見出し` から次の `## ` または水平線 `---` まで。コードブロック内は除外）
2. 意図的差分を吸収: ホワイトリスト行の除去 + パス正規化（`.addf.md` → `.md` 置換）
3. strip 済み非空行を `Counter` で相互比較（リスト線形検索は重複行を過小報告する）

言語が異なるペア（CLAUDE.md 日本語 ⇔ AGENTS.md 英語）はテキスト比較が不可能なため、そこだけ手順番号列（`1, 1.5, 1.6, 2..5`）の構造比較にフォールバックする。

### addfTools はダウンストリーム配布を前提に「欠如 = SKIP」で設計する

`.claude/addf/addfTools/` はダウンストリームに配布される。ADDF 本体固有ファイル（`ProgressTemplate.addf.md`・`AGENTS.md` 等）をハードコード参照すると、ダウンストリームで必ず ERROR になる。設計ルール:

- ADDF 本体固有ファイルの欠如は **SKIP（exit 0 相当）** として扱う。欠如はドリフトではない
- 両環境に存在するファイルはフォールバックで対応する（例: テンプレートは `.addf.md` 版がなければ無印版を正とする）
- exit code は 3値: `0 = OK / 1 = ERROR / 2 = WARNING のみ`。テストとエージェントが重要度を区別できる

**SKIP の乱用は silent 無効化になる**。SKIP は「環境起因で検査できなかった」の可視化であり、成功の別名ではない。ダウンストリーム実例（Issue #19）: run-all.sh 拡張でランタイム（bun）不在を SKIP=成功扱いにした結果、cron の PATH 落ちで 74 テストが 0 件実行のまま `✓ All automated tests passed` を返す構造になった（レビューで Critical 指摘）。テストが依存する必須ランタイムの不在は SKIP にしない — 実行できなかったことと通ったことを区別する。環境的に実行不能なテスト（macOS 専用バイナリ等）を飛ばす場合も、SKIP を必ず明示出力し件数に計上する（`Results: N passed, N failed, N skipped` — test-tools.sh の非 macOS SKIP が実例。run-all.sh 冒頭の設計ガイドラインにも明文化済み）。

### 「存在≠所有」— ファイルの存在で upstream/downstream を判定しない

「欠如 = SKIP」原則の**逆ケース**。ダウンストリーム実運用初日に3件同時に顕在化した（Plan 0033）:

1. **`.addf.md` は配布によりダウンストリームにも物理存在しうる**。addf-init が `.claude/addf/templates/` を丸ごとコピーしていたため、`ProgressTemplate.addf.md` の存在を「ADDF 本体」のシグナルに使っていたペア1は**全ダウンストリームで誤検知**した。同型の欠陥が addf-knowhow-index の「`INDEX.addf.md` が存在すればそちらを優先」にもあった。存在は所有の証明にならない
2. **配布ファイル名はダウンストリームの同名無関係ファイルと衝突しうる**。実例: Misskey 由来の独自 `AGENTS.md` を持つプロジェクトで、ペア3が「ブートシーケンス見出しなし」を誤報した。ファイル名が一致しても中身が ADDF 由来とは限らない
3. **所有判定は明示シグナルで行う**: 一次根拠 = `CLAUDE.repo.md` のプロジェクト種別宣言（「ADDF 開発プロジェクト」/「ADDF 利用プロジェクト」。@メンション1段を解決し、コードブロック内の書き換え例は除外）、フォールバック = `.claude/addf/lock.json` の存在（addf-init / addf-migrate と同じアンカー）。ADDF 本体自身も lock を持つため、**lock 単独では本体をダウンストリームと誤判定する** — 宣言を先に見る順序が重要

根治策はシグナル判定と併せて**発生源を断つ**こと: addf-init / addf-migrate の配布対象から `*.addf.md` を除外し、ダウンストリームに `.addf.md` を物理的に置かない（分離規約）。判定ロジックの防御と配布規約の根治はセットで行う — 片方だけでは旧バージョン配布済みの環境や持ち込みファイルで再発する。

補足2点（Plan 0033 ペルソナ並列レビューで追加）:

- **ペア4（development-process.md）は同型リスクを持つが据え置き**。配布された `.claude/addf/guides/development-process.md` をダウンストリームが独自にリライトすれば、ペア3 と同じ「同名無関係ファイル」誤報になりうる。ただし実運用でのリライト報告がないため分岐を先回りしない — 報告が出たら pair3 と同じ repo_kind 分岐に入れる
- **種別宣言の判定仕様**: 宣言マッチは太字マーカー込みの厳密一致（`**ADDF 開発プロジェクト**` / `**ADDF 利用プロジェクト**`）で、地の文の言及（否定文・沿革の記述）に誤爆しない。upstream/downstream の**両方**がヒットしたら判定不能（安全側）として lock フォールバックへ委ねる — 無条件の upstream 優先はしない。コードフェンス（``` / ~~~）内は除外されるが、**インラインコードスパン（単一バッククオート）内の言及は除外されない** — 宣言文言を CLAUDE.repo.md 内で引用説明する際はフェンスを使う運用。判定不能（宣言なし・lock なし = 旧配布ダウンストリームの可能性）は upstream と同一視せず、ペア1/ペア3 の ERROR を WARNING に格下げして種別宣言/lock の整備を促す。downstream / 判定不能で検査を切り替えたら `[N] SKIP: <理由（repo_kind）>` を必ず出力する（本体が誤って downstream 判定に裏返ったとき SKIP 表示で気づけるフェイルセーフ。実リポジトリテストで「SKIP が無いこと」を固定）

macOS システム python3 は 3.9.6 で `tomllib`（Python 3.11+ stdlib）が無く、素の `import tomllib` は Traceback で落ちる（2026-07-03、pull 後の整合確認で発見）。import ガードで受け、**スクリプトの責務ごとに exit code を選ぶ**:

| 責務 | 例 | tomllib 欠如時 |
|---|---|---|
| 受動的 lint / check | `lint-toml.py`・`sync-optional-skills.py`（check） | SKIP / exit 0（配布先で誤 ERROR を出さない） |
| 実行前ゲート | `speculate-guard.py` | ERROR / exit 1（検証できなければ許可しない — フェイルセーフ） |
| 変更系コマンド | `sync-optional-skills.py apply` | ERROR / exit 1（実行できていないのに成功を装わない） |

- 呼び出し側フォールバック（uv があれば `uv run --python 3.11`、なければ `python3` 直接実行）は**テストと手順書の両方に対称に**置く。テストだけに入れると、手順書を読む人間・エージェントが罠に落ちる非対称が生まれる（`test-optional-skills.sh` には有ったが後発の `test-speculate-guard.sh` に無かったドリフトが実例。パターンをコピーする側のファイルにこそドリフトが宿る）
- 手順書を `uv run --python 3.11` に統一するだけでは不十分 — **uv 自体が無い環境**では案内がシェルレベルの `command not found` になりガードに到達しない。手順書側に「uv が無ければ python3 直接実行」の注記をセットで置く（レビュー指摘で発見）
- 再現テストは PYTHONPATH シム（`raise ModuleNotFoundError("No module named 'tomllib'")` する偽 `tomllib.py`）で環境非依存に注入できる。sys.path で PYTHONPATH が stdlib より優先されることを利用した、ドリフト注入 TDD の変種
- **tomllib（標準ライブラリの世代差）だけでなく PEP 723 のサードパーティ依存（pyyaml 等）も同じ類型で扱う**。`uv run` は PEP 723 の `dependencies` を自動解決するが、`python3` 直接実行では解決されない — つまり uv と python3 は「Python バージョン」と「依存解決」の**2軸で非対称**。依存を宣言するスクリプトには同型の import ガード（lint なら SKIP）を置き、手順書のフォールバック注記には依存の入手方法（`pip install pyyaml`）まで書く（lint-frontmatter.py で投機サイクルのペルソナ並列レビュー3者が独立指摘した実例。「注記の根拠にした実例（tomllib 系）以外は検証していない」一般化が原因）

### 「ファイル⇔ファイル」だけでなく「参照⇔カバレッジ」もペア化できる（ペア5）

Plan 0022 で追加したペア5は、テキスト一致ではなく**参照の被覆**を検査する変種:

1. CLAUDE.md から `.claude/` 配下のファイル参照を抽出する（`@メンション` と バッククオート内パス。コードブロック内は例示の可能性があるため除外）
2. 各参照が addf-init のコピーリストでカバーされるか判定する。判定は4段:
   完全一致 → グロブ（`fnmatch`）→ ディレクトリ前方一致（末尾 `/` エントリ）→ .gitignore ADDF マーカーブロック（実行時生成ファイルはコピー対象外として正当）
3. 漏れ = 外部起動導入したダウンストリームでの参照切れ。WARNING（オーナー独自参照の可能性があるため ERROR にしない）

**正規表現の罠**: 本文に `.claude/`（ルート単体）というバッククオート表記があると、`[^\s`]*`（0文字許容）の抽出ではこれがエントリ化し、ディレクトリ前方一致で**全参照がカバー扱い**になる。`+` で1文字以上を強制して解決した。カバレッジ検査は「広すぎるエントリ1つで全検査が無効化する」失敗モードを持つ — 疑わしいときはドリフトを注入して RED になることを先に確認する（TDD）。

同型の罠はペア8（README スキルテーブル網羅性・Plan 0053）にもある: `check_pair8()` の掲載判定
（`re.findall(r'\*\*(addf-[a-z0-9-]+)\*\*', text)`）はファイル全文を対象にしており、
「テーブル行かどうか」を区別しない。太字マーカー `**addf-xxx**` が本文中のどこにあっても
"掲載済み" とみなすため、将来 README のプロズ（説明文・利用例）でスキル名を太字言及した場合、
実際にはテーブルから削除されていても false negative でドリフトを見逃す余地がある。現時点では
該当する太字表記が全てテーブル行にしか存在しないため実害はないが、広すぎるマッチが検査を
無効化しうる同じ失敗モードの実例として記録する。将来この余地が顕在化したら、テーブル行
（`| **addf-xxx** |` 形式）に限定したマッチへ絞り込む改善余地がある。

### 列挙の陳腐化は「列挙を持たない」設計で構造的に排除できる

addf-init の .gitignore マージ手順は、当初ブロック内容をハードコード列挙しており、本体 .gitignore の変更（`.claude/addf/Dashboard.md` 追加等）に追従できず腐っていた。リストの鮮度を lint で守る前に、**そもそも列挙を持たず「クローン元（`<tmp>/addf-source/.gitignore`）の同ブロックをそのままコピーする」と指示する**ことでドリフトの発生源自体を消せた。同期ペアを増やす（機械化）より、単一ソース化（構造的排除）が上策。lint は単一ソース化できない箇所にだけ張る。

### lint のテストは mktemp サンドボックスにドリフトを注入する

実リポジトリを汚さずに異常系を検証するパターン:

```bash
box="$(mktemp -d)"
# 対象ファイルを相対レイアウトを保ってコピー
mkdir -p "$box/.claude/addf/templates" "$box/.claude/addf/guides"
cp ... # 必要ファイル
# ドリフトを注入（行削除・番号書き換え・ファイル削除）
grep -v '^15\. コミットする' ... / sed 's/^4\. /44. /' ... / rm -f "$box/AGENTS.md"
(cd "$box" && python3 "$LINT")  # 相対パス前提のスクリプトは cwd を切り替えて実行
```

サンドボックスは git リポジトリ外になるため、git 呼び出しは `returncode != 0 → '不明'` のフォールバックが必要（`git log` はリポジトリ外でも例外を投げず exit 128 + 空出力になる）。副産物として、このテストがダウンストリーム環境（ADDF 固有ファイルなし）のシミュレーションにもなる。

### 「動的アサーション化」は分岐条件と検証条件が同じ観測対象なら恒真式になる

Issue #29（downstream 宣言のダウンストリームプロジェクトで実行すると必ず FAIL する固定アサーション）
を Plan 0055 で直した際、最初の修正が別の欠陥を持ち込んだ:

```bash
# 一見「動的」だが、分岐条件と検証が同じ $output に対する同じ grep 述語 → 恒真式
if printf '%s' "$output" | grep -qF "[$pair] SKIP"; then
  assert_contains "SKIP される" "[$pair] SKIP" "$output"
else
  assert_not_contains "SKIP されない" "[$pair] SKIP" "$output"
fi
```

`$output` の中身が何であれ、分岐した時点で以降のアサートは「grep したら見つかった/見つからなかった」を
再確認するだけで、`repo_kind` の分類ロジック自体にバグが入っても（例: 誤って downstream を upstream と
判定する回帰）検出できない。code-review（addf-code-review-agent）がこの構造を Critical として発見した。

**正しい形**: 検証対象（`$output`）とは**独立した経路（オラクル）**で「宣言の真実」を先に判定し、
その独立した期待値で `$output` を検証する:

```bash
expected_kind="$(detect_expected_repo_kind "$PROJECT_DIR")"  # $output を一切参照しない別経路
case "$expected_kind" in
  downstream) assert_contains "SKIP される（downstream 宣言）" "[$pair] SKIP" "$output" ;;
  upstream)   assert_not_contains "SKIP されない（upstream 宣言）" "[$pair] SKIP" "$output" ;;
esac
```

**教訓を一般化すると**: 「テストを固定値から動的判定に変える」という修正そのものは正しい方向でも、
分岐条件と検証条件が**同じ観測対象・同じ述語**になっていないか必ず疑うこと。独立オラクルがあって
初めて regression guard として機能する（この形なら `check_pairN()` が `repo_kind` を無視して常に
比較する回帰を実際に検出できる）。

**独立オラクルを自作するときの罠**: 上記の `detect_expected_repo_kind()` を実装した際、本家の
`detect_repo_kind()`（`verify-checksums.sh` / `lint-template-sync.py`）が持つ前処理
（`strip_fences()` — コードフェンス内の文言を判定対象から除外する）を最初は複製し忘れ、
オラクル自体が壊れて実際にテストが FAIL した。`CLAUDE.repo.example.md` はダウンストリーム向けの
書き換え例（`**ADDF 利用プロジェクト**`）をコードフェンス内に持つため、フェンスを除去しないと
upstream/downstream 両方のマーカーが地の文にヒットしたと誤認する（本ファイルの「存在≠所有」節・
65行目で既に記録済みの `detect_repo_kind()` 本体の仕様と同じ罠を、簡易再実装で踏み直した形）。
**独立オラクルは本家ロジックの前処理まで漏れなく複製するか、可能なら本家の関数自体を呼び出す方が
安全**（今回は bash テストファイルという制約上、関数呼び出しの再利用が難しく簡易再実装を選んだ）。

**同型の再発（2026-07-16・Plan 0058）**: テストのアサーションが**実リポジトリの固有
コンテンツに依存する**のも同じ欠陥クラス。ダッシュボード生成テストの初版が「実在する
Plan 0028 がたまたま含む危険文字列への grep」と「Plan が1件以上ある前提」を検証に使って
おり、contribution-agent が DS サンドボックス実測で「ダウンストリームでは必ず FAIL」を
検出した（Issue #29 / Plan 0055 で直した欠陥を、同型のまま別の場所で再生産した形）。
対処も同型: テスト自身が mktemp サンドボックスに合成フィクスチャ（敵対的入力入りの
合成 Plan）を作って検証する drift-injection 方式に書き換える。**テスト新設時の自問**:
「このアサーションは、Plan が0件の空のダウンストリームリポジトリでも成立するか？」

### 文字列一致 lint は「歴史を語る引用」と「現役の参照」を区別できない

`lint-residual-paths.py`（Plan 0037 移行の完了ゲート。旧パス文字列の単純 grep）は、Progress 日記や
knowhow で「以前この旧パスの残存バグを直した」と過去形で書いた瞬間にも ERROR を出す。lint 自身は
文脈を読まないため、修正の顛末を記録した文章が次の ERROR 源になるという再帰的な罠がある（2026-07-10、
Plan 0044 完了処理中に自分の Progress 日記が引き金になって発覚）。対処は「旧パス文字列そのものを
書かず、意味だけを説明する」言い回しに倒すこと（旧 `docs/` 配下パスのような具体的な文字列そのものを
本文に書かない）。lint 側を
文脈判定に賢くする改修は複雑さに見合わないため、**書く側が気をつける**運用で足りる —
ただし旧パスの実例を記録する knowhow・障害記録では毎回この罠に当たりうるので、該当箇所を書くときは
本節を思い出すこと。

## Plan 0059/0060 の追加知見（2026-07-17）

- **動的アサーションの分岐カバレッジ**: 「独立オラクル → 期待値分岐」パターンは、実行時の
  host 環境で片方の分岐しか踏まれない構造的な穴を持つ（upstream で実行する限り downstream
  分岐は実質未検査）。反対側の分岐条件を人工的に作った fake PROJECT_DIR で明示的に踏む
  回帰テストを1本足すと埋まる（test-binary-checksums.sh Test 16 が実例）
- **DS 安全性の検証は2層必要**: (1) 個別関数を合成オブジェクトで検証する回帰テストと、
  (2) 配布物一式を DS 構成に丸ごとコピーして実行する実測。Plan 0059 は (1) を揃えて
  完了条件を満たしたつもりだったが、contribution-agent の (2) が Test 1・19 の DS FAIL
  （pair1 の非対称挙動への期待ズレ・host 内容前提の sed 注入が no-op）を検出した。
  (1) は「関数が正しい」ことしか言えず、「DS オーナーが run-all.sh を叩いて緑になる」は
  (2) でしか検証できない
- **テストのドリフト注入は「既存文言の sed 除去」でなく「合成行の挿入」で行う**:
  除去方式は host のファイル内容に暗黙依存し、内容が違う環境（真の DS の無印テンプレ由来
  Progress.md）で no-op になる。挿入方式（節内への合成行 awk 挿入）は環境非依存。
  なお挿入位置が検査対象セクションの内側であることを必ず確認する（末尾 >> は節外に落ちる）
- **正規表現の誤検知除去は「新たに開けた穴」の検証をセットにする**: lookbehind 境界の導入
  （Plan 0060）は Issue 記載の具体例のみをテストし、blob URL 自己参照の検出漏れ回帰と
  basename 衝突誤検知（いずれもレビューが実測反証）を見逃した。境界系の変更では
  「検出すべきものリスト」「除外すべきものリスト」の両側を、変更前後で網羅比較する

## 関連ノウハウ

- [アップストリーム / ダウンストリーム分離パターン](upstream-downstream-separation.md) — `.addf.md` サフィックス等、本知見の SKIP 設計が前提とする分離規約
- [スキル設計パターン（Anthropic 社内知見ベース）](skill-design-patterns.md) — スクリプトを `.claude/addf/addfTools/` に同梱する Progressive Disclosure 構成
- [Plan 着手前の実態突合](plan-status-drift-check.md) — ペア5（Plan 0022）の発端となった残差分切り出しの経緯
- [チェックリスト裏付け lint](checklist-backing-lint.md) — 本設計の直系。手順書の「確認」項目に実行チェック/human-judgment マーカーの裏付けを要求する
- [cron 経由 /loop の並行実行競合](cron-loop-worktree-race.md) — 同じ Plan 0044 完了処理中に発見した別種の知見（working tree 競合）
- [ドキュメントサイトの単一ソース同期](docs-site-single-source-sync.md) — 「欠如 = SKIP」設計の応用例（VitePress サイト用テストが node 不在のダウンストリームで誤 FAIL しないようにする）
- [オプトイン式スキルの退避＋有効化コピー設計](optional-skill-optin.md) — SKIP 設計・列挙の陳腐化検査の応用先。gitignore 列挙との突き合わせで孤児コピーを検出する
- [陳腐化しやすい knowhow 記述パターン](knowhow-obsolescence-patterns.md) — 「列挙を持たない単一ソース化」原則を knowhow 記述側に適用したメタパターン
- [既存プロジェクトへの導入パターン](existing-project-install-pattern.md) — 「存在≠所有」の判定ロジックを本知見から引用する側
- [Plan 起票時の詰め方](plan-refinement-pattern.md) — 引用突合・サンドボックステスト作法の供給元として本知見を引用する側
- [投機統合の設計](speculative-integration-design.md) — exit 3値・欠如=SKIP・ドリフト注入テストの原則を本知見から引用する側
- [VitePress 埋め込みのエスケープ落とし穴](vitepress-embed-escape-pitfalls.md) — 「実リポジトリ固有コンテンツ依存テスト」の再発現場（Plan 0058）。合成フィクスチャによる drift-injection の適用例
- [worktree-dotdir-copy.md](worktree-dotdir-copy.md) — サンドボックス再現テストの作法を本知見から引用する側
