#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# ///
"""Plan 0037 パス移行 — paths.toml（単一ソース）駆動の移動＋参照書き換え

使い方（リポジトリルートで実行する。ルート以外の cwd では ERROR）:
  uv run --python 3.11 migrate-paths.py [check]   # 既定。何も変更しない
  uv run --python 3.11 migrate-paths.py apply     # backup ref 作成 → git mv 一括実行
  uv run --python 3.11 migrate-paths.py rewrite   # 旧パス参照を新パスへ書き換え
  （uv が無ければ python3（3.11+）で直接実行する）

モード:
  check   移動対象の実在・移動先の衝突・旧パス参照の全数（ファイル数・箇所数）と
          マッチ例（rewrite 前の誤爆候補の目視確認用）を提示するのみ。
          移動対象が1件以上あるときは末尾に「射程外候補スキャン」（rewrite が
          書き換えられない4類型の候補列挙・WARNING のみ）を実行する。
          exit 0 = 実行可能 / 1 = ブロッカーあり（射程外候補は成否に影響しない）
  apply   作業ツリーが clean であることを確認し、backup ref
          （paths.toml [meta].backup_ref）を作成してから git mv をまとめて実行する。
          既存の backup ref は上書きしない（「本当の移行前」の巻き戻し点を
          静かに失わないため ERROR で拒否する）。
          コミットは**しない** — git mv コミットと参照書き換えコミットを分離できる
          ように、コミットは呼び出し側の責務とする（revert 一発で戻せる原子性）
  rewrite 全 git 追跡テキストファイルの旧パス参照を新パスに書き換える。
          apply 分のコミット後に実行する（dirty なら拒否）。
          apply 未実施（[meta].new_root 不在）の場合も ERROR で拒否する —
          参照だけが実在しないパスへ一括で書き換わる事故を防ぐ

走査対象（check の参照数と rewrite の書き換えで共通。lint-residual-paths.py の
検査対象とも一致させる — check「0箇所」なのに lint で初めて ERROR になる不一致を
作らない）:
  全 git 追跡ファイルのうちテキストのもの。バイナリは NUL バイト検査＋
  UTF-8 デコード失敗で除外する（拡張子に依存しない — Makefile / Dockerfile /
  拡張子なしスクリプトも対象に入る）。**symlink は除外する** — git は symlink を
  blob として追跡するため、open() で辿るとリンク先（リポジトリ外でもよい）を
  読み書きしてしまう（リポジトリ外書き込みの攻撃経路になる）。
  行内に EXCLUSION_MARKER（residual-path: allow）を含む行は集計・書き換え・
  検査の全てでスキップする（移行手順書等の正当な旧パス言及行の行単位除外）。

境界チェック:
  `docs/plans` の置換が `docs/plans-add` に誤マッチしない等のため、長いキーから
  順に置換し、置換対象の前後が英数字・ハイフン・アンダースコアの場合は置換しない。
  さらに Issue #33 対応で、直前2文字が「英数字 + `/`」の場合（外部 URL
  `example.com/docs/guides` や他プロジェクト絶対パス `~/workspace/OTHER/docs/knowhow` <!-- residual-path: allow -->
  の内部）は残存扱いしない — rewrite が URL を書き換えて壊すのを防ぐ。ただし
  「/ + このリポジトリのディレクトリ名 + /」が直前にある場合は例外として検出する。
  この境界規則は lint-residual-paths.py の検出規則と同一に保つ（同期契約:
  lint-residual-paths.py の compile_pattern() と挙動を同期する）。

存在≠所有:
  docs/ は paths.toml の ADDF 管理サブディレクトリ単位でのみ移動する。
  docs/ 直下のその他ファイル（GitHub Pages コンテンツ等）はマップに載っておらず、
  本スクリプトは一切触れない。

exit code: 0 = OK / 1 = ERROR（拒否・失敗）
"""
import os
import re
import shutil
import subprocess
import sys

try:
    import tomllib
