---
title: ccchain（EnumaElish）ADDF 本体ドッグフーディング導入（フェーズ1）
created: 2026-07-14
last_verified: 2026-07-14
depends_on:
  - file: .ccchain.conf
  - file: .claude/settings.local.json
status: active
---

# ccchain（EnumaElish）ADDF 本体ドッグフーディング導入（フェーズ1）

Plan 0040 フェーズ1（ADDF 本体への ccchain 導入）で得た知見。EnumaElish リポジトリ自身の
`docs/knowhow/ccchain-dogfooding.md`（ccchain 開発側の知見。EnumaElish リポジトリ自身のパス） <!-- residual-path: allow -->
とは別に、**ccchain を利用する側**としての導入知見を記録する。

## 発見した知見

### README のリポジトリ名表記に誤りがある

`go install github.com/fruitriin/ccchain/cmd/ccchain@latest`（README・Plan 0040 本文の記述）は
404 になる。実際のリポジトリ名は `EnumaElish`（コマンド名 `ccchain` とは別）で、正しい import
パスは `github.com/fruitriin/EnumaElish/cmd/ccchain`。導入時は必ず `git ls-remote` 等で実在確認
してから `go install` する。

### デフォルト `.ccchain.conf` はそのままでは実運用に耐えない

`ccchain init` が生成するデフォルト設定を `ccchain test` で実際のプロジェクトコマンド群に対して
評価すると、2つの穴が見つかった:

1. **`git reset --hard` がデフォルトで allow**: `git` の `args:` ブロックに列挙されていない
   サブコマンドは、親ルール（`allow git`）にフォールバックするため無条件で allow になる。
   ADDF は `settings.json` の `permissions.ask` と `destructive-git-guard.sh` フックで
   `reset --hard`・`branch -D`・`checkout -- .`・`clean -f` を既に ask 化しているが、これは
   Claude Code の permission システム側の話であり、ccchain の判定とは独立している。ccchain
   だけを見ると「破壊的操作が allow」という誤った印象を与えるため、**既存の settings.json ask
   ルールと二重化する形で ccchain 側にも明示的に ask ルールを足した**（多層防御。片方の設定
   ミスがもう片方で拾われる設計）
2. **`fallback: ask` により ADDF の日常コマンドが軒並み ask になる**: デフォルト設定には
   `bash`・`python3`・`uv`・`gh` の allow ルールが一切無い。ADDF は
   `bash .claude/addf/tests/run-all.sh`・`uv run --python 3.11 <script>`・`gh issue view` 等を
   高頻度で実行するため、そのまま配線すると**ほぼ全ての Bash 呼び出しで確認プロンプトが出る**
   状態になり、`/loop` 等の自律実行が事実上不可能になる。導入前に必ず `ccchain test` で
   実際の運用コマンド群を評価し、ask が多発する箇所を allow 化してから配線すること
   （EnumaElish 自身のドッグフーディング knowhow が言う「テスト駆動のルール調整」フローと同じ）

### `bash` の allow は `-c` オプションだけ除外する

`allow bash` で全面許可すると `bash -c "<任意のシェルコード>"` まで通ってしまい ccchain の
構造解析が意味をなさなくなる。`args: { -c\b: ask }` で「スクリプトファイル実行は allow・
インラインコード実行は ask」に分けると、ADDF の実運用（`bash <path>.sh` 形式がほぼ全て）を
妨げずに危険な経路だけ絞れる。

### `for` ループ等の制御構文は静的解析不能として無条件 deny される（配線後に実運用で発覚）

配線後、`/addf-lint`・`/addf-knowhow-index` を別セッションで実行した際に、`for f in ...; do ...
done` 形式の Bash コマンドが軒並み `deny`（`"dynamic command detected: static analysis not
possible"`、context: `(control-flow)`）になることが判明した。`.ccchain.conf` のルールで
個別に対応できる話ではなく、**ccchain の構造解析エンジン自体が `for`/`while`/`if` 等の
制御構文をそもそもパースできず、無条件で deny する設計**（`ccchain eval 'for f in a b; do
echo $f; done'` で再現・確認済み）。これは Phase 1 導入前のテストバッテリー
（`ccchain test`）に制御構文を含む例を用意していなかったため見落としていた穴で、
配線後に別セッションが実際に for ループを書いて初めて顕在化した。
**対応方針**: ADDF のタスクで複数ファイルに同じ処理をする場合、`for` ループではなく
`grep` の複数ファイル指定・`find ... -exec` を避けた個別コマンドの列挙など、ループを
使わない書き方に倒す（今回別セッションが実際にそう回避して対応した）。これは実質的に
「1コマンド1目的」を強制する副作用があり、悪くはないが実運用でストレスになりうるため、
Phase 1 の運用期間中に頻度を観察し、あまりに頻発するようならフェーズ2のルール設計で
再検討する

### `gh` は読み取り系と書き込み系を分離する

`gh issue/pr/release/repo` の `view`/`list`/`status` は副作用がないため allow、
`comment`/`release create`/`pr create`/`pr merge` 等の外部可視状態を作るサブコマンドは ask に
分けた。これは既存の `settings.local.json` の `Bash(gh issue comment *)` 等の allow 設定と
役割が重複するため、将来的にどちらの層でゲートするかの整理が必要（要検討事項として残す）。

