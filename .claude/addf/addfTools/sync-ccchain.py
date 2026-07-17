#!/usr/bin/env python3
"""ccchain 同期 — Plan 0040 フェーズ2。オプトイン配布機構。

`addf-Behavior.toml` の `[ccchain] enable` に応じて、プロジェクトルートの `.ccchain.conf` と
`.claude/settings.json` の PreToolUse(Bash) フックエントリを配置・撤去する。

sync-optional-skills.py（GUI テストの原本コピー機構）とは以下の点で設計が異なる:
- 対象がプロジェクトルートの `.ccchain.conf`（1ファイル）と settings.json の JSON エントリ
  （commands/agents ディレクトリへのコピーではない）
- **初回配置後、`.ccchain.conf` は書き換え可能**（ダウンストリームが自分の運用コマンドに合わせて
  チューニングする前提のため）。sync-optional-skills.py の「原本と異なる有効化コピーは触らない」
  原則の初回配置版のみを踏襲し、以降の追従強制はしない（ADDF アップデートで原本テンプレートが
  変わった場合の再取り込みは手動判断）
- settings.json の hooks.PreToolUse は ccchain 由来のエントリ（コマンド文字列で識別）だけを
  追加・削除し、他のフック（destructive-git-guard.sh 等）には一切触れない

check モードは以下も検査する:
- enable=true なのにプロジェクトルートに ccchain バイナリが無い場合 WARNING
  （フェイルセーフ方針: バイナリ不在は Claude Code の動作を妨げない。フック自体が空振りする形になる）

使い方:
  uv run --python 3.11 sync-ccchain.py          # check モード（lint。変更しない）
  uv run --python 3.11 sync-ccchain.py apply    # 配置・撤去を実行する

`.claude/addf/optional/ccchain/` または Behavior.toml が無い場合は SKIP する
（未配布構成は問題ではない）。Behavior.toml の構文エラーは SKIP（lint-toml.py の責務）。

exit code: 0 = 整合 / 1 = ERROR（enable が真偽値でない・settings.json が壊れている等） /
2 = WARNING あり
"""
import json
import os
import shutil
import sys

try:
    import tomllib
except ModuleNotFoundError:
    _hint = (f'tomllib がありません（Python {sys.version.split()[0]}）。'
             '`uv run --python 3.11` または Python 3.11+ で実行してください')
    if len(sys.argv) > 1 and sys.argv[1] == 'apply':
        print(f'ERROR: {_hint}')
        sys.exit(1)
    print(f'SKIP: {_hint}')
    sys.exit(0)

BEHAVIOR = '.claude/addf/Behavior.toml'
OPTIONAL_ROOT = '.claude/addf/optional/ccchain'
TEMPLATE = f'{OPTIONAL_ROOT}/.ccchain.conf'
TARGET_CONF = '.ccchain.conf'
SETTINGS = '.claude/settings.json'
BINARY = './ccchain'
HOOK_COMMAND = '"$CLAUDE_PROJECT_DIR"/ccchain hook pre'

apply_mode = len(sys.argv) > 1 and sys.argv[1] == 'apply'
warnings = []
actions = []


def ccchain_enabled():
    """[ccchain] enable を返す。ファイル不在/構文エラーは SKIP、型不正は ERROR で終了"""
    if not os.path.exists(BEHAVIOR):
        print(f'SKIP: {BEHAVIOR} が存在しない')
        sys.exit(0)
    try:
        with open(BEHAVIOR, 'rb') as f:
            conf = tomllib.load(f)
    except tomllib.TOMLDecodeError as e:
        print(f'SKIP: {BEHAVIOR} が構文エラーのため判定不能（lint-toml.py が検出する）: {e}')
        sys.exit(0)
    raw = conf.get('ccchain', {}).get('enable', False)
    if not isinstance(raw, bool):
        print(f'ERROR: [ccchain] enable は真偽値である必要がある（現在: {raw!r}）。'
              f' クオート無しの true / false で指定する')
        sys.exit(1)
    return raw


