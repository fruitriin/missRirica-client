#!/usr/bin/env python3
"""テンプレート同期チェック — 同期が必要なファイルペアのドリフトを検出する

ペア1: ProgressTemplate.addf.md ⇔ 運用中 Progress.md（運用ルールのテキスト包含・ERROR）
       ダウンストリームでは ProgressTemplate.md を正として比較する（`.addf.md` 版が
       配布・持ち込みで物理存在しても比較対象にしない — 存在≠所有）
ペア2: ProgressTemplate.addf.md ⇔ ProgressTemplate.md（正規化した運用ルールの相互比較・WARNING）
       ダウンストリームでは SKIP（同上の理由で `.addf.md` は所有物ではない）
ペア3: CLAUDE.md ⇔ AGENTS.md（ブートシーケンス手順番号の対応・WARNING）
       ダウンストリームでは SKIP（独自の AGENTS.md を持つプロジェクトで
       「ブートシーケンス見出しなし」を誤報するため）
ペア4: CLAUDE.md ⇔ .claude/addf/guides/development-process.md（ブートシーケンス概要手順番号の対応・WARNING）

ペア5: CLAUDE.md ⇔ addf-init.md コピーリスト（参照ファイルのカバレッジ・WARNING）
       CLAUDE.md が参照する .claude/ 配下のファイルが、addf-init の Phase 3
       コピーリスト（グロブ・ディレクトリ含む）または .gitignore の ADDF マーカー
       ブロック（実行時生成ファイル）でカバーされているかを検査する。
       カバー漏れは外部起動導入したダウンストリームでの参照切れになる。

ペア7: verify-checksums.sh detect_repo_kind() ⇔ lint-template-sync.py detect_repo_kind()
       （Python⇔Bash 実装の同期契約・WARNING）
       両ファイルの docstring/コメントに「同期契約」を示す固定文言（`lint-template-sync.py`
       側は「verify-checksums.sh の detect_repo_kind()」への参照、bash 側は
       「lint-template-sync.py の detect_repo_kind() と挙動を同期する契約」）があるかを
       存在チェックする。挙動そのものの比較は困難なため、契約が明示されていることを
       機械保証することでドリフト時のリファクタ意識を促す（Plan 0031 レビュー H3(a)(b)）。
       verify-checksums.sh が不在なダウンストリームでは SKIP。

ペア6: TODO ⇔ Plan 実装状況ヘッダ（状態の矛盾・参照切れ・登録漏れ・WARNING）
       TODO テーブルの状態列と各 Plan ファイルの `## 実装状況:` ヘッダを突合する。
       対象は ADDF 本体（.claude/addf/plans-add/TODO.addf.md ⇔ .claude/addf/plans-add/）と
       ダウンストリーム（TODO.md ⇔ .claude/addf/plans/）の2系統。
       ヘッダの無い Plan は検査しない（旧 Plan の欠如はドリフトではない）。
       ただし `## 状態:` 等の表記ゆれヘッダは「状態を書いているのに検査から漏れる」
       信頼モデルの穴になるため WARNING で形式統一を促す（Plan 0025 で顕在化）。
       エージェントが TODO の状態表記を「信用ベース」で扱えるようにする機械検査
       （.claude/addf/knowhow/ADDF/plan-status-drift-check.md 参照）。

ペア8: README.md / README.en.md のスキルテーブル ⇔ .claude/commands/addf-*.md（WARNING）
       ユーザー起動可能なスキル（`*.exp.md` を除く）が README の掲載から漏れていないかを
       検査する。新設スキルが README のドキュメント公開から漏れる（Plan 0036 の
       addf-plan-audit が未掲載のまま埋没した実例）を防ぐ。エージェント（.claude/agents/）は
       命名規則が不均一なため対象外（Plan 0053）。ダウンストリームは独自 README のため SKIP。

ペア2〜6・8 は対象ファイルが存在しない場合 SKIP する（ADDF 本体固有ファイルは
ダウンストリームプロジェクトに存在しないため、欠如はドリフトではない）。

upstream/downstream の判定はファイルの存在ではなく明示シグナルで行う（存在≠所有 —
配布によって `.addf.md` はダウンストリームにも物理存在しうる）:
1. 一次根拠: CLAUDE.repo.md の種別宣言。テンプレート書式（太字マーカー込みの
   `**ADDF 開発プロジェクト**` / `**ADDF 利用プロジェクト**`）に厳密一致させる。
   @メンション1段を解決し、コードフェンス（``` / ~~~）内の記述は除外する。
   両方の宣言がヒットした場合は判定不能として安全側に倒し、フォールバックへ委ねる
   （無条件の upstream 優先はしない）
2. フォールバック: .claude/addf/lock.json が存在すればダウンストリーム
3. どちらも判定不能（None）な場合のみ、従来のファイル存在フォールバックに委ねる
   （テストサンドボックス等、シグナルの無い環境の互換動作）。ただし判定不能を
   upstream と同一視しない — 旧配布のダウンストリーム（宣言なし・lock なし）で
   誤検知しうるペア1/ペア3 の ERROR は WARNING に格下げし、種別宣言または
   lock の整備を促すメッセージを併記する

downstream / 判定不能によりペアの検査対象を切り替え・SKIP するときは、silent にせず
`[N] SKIP: <理由（repo_kind）>` を stdout に出す（本体が誤って downstream 判定に
なった場合に SKIP 表示で気づけるフェイルセーフ）。

不一致の WARNING には git log による最終更新日ヒントを併記する
（どちらが新しいか＝どちらを正として同期すべきかの判断材料）。

exit code: 0 = 全一致 / 1 = ERROR あり / 2 = WARNING のみ
"""
import fnmatch
import glob
import os
import re
import subprocess
import sys
from collections import Counter

