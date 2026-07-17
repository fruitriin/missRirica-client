#!/usr/bin/env python3
"""オプショナルスキル同期 — GUI スキルの有効化コピーを Behavior.toml と整合させる

GUI を扱うスキル・エージェント定義は `.claude/addf/optional/` に原本として退避されており、
`addf-Behavior.toml` の `[gui-test] enable` でオプトインしたときだけ発見パス
（`.claude/commands/` / `.claude/agents/`）へコピーで実体化される。
無効時はスキルがコンテキストに載らず、GUI の無い環境でエージェントが
GUI テストを試みる余地もなくなる。

3原則:
- 原本（.claude/addf/optional/）が真実源。コミット対象は原本のみ
- 有効化コピーは使い捨て（gitignore 済み・いつでも再生成可能）
- 有効化コピーが原本と異なる場合は削除・上書きしない（WARNING で報告し人間に委ねる。
  直接編集は原本に対して行い、apply で再配置するのが正しい手順）

シンボリックリンクではなくコピーを使う理由: ダウンストリームは Windows も対象で、
シンボリックリンクは権限（Developer Mode）と git 設定（core.symlinks）依存が強い。

check モードは配置状態に加えて以下も検査する（列挙の陳腐化・孤児化の防止）:
- 有効化コピーのパスが .gitignore の ADDF ブロックに列挙されているか
- .gitignore に列挙された有効化コピーが原本を失って孤立していないか
  （原本のリネーム・削除に有効化コピーが取り残されるケース）

使い方:
  uv run --python 3.11 sync-optional-skills.py          # check モード（lint。変更しない）
  uv run --python 3.11 sync-optional-skills.py apply    # 配置・撤去を実行する

/addf-gui-test 自体が退避対象のため、同期の入口はスキルではなくこのスクリプトに置く。
`.claude/addf/optional/` が存在しない場合は SKIP する（未配布構成は問題ではない）。
Behavior.toml の構文エラーは SKIP（構文検査は lint-toml.py の責務）。

exit code: 0 = 整合 / 1 = ERROR（enable が真偽値でない等の設定不正） / 2 = WARNING あり
"""
import os
import shutil
import sys

try:
    import tomllib
except ModuleNotFoundError:
    # tomllib は Python 3.11+。check は SKIP（配布先で誤 ERROR を出さない）、
    # apply は配置できていないのに成功を装わないため ERROR で止める
    _hint = (f'tomllib がありません（Python {sys.version.split()[0]}）。'
             '`uv run --python 3.11` または Python 3.11+ で実行してください')
    # 後段の apply_mode と同一ロジック。判定を変えるときは両方揃えること
    if len(sys.argv) > 1 and sys.argv[1] == 'apply':
        print(f'ERROR: {_hint}')
        sys.exit(1)
    print(f'SKIP: {_hint}')
    sys.exit(0)

BEHAVIOR = '.claude/addf/Behavior.toml'
OPTIONAL_ROOT = '.claude/addf/optional'
GITIGNORE = '.gitignore'
# 原本ディレクトリ → 有効化先ディレクトリ
DIR_MAP = {
    f'{OPTIONAL_ROOT}/commands': '.claude/commands',
    f'{OPTIONAL_ROOT}/agents': '.claude/agents',
}

apply_mode = len(sys.argv) > 1 and sys.argv[1] == 'apply'
warnings = []
actions = []


def gui_test_enabled():
    """[gui-test] enable を返す。ファイル不在/構文エラーは SKIP、型不正は ERROR で終了"""
    if not os.path.exists(BEHAVIOR):
        print(f'SKIP: {BEHAVIOR} が存在しない')
        sys.exit(0)
    try:
        with open(BEHAVIOR, 'rb') as f:
            conf = tomllib.load(f)
    except tomllib.TOMLDecodeError as e:
        print(f'SKIP: {BEHAVIOR} が構文エラーのため判定不能（lint-toml.py が検出する）: {e}')
        sys.exit(0)
    raw = conf.get('gui-test', {}).get('enable', False)
    if not isinstance(raw, bool):
        # 文字列 "false" は bool() で True になり、ユーザーの意図と正反対の配置が起きる
        print(f'ERROR: [gui-test] enable は真偽値である必要がある（現在: {raw!r}）。'
              f' クオート無しの true / false で指定する')
        sys.exit(1)
    return raw