def load_settings():
    if not os.path.exists(SETTINGS):
        print(f'ERROR: {SETTINGS} が存在しない — hook を配線できない')
        sys.exit(1)
    try:
        with open(SETTINGS, encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        print(f'ERROR: {SETTINGS} が JSON として不正（セクション1の責務）: {e}')
        sys.exit(1)


def find_bash_entry(settings):
    """hooks.PreToolUse 内の matcher: Bash エントリを返す（無ければ None）"""
    for entry in settings.get('hooks', {}).get('PreToolUse', []):
        if entry.get('matcher') == 'Bash':
            return entry
    return None


def hook_wired(settings):
    entry = find_bash_entry(settings)
    if entry is None:
        return False
    return any(h.get('command') == HOOK_COMMAND for h in entry.get('hooks', []))


def add_hook(settings):
    pretool = settings.setdefault('hooks', {}).setdefault('PreToolUse', [])
    entry = find_bash_entry(settings)
    if entry is None:
        entry = {'matcher': 'Bash', 'hooks': []}
        pretool.append(entry)
    entry['hooks'].append({'type': 'command', 'command': HOOK_COMMAND})


def remove_hook(settings):
    entry = find_bash_entry(settings)
    if entry is None:
        return
    entry['hooks'] = [h for h in entry.get('hooks', []) if h.get('command') != HOOK_COMMAND]
    if not entry['hooks']:
        settings['hooks']['PreToolUse'] = [
            e for e in settings['hooks']['PreToolUse'] if e is not entry
        ]


def save_settings(settings):
    with open(SETTINGS, 'w', encoding='utf-8') as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write('\n')


if not os.path.isdir(OPTIONAL_ROOT):
    print(f'SKIP: {OPTIONAL_ROOT} が存在しない')
    sys.exit(0)

enabled = ccchain_enabled()
settings = load_settings()
wired = hook_wired(settings)
conf_exists = os.path.exists(TARGET_CONF)

if enabled:
    if not conf_exists:
        if apply_mode:
            shutil.copy2(TEMPLATE, TARGET_CONF)
            actions.append(f'配置: {TARGET_CONF}（原本 {TEMPLATE} から）')
        else:
            warnings.append(
                f'未配置: {TARGET_CONF} が無い（ccchain.enable=true）。'
                f' `uv run --python 3.11 .claude/addf/addfTools/sync-ccchain.py apply` で配置する')
    if not wired:
        if apply_mode:
            add_hook(settings)
            save_settings(settings)
            actions.append(f'配線: {SETTINGS} の PreToolUse(Bash) に ccchain フックを追加')
        else:
            warnings.append(
                f'未配線: {SETTINGS} に ccchain の PreToolUse(Bash) フックが無い'
                f'（ccchain.enable=true）。apply で配線する')
    if not os.path.exists(BINARY):
        warnings.append(
            f'バイナリ不在: {BINARY} が無い（ccchain.enable=true・hook配線済みでも空振りする）。'
            f' `go install github.com/fruitriin/EnumaElish/cmd/ccchain@latest` で取得し'
            f' プロジェクトルートに `ccchain` として配置すること')
else:
    if wired:
        if apply_mode:
            remove_hook(settings)
            save_settings(settings)
            actions.append(f'撤去: {SETTINGS} から ccchain フックを削除')
        else:
            warnings.append(
                f'残存: {SETTINGS} に ccchain フックが残っている（ccchain.enable=false）。'
                f' apply で撤去する')
    if conf_exists:
        warnings.append(
            f'残存: {TARGET_CONF} が残っている（ccchain.enable=false）。'
            f' 不要なら手動で削除する（sync-ccchain.py は自動削除しない —'
            f' チューニング済みの設定を誤って失わないため）')

for msg in actions:
    print(msg)
for msg in warnings:
    print(f'WARNING: {msg}')

if warnings:
    sys.exit(2)
state = '有効（配置・配線済み）' if enabled else '無効'
print(f'OK: ccchain 同期 — {state}')