errors = []
warnings = []
skips = []


def extract_section(path, header_prefix):
    """header_prefix で始まる見出し行から、次の `## ` 見出しまたは水平線 `---` までの行リストを返す"""
    with open(path) as f:
        lines = f.read().splitlines()
    out, in_section, in_code = [], False, False
    for line in lines:
        if not in_section:
            if line.startswith(header_prefix):
                in_section = True
            continue
        if line.startswith('```'):
            in_code = not in_code
        if not in_code and (line.startswith('## ') or line.strip() == '---'):
            break
        out.append(line)
    return out if in_section else None


def last_commit_date(path):
    try:
        r = subprocess.run(
            ['git', 'log', '-1', '--format=%cs', '--', path],
            capture_output=True, text=True, timeout=10,
        )
        if r.returncode != 0:
            return '不明'
        return r.stdout.strip() or '未コミット'
    except Exception:
        return '不明'


def git_hint(path_a, path_b):
    return (f'    ヒント(最終更新): {path_a} = {last_commit_date(path_a)} / '
            f'{path_b} = {last_commit_date(path_b)}')


def _repo_declaration_lines(path, depth=0):
    """CLAUDE.repo.md のコードフェンス外の本文行を、@メンション1段まで解決して返す

    CLAUDE.repo.example.md は「ADDF 利用プロジェクト」への書き換え例をコードブロック内に
    持つため、コードフェンス（``` / ~~~ の両方）内は宣言として扱わない。
    ADDF 本体の CLAUDE.repo.md は `@CLAUDE.repo.example.md` 経由で種別宣言するため、
    @メンションを1段だけ解決する。

    解決仕様の注意:
    - @メンションは行全体が `@xxx.md` の形の場合のみ解決する（行中の @ 言及は対象外）
    - インラインコードスパン（単一バッククオート）内の言及は**除外されない**。
      宣言文言をドキュメント内で引用説明するときはコードフェンスで囲う運用とする
    - パストラバーサル耐性（Plan 0043 項目4）: `..` を含むパス・絶対パスは silent に無視する。
      同ディレクトリまたは配下のみ許可し、realpath で解決先がベースディレクトリ配下に
      収まることも検査する（シンボリックリンク経由の脱出防止）。bash 版の verify-checksums.sh
      detect_repo_kind() と同じガードを持つ契約（ペア7）
    """
    if depth > 1 or not os.path.exists(path):
        return []
    base_dir = os.path.dirname(os.path.realpath(path)) or os.getcwd()
    with open(path) as f:
        lines = f.read().splitlines()
    out, fence = [], None
    for line in lines:
        s = line.strip()
        if fence is None and (s.startswith('```') or s.startswith('~~~')):
            fence = s[:3]
            continue
        if fence is not None:
            if s.startswith(fence):
                fence = None
            continue
        m = re.match(r'@(\S+\.md)$', s)
        if m:
            inc = m.group(1)
            resolved = _safe_resolve_mention(inc, base_dir)
            if resolved is not None:
                out.extend(_repo_declaration_lines(resolved, depth + 1))
            continue
        out.append(line)
    return out