### バイナリ配置とビルド方式

- `go install` 後のバイナリは `$GOPATH/bin`（asdf 環境では
  `~/.asdf/installs/golang/<version>/bin/`）に入る。hook はプロジェクトルート相対の
  `"$CLAUDE_PROJECT_DIR"/ccchain` を参照する設計のため、`cp` でプロジェクトルートに複製する
  （EnumaElish 自身の dogfooding knowhow: `go run` は毎回ビルドが走り hook レイテンシが
  数秒になるため不可）
- バイナリは `.gitignore` でコミット対象外にする（Plan 0031 のバイナリ配布検証問題を
  そもそも発生させない設計判断。各自 `go install` で取得する前提）
- `.ccchain.conf`（プロジェクト共有・git 管理）と `.ccchain.local.conf`（個人上書き・
  gitignore 対象）は EnumaElish 自身の規約どおりに使い分ける

### 権限フィルタが「一言の着手指示」では外部バイナリ導入・自己ゲートフック配線を通さない

対話セッションでオーナーが「cchain やってみたいな」と発言しただけでは、(1) `go install` に
よる外部コード取得・ビルド、(2) `PreToolUse(Bash)` フックの配線（以降の自分の Bash 実行を
ゲートする自己変更）の2箇所で auto mode の権限フィルタに止められた。いずれも
`AskUserQuestion` で明示確認を取ってから進めることで解消した。これは Q5（cron 自律ループでの
着手可否）が懸念していたリスクと同種のもので、**対話セッションであっても「具体的な一段階ずつ
の明示同意」が必要**という運用実態が分かった一例。

## プロジェクトへの適用

- フェーズ1（本知見）は「導入して数タスク分運用し、誤 deny・誤 ask の知見を貯めてからフェーズ2
  （オプトイン配布機構の整備）へ進む」設計（Plan 0040 本文）。今回のセッションでは初期チューニング
  と動作確認までを実施し、実運用での知見蓄積はこれから
- フェーズ2 に進む際は、本 knowhow の「gh の役割重複」を含め、`.claude/settings.local.json` の
  既存 Bash allow リストと ccchain の `.ccchain.conf` のどちらでゲートするかの責務分担を
  再整理すること
- **フェーズ1とフェーズ2の配線先は意図的に別ファイル**: フェーズ1（本知見・ADDF 本体の
  ドッグフーディング）は `.claude/settings.local.json` に直接 hook を配線した。フェーズ2で
  作った `sync-ccchain.py`（オプトイン配布機構）は `.claude/settings.json`（共有・配布対象）
  だけを検査・操作対象にする設計で、`settings.local.json` 側は一切見ない。そのため
  `sync-ccchain.py check` は「フェーズ1の手組み配線」の有無を検出できない
  （`addf-Behavior.toml` の `[ccchain] enable = false` のままでも、フェーズ1の配線が
  生きていれば実際には hook が稼働し続ける）。これは意図的な設計判断であり、バグではない —
  フェーズ2完成時点で両方を同時に有効化すると同じ Bash 呼び出しに対して ccchain が二重評価
  される（実害は小さいが冗長）ため、フェーズ4（「フェーズ1の手組み配線を撤去し、自分の
  配布物を自分で使う状態にする」）で統合するまでは意図的に分離したまま残す。フェーズ4に
  進む際は `settings.local.json` の該当エントリを削除し、代わりに ADDF 自身の
  `addf-Behavior.toml` で `[ccchain] enable = true` にして `sync-ccchain.py apply` に
  一本化すること

## 注意点・制約

- PreToolUse フックは `.claude/settings.json`（`destructive-git-guard.sh`）と
  `.claude/settings.local.json`（ccchain）の両方に `matcher: "Bash"` で登録されている。
  両方が同一の Bash 呼び出しに対して発火する前提だが、「両方が異なる判定を返した場合の優先順位」
  は本セッションでは実際の破壊的操作を発生させて検証していない（次に該当操作が起きた際に
  観察すること）
- ccchain の判定は Claude Code 本体の permission システムとは独立した別レイヤーであり、
  ccchain が allow を返しても settings.json の ask ルールが別途発火しうる（逆も同様）。
  「ccchain の判定 = 最終的な許可/拒否」ではない点を混同しないこと

## 参照

- `.claude/addf/plans-add/0040-ccchain-optin.md` — 本知見が生まれた Plan
- `.ccchain.conf` — ADDF 本体のドッグフーディング設定（チューニング済み）
- EnumaElish リポジトリ（`github.com/fruitriin/EnumaElish`）の
  `docs/knowhow/ccchain-dogfooding.md`（EnumaElish リポジトリ自身のパス） <!-- residual-path: allow -->
  — ccchain 自身の開発側の知見（hook レイテンシ・DSL パーサーの制限・テスト駆動のルール調整等）

## 関連ノウハウ

- [permission-settings-pattern.md](permission-settings-pattern.md) — `settings.json`/`settings.local.json`
  の権限配置パターン（upstream/downstream/汎用の3分類）。ccchain は permission システムとは
  別レイヤーだが、責務分担の検討時に参照する
