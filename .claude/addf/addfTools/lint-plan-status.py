#!/usr/bin/env python3
"""Plan 状態整合チェック — 実装状況ヘッダと完了条件チェックボックスの矛盾（誤完了）を検出する

同期契約: Plan ファイル内の `## 実装状況:` ヘッダ ⇔ 同一ファイルの `## 完了条件`
セクションのチェックボックス状態（ファイル間ペアではなく単一ファイル内の整合。
ファイル間の同期は lint-template-sync.py ペア6 = TODO ⇔ ヘッダが担う。
本 lint はペア6が前提とする「ヘッダが実態を語っている」のさらに手前を機械化する）。

検出対象（Plan 0035 項目3-3）:
- ERROR: 実装状況ヘッダが「完了」で始まるのに、完了条件セクションに未チェック `- [ ]` が
  残っている（フェーズ分割 Plan の途中 PR マージで「済み」に見える誤完了の防止）
- WARNING: 表記ゆれ状態ヘッダ（`## 状態:`・`## ステータス:`・`## 進捗:`・
  レベル違いの `### 実装状況:`・コロン無しの `## 実装状況 完了` 等）を持ち、かつ
  チェックボックスを含む Plan。状態を書いているつもりの Plan が「ヘッダ無し」として
  黙って検査から漏れるのを防ぐ（lint-template-sync.py の plan_nonstandard_header と同旨）。
  ヘッダを `## 実装状況:` に統一する

検査対象外（正当な中間状態・旧書式）:
- ヘッダが「一部完了」「未着手」「進行中」等（完了で始まらない）→ 対象外
- ヘッダ自体が無い旧 Plan → 対象外（欠如はドリフトではない — ペア6と同じ方針。
  ただし表記ゆれヘッダ＋チェックボックス保有は上記 WARNING で拾う）
- 完了条件セクションが無い、またはチェックボックス形式でない旧 Plan
  （0001〜0034 は素の箇条書き）→ SKIP（明示出力・件数計上・ファイル名列挙。silent にしない）
- コードフェンス内のチェックボックス例示 → 無視

検出の制約（既知の限界）:
- 完了条件セクションの見出しは「完了条件」を**含む**ものを拾う（`## 完了条件`・
  `### フェーズA: 完了条件` 等）。見出しに「完了条件」を含まないセクション
  （「Done の定義」等）は検出不能
- セクション内のより深いサブ見出し（`## 完了条件` 配下の `###` 等）は境界とせず
  飲み込む。離脱は同レベル以浅の次見出しまたは水平線 `---` のみ
- コードフェンスは ``` / ~~~ の3連以上（4連以上のバッククォート含む）を開始/終了の
  トグルとして扱う。CommonMark の「開始フェンスと同種・同数以上で閉じる」までは
  追わない（例示の除外にはこの近似で十分）

対象ディレクトリ: .claude/addf/plans-add/（ADDF 本体）と .claude/addf/plans/（ダウンストリーム）の
`[0-9]*.md`。ディレクトリが存在しない場合は SKIP する（欠如はドリフトではない）。
検査対象が 0 件（ディレクトリ不在含む）の場合は NOTE を出して exit 0 する。

stdlib のみ使用（tomllib / pyyaml 不要 — import ガード類型の対象外）。

exit code: 0 = OK / 1 = ERROR あり / 2 = WARNING あり（表記ゆれヘッダ。ERROR 優先）
"""
import glob
import os
import re
import sys

HEADER_RE = re.compile(r'^##\s*実装状況[:：]\s*(.*)')
# 完了条件セクションの見出し（レベル2〜4 を許容。行頭アンカーで本文中の言及を除外。
# 「完了条件」を含む見出し全般にマッチする — 「### フェーズA: 完了条件」対応）
SECTION_RE = re.compile(r'^(#{2,4})(?!#).*完了条件')
# GFM タスクリスト: 箇条書きマーカーは -・*・+、番号付き `1.` / `1)` も有効
CHECKBOX_RE = re.compile(r'^\s*(?:[-*+]|\d+[.)])\s*\[( |x|X)\]\s*(.*)')
# コードフェンス開始/終了（```・~~~ の3連以上）
FENCE_RE = re.compile(r'^\s*(?:`{3,}|~{3,})')
# 表記ゆれ状態ヘッダ（標準形 HEADER_RE に一致しないもの。標準ヘッダ保有ファイルでは検査しない）
ALT_HEADER_RES = [
    re.compile(r'^#{1,6}\s*(?:状態|ステータス|進捗|status)\s*[:：]', re.IGNORECASE),
    re.compile(r'^#{1,6}\s*実装状況'),  # レベル違い（### 実装状況:）・コロン無し（## 実装状況 完了）
]

PLAN_DIRS = ['.claude/addf/plans-add', '.claude/addf/plans']

errors = []
warnings = []
skips = []
total_files = 0        # glob で見つかった Plan ファイル総数
checked_files = 0      # 完了ヘッダ × チェックボックス形式で実際に検査した件数
old_style_skipped = [] # 完了ヘッダだがチェックボックス無し（旧書式）
exempt_files = 0       # 中間状態・未着手・ヘッダ無し（正当な対象外）