def _safe_resolve_mention(inc, base_dir):
    """@メンションのパストラバーサル耐性ガード（Plan 0043 項目4）

    受け入れ条件（全て満たすこと）:
      1. 絶対パスでない（`/` 始まり不可）
      2. パスコンポーネントに `..` を含まない
      3. realpath 解決後が base_dir 配下に収まる（シンボリックリンク経由の脱出防止）
      4. ファイルが実在する

    受け入れ拒否時は None を返す（silent — 宣言なしと同じ扱い）。
    """
    if not inc or inc.startswith('/'):
        return None
    parts = inc.split('/')
    if '..' in parts:
        return None
    candidate = os.path.join(base_dir, inc)
    if not os.path.isfile(candidate):
        return None
    resolved = os.path.realpath(candidate)
    base_real = os.path.realpath(base_dir)
    # base_dir/ 配下（末尾セパレータを付与して境界一致を防ぐ）
    if not (resolved == base_real or resolved.startswith(base_real + os.sep)):
        return None
    return resolved


# 判定不能（repo_kind=None）時に ERROR を格下げした WARNING に添える促しメッセージ
KIND_UNKNOWN_HINT = (
    'upstream/downstream を判定できないため WARNING に格下げ。'
    'ダウンストリームなら CLAUDE.repo.md に種別宣言'
    '（このリポジトリは **ADDF 利用プロジェクト** です。）を書くか、'
    '.claude/addf/lock.json を配置する'
)


def detect_repo_kind():
    """'upstream' / 'downstream' / None（判定不能）を返す

    同期契約: verify-checksums.sh の detect_repo_kind()（bash 実装）と挙動を同期する契約。
    判定仕様（一次: CLAUDE.repo.md の種別宣言＋@メンション1段解決／フォールバック:
    addf-lock.json）を変えるときは bash 側も同時に更新する。契約文言の存在は
    check_pair7 で機械保証している（Plan 0031 レビュー H3）。

    ファイルの存在（ProgressTemplate.addf.md 等）で判定しない — 存在≠所有。
    一次根拠: CLAUDE.repo.md の種別宣言。テンプレートが実際に生成する書式
    （太字マーカー込みの `**ADDF 開発プロジェクト**` / `**ADDF 利用プロジェクト**`）に
    正規表現で厳密一致させ、地の文の言及（「ADDF 開発プロジェクトではありません」
    「かつて ADDF 開発プロジェクトとして始まり…」等）では判定しない。
    upstream/downstream の**両方**がヒットした場合は判定不能（安全側）として
    フォールバックに委ねる — 無条件の upstream 優先はしない。
    フォールバック: addf-lock.json が存在すればダウンストリーム。

    この優先順位・書式マッチは以下に依存する:
    1. addf-init（カテゴリ3）が CLAUDE.repo.md に種別宣言を**太字マーカー込みで直書き**
       すること（@メンションで CLAUDE.repo.example.md に継承させない）
    2. @メンションは行全体が `@xxx.md` の形のみ解決される（_repo_declaration_lines 参照）
    3. インラインコードスパン（単一バッククオート）内の言及は除外されない —
       宣言文言を引用説明する際はコードフェンス（``` / ~~~）を使う運用
    """
    text = '\n'.join(_repo_declaration_lines('CLAUDE.repo.md'))
    kinds = set(re.findall(r'\*\*ADDF (開発|利用)プロジェクト\*\*', text))
    if len(kinds) == 1:
        return 'upstream' if '開発' in kinds else 'downstream'
    # len(kinds) == 2 は宣言の混在（判定不能・安全側）。0 は宣言なし。いずれも lock に委ねる
    if os.path.exists('.claude/addf/lock.json'):
        return 'downstream'
    return None


