#!/usr/bin/env python3
"""投機開発（/addf-speculate）の発動ガード。

addf-Behavior.toml の [speculation] を検証し、現在の speculative worktree 数と
上限を突き合わせて、投機を開始してよいかを決定的に判定する。
解釈と実際の投機はエージェントが行う（検出=スクリプト / 解釈=エージェント）。

出力（stdout、key=value 形式）:
  enable=true|false
  max_worktrees=<int>
  active=<現在の speculative worktree 数>
  slots=<残り枠>

exit code（3値 + 無効）:
  0 = OK（投機を開始してよい / enable=false の場合も正常終了で enable=false を出力）
  1 = ERROR（設定の型不正など。投機を開始してはならない）
  2 = WARNING（enable=true だが上限到達。新規投機は待機）
"""
import subprocess
import sys

try:
    import tomllib
except ModuleNotFoundError:
    # tomllib は Python 3.11+。設定を検証できない場合は投機を許可しない（フェイルセーフ）
    print(f'ERROR: tomllib がありません（Python {sys.version.split()[0]}）。'
          '`uv run --python 3.11` または Python 3.11+ で実行してください。投機は開始できません')
    sys.exit(1)

BEHAVIOR_PATH = '.claude/addf/Behavior.toml'
DEFAULT_MAX_WORKTREES = 3


def load_speculation_config():
    """[speculation] を読む。ファイル・セクション欠如は「無効」として扱う（欠如 = SKIP）"""
    try:
        with open(BEHAVIOR_PATH, 'rb') as f:
            config = tomllib.load(f)
    except FileNotFoundError:
        return {'enable': False, 'max_worktrees': DEFAULT_MAX_WORKTREES}
    except Exception as e:
        print(f'ERROR: {BEHAVIOR_PATH} の読み込みに失敗: {e}')
        sys.exit(1)

    spec = config.get('speculation')
    if spec is None:
        return {'enable': False, 'max_worktrees': DEFAULT_MAX_WORKTREES}

    enable = spec.get('enable', False)
    if not isinstance(enable, bool):
        # 文字列 "false" が truthy 判定される事故を防ぐ（bool 以外は型不正）
        print(f'ERROR: [speculation].enable は bool で指定すること（現在: {enable!r}）')
        sys.exit(1)

    max_worktrees = spec.get('max_worktrees', DEFAULT_MAX_WORKTREES)
    # bool は int のサブクラスのため先に弾く
    if isinstance(max_worktrees, bool) or not isinstance(max_worktrees, int) or max_worktrees < 1:
        print(f'ERROR: [speculation].max_worktrees は 1 以上の整数で指定すること（現在: {max_worktrees!r}）')
        sys.exit(1)

    return {'enable': enable, 'max_worktrees': max_worktrees}


def count_speculative_worktrees():
    """speculative/ ブランチをチェックアウトしている worktree 数を数える"""
    result = subprocess.run(
        ['git', 'worktree', 'list', '--porcelain'],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        # git リポジトリ外・git なし等。数えられない場合は 0 とする
        # （enable=false 環境の検査を邪魔しないため。enable=true で git が無い状況は実行時に破綻する）
        return 0
    count = 0
    for line in result.stdout.splitlines():
        if line.startswith('branch refs/heads/speculative/'):
            count += 1
    return count


def main():
    cfg = load_speculation_config()
    active = count_speculative_worktrees()
    slots = max(0, cfg['max_worktrees'] - active)

    print(f"enable={'true' if cfg['enable'] else 'false'}")
    print(f"max_worktrees={cfg['max_worktrees']}")
    print(f'active={active}')
    print(f'slots={slots}')

    if cfg['enable'] and slots == 0:
        print('WARNING: 上限到達。新規投機は待機（Worktrees.md と Dashboard に記録すること）')
        sys.exit(2)
    sys.exit(0)


if __name__ == '__main__':
    main()
