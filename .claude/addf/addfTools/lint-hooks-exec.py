#!/usr/bin/env python3
"""hooks 実行権限チェック — .claude/hooks/*.sh が実行可能かを検査する

実行権限のないフックは settings.json に登録されていても静かに失敗し、
ターンカウンター等の安全網が機能しない（手検査依存は見落としの温床）。
addf-lint セクション2 の手作業チェックをスクリプト化したもの。

.claude/hooks/ が存在しない場合は SKIP する（フック未導入の構成は問題ではない）。

exit code: 0 = 全て実行可能 / 2 = WARNING あり
"""
import glob
import os
import sys

HOOKS_DIR = '.claude/hooks'

if not os.path.isdir(HOOKS_DIR):
    print(f'SKIP: {HOOKS_DIR} が存在しない')
    sys.exit(0)

not_executable = [
    path for path in sorted(glob.glob(f'{HOOKS_DIR}/*.sh'))
    if not os.access(path, os.X_OK)
]

if not_executable:
    print('WARNING: 以下のフックに実行権限がない'
          '（settings.json に登録されていても静かに失敗する。'
          ' `chmod +x <ファイル>` で付与する）:')
    for path in not_executable:
        print(f'    {path}')
    sys.exit(2)

print(f'OK: hooks 実行権限チェック通過（{HOOKS_DIR}/*.sh）')
