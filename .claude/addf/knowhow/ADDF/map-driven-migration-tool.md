---
title: 自分自身を移動させる移行ツールの設計パターン
created: 2026-07-06
last_verified: 2026-07-11
depends_on:
  - file: .claude/addf/addfTools/paths.toml
  - file: .claude/addf/addfTools/migrate-paths.py
  - file: .claude/addf/addfTools/lint-residual-paths.py
status: active
---

# 自分自身を移動させる移行ツールの設計パターン

Plan 0037（ADDF ディレクトリ大集約）フェーズ1 で、リポジトリ内の大規模ファイル移動＋参照書き換えを
マップ駆動で行うツールを実装して得たパターン。**ツール自身が移動対象に含まれる**点が通常の
リファクタリングスクリプトと違う難所になる。

## 発見した知見

### モード分離とコミット分離の構造的強制

- `check`（読み取り専用プリフライト）/ `apply`（git mv のみ）/ `rewrite`（参照書き換えのみ）の
  3モードに分け、**apply と rewrite の両方が dirty な作業ツリーを拒否**する。これにより
  「git mv コミット」と「参照書き換えコミット」の分離（revert 一発で戻せる原子性）が
  オペレーターの規律ではなく構造で強制される
- backup ref は**既存確認してから**作成する。無条件 `update-ref` だと2回目の実行が
  「本当の移行前」を指す ref を静かに上書きし、巻き戻し案内が嘘になる

### 自己移動の罠

- apply でツール自身のディレクトリが移動するため、**完了メッセージには移動後の新パスで
  次コマンドのコマンドラインを具体的に表示**する（旧パスをコピペすると No such file で即死。
  2ペルソナが独立に指摘した実質 Critical）
- マップファイル（paths.toml）の探索は**新位置優先**の候補リストにする。マップ内の旧パス文字列は
  書き換え除外（allowlist）にし、移行後もマップが旧→新対応を保持し続ける = ダウンストリーム移行に再利用できる
- テストは「apply 後に**新位置から** rewrite を呼ぶ」経路を実際に通すこと。旧位置固定の
  テストハーネスはこの罠を素通りする

### 走査の安全化

- **symlink は open 前に除外する**。git は symlink を blob として追跡するため、走査対象に普通に
  混入し、rewrite がリンク先（リポジトリ外の任意ファイル）へ書き込む脆弱性になる（attacker
  ペルソナが実再現）
- バイナリ判定は拡張子ホワイトリストではなく **NUL バイト検査＋UTF-8 デコード失敗**で行い、
  書き換え系と検査系（lint）で走査対象集合を一致させる。不一致だと「check 0箇所 → lint で初 ERROR」
  という食い違いが完了ゲートで初めて露見する
- 部分文字列の誤マッチ（`.claude/addf/plans` → `.claude/addf/plans-add`）は長いキー優先＋境界判定
  （前後が英数字・ハイフン・アンダースコアならマッチしない）で防ぐ。逐次置換は
  「置換後の新パス文字列が他エントリの旧キーを含まない」という**暗黙の不変条件**に依存する —
  マップ拡張時に守る必要があるためコメントで明示し、ロード時 assert（immovable との重複検査等）を置く

### クラッシュ耐性

- 移動直前の `makedirs` が残す**空の中間ディレクトリは `git status` に出ない**。そのため
  「dirty 判定は clean なのにプリフライトは衝突で拒否」という自己ロックが起きる（attacker が実再現）。
  移動先が空ディレクトリなら衝突扱いせず rmdir して継続する
- 途中失敗状態（apply 済み・rewrite 未了等）を識別できるよう、lint の ERROR には
  「未完了の可能性 → check で確認」の注記を添える

### rewrite の射程外 — 5類型（フェーズ2 実施＋事後レビューで実測）

マップ駆動 rewrite は「フルパス文字列のリテラル出現」しか書き換えられない。本体移行の実施では
run-all 全19スイート中18が移行直後に失敗し、原因は類型1〜3だった。類型4・5は run-all にもかからず
事後レビューで発見された（lint-residual-paths はいずれも検出できない — フルパス文字列が存在しないため）:

1. **相対階層参照**: `SCRIPT_DIR/../../..` 等。ディレクトリが深くなると全てのルート算出がずれる
2. **分割断片**: `os.path.join(dir, '.claude', 'addf-Behavior.toml')`・Swift の `scriptDir + "/../addf-Behavior.toml"`
   のような組み立て。**コンパイル済みバイナリ内の断片はソース修正＋再ビルド＋checksums 更新まで必要**。
   **ダウンストリーム実測（Issue #26・wardrobe-test の v0.5.0→v0.6.1 移行）で質的に重い実害を確認**:
   `window-info.swift`/`capture-window.swift` の `configPath` 計算が旧パス前提のまま再ビルドされずに
   残っていたため、`gui-test.enable = false` の disabled 判定に失敗 → フォールバックで実際の GUI 情報
   取得処理に入り、**画面収録権限ダイアログ待ちで `window-info` プロセスが9時間ハングし続けた**
   （`test-tools.sh` 経由で一度でも実行すると CI・cron 双方で無期限にプロセスが残るリスク）。
   単なるテスト失敗と違い**無期限ハング**という質の異なる実害になる点が GUI バイナリの特有の危険度
   — 対策は `test-tools.sh` の timeout ガード（原因によらない機械的な打ち切り）と、移行手順書
   （`addf-migrate.md` 6.7）への「再ビルド後は timeout 付きで実際に実行して確認する」明記（Plan 0052）
