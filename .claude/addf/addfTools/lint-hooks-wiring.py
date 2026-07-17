#!/usr/bin/env python3
"""hooks 配線チェック — .claude/hooks/*.sh が settings.json に配線されているかを検査する

フックファイルが存在しても settings.json の hooks セクションに配線されていなければ
実行されない（手縫い導入・部分マージで配線を忘れると、ターンカウンター等の安全網が
静かに欠落する — ダウンストリーム実働報告 Issue #19 引っかかり5）。
lint-hooks-exec.py（実行権限）と対になる検査: 権限があっても配線がなければ動かない。

検査方法: .claude/hooks/*.sh の各ファイル名が、settings.json（存在すれば
settings.local.json も参照）の hooks セクション内のいずれかの command 文字列に
現れるかを突合する。突合は境界チェック付き正規表現で行う — 素朴な部分文字列一致では
`reminder.sh` が `turn-reminder.sh` の配線文字列に含まれてしまい、未配線フックを
配線済みと誤判定する。

- 走査対象は `.claude/hooks/` 直下の `*.sh` のみ。サブディレクトリは走査しない
- 参照されていないフックは WARNING — ダウンストリームが意図的に外している可能性が
  あるため ERROR にしない
- settings.local.json のみで配線されているフックは OK と区別して NOTE を出す
  （他環境・CI には適用されない構成の可視化。exit は 0 のまま）
- フックのコメントヘッダ（先頭の連続コメント行）に `# hooks-wiring: indirect` を
  置いたフックは検査対象外（NOTE 表示）— 他スクリプト経由で呼ばれる等、command
  文字列にファイル名が現れない正当な構成のためのエスケープハッチ
- .claude/settings.json が存在しない場合は SKIP（未導入の構成は問題ではない）
- settings.json が JSON として不正な場合も SKIP（構文検査は lint-json.py の責務）
- settings.json が読めない場合（PermissionError 等の OSError）も SKIP

exit code: 0 = OK / SKIP / 2 = WARNING あり（この lint に ERROR 級は無い。
3値規約 0 = OK / 1 = ERROR / 2 = WARNING のうち 1 は将来のために予約）
tomllib 不要 — システム python3（3.6+）でそのまま動く。
"""
import glob
import json
import os
import re
import sys

HOOKS_DIR = '.claude/hooks'
SETTINGS = '.claude/settings.json'
SETTINGS_LOCAL = '.claude/settings.local.json'
INDIRECT_MARKER = 'hooks-wiring: indirect'
UPSTREAM_SETTINGS_URL = 'https://github.com/fruitriin/ADDF/blob/main/.claude/settings.json'


def collect_commands(node, out):
    """hooks セクション以下を再帰的に歩き、"command" キーの値を集める。"""
    if isinstance(node, dict):
        for key, value in node.items():
            if key == 'command' and isinstance(value, str):
                out.append(value)
            else:
                collect_commands(value, out)
    elif isinstance(node, list):
        for item in node:
            collect_commands(item, out)


def load_hook_commands(path):
    """settings ファイルから hooks セクションの command 文字列一覧を返す。
    ファイル不在は None、JSON 不正は ValueError、読み取り不能は OSError を送出する。"""
    if not os.path.isfile(path):
        return None
    with open(path, encoding='utf-8') as f:
        settings = json.load(f)  # 不正 JSON は json.JSONDecodeError (ValueError)
    commands = []
    collect_commands(settings.get('hooks', {}), commands)
    return commands


def is_wired(basename, commands):
    """basename が command 文字列内に境界付きで現れるか。
    前後がファイル名構成文字（英数・`.`・`-`・`_`）でないことを要求し、
    `count.sh` が `reset-turn-count.sh` の配線にマッチする誤判定を防ぐ。
    パス区切り `/` は境界として許容される。"""
    pattern = re.compile(r'(?<![\w.-])' + re.escape(basename) + r'(?![\w.-])')
    return any(pattern.search(cmd) for cmd in commands)


def is_indirect(path):
    """フックのコメントヘッダに `# hooks-wiring: indirect` 宣言があるか。
    先頭の連続コメント行（shebang 含む）のみを見る。読めない場合は宣言なし扱い。"""
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            for line in f:
                stripped = line.strip()
                if stripped and not stripped.startswith('#'):
                    break  # コメントヘッダ終了
                if INDIRECT_MARKER in stripped:
                    return True
    except OSError:
        pass
    return False


def main():
    if not os.path.isfile(SETTINGS):
        print(f'SKIP: {SETTINGS} が存在しない')
        return 0

    hook_files = sorted(glob.glob(f'{HOOKS_DIR}/*.sh'))
    if not hook_files:
        print(f'SKIP: {HOOKS_DIR}/*.sh が存在しない')
        return 0

    try:
        commands = load_hook_commands(SETTINGS)
    except ValueError:
        print(f'SKIP: {SETTINGS} が JSON として読めない（構文検査は lint-json.py の責務）')
        return 0
    except OSError as e:
        print(f'SKIP: {SETTINGS} を読めない（{e}）')
        return 0

    # settings.local.json での配線も有効な配線として認めるが、他環境・CI には
    # 適用されないため OK と区別して NOTE を出す。
    # local 側が不正 JSON・読み取り不能でも本検査は SKIP しない（主対象は settings.json）
    try:
        local_commands = load_hook_commands(SETTINGS_LOCAL) or []
    except (ValueError, OSError):
        local_commands = []

    unwired = []
    notes = []
    indirect_count = 0
    for path in hook_files:
        basename = os.path.basename(path)
        if is_indirect(path):
            indirect_count += 1
            notes.append(f'NOTE: {path} は `# hooks-wiring: indirect` 宣言により検査対象外'
                         '（間接参照の実在は宣言した側で担保する）')
        elif is_wired(basename, commands):
            pass
        elif is_wired(basename, local_commands):
            notes.append(f'NOTE: {basename} は settings.local.json 経由'
                         '（他環境・CI には適用されない）')
        else:
            unwired.append(path)

    for note in notes:
        print(note)

    if unwired:
        print('WARNING: 以下のフックは settings.json の hooks セクションに配線されていない'
              '（配線がなければファイルが存在しても実行されない。意図的に外している場合は'
              ' このままでよい）:')
        for path in unwired:
            print(f'    {path}')
        print('  配線例は ADDF リポジトリの .claude/settings.json の hooks セクションを'
              f'参照する（{UPSTREAM_SETTINGS_URL}）')
        return 2

    checked = len(hook_files) - indirect_count
    suffix = f'、{indirect_count} フック検査対象外（indirect 宣言）' if indirect_count else ''
    print(f'OK: hooks 配線チェック通過（{checked} フック配線済み{suffix}）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
