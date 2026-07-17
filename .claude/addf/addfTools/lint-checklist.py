#!/usr/bin/env python3
"""チェックリスト裏付け検査 — 手順書の「確認/検証」ステップに裏付けがあるかを点検する

手順書のチェック項目には2種類ある:
- A型（機械検証可能な事実の主張）: 実行可能なチェック（コードブロック・コマンド）を伴うべき
- B型（人間・エージェントの判断）: `<!-- human-judgment -->` マーカーで明示すべき

どちらの裏付けもない「確認」ステップは、努力目標に堕ちて theater 化しやすく、
最悪の場合「構造上パス不可能な項目」（例: lock ファイルに自身を含むコミットの
ハッシュを書く確認 — 自己参照で原理的に不可能）が誰にも気づかれず残り続ける。

この lint は**エージェントの確認漏れを見つけるものではない**。手順書側が
「偽の確認をさせない裏付け」を持てているかの点検であり、WARNING が出たら
直すのは手順書のほう（A型なら実行コマンドを添える / B型ならマーカーを付ける /
アサーションが書けないと気づいたらその項目自体を設計し直す）。

判定ルール:
- ステップ = リスト項目行（ネスト含む全項目を個別に評価する。ブロック = その項目
  から次の同レベル以浅の項目・見出し・リスト外の平文/引用まで）
- 候補: 項目自身のテキスト（ソフトラップ継続行含む）に「確認」「検証」を含む。
  チェックリスト体の手順書（CHECKLIST_STYLE）では「〜こと」（行末、または
  ダッシュ・コロン等で説明が続く形）も候補
- 裏付けあり: ブロック内にフェンスコードブロック / 実行可能なインラインコマンド
  （bash/git/python3 等で始まる `...`、`/addf-*` スキル起動）/ human-judgment マーカー
- セクション除外: 見出し直下に `<!-- checklist-lint: skip-section -->` を置くと
  そのセクション（同レベル以浅の次の見出しまで。サブセクションを含む）を検査しない
  （チェックの実装そのもの・Gotchas 等の解説文はチェックリストではないため）
- ホワイトリスト: 裏付け形式に馴染まない既知の行を理由付きで除外する

対象ファイルが存在しない場合は SKIP する（ADDF 本体固有ファイルは
ダウンストリームに存在しないため、欠如は問題ではない）。

exit code: 0 = 裏付けあり / 2 = WARNING あり（ERROR 級はこの lint には無い）
"""
import os
import re
import sys

# 検査対象の手順書（「確認した」という主張を含むチェックリストを持つファイル）
TARGETS = [
    '.claude/addf/Release.addf.md',
    '.claude/commands/addf-init.md',
    '.claude/commands/addf-migrate.md',
    '.claude/commands/addf-plan-audit.md',
    '.claude/addf/templates/ProgressTemplate.addf.md',
    '.claude/addf/templates/ProgressTemplate.md',
]

# チェックリスト体（「〜こと」で項目が終わる書式）の手順書。「〜こと」行も候補にする
CHECKLIST_STYLE = {'.claude/addf/Release.addf.md'}

HUMAN_JUDGMENT = '<!-- human-judgment -->'
SKIP_SECTION = '<!-- checklist-lint: skip-section'

STEP_RE = re.compile(r'^(\s*)(?:\d+(?:\.\d+)*\.|[-*])\s+(.*)')
CANDIDATE_RE = re.compile(r'確認|検証')
# 「〜こと」: 行末のほか、ダッシュ・コロン・読点で説明が続く形も候補にする
# （行末アンカーのみだと「〜こと — 補足:」の形が候補から漏れる）
KOTO_RE = re.compile(r'こと(?:[。）)]?\s*$|\s*[—:：、])')
# 実行可能なインラインコマンド: コマンド名で始まる `...` またはスキル起動
INLINE_CMD_RE = re.compile(
    r'`(?:bash|sh|git|python3|python|grep|jq|diff|find|ls|test|\[)\s[^`]*`'
    r'|`/addf-[a-z-]+[^`]*`'
)

# 裏付け形式に馴染まない既知の行（strip 済み完全一致 → 理由）。増やすときは理由を必ず書く
WHITELIST = {
    # 引数の説明であり「確認した」という主張ではない
    '`check`: 構造検証（check モード）':
        'addf-init の引数説明。チェック項目ではない',
    # 再実行するコマンドの実体はステップ4とプロジェクト固有設定（CLAUDE.repo.md）が
    # 定義する。テンプレートはプロジェクト非依存のためコマンドをインラインできない
    '修正後、ビルド・Lint・テストを再実行して通過を確認する':
        'コマンド実体はステップ4と CLAUDE.repo.md が定義（テンプレートは非依存）',
}

