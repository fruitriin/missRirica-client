#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# ///
"""残存参照 lint — Plan 0037 移行の完了ゲート

paths.toml（単一ソース）の旧パスが git 追跡ファイルに残存していないかを検査する。
ERROR ゼロになるまで移行を完了扱いしない（「警告は出すが止めない」の禁止）。

移行前のリポジトリでは検査しない: 新構造（[meta].new_root = .claude/addf/）の
存在を検出条件にし、移行前は SKIP を明示出力する（ダウンストリーム配布時の
誤 ERROR 防止。SKIP は silent にしない — 環境起因で検査しなかったことの可視化）。
注意: new_root の存在は「apply が完走した」ことまでは保証しない。旧パス残存の
ERROR には部分適用（apply/rewrite の途中失敗）の可能性の注記を添える。

移行後の恒久検査として、docs/ 配下への ADDF 管理ファイルの新規追加（逆流）を
WARNING で検出する（マップの old が docs/ で始まるディレクトリ配下に
git 追跡ファイルが再出現したケース）。

`.gitignore` の旧位置パターン残存も WARNING で検出する。git mv 後、`.gitignore` が
旧位置の literal パスをそのまま残していれば通常のスキャンで ERROR になるが、
`.claude/*.md` のような**グロブパターン**は旧位置にはマッチしても新位置には
マッチしない場合があり、これは文字列一致では検出できない別種の穴（ダウンストリーム
実測 Issue #26: Progress.md 等4ファイルが意図せず追跡された）。gitignore_like_match()
（セグメント単位 fnmatch — 素の fnmatch だと `*` が '/' を跨いでマッチしてしまい
ディレクトリが1段深くなっただけの非対称を見逃す）で旧パス・新パスへのマッチ有無を
比較し、非対称なら WARNING にする（完全な gitignore 構文はサポートしない簡易判定 —
`**`・否定パターン `!` 等は対象外）。

検査から除外するファイルは paths.toml の [rewrite_exclusions].files（マップ定義・
移行ロジック・テストの合成フィクスチャとして旧パス文字列が本質的に大量にある
道具・テストのみ）。移行手順書・移行ガイド等のドキュメントはファイル除外しない —
正当な旧パス言及行に行内マーカー `residual-path: allow` を付けて行単位で除外する
（ファイル丸ごと除外はそのファイル全体が本 lint の永久盲点になるため）。

走査対象は migrate-paths.py の check / rewrite と一致させる（check「0箇所」なのに
lint で初めて ERROR になる不一致を作らない）: 全 git 追跡ファイルのうちテキストの
もの。バイナリは NUL バイト検査＋ UTF-8 デコード失敗で除外し、**symlink は除外**
する（git は symlink を blob 追跡するため、open() で辿るとリンク先 —
リポジトリ外でもよい — を読んでしまう）。

境界チェックは migrate-paths.py と同一規則
（同期契約: migrate-paths.py の compile_pattern() と挙動を同期する）:
前後が英数字・ハイフン・アンダースコアならマッチしない
（`docs/plans-add` の残存を `docs/plans` の残存として誤検出・二重検出しない）。
Issue #33 対応で、直前2文字が「英数字 + `/`」の場合（外部 URL
`example.com/docs/guides` や他プロジェクト絶対パス `~/workspace/OTHER/docs/knowhow` <!-- residual-path: allow -->
の内部）は残存扱いしない。ただし「/ + このリポジトリのディレクトリ名 + /」が直前に
ある場合（自リポジトリへの絶対パス参照）は例外として検出する。

exit code: 0 = OK / SKIP、1 = ERROR（旧パス残存）、2 = WARNING のみ（逆流・.gitignore 非対称）
"""
import fnmatch
import os
import re
import subprocess
import sys

try:
    import tomllib
except ModuleNotFoundError:
    # 受動的 lint のため欠如は SKIP（配布先で誤 ERROR を出さない）
    print(f'SKIP: tomllib がありません（Python {sys.version.split()[0]}）。'
          '`uv run --python 3.11` または Python 3.11+ で実行してください')
    sys.exit(0)

# paths.toml の探索先（移行後の新位置を優先し、移行前の旧位置にフォールバック）
MAP_CANDIDATES = [
    '.claude/addf/addfTools/paths.toml',
    '.claude/addfTools/paths.toml',
]

