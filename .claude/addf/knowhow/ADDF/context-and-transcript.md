---
title: コンテキストとトランスクリプトの関係 — 非対称双方向性・resume・能動 compaction の限界
created: 2026-07-06
last_verified: 2026-07-06
depends_on: []
status: active
---

# コンテキストとトランスクリプトの関係 — 非対称双方向性・resume・能動 compaction の限界

Plan 0041 の調査・実験（2026-07-06）で確立した、セッションのコンテキスト（メモリ内会話履歴）とトランスクリプト JSONL の関係についての知見。実装されなかったアイデア（死蔵）も、着手トリガーとともにここに保存する。

## 発見した知見

### トランスクリプト JSONL の構造

`~/.claude/projects/<プロジェクトスラグ>/<session-id>.jsonl` に1セッション1ファイルで保存される。

- 各エントリは `uuid` / `parentUuid` の**連結リスト**。`parentUuid: null` がチェーンの起点
- 主なエントリ型: `user` / `assistant` / `attachment`（フック出力等）/ `file-history-snapshot` / `queue-operation` / `ai-title` / `last-prompt`
- `assistant` エントリの `message.usage`（`input_tokens` + `cache_read_input_tokens` + `cache_creation_input_tokens`）がコンテキスト実測の情報源（計測の罠は [claude-code-hooks.md](claude-code-hooks.md) 参照）
- `tool_use`（assistant）と `tool_result`（user）はペアリング制約があり、片方だけ消すと API 制約違反になりうる
- `version` フィールドを持つ非公開フォーマット。Claude Code のバージョンアップで構造が変わりうる前提で扱う

### 非対称双方向性（実験で確認）

| 方向 | タイミング | 性質 |
|---|---|---|
| セッション → JSONL | リアルタイム追記 | 常時。ただし追記専用ログ |
| JSONL → セッション | **resume 時のみ** | `claude --resume <session-id>` でファイルからコンテキストを再構築。**外部編集・複製を無検証で受け入れる** |

- **実行中のセッションは JSONL を読み直さない**（コンテキストはメモリ内の会話履歴から構築される）。実行中に自分のトランスクリプトを外部編集しても現セッションには何も起きない
- 実験（使い捨て headless セッション）: 「合言葉は『りんご』」→ JSONL を sed で「みかん」に置換 → `claude --resume` → モデルは「みかん」を合言葉として回答。エントリ行を1行削除（parentUuid チェーン断絶）しても resume はエラーにならず会話を継続できた
- 再現手順: `claude -p "<プロンプト>" --output-format json` で session_id を取得 → JSONL を編集 → `claude --resume <session-id> -p "<確認プロンプト>"`
- 系: **アーカイブした JSONL を新しい有効な UUID にリネームして projects ディレクトリに置けば、その時点の状態に `--resume` で戻れる**（スナップショット復元。Plan 0042 の PreCompact アーカイブの価値の根拠）

### 能動 compaction は存在しない（2026-07 時点）

- `/compact` はユーザー専用スラッシュコマンド。エージェントが Skill/Bash 経由で自セッションに対して呼ぶ手段はない
- hooks の `PreCompact` は `decision: "block"`（抑止）のみ。発動させる方向の制御は不可
- Agent SDK には compaction API（`context_management.edits`）があるが Claude Code CLI には露出していない
- auto-compact は harness がコンテキスト上限接近時に自動発動する。エージェントにできるのは「止まらずに作業を続けて発動点まで到達する」ことだけ（Plan 0041 の教義）

### トランスクリプト汚染 — 自己強化劣化（transcript poisoning）