except ModuleNotFoundError:
    # 変更系スクリプトのため ERROR 類型（実行できていないのに成功を装わない）
    print(f'ERROR: tomllib がありません（Python {sys.version.split()[0]}）。'
          '`uv run --python 3.11` または Python 3.11+ で実行してください')
    sys.exit(1)

# paths.toml の探索先（移行後の新位置を優先し、移行前の旧位置にフォールバック）
MAP_CANDIDATES = [
    '.claude/addf/addfTools/paths.toml',
    '.claude/addfTools/paths.toml',
]

# 行単位の除外マーカー。この文字列を行内に含む行は check の参照集計・rewrite の
# 書き換え・射程外候補スキャン・lint-residual-paths.py の検査の全てでスキップされる
# （コメント形式は問わない — `<!-- residual-path: allow -->` でも
# `# residual-path: allow` でも行内一致で判定する）。
# 移行手順書・移行ガイド（addf-migrate.md / addf-init.md / CHANGELOG.md）が正当に
# 含む旧パス言及行に付ける。ファイル丸ごとの除外（rewrite_exclusions）は
# そのファイル全体が lint の永久盲点になるため、ドキュメントには使わない
# （同期契約: lint-residual-paths.py の EXCLUSION_MARKER と同一に保つ）
EXCLUSION_MARKER = 'residual-path: allow'

# check のマッチ例表示の上限（旧パスごと）と1行の最大表示幅
SAMPLE_LIMIT = 3
SAMPLE_WIDTH = 100

# 走査するテキストファイルのサイズ上限。超過したファイルは読み込まずスキップし、
# 走査後に件数付きで手動確認を案内する（巨大ファイルでの実行時間・メモリの爆発防止。
# 実測: 392MB のテキストで check 67秒 / RSS 1.35GB — attacker 指摘。
# 同期契約: lint-residual-paths.py の MAX_TEXT_BYTES と同一に保つ）
MAX_TEXT_BYTES = 5 * 1024 * 1024
SIZE_SKIPPED = set()  # サイズ超過でスキップしたパス（重複走査があるため set）


