#!/usr/bin/env python3
"""コンテキスト残量リマインダー — 実測トークン数に基づく能動コンパクション促し

UserPromptSubmit フックの stdin JSON（turn-reminder.sh から中継）を受け取り、
transcript JSONL の直近 assistant メッセージの usage からコンテキスト使用量を
実測する。設定閾値を超えていたら「観測事実＋モデル別の実効コンテキスト目安」を
注入し、能動コンパクション（知見記録→整理）の判断はモデル自身に委ねる。

設計（.claude/addf/plans-add/0023-turn-reminder-context-split.md）:
- フックの仕事は事実の注入のみ。固定文言で状態を断言しない
- ウィンドウ variant（200k/1M）は transcript から判別できないため、
  モデル名に対する「実効コンテキストの目安」を設定表から添えるだけにする
- usage が取得できない状況（transcript 不在・圧縮直後・パース失敗）は静かに終了する
  （誤発火より無発火が安全。ターンベースの棚卸しリマインダーは別途生きている）

設定（addf/Behavior.toml）:
  [context-reminder]
  threshold_tokens = 180000        # 発火閾値（0 で無効化）
  renotify_step_tokens = 50000     # 再通知に必要な増分
  [context-reminder.effective-context]
  opus = 200000                    # モデル名（部分一致）→ 実効コンテキスト目安

状態: .claude/.context-reminder-state に前回通知時の実測値を保持する。
実測値が前回通知より小さくなったら（コンパクション後）状態をリセットする。
"""
import json
import os
import re
import sys

TAIL_BYTES = 2 * 1024 * 1024  # transcript は末尾だけ読む


def read_settings(project_dir):
    """addf/Behavior.toml の [context-reminder] を依存なしで読む（tomllib 非依存）"""
    settings = {'threshold_tokens': 180000, 'renotify_step_tokens': 50000}
    effective = {}
    path = os.path.join(project_dir, '.claude', 'addf', 'Behavior.toml')
    if not os.path.exists(path):
        return settings, effective
    section = None
    with open(path) as f:
        for line in f:
            line = line.split('#', 1)[0].strip()
            if not line:
                continue
            m = re.match(r'\[([\w.-]+)\]$', line)
            if m:
                section = m.group(1)
                continue
            m = re.match(r'"?([\w.-]+)"?\s*=\s*(\d+)$', line)
            if not m:
                continue
            key, value = m.group(1), int(m.group(2))
            if section == 'context-reminder' and key in settings:
                settings[key] = value
            elif section == 'context-reminder.effective-context':
                effective[key] = value
    return settings, effective


def last_assistant_usage(transcript_path):
    """メインチェーン直近の assistant エントリから (使用量合算, モデル名) を返す"""
    size = os.path.getsize(transcript_path)
    with open(transcript_path, 'rb') as f:
        if size > TAIL_BYTES:
            f.seek(size - TAIL_BYTES)
            f.readline()  # 途中から読むため先頭の不完全な行を捨てる
        chunk = f.read().decode('utf-8', errors='replace')
    result = None
    for line in chunk.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get('type') != 'assistant' or entry.get('isSidechain'):
            continue
        usage = entry.get('message', {}).get('usage')
        if not usage:
            continue
        total = (usage.get('input_tokens', 0)
                 + usage.get('cache_read_input_tokens', 0)
                 + usage.get('cache_creation_input_tokens', 0))
        result = (total, entry.get('message', {}).get('model', '不明'))
    return result


def main():
    project_dir = os.environ.get('CLAUDE_PROJECT_DIR', '.')
    hook_input = json.load(sys.stdin)
    transcript_path = hook_input.get('transcript_path')
    if not transcript_path or not os.path.exists(transcript_path):
        return

    settings, effective = read_settings(project_dir)
    threshold = settings['threshold_tokens']
    if threshold <= 0:  # 無効化
        return

    found = last_assistant_usage(transcript_path)
    if not found:
        return
    total, model = found

    state_path = os.path.join(project_dir, '.claude', '.context-reminder-state')
    last_notified = 0
    if os.path.exists(state_path):
        try:
            with open(state_path) as f:
                last_notified = int(f.read().strip() or 0)
        except ValueError:
            last_notified = 0

    if total < last_notified:  # コンパクション等で使用量が下がった → 状態リセット
        os.remove(state_path)
        last_notified = 0
    if total < threshold:
        return
    if last_notified and total - last_notified < settings['renotify_step_tokens']:
        return  # 通知済みで増分が小さいうちは黙る

    # transcript 由来の値で注入タグ構造が壊れないよう無害化する
    model = re.sub(r'[<>\r\n]', ' ', model)[:80]
    # 目安キーは単語単位の部分一致（"o" が "opus" に誤マッチしない）
    guideline = next((f'このモデルの実効コンテキストの目安は約 {v:,} トークン'
                      f'（addf/Behavior.toml の設定値）。'
                      for k, v in effective.items()
                      if re.search(r'(?<![a-z0-9])' + re.escape(k) + r'(?![a-z0-9])', model)),
                     None)
    if guideline is None:
        guideline = 'このモデルの実効コンテキスト目安は未設定。自分のモデルのコンテキストウィンドウと突き合わせて判断すること。'

    with open(state_path, 'w') as f:
        f.write(str(total))
    print(f"""<user-prompt-submit-hook>
[コンテキスト使用量の観測] 現在の実測使用量は約 {total:,} トークン（モデル: {model}）。
{guideline}
目安を超えている・近いと判断したら、システムコンパクションに巻き込まれる前に
知見の記録（/addf-knowhow）と Progress.md の日記更新を済ませること。
これは作業を縮小・切り上げる指示ではない。整理を済ませたら、そのまま作業を継続してよい。
記録が済んでいるなら、そのまま作業を続行してよい。compaction を起こすのは harness の
仕事であり、復帰フックと日記が受け止める準備は整っている。エージェントの仕事は
止まらないことである（Plan 0041 の教義）。
</user-prompt-submit-hook>""")


if __name__ == '__main__':
    try:
        main()
    except Exception:
        sys.exit(0)  # 取得不能・パース失敗は静かに終了（誤発火より無発火が安全）