def pairs():
    """(原本パス, 有効化コピーパス) を列挙する"""
    out = []
    for src_dir, dst_dir in DIR_MAP.items():
        if not os.path.isdir(src_dir):
            continue
        for name in sorted(os.listdir(src_dir)):
            if name.endswith('.md'):
                out.append((os.path.join(src_dir, name),
                            os.path.join(dst_dir, name)))
    return out


def same_content(a, b):
    with open(a, 'rb') as fa, open(b, 'rb') as fb:
        return fa.read() == fb.read()


def gitignore_addf_entries():
    """ADDF マーカーブロック内のエントリを返す（.gitignore 不在時は None = 検査しない）"""
    if not os.path.exists(GITIGNORE):
        return None
    entries, in_block = [], False
    with open(GITIGNORE) as f:
        for line in f.read().splitlines():
            s = line.strip()
            if s.startswith('# --- /ADDF Framework'):
                in_block = False
                continue
            if s.startswith('# --- ADDF Framework'):
                in_block = True
                continue
            if in_block and s and not s.startswith('#'):
                entries.append(s)
    return entries


def check_gitignore_consistency(pair_list):
    """有効化コピーの gitignore 列挙漏れと、原本を失った孤児コピーを検査する"""
    entries = gitignore_addf_entries()
    if entries is None:
        return  # .gitignore 不在（サンドボックス等）は検査対象外
    dsts = {dst for _, dst in pair_list}
    # 列挙漏れ: 原本があるのに gitignore に載っていない → 有効化コピーがコミットされうる
    for dst in sorted(dsts):
        if dst not in entries:
            warnings.append(
                f'gitignore 列挙漏れ: {dst} が {GITIGNORE} の ADDF ブロックに無い。'
                f' 有効化コピーが誤ってコミットされうるため追記する')
    # 孤児: gitignore に載っている有効化コピーが実在するのに原本が無い
    managed_dirs = tuple(f'{d}/' for d in DIR_MAP.values())
    for entry in entries:
        if entry.startswith(managed_dirs) and entry not in dsts \
                and os.path.exists(entry):
            warnings.append(
                f'孤立: {entry} に対応する原本が {OPTIONAL_ROOT} に無い'
                f'（原本のリネーム・削除に取り残された可能性）。内容を確認して'
                f' 原本を復元するか、このコピーと gitignore エントリを削除する')


if not os.path.isdir(OPTIONAL_ROOT):
    print(f'SKIP: {OPTIONAL_ROOT} が存在しない')
    sys.exit(0)

enabled = gui_test_enabled()
pair_list = pairs()

for src, dst in pair_list:
    if enabled:
        if not os.path.exists(dst):
            if apply_mode:
                if os.path.islink(dst):  # リンク切れの残骸はコピー前に除去する
                    os.remove(dst)
                shutil.copy2(src, dst)
                actions.append(f'配置: {dst}')
            else:
                warnings.append(
                    f'未配置: {dst} が無い（gui-test.enable=true）。'
                    f' `uv run --python 3.11 .claude/addf/addfTools/sync-optional-skills.py apply` で配置する')
        elif not same_content(src, dst):
            # 有効化コピー側の直接編集か原本の更新か区別できないため自動では触らない
            warnings.append(
                f'差分: {dst} が原本 {src} と異なるため触らない。diff を確認して'
                f'変更を原本側に取り込み、{dst} を削除してから apply で再配置する')
    else:
        if os.path.exists(dst):
            if same_content(src, dst):
                if apply_mode:
                    os.remove(dst)
                    actions.append(f'撤去: {dst}')
                else:
                    warnings.append(
                        f'残存: {dst} が残っている（gui-test.enable=false）。'
                        f' apply で撤去する')
            else:
                warnings.append(
                    f'残存(改変あり): {dst} は原本と異なるため削除しない。'
                    f' 変更内容を確認し、必要なら原本に取り込んでから手で削除する')

check_gitignore_consistency(pair_list)

for msg in actions:
    print(msg)
for msg in warnings:
    print(f'WARNING: {msg}')

if warnings:
    sys.exit(2)
state = '有効（配置済み）' if enabled else '無効（撤去済み）'
print(f'OK: オプショナルスキル同期 — gui-test は{state}')