def run_git(*args, check=False):
    r = subprocess.run(['git', *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        print(f'ERROR: git {" ".join(args)} が失敗: {r.stderr.strip()}')
        sys.exit(1)
    return r


def ensure_repo_root():
    """cwd が git リポジトリのルートであることを検証する（相対パス前提の誤動作防止）"""
    r = run_git('rev-parse', '--show-toplevel')
    if r.returncode != 0:
        print('ERROR: git リポジトリ内で実行してください')
        sys.exit(1)
    top = os.path.realpath(r.stdout.strip())
    cwd = os.path.realpath(os.getcwd())
    if top != cwd:
        print(f'ERROR: リポジトリルートで実行してください（cwd: {cwd} / ルート: {top}）')
        sys.exit(1)


def entries(cfg):
    """dirs → files → dynamic の順で (entry, kind) を返す"""
    for e in cfg.get('dirs', []):
        yield e, 'dir'
    for e in cfg.get('files', []):
        yield e, 'file'
    for e in cfg.get('dynamic', []):
        yield e, 'dynamic'


def validate_map(cfg):
    """マップの軽量整合チェック: immovable と移動エントリの old が重複していないこと"""
    olds = {e['old'] for e, _ in entries(cfg)}
    immovable = set(cfg.get('immovable', {}).get('paths', []))
    dup = sorted(olds & immovable)
    if dup:
        print(f'ERROR: paths.toml の不整合 — immovable と移動エントリ（old）が重複: {dup}')
        sys.exit(1)


def load_map():
    """paths.toml を読み、(設定 dict, 読み込み元パス) を返す。無ければ ERROR 終了"""
    for path in MAP_CANDIDATES:
        if os.path.exists(path):
            with open(path, 'rb') as f:
                cfg = tomllib.load(f)
            validate_map(cfg)
            return cfg, path
    print(f'ERROR: paths.toml が見つかりません（探索先: {", ".join(MAP_CANDIDATES)}）。'
          'リポジトリルートで実行してください')
    sys.exit(1)


def compile_pattern(old):
    """境界チェック付きの置換パターン。

    前後が英数字・ハイフン・アンダースコアなら別トークンの一部とみなして
    マッチしない（`docs/plans` が `docs/plans-add` や `docs/plans-addendum` の
    内部に誤マッチしない）。`/`・`@`・バッククオート・行頭行末は境界として許容する。

    Issue #33 対応: 直前2文字が「英数字 + `/`」の場合は別のパス階層の内部
    （外部 URL の `example.com/docs/guides` や他プロジェクト絶対パスの
    `~/workspace/OTHER/docs/knowhow` 等）とみなしてマッチしない。旧パスは
    リポジトリルート相対のため、こうした埋め込み位置は本物の残存ではない。
    ただし例外として「/ + このリポジトリのディレクトリ名 + /」が直前にある場合
    （自リポジトリへの絶対パス参照）は本物の残存として検出する
    （検出漏れを避けるための例外 — cwd はリポジトリルート強制済み）。
    既知の限界: 別名で clone された複製（例: リポジトリ名 `foo` を `bar` として
    clone した先）への絶対パス参照は検出できない。実運用では巻き添えが少なく、
    誤検知除去の便益の方が大きいというトレードオフ（Issue #33 の下流実測に基づく）。
    既知の限界2（Plan 0059/0060 レビューで検出・根治は Plan 0068）:
    (a) GitHub blob/raw URL 形式の自リポジトリ自己参照（.../blob/<branch>/<path>）は
    直前セグメントがブランチ名のため検出できない（検出漏れ側）。
    (b) リポジトリディレクトリ名が外部 URL のパスセグメントと偶然一致すると
    その URL 内パスを誤検知しうる（例: ディレクトリ名 ADDF と github.com/owner/ADDF/...）。
    いずれも URL スキーム検出を持たない basename 文字列一致の構造的限界。
    同期契約: lint-residual-paths.py の compile_pattern() と同一実装に保つ。
    """
    self_prefix = r'(?<=/' + re.escape(os.path.basename(os.getcwd())) + r'/)'
    return re.compile(r'(?<![A-Za-z0-9_-])'
                      + r'(?:' + self_prefix + r'|(?<![A-Za-z0-9]/))'
                      + re.escape(old) + r'(?![A-Za-z0-9_-])')


def sorted_replacements(cfg):
    """(pattern, old, new) を old の長い順に返す（長いキー優先の置換順序）"""
    reps = [(compile_pattern(e['old']), e['old'], e['new'])
            for e, _ in entries(cfg)]
    return sorted(reps, key=lambda r: len(r[1]), reverse=True)


def tracked_files():
    r = run_git('ls-files', '-z', check=True)
    return [p for p in r.stdout.split('\0') if p]


def read_text(path):
    """走査対象なら中身のテキストを、対象外なら None を返す。

    - symlink は除外: git は symlink を blob 追跡するため、open() で辿ると
      リンク先（リポジトリ外でもよい）を読み書きしてしまう
    - バイナリは NUL バイト検査＋ UTF-8 デコード失敗で除外（拡張子に依存しない）
    - MAX_TEXT_BYTES 超過は読み込まずスキップし SIZE_SKIPPED に記録する
      （report_size_skips() が件数付きで手動確認を案内 — silent 無効化の禁止）
    """
    if os.path.islink(path) or not os.path.isfile(path):
        return None
    try:
        if os.path.getsize(path) > MAX_TEXT_BYTES:
            SIZE_SKIPPED.add(path)
            return None
        with open(path, 'rb') as f:
            data = f.read()
    except OSError:
        return None
    if b'\0' in data:
        return None
    try:
        return data.decode('utf-8')
    except UnicodeDecodeError:
        return None


def scan_targets(cfg):
    """(path, text) を返すイテレータ。除外リスト（rewrite_exclusions）適用済み"""
    excluded = set(cfg.get('rewrite_exclusions', {}).get('files', []))
    for path in tracked_files():
        if path in excluded:
            continue
        text = read_text(path)
        if text is not None:
            yield path, text


def is_tracked(path):
    """path（ファイルまたはディレクトリ）配下に git 追跡ファイルがあるか"""
    r = run_git('ls-files', '--', path)
    return bool(r.stdout.strip())


def _is_empty_dir(path):
    return os.path.isdir(path) and not os.path.islink(path) and not os.listdir(path)


def preflight(cfg):
    """移動計画を検査し (moves, skips, infos, problems) を返す。

    moves    = 実行する移動 [(old, new, kind)]
    skips    = optional で旧パスが無いエントリ（明示出力する — silent 無効化の禁止）
    infos    = 旧パスが無く新パスが有る（移行済みとみなす）
    problems = ブロッカー（衝突・必須エントリの欠如）

    移動先が**空ディレクトリ**の場合は衝突扱いしない（apply 途中クラッシュで
    残った空の中間ディレクトリは git 的に clean のまま preflight を永久ブロック
    しうる。apply が rmdir してから移動する）。
    """
    moves, skips, infos, problems = [], [], [], []
    for e, kind in entries(cfg):
        old, new = e['old'], e['new']
        optional = e.get('optional', True)
        old_exists = os.path.lexists(old)
        new_exists = os.path.lexists(new)
        if old_exists and new_exists and not _is_empty_dir(new):
            problems.append(
                f'衝突: {new} が既に存在する（{old} の移動先）。中身を確認し、'
                '以前の移行途中の残骸で不要なら削除（必要ならリネームで退避）してから再実行する')
        elif old_exists:
            moves.append((old, new, kind))
        elif new_exists:
            infos.append(f'移行済み: {old} → {new}（旧パスなし・新パスあり）')
        elif optional:
            skips.append(f'SKIP: {old} は存在しない（optional — このプロジェクトには無い）')
        else:
            problems.append(f'必須エントリ欠如: {old} も {new} も存在しない'
                            '（ADDF プロジェクトのルートで実行しているか確認する）')
    return moves, skips, infos, problems


def scan_references(cfg, fragment_match=None):
    """旧パス参照の全数とマッチ例を集計し、(stats, fragment_hits) を返す。

    stats = {old: {'files': set, 'count': int, 'samples': [(path, lineno, line)]}}
    長いキー優先＋マッチ済み範囲の消し込みで、docs/plans-add の参照を
    docs/plans の参照として二重計上しない。

    fragment_match（fragment_matcher() の戻り値）が与えられた場合、**同じ1周**で
    射程外類型2（分割断片）の候補行も fragment_hits に集計する — 巨大リポジトリで
    走査を複数回繰り返さないため。全ファイルの全文はメモリに保持せず、
    1ファイルずつ読んで両方の集計に通す。
    """
    reps = sorted_replacements(cfg)
    stats = {old: {'files': set(), 'count': 0, 'samples': []} for _, old, _ in reps}
    fragment_hits = []
    for path, text in scan_targets(cfg):
        for lineno, line in enumerate(text.splitlines(), 1):
            if EXCLUSION_MARKER in line:
                continue  # 行単位マーカー（正当な旧パス言及行）はスキップ
            if fragment_match is not None and fragment_match(line):
                fragment_hits.append((path, lineno, line.strip()))
            remaining = line
            for pattern, old, _ in reps:
                n = len(pattern.findall(remaining))
                if not n:
                    continue
                s = stats[old]
                s['files'].add(path)
                s['count'] += n
                if len(s['samples']) < SAMPLE_LIMIT:
                    s['samples'].append((path, lineno, line.strip()))
                remaining = pattern.sub(lambda m: '\0' * len(m.group(0)), remaining)
    return stats, fragment_hits


def migrated_tool_dir(cfg):
    """移行後のツールディレクトリ（addfTools エントリの new）を返す"""
    for e in cfg.get('dirs', []):
        if e['old'] == '.claude/addfTools':
            return e['new']
    return '.claude/addfTools'


# ------------------------------------------------------------
# 射程外候補スキャン（check 専用・WARNING のみ）
#
# rewrite はフルパス文字列のリテラル出現しか書き換えられない。本体移行
# （フェーズ2）では移行直後に run-all 18/19 スイートが失敗し、原因は全て
# この「射程外」だった（knowhow: map-driven-migration-tool.md
# 「rewrite の射程外 — 4類型」）。ダウンストリーム移行では事後デバッグでは
# なく事前検出に変えるため、check の末尾で候補を列挙する。
#
# これは lint ではなく「apply/rewrite 後に目視確認する箇所の案内」であり、
# 偽陽性を恐れず recall 優先で拾う。check の成否（exit code）には影響させない。
# 移動対象が1件以上あるとき（= 移行前のリポジトリ）のみ実行する。
# ------------------------------------------------------------

# 射程外候補の表示上限（類型ごと）
OOS_SAMPLE_LIMIT = 5

# 類型1: 親ディレクトリ算出・相対階層参照（移動で階層が変わるとずれる候補）
OOS_REL_HIERARCHY_PATTERNS = [
    re.compile(r'dirname\s+"?\$\{?BASH_SOURCE'),                # dirname "${BASH_SOURCE[0]}"
    re.compile(r'dirname\s+"?\$0'),                             # dirname "$0"
    re.compile(r'\$\{?\w+\}?"?/\.\.'),                          # $SCRIPT_DIR/.. / "${DIR}"/..
    re.compile(r'os\.path\.dirname\s*\(\s*os\.path\.dirname'),  # 二重 dirname（上方向の遡り）
    re.compile(r'\.parent\.parent|\bparents\['),                # pathlib の親遡り
    re.compile(r'''['"]\.\.['"/]'''),                           # '..' / "../" の断片
]


def derive_move_basenames(cfg):
    """paths.toml から移動対象のベース名を導出する。

    files/dynamic エントリの old のファイル名（addf-Behavior.toml 等）と
    dirs の old 最終セグメント（addfTools 等）。ハードコード列挙は
    paths.toml 追従にならないため禁止（マップが単一ソース）。
    """
    return {os.path.basename(e['old']) for e, _ in entries(cfg)}


def oos_files_under_moves(cfg, moves):
    """移動対象（old）自身とその配下の git 追跡ファイル（rewrite_exclusions 適用）"""
    excluded = set(cfg.get('rewrite_exclusions', {}).get('files', []))
    prefixes = [old for old, _new, _kind in moves]
    return [path for path in tracked_files()
            if path not in excluded
            and any(path == p or path.startswith(p + '/') for p in prefixes)]


def oos_scan_relative_hierarchy(move_files):
    """類型1: 移動対象内の .sh/.py/.bash にある親ディレクトリ算出・相対階層参照"""
    hits = []
    for path in move_files:
        if not path.endswith(('.sh', '.bash', '.py')):
            continue
        text = read_text(path)
        if text is None:
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            if EXCLUSION_MARKER in line:
                continue
            if any(p.search(line) for p in OOS_REL_HIERARCHY_PATTERNS):
                hits.append((path, lineno, line.strip()))
    return hits


def fragment_matcher(cfg):
    """類型2（分割断片）の行マッチャを返す: os.path.join / 文字列連結のパス組み立て。

    フルパス文字列が現れないため rewrite は書き換えられない候補行を検出する。
    scan_references() に渡し、参照集計と**同じ1周**で全 git 追跡テキストを走査する
    （走査を複数回繰り返さない — 巨大リポジトリの性能対策）。

    偽陽性抑制のヒューリスティック: 一般語 basename（templates / tests / plans 等）は
    無関係な定型句（Django の os.path.join(BASE_DIR, 'templates') 等）に大量マッチする。
    - 行内に `.claude` を含む → 全 basename で検出（ADDF 文脈の確度が高い）
    - 行内に `.claude` を含まない → **固有名 basename**（`addf` を含む・大文字を含む・
      拡張子付きのファイル名）が現れる行のみ検出し、全小文字の一般語ディレクトリ名は
      対象外にする
    """
    basenames = sorted({'.claude', *derive_move_basenames(cfg)})
    distinctive = sorted(b for b in basenames
                         if 'addf' in b.lower() or b != b.lower() or '.' in b)

    def quoted_re(names):
        return re.compile('[\'"](' + '|'.join(re.escape(b) for b in names) + ')[\'"]')

    quoted_any = quoted_re(basenames)
    quoted_distinctive = quoted_re(distinctive)
    distinctive_sub = re.compile('|'.join(re.escape(b) for b in distinctive))
    joiner = re.compile(r'os\.path\.join\s*\(')
    concat = re.compile(r'''\+\s*f?['"]/''')  # scriptDir + "/../..." 等の文字列連結パス

    def match(line):
        if '.claude' in line:
            return bool((joiner.search(line) and quoted_any.search(line))
                        or concat.search(line))
        return bool((joiner.search(line) and quoted_distinctive.search(line))
                    or (concat.search(line) and distinctive_sub.search(line)))

    return match


def oos_scan_md_relative_links(move_files):
    """類型3: 移動対象内の .md にある `](../` 形式の相対リンク。

    ファイル自身の階層が変わるとリンク先がずれる。テストにもかからない
    （レンダリング時にしか壊れない）ため事前列挙が特に効く。
    """
    pat = re.compile(r'\]\(\.\./')
    hits = []
    for path in move_files:
        if not path.endswith('.md'):
            continue
        text = read_text(path)
        if text is None:
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            if EXCLUSION_MARKER in line:
                continue
            if pat.search(line):
                hits.append((path, lineno, line.strip()))
    return hits


def oos_scan_binaries(move_files):
    """類型4: 移動対象内のバイナリ（NUL 検査で判定。symlink は除外）。

    内部にパス断片を含む場合、ソース修正＋再ビルド＋checksums 更新まで必要。
    """
    bins = []
    for path in move_files:
        if os.path.islink(path) or not os.path.isfile(path):
            continue
        try:
            with open(path, 'rb') as f:
                data = f.read()
        except OSError:
            continue
        if b'\0' in data:
            bins.append(path)
    return bins


def print_oos_hits(label, hits):
    print(f'[{label}]: {len(hits)} 箇所')
    for path, lineno, line in hits[:OOS_SAMPLE_LIMIT]:
        if len(line) > SAMPLE_WIDTH:
            line = line[:SAMPLE_WIDTH] + '…'
        print(f'    {path}:{lineno}: {line}')
    if len(hits) > OOS_SAMPLE_LIMIT:
        print(f'    …ほか {len(hits) - OOS_SAMPLE_LIMIT} 箇所')


def scan_out_of_scope(cfg, moves, fragment_hits):
    """rewrite 射程外4類型の候補スキャン。WARNING のみで exit code に影響しない。

    類型2（fragment_hits）は scan_references() の1周で集計済みのものを受け取る
    （全追跡テキストの再走査をしない）。類型1/3/4 は移動対象内のファイルのみの
    小さな部分集合走査のためここで読む。
    """
    print('\n--- 射程外候補スキャン（WARNING — check の成否には影響しない）---')
    print('rewrite はフルパス文字列のリテラル出現しか書き換えられません。以下は移行で壊れる可能性の')
    print('ある箇所の候補です（偽陽性を含みます）。apply/rewrite 後にこれらを確認し、')
    print('プロジェクト自身のテストを実行してください。')
    move_files = oos_files_under_moves(cfg, moves)
    print_oos_hits('類型1: 相対階層参照（SCRIPT_DIR/.. 等・移動対象内の .sh/.py/.bash）',
                   oos_scan_relative_hierarchy(move_files))
    print_oos_hits('類型2: 分割断片（os.path.join / 文字列連結のパス組み立て・全追跡テキスト）',
                   fragment_hits)
    print_oos_hits('類型3: Markdown 相対リンク（](../ 形式・移動対象内の .md）',
                   oos_scan_md_relative_links(move_files))
    bins = oos_scan_binaries(move_files)
    print(f'[類型4: バイナリ（NUL 検査・移動対象内）]: {len(bins)} 件')
    for path in bins[:OOS_SAMPLE_LIMIT]:
        print(f'    {path}（rewrite 対象外 — 内部にパスを含むならソース修正＋再ビルドが必要）')
    if len(bins) > OOS_SAMPLE_LIMIT:
        print(f'    …ほか {len(bins) - OOS_SAMPLE_LIMIT} 件')
    print('注意: git 追跡外のファイル（.claude/settings.local.json の許可ルール等）は'
          '走査対象外です。移行後に旧パスが残っていないか手動で確認してください')


def report_size_skips():
    """サイズ上限超過でスキップしたファイルを件数付きで案内する（silent 無効化の禁止）"""
    if not SIZE_SKIPPED:
        return
    print(f'\n注意: サイズ上限（{MAX_TEXT_BYTES // (1024 * 1024)}MB）超過のため '
          f'{len(SIZE_SKIPPED)} ファイルの読み込みをスキップしました。'
          '旧パス参照が残っていないか手動で確認してください:')
    for p in sorted(SIZE_SKIPPED):
        print(f'    {p}')


def mode_check(cfg, map_path):
    print(f'マップ: {map_path}')
    moves, skips, infos, problems = preflight(cfg)
    print('\n--- 移動計画 ---')
    for old, new, kind in moves:
        print(f'MOVE ({kind}): {old} → {new}')
    for line in skips + infos:
        print(line)
    for line in problems:
        print(f'ERROR: {line}')
    print('\n--- 旧パス参照の全数（git 追跡テキストファイル・除外リスト適用後）---')
    print(f'（マッチ例は旧パスごとに先頭 {SAMPLE_LIMIT} 件。rewrite 前の誤爆候補の目視確認用）')
    # 射程外類型2 は参照集計と同じ1周で集める（移動対象ゼロ = 移行済みなら集めない）
    stats, fragment_hits = scan_references(
        cfg, fragment_matcher(cfg) if moves else None)
    total_refs = 0
    for old, s in stats.items():
        if not s['count']:
            continue
        total_refs += s['count']
        print(f'{old}: {len(s["files"])} ファイル / {s["count"]} 箇所')
        for path, lineno, line in s['samples']:
            if len(line) > SAMPLE_WIDTH:
                line = line[:SAMPLE_WIDTH] + '…'
            print(f'    例: {path}:{lineno}: {line}')
    print(f'参照合計: {total_refs} 箇所（`rewrite` で書き換える）')
    if moves:
        # 移行前のリポジトリでのみ意味がある案内のため、移動対象ゼロなら実行しない
        scan_out_of_scope(cfg, moves, fragment_hits)
    report_size_skips()
    if problems:
        print('\nERROR: ブロッカーがあります。解消してから apply してください')
        sys.exit(1)
    print(f'\nOK: 移動 {len(moves)} 件・スキップ {len(skips)} 件。'
          '`apply` で実行できます（何も変更していません）')


def ensure_clean_tree(hint):
    r = run_git('status', '--porcelain', check=True)
    if r.stdout.strip():
        print(f'ERROR: 作業ツリーが dirty です。{hint}')
        print(r.stdout.rstrip())
        sys.exit(1)


def mode_apply(cfg, map_path):
    ensure_clean_tree('コミットまたは退避してから apply してください')
    moves, skips, infos, problems = preflight(cfg)
    for line in problems:
        print(f'ERROR: {line}')
    if problems:
        sys.exit(1)
    if not moves:
        print('ERROR: 移動対象がありません（既に移行済みの可能性があります）')
        sys.exit(1)

    backup_ref = cfg.get('meta', {}).get('backup_ref', 'refs/backup/pre-0037-migration')
    if run_git('show-ref', '--verify', '--quiet', backup_ref).returncode == 0:
        print(f'ERROR: backup ref {backup_ref} が既に存在します（以前の apply の巻き戻し点）。\n'
              '「本当の移行前」の巻き戻し点を静かに失わないため、上書きしません。\n'
              f'  以前の移行を巻き戻してやり直す場合: git reset --hard {backup_ref}\n'
              f'  この ref が不要と確認できた場合のみ: git update-ref -d {backup_ref} '
              'を実行してから apply をやり直してください')
        sys.exit(1)
    run_git('update-ref', backup_ref, 'HEAD', check=True)
    print(f'backup ref 作成: {backup_ref} → HEAD')

    for line in skips + infos:
        print(line)
    for old, new, kind in moves:
        os.makedirs(os.path.dirname(new), exist_ok=True)
        if _is_empty_dir(new):
            # 途中クラッシュ等で残った空ディレクトリは衝突ではない（preflight と対。
            # rmdir しないと git mv / shutil.move がディレクトリ内へ移動してしまう）
            os.rmdir(new)
        if is_tracked(old):
            run_git('mv', old, new, check=True)
            print(f'git mv ({kind}): {old} → {new}')
        else:
            # 動的生成ファイル等の git 未追跡はファイルシステム移動
            shutil.move(old, new)
            print(f'mv ({kind}, 未追跡): {old} → {new}')

    tools_dir = migrated_tool_dir(cfg)
    print(f'\n完了: {len(moves)} 件を移動しました。**ここでコミットしてください**'
          '（git mv 単独のコミット — 参照書き換えと混ぜない。例: git add -A && git commit）\n'
          '続けて参照書き換えを別コミットにします。**ツール自身も移動済みのため新パスで実行**:\n'
          f'  uv run --python 3.11 {tools_dir}/migrate-paths.py rewrite\n'
          f'  （uv が無ければ: python3 {tools_dir}/migrate-paths.py rewrite）\n'
          f'巻き戻す場合: git reset --hard {backup_ref}')


def mode_rewrite(cfg, map_path):
    new_root = cfg.get('meta', {}).get('new_root', '.claude/addf')
    if not os.path.isdir(new_root):
        print(f'ERROR: {new_root}/ が存在しません。apply（git mv）を先に実行してください'
              '（apply 前に rewrite すると、参照だけが実在しないパスへ一括で書き換わる）')
        sys.exit(1)
    ensure_clean_tree('未コミットの変更（apply 分のコミット忘れ、または apply 後の別の編集）を'
                      'コミットか退避してから rewrite してください')
    reps = sorted_replacements(cfg)
    changed_files = 0
    total = 0
    for path, text in scan_targets(cfg):
        # 行単位マーカー（EXCLUSION_MARKER）行を書き換えから外すため行ごとに処理する
        # （keepends=True の join は原文を完全復元する — 改行コードを壊さない）
        lines = text.splitlines(keepends=True)
        n_file = 0
        for i, line in enumerate(lines):
            if EXCLUSION_MARKER in line:
                continue
            for pattern, old, new in reps:
                line, n = pattern.subn(new, line)
                n_file += n
            lines[i] = line
        if n_file:
            with open(path, 'w', encoding='utf-8') as f:
                f.write(''.join(lines))
            changed_files += 1
            total += n_file
    report_size_skips()
    tools_dir = migrated_tool_dir(cfg)
    print(f'完了: {changed_files} ファイル / {total} 箇所を書き換えました。'
          'ここでコミットし、残存ゼロを確認してください:\n'
          f'  uv run --python 3.11 {tools_dir}/lint-residual-paths.py\n'
          f'  （uv が無ければ: python3 {tools_dir}/lint-residual-paths.py）\n'
          '\n'
          '注意: 以下は rewrite の書き換え対象外です。移行後に手動確認してください（lint も検出できません）:\n'
          '  - git 追跡外のファイル（.claude/settings.local.json の許可ルール等）に残る旧パス\n'
          '  - 相対階層参照（SCRIPT_DIR/../.. 等）・os.path.join / 文字列連結で組み立てるパス断片\n'
          '  - Markdown の相対リンク（../../ 等。ファイルの階層が変わるとずれる）\n'
          '  - コンパイル済みバイナリ内のパス（ソース修正＋再ビルドが必要）\n'
          '  確認後、プロジェクト自身のテストを一度回すことを推奨します')


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'check'
    if mode not in ('check', 'apply', 'rewrite'):
        print(f'ERROR: 不明なモード: {mode}（check / apply / rewrite）')
        sys.exit(1)
    ensure_repo_root()
    cfg, map_path = load_map()
    if mode == 'check':
        mode_check(cfg, map_path)
    elif mode == 'apply':
        mode_apply(cfg, map_path)
    else:
        mode_rewrite(cfg, map_path)


if __name__ == '__main__':
    main()