# 行単位の除外マーカー（コメント形式は問わない — 行内一致で判定。
# 同期契約: migrate-paths.py の EXCLUSION_MARKER と同一に保つ）
EXCLUSION_MARKER = 'residual-path: allow'

# 走査するテキストファイルのサイズ上限。超過は読み込まずスキップし件数付きで案内する
# （同期契約: migrate-paths.py の MAX_TEXT_BYTES と同一に保つ — 走査対象集合の一致）
MAX_TEXT_BYTES = 5 * 1024 * 1024
SIZE_SKIPPED = set()


def compile_pattern(old):
    """境界チェック付きの検出パターン（migrate-paths.py の compile_pattern() と同一規則）。

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
    同期契約: migrate-paths.py の compile_pattern() と同一実装に保つ。
    """
    self_prefix = r'(?<=/' + re.escape(os.path.basename(os.getcwd())) + r'/)'
    return re.compile(r'(?<![A-Za-z0-9_-])'
                      + r'(?:' + self_prefix + r'|(?<![A-Za-z0-9]/))'
                      + re.escape(old) + r'(?![A-Za-z0-9_-])')


def gitignore_like_match(path, pattern):
    """簡易 gitignore 風マッチ（`**`・否定 `!` は非対応の簡略版）。
    末尾 '/'（ディレクトリ限定指定）はディレクトリ丸ごと移動エントリ（`.claude/addfTools/` 等の
    慣用記法）が検出漏れにならないよう、比較前に取り除く（ファイル/ディレクトリの型は区別しない）。
    先頭 '/' のみ（内部に '/' を含まない）はリポジトリルート限定のアンカーとして扱い、
    任意階層のベース名一致（アンカーなしの裸パターン）と区別する（アンカー情報を lstrip で
    落とすと `/foo.md` と `foo.md` の意味の違いが消え、非対称の見逃しになる）。
    '/' を含むパターンはセグメント数が一致するパスにのみマッチし、各セグメント内で fnmatch する
    （`fnmatch.fnmatch(old, pattern)` をそのまま使うと `*` が '/' を跨いでマッチしてしまい、
    ディレクトリが1段深くなっただけの非対称を見逃す — 実際に起きた不具合の型）"""
    pattern = pattern.rstrip('/')
    anchored = pattern.startswith('/')
    pattern = pattern.lstrip('/')
    if '/' not in pattern:
        if anchored:
            return '/' not in path and fnmatch.fnmatch(path, pattern)
        return fnmatch.fnmatch(path.rsplit('/', 1)[-1], pattern)
    path_parts = path.split('/')
    pattern_parts = pattern.split('/')
    if len(path_parts) != len(pattern_parts):
        return False
    return all(fnmatch.fnmatch(pp, patp) for pp, patp in zip(path_parts, pattern_parts))


def load_map():
    for path in MAP_CANDIDATES:
        if os.path.exists(path):
            with open(path, 'rb') as f:
                return tomllib.load(f), path
    return None, None


def read_text(path):
    """走査対象なら中身のテキストを、対象外（symlink・バイナリ等）なら None を返す
    （migrate-paths.py の read_text() と同一規則 — 走査対象の同期契約）"""
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


# cwd 検証: 相対パス前提のため、git リポジトリ内ではルート以外の実行を ERROR にする。
# git リポジトリ外は従来どおり SKIP（配布先で誤 ERROR を出さない受動 lint の原則）
_top = subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                      capture_output=True, text=True)
if _top.returncode != 0:
    print('SKIP: git リポジトリ外のため検査できない')
    sys.exit(0)
if os.path.realpath(_top.stdout.strip()) != os.path.realpath(os.getcwd()):
    print(f'ERROR: リポジトリルートで実行してください'
          f'（cwd: {os.path.realpath(os.getcwd())} / ルート: {os.path.realpath(_top.stdout.strip())}）')
    sys.exit(1)

cfg, map_path = load_map()
if cfg is None:
    print(f'SKIP: paths.toml が見つからない（探索先: {", ".join(MAP_CANDIDATES)}）')
    sys.exit(0)

new_root = cfg.get('meta', {}).get('new_root', '.claude/addf')
if not os.path.isdir(new_root):
    print(f'SKIP: 移行前のリポジトリ（{new_root}/ が存在しない）— 残存参照は検査しない')
    sys.exit(0)