def check_pair1(repo_kind):
    """テンプレートの運用ルールが Progress.md に全て含まれているか（ERROR）

    **検査範囲の境界**（Plan 0046 明文化）: 検査対象は `## 運用ルール` セクション
    （`## タスク` の直前まで）に限定する。`## タスク` 以降（現在のタスク・チェックリスト・
    日記）は親エージェントが管理する進行中領域であり、テンプレートとの同期対象外。
    委譲エージェントは運用ルール節をテンプレートに合わせて同一差分で更新してよい
    （委譲プロンプトの禁止事項テンプレートは `.claude/addf/templates/DelegationRules.md`）。

    repo_kind=None（宣言なし・lock なし = 旧配布ダウンストリームの可能性）で
    `.addf.md` を比較対象にした場合の乖離は、誤検知の可能性があるため
    WARNING に格下げして種別宣言/lock の整備を促す（判定不能を upstream と同一視しない）。
    """
    addf_tmpl = '.claude/addf/templates/ProgressTemplate.addf.md'
    tmpl_path = addf_tmpl
    kind_unknown = False
    if repo_kind == 'downstream' or not os.path.exists(addf_tmpl):
        if repo_kind == 'downstream' and os.path.exists(addf_tmpl):
            skips.append(
                f'[1] SKIP: repo_kind=downstream のため {addf_tmpl} を比較対象にしない'
                f'（物理存在しても配布物 — ProgressTemplate.md を正として検査する）'
            )
        # ダウンストリームでは無印版が正（.addf.md が物理存在しても配布物のため比較しない）
        tmpl_path = '.claude/addf/templates/ProgressTemplate.md'
    elif repo_kind is None:
        kind_unknown = True
    prog_path = '.claude/addf/Progress.md'
    if not os.path.exists(tmpl_path) or not os.path.exists(prog_path):
        skips.append(f'[1] SKIP: {tmpl_path} または {prog_path} が存在しない')
        return
    tmpl = extract_section(tmpl_path, '## 運用ルール')
    prog = extract_section(prog_path, '## 運用ルール')
    if tmpl is None or prog is None:
        errors.append(f'[1] ERROR: {tmpl_path} または {prog_path} に「## 運用ルール」が見つからない')
        return
    prog_text = '\n'.join(prog)
    missing = [s for s in (line.strip() for line in tmpl) if s and s not in prog_text]
    if missing:
        if kind_unknown:
            msg = [f'[1] WARNING: {prog_path} の運用ルールがテンプレート（{tmpl_path}）と乖離'
                   f'（{KIND_UNKNOWN_HINT}）:']
            msg += [f'    MISSING: {m}' for m in missing]
            warnings.append('\n'.join(msg))
            return
        msg = [f'[1] ERROR: {prog_path} の運用ルールがテンプレート（{tmpl_path}）と乖離（テンプレートを正として同期する）:']
        msg += [f'    MISSING: {m}' for m in missing]
        errors.append('\n'.join(msg))


def check_pair2(repo_kind):
    """ProgressTemplate.addf.md ⇔ ProgressTemplate.md の運用ルールを正規化して相互比較（WARNING）"""
    addf_path = '.claude/addf/templates/ProgressTemplate.addf.md'
    down_path = '.claude/addf/templates/ProgressTemplate.md'
    if repo_kind == 'downstream':
        skips.append(f'[2] SKIP: repo_kind=downstream のため対象外（{addf_path} が物理存在しても配布物のため比較しない）')
        return
    if not os.path.exists(addf_path) or not os.path.exists(down_path):
        skips.append(f'[2] SKIP: {addf_path} がない（ダウンストリームでは対象外）')
        return
    addf = extract_section(addf_path, '## 運用ルール')
    down = extract_section(down_path, '## 運用ルール')
    if addf is None or down is None:
        errors.append(f'[2] ERROR: {addf_path} または {down_path} に「## 運用ルール」が見つからない')
        return

    # ペア2専用ホワイトリスト: ADDF 版にのみ存在してよい意図的差分（strip 済みで比較）
    whitelist_addf_only = {
        '- ADD フレームワークテスト: `bash .claude/addf/tests/run-all.sh`',
    }

    def normalize(lines, is_addf):
        out = []
        for line in lines:
            s = line.strip()
            if not s:
                continue
            if is_addf and s in whitelist_addf_only:
                continue
            # テンプレート自己参照パスは意図的差分のため正規化して比較する
            out.append(s.replace('ProgressTemplate.addf.md', 'ProgressTemplate.md'))
        return out

    addf_count = Counter(normalize(addf, True))
    down_count = Counter(normalize(down, False))
    only_addf = list((addf_count - down_count).elements())
    only_down = list((down_count - addf_count).elements())
    if only_addf or only_down:
        msg = [f'[2] WARNING: {addf_path} と {down_path} の運用ルールが乖離:']
        msg += [f'    ADDF版のみ: {s}' for s in only_addf]
        msg += [f'    ダウンストリーム版のみ: {s}' for s in only_down]
        msg.append(git_hint(addf_path, down_path))
        warnings.append('\n'.join(msg))


