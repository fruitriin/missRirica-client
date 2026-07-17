#!/usr/bin/env python3
"""speculative/integration ブランチと worktree の状態走査（check）・確定済み削除（clean）。

/addf-speculate のサイクル冒頭（再構築と掃除）と `clean` サブコマンドから呼ばれる
決定的スクリプト。git の実体（worktree・ローカル/リモートブランチ）を走査して
機械的事実を key=value で出力するまでが責務で、解釈（.claude/addf/Worktrees.md との突合・
復元・「昇格済み」の確定判断）はエージェントが行う（検出=スクリプト / 解釈=エージェント）。

原則の例外（不可逆な削除だけは記録との突合をスクリプトが強制する）:
  `--delete` 対象については、`.claude/addf/Worktrees.md` の該当行の状態が「昇格済み」または
  「放棄」であることをスクリプト自身が検証する。ファイルが無い・行が無い・状態が違う場合は
  「記録なし/不一致」として削除せず ERROR で中断する（`--force-delete` 併用時のみスキップ）。
  消したら戻らない操作の安全は、解釈の柔軟さより優先する。

tomllib を使わないため、システム python3（3.9 等）でそのまま動く（uv 不要）。

merged_hint の限界（重要）:
  `git cherry <base> <branch>` の全コミットが `-`（等価パッチが base に存在）なら
  merged_hint=yes（取り込み済みの可能性）とする。ただし **squash マージは履歴が
  繋がらず、複数コミットを1つに畳むとパッチ等価も成立しない**ため、正規フロー
  （squash 昇格）で main に取り込まれたブランチは**恒常的に merged_hint=no のまま**になる。
  これは壊れているのではなく、履歴が繋がらないため検出できないだけである。
  「昇格済み」の確定はスクリプトではできない — yes/no/unknown はあくまでヒントであり、
  確定判断は Worktrees.md の記録とエージェントに委ねる。

使い方:
  python3 speculate-reconcile.py [check] [--base main] [--today YYYY-MM-DD]
  python3 speculate-reconcile.py clean [--delete <branch>]... [--prune-worktrees]
      [--keep-integrations] [--force-delete] [--base main] [--today YYYY-MM-DD]

  --today: integration/loop-<日付> の当日/過去判定に使う（省略時は今日）。
           **テスト注入用の引数**であり、注入してよいのは過去日付のみ。実システム日付より
           未来の日付は ERROR（未来を today にすると当日の integration まで「過去」扱いに
           なり誤削除するため）
  --base:  merged_hint の比較先ブランチ（デフォルト: main）
  --delete: 削除を確定した speculative ブランチ（複数指定可・重複指定は除去される）。
           **削除専用であり、main への統合（昇格）は一切しない**。昇格は
           addf-speculate.md「昇格手順」（オーナー承認必須）で行う
  --force-delete: Worktrees.md 突合と dirty worktree 保護をスキップして削除する
  --keep-integrations: 過去 integration/loop-* の自動削除をスキップする

check モード（デフォルト）の出力（stdout、key=value 形式）:
  today=2026-07-03
  base=main
  remote=origin|none                        # remote 無しは SKIP 行も出す
  speculative_worktree=<branch>:<path>      # 1行/worktree
  detached_worktree=<path>                  # どのブランチにも属さない worktree（残骸候補）
  local_speculative=speculative/a,...
  remote_speculative=speculative/a,...      # origin/speculative/*（remote 無しは省略）
  integration_today=integration/loop-...    # 猶予内（当日・前日・未来日）の integration
  integration_past=integration/loop-...     # 2日以上前の integration（clean の削除対象）
  integration_undated=...                   # 日付が読めない integration（保護）
  pending_count=0                           # Worktrees.md の状態「Pending」行数（投機在庫の機械シグナル）
  active_count=0                            # Worktrees.md の進行中状態（ACTIVE_STATES）の行数
  branch=speculative/a worktree=yes|no origin=yes|no|unknown merged_hint=yes|no|unknown

  pending_count / active_count は Worktrees.md の**投機管理表**（ヘッダに「ブランチ」
  「状態」列を持つ表）だけを列位置ベースで数える。ヘッダの無い表・無関係テーブルは
  対象外（概念名など他列のセルが状態語で始まっていても誤計上しない）。

  「過去」の判定には1日の猶予がある: branch 日付 < today - 1日 のみ past とする
  （前日以前ではなく**2日以上前**。当日深夜に作った integration が日付またぎ一発で
  削除対象になるのを防ぐ）。

  冒頭で `git worktree prune` を実行する（rm -rf された stale worktree の掃除。
  speculate-guard.py は読み取り専用のため、prune するまで stale が active に
  カウントされ続ける既知の制約への対応）。

clean モードの削除ルール（実行順）:
  1. 2日以上前の `integration/loop-*` ブランチとその worktree は**常に自動削除**する
     （猶予内・日付不明のものは残す。`--keep-integrations` でオプトアウト可）
  2. `--delete <branch>` で明示指定された speculative ブランチを、
     worktree（あれば）→ ローカルブランチ → origin 側（remote があれば）の順で削除する。
     削除前に Worktrees.md の記録と突合する（冒頭「原則の例外」参照）。
     **origin 側の削除はローカル側（worktree・ブランチ）の削除完了が前提**:
     ローカルが未確定のまま origin だけ消える事故を防ぐため、ローカル削除が失敗したら
     `kept=origin:<branch>` として origin には触れない
  消してはいけない（判断待ち保護）:
  - 明示指定のない speculative ブランチ。worktree ディレクトリだけ外したい場合は
    `--prune-worktrees` を付ける（ブランチは残る。未コミット変更のある worktree は
    外さず WARNING にする — silent に捨てない）
  未コミット変更のある worktree は `--delete` 対象・過去 integration とも**既定で削除拒否**
  （kept= + WARNING）。`--force-delete` 併用時のみ WARNING を出して破棄する。
  削除・保護の各行を removed= / kept= で報告する。

exit code（3値）:
  0 = 走査完了 / 削除完了
  1 = ERROR（git リポジトリ外・引数不正・--today が未来日付・Worktrees.md 突合の不一致など
      前提不成立）
  2 = 要確認。実害系は `WARNING:`（削除失敗・dirty 破棄・origin 保護など）、
      指定ミス系は `NOTE:`（speculative/ 以外の指定・指定ブランチ不在など）で区別して報告する
"""
import argparse
import datetime
import os
import re
import subprocess
import sys