def visible_lines(lines):
    """コードフェンス外の行を (0始まり行番号, 行) で yield する"""
    in_code = False
    for i, line in enumerate(lines):
        if FENCE_RE.match(line):
            in_code = not in_code
            continue
        if not in_code:
            yield i, line


def header_value(lines):
    """最初の `## 実装状況:` ヘッダの値を返す（無ければ None）。コードフェンス内は除外"""
    for _, line in visible_lines(lines):
        m = HEADER_RE.match(line)
        if m:
            return m.group(1).strip()
    return None


def alt_status_header(lines):
    """表記ゆれ状態ヘッダの行を返す（無ければ None）。コードフェンス内は除外

    呼び出し側は header_value() が None（標準ヘッダ無し）のときだけ使うこと。
    標準ヘッダがあるファイルでは表記ゆれを検査しない（検査から漏れていないため）。
    """
    for _, line in visible_lines(lines):
        for pattern in ALT_HEADER_RES:
            if pattern.match(line):
                return line.strip()
    return None


def has_checkbox(lines):
    """ファイル内（コードフェンス外）にチェックボックスが1つでもあるか"""
    return any(CHECKBOX_RE.match(line) for _, line in visible_lines(lines))


def completion_checkboxes(lines):
    """完了条件セクション内のチェックボックスを (行番号1始まり, checked, テキスト) で返す

    セクションは見出しから、同レベル以浅の次見出しまたは水平線 `---` まで。
    より深いサブ見出し（###〜）は境界とせず飲み込む（配下のチェックボックスも対象）。
    コードフェンス内の見出し・チェックボックスは例示として無視する。
    複数の完了条件セクションがあれば全て対象にする。
    """
    boxes = []
    section_level = None  # None = セクション外 / int = このレベル以浅の見出しで離脱
    for i, line in visible_lines(lines):
        m = SECTION_RE.match(line)
        if m:
            section_level = len(m.group(1))
            continue
        if section_level is not None:
            hm = re.match(r'^(#{1,6})\s', line)
            if (hm and len(hm.group(1)) <= section_level) or line.strip() == '---':
                section_level = None
                continue
            cm = CHECKBOX_RE.match(line)
            if cm:
                boxes.append((i + 1, cm.group(1) != ' ', cm.group(2).strip()))
    return boxes


def check_plan(path):
    global checked_files, exempt_files
    with open(path) as f:
        lines = f.read().splitlines()
    value = header_value(lines)
    if value is None:
        # ヘッダ無し（旧 Plan）は正当な対象外。ただし表記ゆれヘッダで状態を書いている
        # つもりの Plan（チェックボックス保有）は無言スキップにせず WARNING で拾う
        alt = alt_status_header(lines)
        if alt and has_checkbox(lines):
            warnings.append(
                f'WARNING: {path} — 状態ヘッダ「{alt}」は `## 実装状況:` 形式でないため'
                f'状態検査から漏れる。ヘッダを「## 実装状況:」に統一する'
            )
        exempt_files += 1
        return
    if not value.startswith('完了'):
        # 「一部完了」「未着手」等の中間状態は正当な対象外。
        # 「一部完了」は「完了」で始まらない（先頭は「一部」）ため、ここで除外される
        exempt_files += 1
        return
    boxes = completion_checkboxes(lines)
    if not boxes:
        # 完了条件がチェックボックス形式でない旧 Plan（素の箇条書き・セクション無し）
        old_style_skipped.append(path)
        return
    checked_files += 1
    unchecked = [(ln, text) for ln, done, text in boxes if not done]
    if unchecked:
        msg = [f'ERROR: {path} — 実装状況ヘッダ「{value}」に対し、'
               f'完了条件に未チェック項目が残っている:']
        msg += [f'    L{ln}: - [ ] {text}' for ln, text in unchecked]
        msg.append('    （実態に合わせてどちらかを直す: 残作業があるならヘッダを'
                   '「一部完了（残り: …）」へ / 実施済みならチェックを付ける。'
                   'フェーズ途中のマージは正常な運用 — ヘッダが残フェーズを語っていれば十分）')
        errors.append('\n'.join(msg))


for plans_dir in PLAN_DIRS:
    if not os.path.isdir(plans_dir):
        skips.append(f'SKIP: {plans_dir} が存在しない')
        continue
    for path in sorted(glob.glob(f'{plans_dir}/[0-9]*.md')):
        total_files += 1
        check_plan(path)

if old_style_skipped:
    skips.append(
        f'SKIP: 完了ヘッダだが完了条件がチェックボックス形式でない旧書式 Plan '
        f'{len(old_style_skipped)} 件は対象外（チェックボックス化は強制しない）: '
        + ', '.join(old_style_skipped)
    )

for msg in errors + warnings + skips:
    print(msg)

if errors:
    sys.exit(1)

if total_files == 0:
    print('NOTE: 検査対象 0 件 — リポジトリルートで実行しているか確認')

counts = (f'検査 {checked_files} 件 / 旧書式 SKIP {len(old_style_skipped)} 件 / '
          f'中間状態・ヘッダ無し対象外 {exempt_files} 件')
if warnings:
    print(f'WARNING: Plan 状態整合チェック — 表記ゆれヘッダ {len(warnings)} 件（{counts}）')
    sys.exit(2)
print(f'OK: Plan 状態整合チェック通過（{counts}）')