3. **書き込み先の親ディレクトリ**: テストのサンドボックス構築（`mkdir -p "$box/.claude"` → 書き込みは
   `.claude/addf/...`）。書き込みパスだけ rewrite され、mkdir/cp の準備側が旧構造のまま残る
4. **Markdown 相対リンク**: `[CONTRIBUTING.md](../../CONTRIBUTING.md)` 等。移動でファイル自身の階層が
   変わるとリンク先がずれる。テストにもかからない（レンダリング時にしか壊れない）ため、
   移行後に全 Markdown の相対リンク解決チェックを一度回すこと

5. **裸参照・分割文字列**: `.claude/` プレフィックスを欠く裸のファイル名言及
   （「ADDF-CHANGELOG.md から表示」等）や、ドキュメントのツリー図のように**インデントで
   親子が分割された表現**は、フルパス文字列として出現しないため rewrite も lint も素通りする。
   ガイド・README のツリー図と裸のファイル名参照は移行後に目視で洗うこと（doc-review が実測検出）

補足: git 追跡外のファイル（`settings.local.json` の許可ルール等）も走査対象外で旧パスが残る。
移行後に permission ルールを確認すること。`.gitignore` は git 追跡対象だが、**グロブパターンの
非対称**という別種の穴がある（下記「`.gitignore` グロブパターンの非対称検知」参照）。

対策: 移行後の run-all を完了ゲートに含める（lint ゼロだけでは足りない）。移行を計画する段階で
`os.path.join`・`SCRIPT_DIR/..`・Markdown 相対リンクの断片走査をプリフライトに足すと、
事後デバッグではなく事前修正にできる。

### `.gitignore` グロブパターンの非対称検知（Plan 0052・Issue #26 実測）

`.gitignore` に旧位置ベースの独自パターン（例: `.claude/*.md`）がある場合、リテラル文字列一致の
rewrite/lint では検出できない非対称が起きる — パターン自体は書き換えられないため、
「旧位置にはマッチしていたが新位置にはマッチしない」状態のまま残り、ファイルが意図せず
追跡対象になる（ダウンストリーム実測で Progress.md 等4ファイルが該当）。

対策として `lint-residual-paths.py` に `gitignore_like_match()` を追加した。実装上の落とし穴:

- **素の `fnmatch.fnmatch(old, pattern)` は使えない**: `*` が `/` を跨いでマッチしてしまうため、
  `.claude/*.md` は `.claude/Progress.md`（旧）にも `.claude/addf/Progress.md`（新）にも <!-- residual-path: allow -->
  マッチしてしまい、本来検出すべき非対称を見逃す。対策は `/` でセグメント分割し、
  セグメント数が一致する場合のみ各セグメントを個別に fnmatch する
- **アンカー情報を lstrip で落とさない**: 先頭 `/` のみ（内部に `/` を含まない）パターンは
  リポジトリルート限定を意味し、`/foo.md` と `foo.md`（任意階層のベース名一致）は区別が必要。
  `pattern.lstrip('/')` を呼び出し側で先に行うとこの区別が失われる
- **末尾 `/`（ディレクトリ限定指定）は比較前に `rstrip('/')` で落とす**: `.claude/addfTools/` の <!-- residual-path: allow -->
  ような慣用記法が、ディレクトリ単位で移動されるエントリ（`paths.toml` の `dirs`）と
  型不一致で検出漏れにならないようにする
- **ワイルドカードなしのリテラルパターンは対象から除外する**: 既存の文字列一致ベースの
  ERROR 検査と重複するため、同じ行に ERROR と WARNING が両方出て紛らわしくなる。
  `*`・`?`・`[` のいずれかを含むパターンのみこの検査にかける

## プロジェクトへの適用

- Plan 0037 フェーズ2（本体移行）・フェーズ3（addf-migrate 統合）はこのツール群を使う。
  実行順は apply → コミット → **新位置の** rewrite → コミット → lint-residual-paths ERROR ゼロ
- 将来の再配置は paths.toml の更新だけで migrate・lint・テストが追従する（単一ソース）

## 注意点・制約

- import ガード（変更系=ERROR / lint=SKIP）とドリフト注入 TDD の一般則は
  [sync-lint-design.md](sync-lint-design.md) が単一ソース
- ADDF 管理サブディレクトリ内部の非所有ファイルは無条件に巻き込む仮定が残る（Plan 0037
  レビュー残課題参照）。ツールの仮定自体は残るが、運用面は addf-migrate Phase 2.5 の 6.3
  「ディレクトリ丸ごと移動の混在確認」（クローン元との diff で独自ファイルを退避）と
  Phase 5 ステップ14 の保護句で緩和済み（フェーズ3 レビュー C3 対応）

## 参照

- `.claude/addf/addfTools/migrate-paths.py` / `lint-residual-paths.py` / `paths.toml`
- `.claude/addf/tests/tools/test-migrate-paths.sh`（71アサーション。攻撃再現テスト込み）
- `.claude/addf/plans-add/0037-addf-directory-consolidation.md`
- [persona-review-oneshot.md](persona-review-oneshot.md) — これらの穴を検出したレビュー体制