INTEGRATION_RE = re.compile(r'^integration/loop-(\d{4}-\d{2}-\d{2})$')

# Worktrees.md の状態列の語彙（addf-speculate.md 手順5の列挙と同期。
# ACTIVE_STATES（active_count= の進行中状態リスト）は同手順 1.8 の在庫ゼロ判定の
# 列挙とも同期する — どちらかを変えたら両方を更新すること）
KNOWN_STATES = ['昇格済み', '放棄', '開発中', 'テスト通過', 'テスト失敗', '衝突',
                '統合済み', '上限で待機', '要再検証', 'Pending', '掃除済み']
DELETABLE_STATES = ('昇格済み', '放棄')
# 進行中状態（active_count= の計上対象。Pending 以外の「在庫が残っている」状態）
ACTIVE_STATES = ('開発中', 'テスト通過', 'テスト失敗', '衝突',
                 '統合済み', '要再検証', '上限で待機')


def run(args, cwd=None):
    return subprocess.run(['git'] + args, cwd=cwd, capture_output=True, text=True)


def die(msg):
    print(f'ERROR: {msg}')
    sys.exit(1)


def list_worktrees():
    """[(path, branch|None), ...] を返す（detached HEAD の worktree は branch=None）"""
    result = run(['worktree', 'list', '--porcelain'])
    entries = []
    path, branch = None, None
    for line in result.stdout.splitlines() + ['']:
        if line.startswith('worktree '):
            path = line[len('worktree '):]
            branch = None
        elif line.startswith('branch refs/heads/'):
            branch = line[len('branch refs/heads/'):]
        elif line == '':
            if path is not None:
                entries.append((path, branch))
            path, branch = None, None
    return entries