def boot_steps(path, header_prefix):
    """ブートシーケンスの手順番号列を抽出する（トップレベル: `N. ` / 枝番: `- N.M. `）"""
    section = extract_section(path, header_prefix)
    if section is None:
        return None
    steps = []
    for line in section:
        m = re.match(r'(\d+)\.\s', line)  # 行頭アンカーで入れ子リストを除外
        if m:
            steps.append(m.group(1))
            continue
        m = re.match(r'\s*-\s*(\d+\.\d+)\.\s', line)
        if m:
            steps.append(m.group(1))
    return steps


def check_boot_pair(pair_no, base, base_header, other, other_header, label,
                    downgrade_missing_header=False):
    """downgrade_missing_header: repo_kind=None（判定不能）のとき True。
    見出し不在の ERROR を WARNING に格下げする（旧配布ダウンストリームの
    独自 AGENTS.md で誤検知しうるため — 判定不能を upstream と同一視しない）。
    """
    if not os.path.exists(base) or not os.path.exists(other):
        missing = base if not os.path.exists(base) else other
        skips.append(f'[{pair_no}] SKIP: {missing} が存在しない')
        return
    base_steps = boot_steps(base, base_header)
    other_steps = boot_steps(other, other_header)
    if base_steps is None or other_steps is None:
        missing = base if base_steps is None else other
        if downgrade_missing_header:
            warnings.append(
                f'[{pair_no}] WARNING: {missing} にブートシーケンス見出しが見つからない'
                f'（{KIND_UNKNOWN_HINT}）'
            )
        else:
            errors.append(f'[{pair_no}] ERROR: {missing} にブートシーケンス見出しが見つからない')
        return
    if base_steps != other_steps:
        warnings.append(
            f'[{pair_no}] WARNING: {label} の手順番号が対応していない:\n'
            f'    {base} = {", ".join(base_steps)}\n'
            f'    {other} = {", ".join(other_steps)}\n'
            + git_hint(base, other)
        )


def claude_md_references(path):
    """CLAUDE.md が @メンション/バッククオートで参照する .claude/ 配下のファイルパスを返す

    コードブロック内は例示パスの可能性があるため除外する。
    検査対象を CLAUDE.md に限定するのは意図的: CLAUDE.repo.example.md や
    テンプレート群が参照するファイルは `.claude/addf/templates/` 等のディレクトリ丸ごと
    コピーでカバーされるため、参照切れの主リスクは CLAUDE.md 直下参照に集中する。
    """
    with open(path) as f:
        lines = f.read().splitlines()
    refs = set()
    in_code = False
    for line in lines:
        if line.strip().startswith('```'):
            in_code = not in_code
            continue
        if in_code:
            continue
        # @.claude/addf/Feedback.md 形式（@メンション）
        refs.update(re.findall(r'@(\.claude/[^\s`]+\.\w+)', line))
        # `.claude/addf/Questions.md` 形式（バッククオート内・拡張子付きファイルのみ）
        refs.update(re.findall(r'`(\.claude/[^\s`]+\.\w+)`', line))
    return sorted(refs)


def gitignore_addf_block(path):
    """マーカーブロック `# --- ADDF Framework ---` 〜 `# --- /ADDF Framework ---` 内のエントリを返す"""
    if not os.path.exists(path):
        return []
    with open(path) as f:
        lines = f.read().splitlines()
    out, in_block = [], False
    for line in lines:
        s = line.strip()
        if s.startswith('# --- /ADDF Framework'):  # 重複ブロックにも対応するため break しない
            in_block = False
            continue
        if s.startswith('# --- ADDF Framework'):
            in_block = True
            continue
        if in_block and s and not s.startswith('#'):
            out.append(s)
    return out


