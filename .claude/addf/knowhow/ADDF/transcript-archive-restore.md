---
title: PreCompact アーカイブからの resume 復元手順
created: 2026-07-07
last_verified: 2026-07-07
depends_on: [context-and-transcript.md, claude-code-hooks.md]
status: active
---

# PreCompact アーカイブからの resume 復元手順

Plan 0042 で導入した PreCompact フック（`.claude/hooks/pre-compact-archive.sh`）が保全した compaction 直前のトランスクリプト JSONL を、`claude --resume` で復元する手順と落とし穴。原理は [context-and-transcript.md](context-and-transcript.md) の「非対称双方向性」— JSONL → セッションの方向は resume 時のみ開通し、外部編集・複製を無検証で受け入れる — に立脚する。

## 発見した知見

### 復元の基本手順

前提: `.claude/addf/Behavior.toml` の `[transcript-archive] enable = true` で PreCompact フックが動いており、`~/.claude/addf-transcript-archive/<プロジェクトスラグ>/<日時>-<trigger>-<session-id>.jsonl` が蓄積されている。

```bash
# 1. アーカイブから復元したい世代を選ぶ（新しいものが下）
ls -lt ~/.claude/addf-transcript-archive/<スラグ>/

# 2. 復元先の Claude Code プロジェクトディレクトリを特定
#    通常: ~/.claude/projects/<スラグ>/
ls ~/.claude/projects/<スラグ>/

# 3. 新しい有効な UUID を発行してリネームコピー
NEW_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
cp ~/.claude/addf-transcript-archive/<スラグ>/<日時>-<trigger>-<session-id>.jsonl \
   ~/.claude/projects/<スラグ>/${NEW_UUID}.jsonl

# 4. 復元セッションを開く
claude --resume "$NEW_UUID"
```

resume に成功すると compaction 直前の会話文脈がメモリに戻り、その先から話を続けられる。要約を跨ぐ前の生発言・生ツール結果まで取り戻せる点が auto-compact 経由の復帰との違い。

### プロジェクトスラグの決め方（Claude Code 慣習）

`~/.claude/projects/` 直下のディレクトリ名は cwd を `/` → `-` で変換したもの（例: `/Users/riin/workspace/AutomatonDevDriveFramework` → `-Users-riin-workspace-AutomatonDevDriveFramework`）。`pre-compact-archive.sh` は `transcript_path` の親ディレクトリ名をそのままアーカイブ配下のディレクトリ名に採用するので、archive 側と projects 側のスラグは自然に一致する。復元時は archive 側のディレクトリ名を projects 側にコピーすればよい。

### session_id を「振り直す」理由

元の session-id のまま projects に置くと Claude Code の管理下で衝突する可能性がある（同名の JSONL が別セッションとして残っていることがある）。新しい UUID にすれば安全に並置でき、元セッションと復元セッションを別物として扱える。

### 元セッションと復元セッションを並走させない

同じ会話履歴を持つ複数セッションを同時に走らせると、ハーネスの状態管理（`.turn-count`・`.context-reminder-state`・`skill-usage.jsonl` 等）が競合する。復元セッションを開くときは元セッションを終了させておく。並走が必要な場合は、復元セッションを別プロジェクトディレクトリで開く（新 cwd → 新スラグ → 完全に独立した状態管理）。

### トランスクリプト汚染ごと復元されるリスク

[context-and-transcript.md](context-and-transcript.md) の「トランスクリプト汚染 — 自己強化劣化」で扱った現象は復元にも影響する。復元直後から**同種のツールコール失敗が頻発する場合、アーカイブ時点で汚染が既に混入していた**可能性を疑う（[claude-code#72015](https://github.com/anthropics/claude-code/issues/72015)）。

- 悪化条件（Fable/Opus 1M variant・xhigh・長セッション・非 ASCII 主体・高ツール密度）が揃った状態で取ったアーカイブは復元しても劣化状態から始まる。汚染 auto-compact による解毒効果が失われるため、その復元は諦めるのが早い
- 見分け方: 復元直後の数ターンで legacy XML 形式のツールコール失敗（`<invoke>` が `<invoke>` にならない）が繰り返される → 汚染復元。素直に auto-compact 経由で復帰した方が結果的に早い

### バージョン差異

トランスクリプト JSONL は非公開フォーマット（`version` フィールドあり）。Claude Code のバージョンアップで構造が変わりうるため、**古い世代（数ヶ月前など）のアーカイブは resume できない場合がある**。復元の実用範囲は「直近のセッション寿命内」を想定し、長期保管ではなく直近の巻き戻し用と割り切る。

### tool_use と tool_result のペアリング

エントリを手動で編集する場合（汚染エントリの手術等）、`tool_use`（assistant 側）と `tool_result`（user 側）はペアで整合していなければならない。片方だけ削除すると API 制約違反で resume が失敗する（[context-and-transcript.md](context-and-transcript.md) 参照）。素朴な世代復元だけならエントリは触らないので問題ないが、部分編集する場合は uuid/parentUuid チェーンと tool ペアを保つこと。

### アーカイブが取れない環境

- **Behavior.toml の `[transcript-archive] enable = false`（デフォルト）**: PreCompact フックが早期 return する。有効化しない限り何も起きない
- **PreCompact が発火しない環境**（一部の CLI 実行モード・エフェメラル環境）: hook 自体が呼ばれない。アーカイブ有無は `~/.claude/addf-transcript-archive/<スラグ>/` の存在で事後確認する
- **compaction 時に transcript_path が新 ID に切り替わる環境**: 発火時点の path を無条件にコピーする実装なので、切替前の path が拾える限り正しくアーカイブされる（Plan 0042 テスト方針で対応済み）

## プロジェクトへの適用

- ADDF 本体・ダウンストリーム双方で共通の手順（配布物には無効デフォルトのフックのみが載る）
- 復元頻度は高くない想定（compaction は多くの場合 auto-compact + post-compact-recovery.sh で十分）。復元が必要になるのは「直前の生発言・生ツール結果を失いたくない特殊ケース」に限る
- 復元セッションを日常運用に組み込むと、汚染復元のリスクが常時つきまとう。**復元は例外運用**として扱い、成功したら通常のブートシーケンス（Progress.md 日記読み込み等）で通常フローに戻ること

## 参照

- [Plan 0042: PreCompact トランスクリプトアーカイブ](../../plans-add/0042-precompact-transcript-archive.md) — 本手順が復元手順に対応する実装 Plan
- 関連 knowhow: [context-and-transcript.md](context-and-transcript.md) — 非対称双方向性・トランスクリプト汚染の原理
- 関連 knowhow: [claude-code-hooks.md](claude-code-hooks.md) — PreCompact フックの発火タイミング・stdin JSON 構造
- [claude-code#72015](https://github.com/anthropics/claude-code/issues/72015) — トランスクリプト汚染（不正ツールコールの自己強化劣化）の報告