r = subprocess.run(['git', 'ls-files', '-z'], capture_output=True, text=True)
if r.returncode != 0:
    print('SKIP: git ls-files が失敗したため検査できない')
    sys.exit(0)
files = [p for p in r.stdout.split('\0') if p]

all_entries = cfg.get('dirs', []) + cfg.get('files', []) + cfg.get('dynamic', [])
excluded = set(cfg.get('rewrite_exclusions', {}).get('files', []))
# 長いキー優先＋境界チェックで、docs/plans-add の残存が docs/plans と二重報告されない
patterns = sorted(((compile_pattern(e['old']), e['old']) for e in all_entries),
                  key=lambda p: len(p[1]), reverse=True)

errors = []
warnings = []

for path in files:
    if path in excluded:
        continue
    text = read_text(path)
    if text is None:
        continue  # symlink・バイナリ等は対象外
    for lineno, line in enumerate(text.splitlines(), 1):
        if EXCLUSION_MARKER in line:
            continue  # 行単位マーカー（正当な旧パス言及行）は検査しない
        remaining = line
        for pattern, old in patterns:
            if pattern.search(remaining):
                errors.append(f'{path}:{lineno}: 旧パス `{old}` が残存')
                # 長いキーでマッチした範囲を消し込み、短いキーでの二重報告を防ぐ
                remaining = pattern.sub('\0' * len(old), remaining)

# 逆流検査: docs/ 配下の ADDF 管理ディレクトリに git 追跡ファイルが再出現していないか
docs_prefixes = [e['old'] for e in cfg.get('dirs', []) if e['old'].startswith('docs/')]
for path in files:
    for prefix in docs_prefixes:
        if path.startswith(prefix + '/'):
            warnings.append(f'WARNING: docs/ 配下への逆流 — {path} は移行済みの '
                            f'{prefix} 配下に新規追加されている（{new_root} 側に置く）')

# .gitignore の旧位置パターン残存検査（グロブの非対称マッチは文字列一致で検出できない）。
# read_text() を再利用し symlink・バイナリ・サイズ上限の走査対象規則を他の検査と一致させる。
# ワイルドカード（* ? []）を含まないリテラルパターンは主走査ループの ERROR で既に検出済みの
# ため対象外にする（同一行に ERROR と WARNING が重複して出る混乱を避ける）
gi_text = read_text('.gitignore') if '.gitignore' not in excluded else None
if gi_text is not None:
    gi_lines = gi_text.splitlines()
    for lineno, raw in enumerate(gi_lines, 1):
        if EXCLUSION_MARKER in raw:
            continue
        stripped = raw.strip()
        if not stripped or stripped.startswith('#') or stripped.startswith('!'):
            continue
        pattern = stripped
        if not any(c in pattern for c in '*?['):
            continue  # ワイルドカードなしのリテラルパターンは ERROR 側の走査に任せる
        for e in all_entries:
            old, new = e['old'], e['new']
            if gitignore_like_match(old, pattern) and not gitignore_like_match(new, pattern):
                warnings.append(f'WARNING: .gitignore:{lineno}: パターン `{stripped}` は旧位置 '
                                f'`{old}` にマッチするが新位置 `{new}` にはマッチしない — '
                                '移行後に意図せず追跡される可能性')

for msg in errors + warnings:
    print(msg)

if SIZE_SKIPPED:
    print(f'注意: サイズ上限（{MAX_TEXT_BYTES // (1024 * 1024)}MB）超過のため '
          f'{len(SIZE_SKIPPED)} ファイルを検査せずスキップしました。'
          '旧パス参照が残っていないか手動で確認してください:')
    for p in sorted(SIZE_SKIPPED):
        print(f'    {p}')

if errors:
    print(f'ERROR: 旧パス参照が {len(errors)} 箇所残存。'
          'migrate-paths.py rewrite で書き換えるか手動で解消するまで移行は完了しない')
    print('注記: apply/rewrite が未完了の可能性があります。'
          'migrate-paths.py check で移動残・参照残を確認してください')
    sys.exit(1)
if warnings:
    sys.exit(2)
print('OK: 旧パス残存なし（逆流もなし）')