def local_branches(prefix):
    result = run(['for-each-ref', '--format=%(refname:short)', f'refs/heads/{prefix}'])
    return [b for b in result.stdout.splitlines() if b]


def remote_speculative():
    result = run(['for-each-ref', '--format=%(refname:short)',
                  'refs/remotes/origin/speculative/'])
    return [b[len('origin/'):] for b in result.stdout.splitlines() if b.startswith('origin/')]


def has_remote_origin():
    return run(['remote', 'get-url', 'origin']).returncode == 0


def classify_integration(today):
    """integration/loop-* を (猶予内, 過去, 日付不明) に分類する。
    「過去」は branch 日付 < today - 1日（2日以上前）のみ。1日の猶予は、当日深夜に作った
    integration が日付またぎ一発で削除対象になるのを防ぐ"""
    current, past, undated = [], [], []
    cutoff = today - datetime.timedelta(days=1)
    for branch in local_branches('integration/'):
        m = INTEGRATION_RE.match(branch)
        if not m:
            if branch.startswith('integration/loop-'):
                undated.append(branch)
            continue
        try:
            date = datetime.date.fromisoformat(m.group(1))
        except ValueError:
            undated.append(branch)
            continue
        (past if date < cutoff else current).append(branch)
    return current, past, undated


def merged_hint(base, branch):
    """base に等価パッチが全て存在するかのヒント。squash マージは検出できないため、
    正規フロー（squash 昇格）で取り込み済みでも no のままになる（docstring 参照）"""
    result = run(['cherry', base, branch])
    if result.returncode != 0:
        return 'unknown'
    lines = [l for l in result.stdout.splitlines() if l.strip()]
    if not lines or all(l.startswith('-') for l in lines):
        return 'yes'
    return 'no'


def worktrees_md_state(branch):
    """.claude/addf/Worktrees.md の表から branch の行の状態セルを緩く拾う。
    「| <path> | <branch> | ... | <状態> |」形式の行からセルを分割し、branch と一致する
    セルを含む行を探して、既知の状態語彙で始まるセルを状態として返す。
    返り値: ('no-file'|'no-row'|'found', 状態セル or None)"""
    top = run(['rev-parse', '--show-toplevel']).stdout.strip()
    path = os.path.join(top, '.claude', 'addf', 'Worktrees.md')
    if not os.path.isfile(path):
        return 'no-file', None
    with open(path, encoding='utf-8') as f:
        for line in f:
            stripped = line.strip()
            if not stripped.startswith('|'):
                continue
            cells = [c.strip() for c in stripped.strip('|').split('|')]
            if branch not in cells:
                continue
            for cell in cells:
                for state in KNOWN_STATES:
                    if cell.startswith(state):
                        return 'found', cell
            return 'found', None
    return 'no-row', None


def _worktrees_table_states():
    """.claude/addf/Worktrees.md の**投機管理表**の状態セルを列位置ベースで列挙する。

    ヘッダ行（「ブランチ」と「状態」の両列を持つ行 — 手順5の書式
    「| worktree パス | ブランチ | 対象概念（出典） | 状態 | 最終更新 |」）を検出して
    「状態」列のインデックスを特定し、後続行の**そのセルだけ**を状態として返す。
    ヘッダの無い表・無関係テーブルは対象外（概念名など他列のセルが状態語で
    始まっていても拾わない — worktrees_md_state() の緩い方式との違い。
    あちらは削除系の突合に使われており、挙動変更のリスクを避けるため触らない）。
    セル値は前後空白と `**` 強調を剥がしてから返す。ファイルが無ければ空リスト。
    """
    top = run(['rev-parse', '--show-toplevel']).stdout.strip()
    path = os.path.join(top, '.claude', 'addf', 'Worktrees.md')
    if not os.path.isfile(path):
        return []
    states = []
    state_idx = None
    with open(path, encoding='utf-8') as f:
        for line in f:
            stripped = line.strip()
            if not stripped.startswith('|'):
                state_idx = None  # 表が途切れた（次の表は改めてヘッダを要求する）
                continue
            cells = [c.strip() for c in stripped.strip('|').split('|')]
            if 'ブランチ' in cells and '状態' in cells:
                state_idx = cells.index('状態')  # 投機管理表のヘッダを検出
                continue
            if state_idx is None or state_idx >= len(cells):
                continue
            cell = cells[state_idx]
            if not cell or set(cell) <= set('-: '):
                continue  # 区切り行（|---|）・空セル
            states.append(cell.strip('*').strip())
    return states