def check_pair5():
    """CLAUDE.md が参照する .claude/ 配下ファイルが addf-init コピーリストでカバーされているか（WARNING）"""
    claude_path = 'CLAUDE.md'
    init_path = '.claude/commands/addf-init.md'
    if not os.path.exists(claude_path) or not os.path.exists(init_path):
        missing = claude_path if not os.path.exists(claude_path) else init_path
        skips.append(f'[5] SKIP: {missing} が存在しない')
        return
    refs = claude_md_references(claude_path)
    with open(init_path) as f:
        init_text = f.read()
    # addf-init.md 本文中のバッククオートパス（コピーリストのエントリ。グロブ・ディレクトリ含む）
    # `.claude/` 単体（Phase 1 の状態判定で言及されるルート）はコピーエントリではないため除外
    init_entries = set(re.findall(r'`(\.claude/[^\s`]+)`', init_text)) - {'.claude/'}
    # .gitignore の ADDF マーカーブロック（実行時生成ファイルはコピー対象外として正当）
    ignore_entries = gitignore_addf_block('.gitignore')

    def covered(ref):
        if ref in init_entries:
            return True
        for entry in init_entries:
            if entry.endswith('/') and ref.startswith(entry):  # ディレクトリ丸ごとコピー
                return True
            if '*' in entry and fnmatch.fnmatch(ref, entry):  # グロブ指定
                return True
        for entry in ignore_entries:
            if entry.endswith('/') and ref.startswith(entry):
                return True
            if fnmatch.fnmatch(ref, entry):
                return True
        return False

    uncovered = [r for r in refs if not covered(r)]
    if uncovered:
        msg = [f'[5] WARNING: {claude_path} が参照する以下のファイルが {init_path} の'
               f'コピーリスト・.gitignore ADDF ブロックのいずれでもカバーされていない'
               f'（外部起動導入したダウンストリームで参照切れになる。'
               f'オーナー独自の参照であれば、コピー手段を確保した上で意図的に無視してよい）:']
        msg += [f'    UNCOVERED: {r}' for r in uncovered]
        msg.append(git_hint(claude_path, init_path))
        warnings.append('\n'.join(msg))


def plan_header_status(path):
    """Plan ファイルの `## 実装状況:` ヘッダから状態を正規化して返す（無ければ None）

    「完了（2026-06-10、PR #11）」のような注記付き表記は先頭語で判定する。
    完了/未着手 以外（進行中等の中間状態）は矛盾判定の対象外として None 扱い。
    """
    with open(path) as f:
        for line in f.read().splitlines():
            m = re.match(r'##\s*実装状況[:：]\s*(\S+)', line)  # コロンは半角・全角とも許容
            if m:
                value = m.group(1)
                for status in ('完了', '未着手'):
                    if value.startswith(status):
                        return status
                return None
    return None


def plan_nonstandard_header(path):
    """`## 実装状況:` ではない状態系ヘッダ（`## 状態:` 等の表記ゆれ）を返す（無ければ None）

    表記ゆれヘッダは plan_header_status() が「ヘッダ無し」として黙ってスキップするため、
    状態を書いているつもりの Plan が機械検査から漏れる。検出して形式統一を促す。
    """
    pattern = re.compile(r'##\s*(状態|ステータス|進捗|status)\s*[:：]', re.IGNORECASE)
    with open(path) as f:
        for line in f.read().splitlines():
            if pattern.match(line):
                return line.strip()
    return None


# TODO テーブル内で Plan ファイルへ言及する記法は2種類ある（Issue #31）:
#   - バックティック書式: `.claude/addf/plans/xxx.md`（ADDF 本体のデフォルト）
#   - Markdown リンク書式: [Plan タイトル](.claude/addf/plans/xxx.md)
#     （clickable リンク化のためダウンストリームで広く採用される。Plan 0006 → v0.6 系 migrate
#      で上書き失効 → 再適用のループを経て、上流本体でも両書式を受理する方針を採用）
# 両分岐は `|` で排他的なため `m.group(1) or m.group(2)` は必ず非 None 文字列を返す。
# バックティック分岐の (?!\]\() は「[`path`](href) のようにリンクタイトル内へパスを
# 併記した行」でタイトル側（古い表記でありうる）を拾わず href 側を採用するための除外
# （code-review M-2: re.search の左優先でタイトル側が勝ってしまう問題への対処）
TODO_PLAN_PATH_RE = re.compile(
    r'`(\.claude/addf/plans[^`]*?\.md)`(?!\]\()'
    r'|\]\((\.claude/addf/plans[^)]*?\.md)\)'
)