[claude-code#72015](https://github.com/anthropics/claude-code/issues/72015)（2026-06 報告・open・関連 issue 多数の duplicate ラベル付き）: Opus 4.8[1m] で、ツールコールが不正な legacy XML（`antml:` プレフィックス欠落の `<invoke>`）として出力される失敗が、一度トランスクリプトに混入すると**以後の失敗確率を自己強化的に上げる**。コンテキスト内の不正パターンがモデルを同じ出力に誘導するため。

- 悪化条件: 1M variant・effort xhigh・長セッション・非 ASCII 主体（報告は韓国語だが日本語も同条件）・高ツール/MCP 密度 — **日本語運用で /loop 自走する ADDF の条件とほぼ一致する**
- 大きな `Write`/`Edit` ペイロードや長い前置きテキスト付きの呼び出しほど失敗しやすく、短い呼び出しは通る
- 含意1: **compaction は解毒を兼ねる**。要約で汚染パターンが洗い流されるため、「止まらず auto-compact に到達する」教義（Plan 0041）には劣化リセットの価値もある
- 含意2: **スナップショット復元（Plan 0042）は汚染ごと復元する**。復元直後から同種のツールコール失敗が頻発する場合は、アーカイブ時点で汚染が混入していたことを疑う
- 含意3: 死蔵中のトランスクリプト手術には「解毒」ユースケースがある — コンテキスト圧縮ではなく、汚染エントリ（不正 XML を含む assistant 出力）の間引きを目的に手術 → resume する道。ツールコール失敗が自己強化ループに入ったときの脱出手段になりうる

### セッション内再帰装置の寿命

セッションの死を越えるループを組もうとすると、ハーネス内の道具は全て使えない:

- **ScheduleWakeup**（/loop の心臓）: セッション内の再入予約。セッション終了で消える
- **CronCreate**: 仕様に session-only と明記（メモリ内のみ・REPL アイドル時に同一セッションへ enqueue・セッション終了で消滅）
- **RemoteTrigger / schedule**（クラウドルーチン）: 永続するが実行環境がクラウドで、ローカルの JSONL・作業ツリーに触れない

セッションの死を越えるループには、定義上セッションの外（OS レベル）に発火装置が要る。

## 死蔵アイデア（実装しない・記録として保存）

> 2026-07-06 オーナー決定: アイデアは良いが「ループが閉じきっていない」（外部足場が必須）ため実装しない。
> 着手のトリガー: unattended 常時自走の需要が高まり、OS レベルの足場（launchd/systemd）のセットアップコストを払う価値が出たとき。

- **トランスクリプト手術 + resume（能動的・選択的 compaction）**: セッション終了 → JSONL バックアップ → 古い `tool_result` の content をプレースホルダに置換して間引き → 同一 session-id で resume。auto-compact と違い何を残すか選べ、残した部分は無劣化。原理成立は上記実験で確認済み。安全な手術は「エントリ削除」より「content 置換」（tool ペアと uuid チェーンを保つ。Anthropic API のサーバー側 context editing と同じ発想）
- **世代交代（generational handoff）**: 記録完了後に次世代セッションを起動して正常終了する。実装案: (A) セッション内 Bash から `claude -p` 起動 / (B) 外部ループスクリプトによるセッション連鎖 / (C) 手術 + resume の連鎖。日記・Progress.md が引き継ぎチャネル（Plan 0017 の「本当の代替わり」の完全形）
- **ループの閉じ方3案の評価**: (1) 遺言プロセス（nohup で死後発火）— エージェント主導だが1回切れたら静かに死ぬ / (2) launchd・systemd のステートレス watchdog —「継続フラグが立っているのに対象セッションが死んでいる」ときだけ発火する番犬。自己修復的で堅いが、ダウンストリーム配布物にプラットフォーム依存が入る / (3) ハイブリッド（遺言＋watchdog 保険）
- **燃料投下（意図的なコンテキスト消費で auto-compact を誘発）**: 200k セッションでは教義で足り、1M セッションでは発動点まで数十万トークンを捨てる。どちらも割に合わず不採用
- **実行中セッションの JSONL 直接編集**: 実行中は読み直されないため効果がない（実験済み）。効くのは resume 経由のみ

## 参照

- [Plan 0041: コンテキスト枯渇によるループ停止の壁の突破](../../plans-add/0041-context-exhaustion-loop-wall.md) — 本知見の出自。採用された方針（止まらない教義＋compaction 耐性のタスク運び）
- [Plan 0042: PreCompact トランスクリプトアーカイブ](../../plans-add/0042-precompact-transcript-archive.md) — 「resume 可能スナップショット」の系を応用する実装 Plan
- 関連 knowhow: [transcript-archive-restore.md](transcript-archive-restore.md) — Plan 0042 のアーカイブから resume で復元する具体手順・落とし穴
- 関連 knowhow: [claude-code-hooks.md](claude-code-hooks.md) — フックイベント一覧・transcript からのコンテキスト使用量実測の罠
- [claude-code#72015](https://github.com/anthropics/claude-code/issues/72015) — トランスクリプト汚染（不正ツールコールの自己強化劣化）の報告。関連: #64235, #63604, #64658, #63875, #62123, #61133
