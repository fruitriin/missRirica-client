#!/usr/bin/env python3
"""JSON 構文チェック — settings.json / settings.local.json"""
import json, sys, os

errors = []
for path in ['.claude/settings.json', '.claude/settings.local.json']:
    if not os.path.exists(path):
        continue
    try:
        with open(path) as f:
            json.load(f)
    except json.JSONDecodeError as e:
        errors.append(f'{path}: {e}')

for e in errors:
    print(e)
sys.exit(1 if errors else 0)