def count_state_rows():
    """(pending_count, active_count) を返す — 投機在庫の機械シグナル。

    大改造の窓検出（addf-speculate.md 手順 1.8）の在庫ゼロ判定と、Pending 在庫上限の
    整理提案が参照する（Plan 0038 / 0035 申し送りの採用分）。Pending はスロット非占有・
    worktree 削除可のため、ブランチ走査だけでは在庫として見えないことがある —
    表の記録が唯一の網羅的シグナル。判定は完全一致寄り: 装飾を剥がしたセルが
    状態語そのもの、または状態語＋注記（「Pending（PR #9）」「放棄（実体なし）」等）の
    ときだけ数える（「開発中止」のような別語は数えない）。
    """
    pending = active = 0
    for cell in _worktrees_table_states():
        state = next((s for s in KNOWN_STATES
                      if cell == s or cell.startswith((s + '（', s + '(', s + ' '))), None)
        if state == 'Pending':
            pending += 1
        elif state in ACTIVE_STATES:
            active += 1
    return pending, active


def verify_delete_targets(branches):
    """不可逆な削除だけは記録との突合をスクリプトが強制する（docstring「原則の例外」）。
    Worktrees.md の状態が「昇格済み」「放棄」でない対象が1つでもあれば、何も消さずに ERROR"""
    problems = []
    for branch in branches:
        kind, state = worktrees_md_state(branch)
        if kind == 'no-file':
            problems.append(f'{branch}: .claude/addf/Worktrees.md が無く記録を確認できない（記録なし）')
        elif kind == 'no-row':
            problems.append(f'{branch}: Worktrees.md に記録なし')
        elif state is None or not state.startswith(DELETABLE_STATES):
            problems.append(f'{branch}: 状態「{state or "不明"}」'
                            '（削除できるのは「昇格済み」「放棄」のみ。'
                            'Pending 等の持ち越し・進行中の状態は削除対象外）')
    if problems:
        for p in problems:
            print(f'ERROR: --delete の突合に失敗: {p}')
        die('削除を中断した（Worktrees.md の記録を確定するか、検証を承知でスキップするなら --force-delete）')


def remove_worktree(path, force_delete, warnings):
    """worktree を除去する。未コミット変更があれば既定で拒否し（kept= + WARNING）、
    --force-delete 時のみ WARNING を出して破棄する。返り値: 除去できたか（bool）"""
    dirty = run(['status', '--porcelain'], cwd=path)
    if dirty.returncode == 0 and dirty.stdout.strip():
        if not force_delete:
            print(f'kept=worktree:{path} (未コミット変更があるため保護。破棄するなら --force-delete)')
            warnings.append(f'{path} に未コミット変更があるため除去しない（--force-delete で破棄可）')
            return False
        print(f'WARNING: {path} の未コミット変更を破棄して除去する')
        warnings.append(f'{path} の未コミット変更を破棄した（--force-delete 指定）')
    if run(['worktree', 'remove', '--force', path]).returncode == 0:
        print(f'removed=worktree:{path}')
        return True
    warnings.append(f'worktree を除去できない: {path}')
    return False