def todo_table_rows(path):
    """TODO のテーブル行から (Plan パス, 状態, 行テキスト) のリストを返す

    「状態」列の位置はヘッダ行から動的に特定する（バックログとアーカイブで
    列構成が異なり、将来の列追加にも備えるため）。ヘッダ未検出時は末尾セルに
    フォールバックする。

    Plan ファイル参照はバックティック書式と markdown リンク書式の両方を受理する
    （Issue #31 現象1・下流実装済みの対処を上流反映）。
    """
    with open(path) as f:
        lines = f.read().splitlines()
    rows = []
    status_idx = -1
    for line in lines:
        if not line.lstrip().startswith('|'):
            continue
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if '状態' in cells:  # ヘッダ行。以降のデータ行にこの列位置を適用する
            status_idx = cells.index('状態')
            continue
        m = TODO_PLAN_PATH_RE.search(line)
        if not m:
            continue
        plan_path = m.group(1) or m.group(2)
        status = cells[status_idx] if -1 < status_idx < len(cells) else cells[-1]
        rows.append((plan_path, status, line.strip()))
    return rows


def check_pair7():
    """verify-checksums.sh の detect_repo_kind() と本ファイルの detect_repo_kind() の
    同期契約が両ファイルの docstring/コメントに明示されているかを検査する（WARNING）

    挙動そのものの比較は困難（言語が異なる）なため、契約文言の存在を機械保証することで
    実装差分を発見しやすくする。ダウンストリームで verify-checksums.sh が無ければ SKIP。
    """
    verify_path = '.claude/addf/addfTools/verify-checksums.sh'
    self_path = '.claude/addf/addfTools/lint-template-sync.py'
    if not os.path.exists(verify_path):
        skips.append(f'[7] SKIP: {verify_path} が存在しない（ダウンストリームでは対象外）')
        return
    if not os.path.exists(self_path):
        skips.append(f'[7] SKIP: {self_path} が存在しない')
        return
    with open(verify_path) as f:
        vtext = f.read()
    with open(self_path) as f:
        stext = f.read()
    # bash 側の契約文言（verify-checksums.sh 内に必ず1回以上出現すること）
    bash_contract = 'lint-template-sync.py の detect_repo_kind() と挙動を同期する契約'
    # Python 側の契約文言（lint-template-sync.py 内に必ず1回以上出現すること）
    py_contract = 'verify-checksums.sh の detect_repo_kind()'
    issues = []
    if bash_contract not in vtext:
        issues.append(
            f'    {verify_path} に同期契約の明示が無い（追加すべき文言: '
            f'「{bash_contract}」）'
        )
    if py_contract not in stext:
        issues.append(
            f'    {self_path} に同期契約の明示が無い（追加すべき文言: '
            f'「{py_contract}」）'
        )
    if issues:
        msg = [f'[7] WARNING: verify-checksums.sh / lint-template-sync.py の '
               f'detect_repo_kind() 同期契約が明示されていない '
               f'（片方の実装を変更したときにもう片方の更新が漏れる）:']
        msg += issues
        warnings.append('\n'.join(msg))


def check_pair6():
    """TODO の状態列 ⇔ Plan の実装状況ヘッダの突合（WARNING）

    完了⇔未着手の明確な矛盾のみ flag する（中間状態は誤検出回避のため対象外）。
    加えて TODO が指す Plan の不在と、Plan の TODO 登録漏れを検出する。
    """
    targets = [
        ('.claude/addf/plans-add/TODO.addf.md', '.claude/addf/plans-add'),
        ('TODO.md', '.claude/addf/plans'),
    ]
    for todo_path, plans_dir in targets:
        if not os.path.exists(todo_path):
            skips.append(f'[6] SKIP: {todo_path} が存在しない')
            continue
        rows = todo_table_rows(todo_path)
        listed = set()
        issues = []
        for plan_path, todo_status, _ in rows:
            listed.add(plan_path)
            if not os.path.exists(plan_path):
                issues.append(f'    不在: {todo_path} が参照する {plan_path} が存在しない')
                continue
            header = plan_header_status(plan_path)
            if header is None:
                variant = plan_nonstandard_header(plan_path)
                if variant:
                    issues.append(
                        f'    表記ゆれ: {plan_path} のヘッダ「{variant}」は'
                        f' `## 実装状況:` 形式でないため状態検査から漏れる（形式を統一する）'
                    )
                continue  # ヘッダ無し・中間状態は信用ベースで検査しない
            # こちらの None は「TODO の状態列が完了/未着手以外（要確認等）」の意。
            # header 側の None（ヘッダ不在・中間状態）とは起源が異なるが、扱いは同じく検査対象外
            todo_norm = next((s for s in ('完了', '未着手') if todo_status.startswith(s)), None)
            if todo_norm and header != todo_norm:
                issues.append(
                    f'    矛盾: {plan_path} のヘッダ「{header}」⇔ {todo_path} の状態「{todo_status}」'
                )
        if os.path.isdir(plans_dir):
            for plan_path in sorted(glob.glob(f'{plans_dir}/[0-9]*.md')):
                if plan_path not in listed:
                    issues.append(f'    登録漏れ: {plan_path} が {todo_path} のテーブルにない')
        if issues:
            warnings.append(
                f'[6] WARNING: {todo_path} と Plan ファイルの状態がドリフト'
                f'（完了処理の反映漏れを疑い、実態を確認して同期する）:\n'
                + '\n'.join(issues)
            )