warnings = []
skips = []


def line_attrs(lines):
    """各行の (コードフェンス内か, 除外セクション内か) を返す

    除外はマーカー直前の見出しレベルを起点とし、同レベル以浅の見出しで解除する
    （`## check モード` 直下のマーカーが `### チェック項目` サブセクションにも及ぶように）。
    """
    in_code = False
    skip_level = None  # None = 非除外 / int = このレベル以浅の見出しで解除
    heading_level = 0
    attrs = []
    for line in lines:
        if line.strip().startswith('```'):
            in_code = not in_code
            attrs.append((True, skip_level is not None))
            continue
        if not in_code:
            m = re.match(r'(#+)\s', line)
            if m:
                heading_level = len(m.group(1))
                if skip_level is not None and heading_level <= skip_level:
                    skip_level = None
            if SKIP_SECTION in line:
                if heading_level == 0:
                    # 見出しより前のマーカーはファイル末尾まで解除されない footgun
                    print('NOTICE: 見出しの無い位置の skip-section マーカーは'
                          'ファイル全体を除外します（配置を見直してください）',
                          file=sys.stderr)
                skip_level = heading_level
        attrs.append((in_code, skip_level is not None))
    return attrs


def step_blocks(lines, attrs):
    """全リスト項目（ネスト含む）について (行 index, ブロック行リスト) を列挙する

    ブロック終端は「見出し」「同レベル以浅のリスト項目」に加えて「項目のインデント
    以下に戻った平文・引用」でも打ち切る（リスト直後の無関係な解説文・引用ブロックを
    項目の裏付けとして誤計上しないため）。
    """
    blocks = []
    for i, line in enumerate(lines):
        code, skip = attrs[i]
        if code or skip:
            continue
        m = STEP_RE.match(line)
        if not m:
            continue
        indent = len(m.group(1))
        j = i + 1
        while j < len(lines):
            if not attrs[j][0]:  # フェンス外でのみブロック境界を判定
                if lines[j].startswith('#'):
                    break
                nm = STEP_RE.match(lines[j])
                if nm and len(nm.group(1)) <= indent:
                    break
                stripped = lines[j].strip()
                if (stripped and not nm
                        and len(lines[j]) - len(lines[j].lstrip()) <= indent):
                    break  # リスト外の平文・引用に出た
            j += 1
        blocks.append((i, lines[i:j]))
    return blocks


def own_text(block):
    """項目自身のテキスト（先頭行＋ソフトラップ継続行）を返す

    候補判定に使う。ネストした子項目・コードフェンス以降は含めない
    （子項目は独立に評価されるため）。
    """
    parts = [STEP_RE.match(block[0]).group(2)]
    for line in block[1:]:
        if line.strip().startswith('```') or STEP_RE.match(line):
            break
        parts.append(line.strip())
    return ' '.join(p for p in parts if p)


def check_file(path):
    if not os.path.exists(path):
        skips.append(f'SKIP: {path} が存在しない')
        return
    with open(path) as f:
        lines = f.read().splitlines()
    attrs = line_attrs(lines)
    issues = []
    for idx, block in step_blocks(lines, attrs):
        text = own_text(block)  # ソフトラップ継続行も候補判定に含める
        is_candidate = bool(CANDIDATE_RE.search(text)) or (
            path in CHECKLIST_STYLE and KOTO_RE.search(text))
        if not is_candidate:
            continue
        if STEP_RE.match(block[0]).group(2).strip() in WHITELIST:
            continue
        block_text = '\n'.join(block)
        has_code_fence = any(l.strip().startswith('```') for l in block[1:])
        has_inline_cmd = bool(INLINE_CMD_RE.search(block_text))
        has_marker = HUMAN_JUDGMENT in block_text
        if not (has_code_fence or has_inline_cmd or has_marker):
            issues.append(f'    L{idx + 1}: {text.strip()}')
    if issues:
        warnings.append(
            f'WARNING: {path} の以下の「確認/検証」ステップに裏付けがない\n'
            f'  （手順書側の点検です。A型=機械検証可能なら実行コマンドを添える /\n'
            f'   B型=人間判断なら {HUMAN_JUDGMENT} を付ける /\n'
            f'   アサーションが書けない項目は構造上通らない可能性があるので設計を見直す）:\n'
            + '\n'.join(issues)
        )


for target in TARGETS:
    check_file(target)

for msg in warnings + skips:
    print(msg)

if warnings:
    sys.exit(2)
print('OK: チェックリスト裏付け検査通過（対象: ' + ', '.join(
    os.path.basename(t) for t in TARGETS) + '）')