def do_check(opts, today):
    run(['worktree', 'prune'])
    worktrees = list_worktrees()
    spec_wts = [(p, b) for p, b in worktrees if b and b.startswith('speculative/')]
    wt_branches = {b for _, b in spec_wts}
    local_spec = local_branches('speculative/')
    remote_ok = has_remote_origin()
    remote_spec = set(remote_speculative()) if remote_ok else set()
    current, past, undated = classify_integration(today)

    print(f'today={today}')
    print(f'base={opts.base}')
    print(f"remote={'origin' if remote_ok else 'none'}")
    for path, branch in spec_wts:
        print(f'speculative_worktree={branch}:{path}')
    for path, branch in worktrees:
        if branch is None:
            # どのブランチ走査にも出ない detached HEAD の worktree（放置すると永久残骸）
            print(f'detached_worktree={path}')
    print(f"local_speculative={','.join(sorted(local_spec))}")
    if remote_ok:
        print(f"remote_speculative={','.join(sorted(remote_spec))}")
    else:
        print('SKIP: remote なし（origin/speculative の走査をスキップ）')
    print(f"integration_today={','.join(current)}")
    print(f"integration_past={','.join(past)}")
    if undated:
        print(f"integration_undated={','.join(undated)}")
    pending_count, active_count = count_state_rows()
    print(f'pending_count={pending_count}')
    print(f'active_count={active_count}')

    base_ok = run(['rev-parse', '--verify', '--quiet', opts.base]).returncode == 0
    for branch in sorted(local_spec):
        wt = 'yes' if branch in wt_branches else 'no'
        origin = ('yes' if branch in remote_spec else 'no') if remote_ok else 'unknown'
        hint = merged_hint(opts.base, branch) if base_ok else 'unknown'
        print(f'branch={branch} worktree={wt} origin={origin} merged_hint={hint}')
    sys.exit(0)