def check_pair8(repo_kind):
    """.claude/commands/addf-*.md（*.exp.md 除く）が README.md / README.en.md の
    スキルテーブルに掲載されているかを検査する（WARNING）

    新設スキルが README のドキュメント公開から漏れる（Plan 0036 の addf-plan-audit が
    未掲載のまま埋没した実例）を防ぐ。対象はユーザー起動可能なスキルのみ:
    - `.claude/agents/` のエージェント定義は対象外（`addf-implementer` が `-agent` 接尾辞を
      持たない・`addf-ui-test-agent` は README にのみ存在するプレースホルダ等、命名規則が
      不均一で自動判定の誤検知リスクが高いため。`checklist-backing-lint.md` の
      「裏付けの弱いチェックは追加しない」方針に沿う判断）
    - ダウンストリームは独自 README を持つため対象外（SKIP）
    """
    if repo_kind != 'upstream':
        skips.append('[8] SKIP: repo_kind != upstream のため対象外（ダウンストリームは独自 README）')
        return
    commands_dir = '.claude/commands'
    if not os.path.isdir(commands_dir):
        skips.append(f'[8] SKIP: {commands_dir} が存在しない')
        return
    skill_names = sorted(
        os.path.splitext(os.path.basename(p))[0]
        for p in glob.glob(f'{commands_dir}/addf-*.md')
        if not p.endswith('.exp.md')
    )
    for readme_path in ('README.md', 'README.en.md'):
        if not os.path.exists(readme_path):
            skips.append(f'[8] SKIP: {readme_path} が存在しない')
            continue
        with open(readme_path) as f:
            text = f.read()
        listed = set(re.findall(r'\*\*(addf-[a-z0-9-]+)\*\*', text))
        missing = [s for s in skill_names if s not in listed]
        if missing:
            msg = [f'[8] WARNING: {readme_path} のスキルテーブルに未掲載のスキルがある'
                   f'（{commands_dir} には存在するが README のドキュメント公開から漏れている）:']
            msg += [f'    MISSING: {m}' for m in missing]
            warnings.append('\n'.join(msg))


repo_kind = detect_repo_kind()
check_pair1(repo_kind)
check_pair2(repo_kind)
if repo_kind == 'downstream':
    # 独自 AGENTS.md（ADDF ブートシーケンス見出しなし）を持つプロジェクトでの誤報を防ぐ
    skips.append('[3] SKIP: repo_kind=downstream のため対象外（AGENTS.md は独自ファイルの可能性がある）')
else:
    # repo_kind=None（判定不能）は upstream と同一視せず、見出し不在の ERROR を WARNING に格下げ
    check_boot_pair(3, 'CLAUDE.md', '## ブートシーケンス',
                    'AGENTS.md', '## Boot Sequence',
                    'CLAUDE.md ⇔ AGENTS.md ブートシーケンス',
                    downgrade_missing_header=(repo_kind is None))
check_boot_pair(4, 'CLAUDE.md', '## ブートシーケンス',
                '.claude/addf/guides/development-process.md', '## ブートシーケンス',
                'CLAUDE.md ⇔ development-process.md ブートシーケンス概要')
check_pair5()
check_pair6()
check_pair7()
check_pair8(repo_kind)

for msg in errors + warnings + skips:
    print(msg)

if errors:
    sys.exit(1)
if warnings:
    sys.exit(2)
print('OK: 同期チェック通過 (1: Progress.md / 2: ProgressTemplate / 3: AGENTS.md / 4: development-process.md / 5: addf-init コピーリスト / 6: TODO⇔Plan 状態 / 7: verify-checksums.sh detect_repo_kind 同期契約 / 8: README スキルテーブル網羅性)')
