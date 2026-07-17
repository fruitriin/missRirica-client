#!/usr/bin/env python3
"""addf-Behavior.toml 構文チェック"""
import sys

try:
    import tomllib
except ModuleNotFoundError:
    # tomllib は Python 3.11+。旧環境では検査せず SKIP（配布先で誤 ERROR を出さない）
    print(f'SKIP: tomllib がありません（Python {sys.version.split()[0]}）。'
          '`uv run --python 3.11` または Python 3.11+ で実行してください')
    sys.exit(0)

try:
    with open('.claude/addf/Behavior.toml', 'rb') as f:
        tomllib.load(f)
    print('OK')
except FileNotFoundError:
    print('SKIP: ファイルなし')
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