def do_clean(opts, today):
    warnings = []   # 実害系（削除失敗・dirty 破棄・origin 保護）
    notes = []      # 指定ミス系（speculative/ 以外の指定・指定ブランチ不在）
    run(['worktree', 'prune'])
    wt_by_branch = {b: p for p, b in list_worktrees() if b}
    local_spec = set(local_branches('speculative/'))
    remote_ok = has_remote_origin()
    remote_spec = set(remote_speculative()) if remote_ok else set()
    # 重複指定を除去する（同一ブランチを2度処理して「削除成功後の失敗」誤警告を出さない）
    deletes = list(dict.fromkeys(opts.delete or []))

    # 削除前の突合（何かを消し始める前に全対象を検証し、不一致なら ERROR で中断する）
    spec_targets = [b for b in deletes if b.startswith('speculative/')]
    if spec_targets and not opts.force_delete:
        verify_delete_targets(spec_targets)

    # 1. 過去（2日以上前）の integration/loop-* とその worktree は常に自動削除
    #    （猶予内・日付不明は残す。--keep-integrations でオプトアウト）
    current, past, undated = classify_integration(today)
    if opts.keep_integrations:
        for branch in past:
            print(f'kept=branch:{branch} (--keep-integrations で保護)')
    else:
        for branch in past:
            wt_gone = True
            if branch in wt_by_branch:
                wt_gone = remove_worktree(wt_by_branch[branch], opts.force_delete, warnings)
            if not wt_gone:
                print(f'kept=branch:{branch} (worktree を除去できないため削除しない)')
                continue
            if run(['branch', '-D', branch]).returncode == 0:
                print(f'removed=branch:{branch}')
            else:
                warnings.append(f'integration ブランチを削除できない: {branch}')
    for branch in current:
        print(f'kept=branch:{branch} (猶予内の integration)')
    for branch in undated:
        print(f'kept=branch:{branch} (日付を読めないため保護)')

    # 2. 明示指定されたブランチの削除（worktree → ローカル → origin）
    #    origin 側の削除はローカル側の削除完了（local_gone）が前提。ローカルが残ったまま
    #    origin だけ消えると、退避先（最後の砦）を先に失うため
    for branch in deletes:
        if not branch.startswith('speculative/'):
            print(f'kept=branch:{branch} (speculative/ 以外は --delete の対象外)')
            notes.append(f'--delete に speculative/ 以外が指定された: {branch}（削除しない）')
            continue
        found = False
        local_gone = True
        if branch in wt_by_branch:
            found = True
            if not remove_worktree(wt_by_branch[branch], opts.force_delete, warnings):
                local_gone = False
        if branch in local_spec:
            found = True
            if run(['branch', '-D', branch]).returncode == 0:
                print(f'removed=branch:{branch}')
            else:
                warnings.append(f'ローカルブランチを削除できない: {branch}')
                local_gone = False
        if branch in remote_spec:
            found = True
            if not local_gone:
                print(f'kept=origin:{branch}（ローカル削除未完了のため保護）')
                warnings.append(f'{branch} のローカル削除が未完了のため origin 側に触れない'
                                '（ローカル側を解消してから再実行する）')
            elif run(['push', 'origin', '--delete', branch]).returncode == 0:
                print(f'removed=origin:{branch}')
            else:
                warnings.append(f'origin 側を削除できない: {branch}（認証・ネットワークを確認）')
        elif not remote_ok:
            print(f'SKIP: remote なし（{branch} の origin 側削除をスキップ）')
        if not found:
            notes.append(f'--delete 指定の {branch} が見つからない'
                         '（worktree・ローカル・origin のいずれにも無い）')

    # 3. 明示指定のない speculative ブランチは保護（判断待ち）
    for branch in sorted(local_spec):
        if branch in deletes:
            continue
        if opts.prune_worktrees and branch in wt_by_branch:
            path = wt_by_branch[branch]
            # ブランチが真実源。ただし未コミット変更は worktree にしか無いため
            # 非 force で外し、dirty なら外さず知らせる（silent に捨てない）
            if run(['worktree', 'remove', path]).returncode == 0:
                print(f'removed=worktree:{path}')
                print(f'kept=branch:{branch} (判断待ち保護。worktree のみ外した)')
            else:
                print(f'kept=branch:{branch} (判断待ち保護)')
                print(f'kept=worktree:{path} (未コミット変更等で外せない)')
                warnings.append(f'{branch} の worktree を外せない: {path}'
                                '（未コミット変更があれば退避してから再実行）')
        else:
            print(f'kept=branch:{branch} (判断待ち保護)')

    for msg in warnings:
        print(f'WARNING: {msg}')
    for msg in notes:
        print(f'NOTE: {msg}')
    sys.exit(2 if (warnings or notes) else 0)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', nargs='?', choices=['check', 'clean'], default='check')
    parser.add_argument('--base', default='main')
    parser.add_argument('--today', default=None, metavar='YYYY-MM-DD')
    parser.add_argument('--delete', action='append', default=[], metavar='BRANCH',
                        help='削除を確定した speculative ブランチ（clean モード。複数指定可。'
                             '削除専用 — main への統合はしない。Worktrees.md の記録と突合される）')
    parser.add_argument('--force-delete', action='store_true',
                        help='Worktrees.md 突合と dirty worktree 保護をスキップして削除する')
    parser.add_argument('--keep-integrations', action='store_true',
                        help='過去日付 integration/loop-* の自動削除をスキップする（clean モード）')
    parser.add_argument('--prune-worktrees', action='store_true',
                        help='判断待ちブランチの worktree ディレクトリだけ外す（ブランチは残す）')
    opts = parser.parse_args()

    if run(['rev-parse', '--show-toplevel']).returncode != 0:
        die('git リポジトリ外で実行された')

    if opts.today:
        try:
            today = datetime.date.fromisoformat(opts.today)
        except ValueError:
            die(f'--today は YYYY-MM-DD 形式で指定すること（現在: {opts.today!r}）')
        if today > datetime.date.today():
            die(f'--today に未来日付は指定できない（テスト注入は過去日付のみ許容。'
                f'未来を today にすると当日の integration まで過去扱いになる: {opts.today}）')
    else:
        today = datetime.date.today()

    if opts.mode == 'clean':
        do_clean(opts, today)
    else:
        do_check(opts, today)


if __name__ == '__main__':
    main()
