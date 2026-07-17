#!/usr/bin/env python3
"""integration ブランチの生成と speculative feature の squash 統合。

/addf-speculate の統合ステップから呼ばれる決定的スクリプト。
integration ブランチを base から作り直し（使い捨て・再生成可能）、指定された
speculative/ ブランチを1本ずつ squash マージして「1 feature = 1コミット」の
統合ブランチを組み立てる。衝突した feature はスキップして報告し、続行する。
解釈（Worktrees.md / Dashboard への記録・衝突 feature の扱い）はエージェントが行う
（検出=スクリプト / 解釈=エージェント）。

メインの作業ツリーには一切触れない: 統合は専用 worktree の中だけで行う。
統合後の worktree は Stage 2（integration 上でのテスト・一括レビュー）のために
残して worktree= で報告する。掃除はサイクル末にエージェントが行う。

tomllib を使わないため、システム python3（3.9 等）でそのまま動く（uv 不要）。

使い方:
  python3 speculate-integrate.py [--base <branch>] [--name integration/loop-<日付>] \
      speculative/<concept> [speculative/<concept> ...]

  --base: 統合の起点ブランチ。省略時は `git symbolic-ref refs/remotes/origin/HEAD` から
      origin の default branch（origin/<name> の <name>）を自動検出する。
      検出した <name> のローカルブランチが無い場合（fetch 済み・ローカルブランチ無しの
      CI/コンテナ環境）は remote-tracking ref の origin/<name> を起点にする。
      検出できない場合（remote なし・未設定）は NOTE を stdout に出して main に
      フォールバックする（サイレントにしない）。
      remote 名は origin 固定を前提とする — fork ワークフロー（upstream が権威）等、
      origin が権威でない構成では --base を明示指定すること
  --name: integration ブランチ名（デフォルト: integration/loop-<今日 YYYY-MM-DD>）
  worktree は base リポジトリの隣（../<リポジトリ名>-integration）に作る。
  同名の integration ブランチ・worktree が既にあれば除去して作り直す（使い捨て）。
  ただし置き先パスが git 管理外のディレクトリだった場合は ERROR（勝手に消さない）。

出力（stdout、key=value 形式）:
  branch=integration/loop-2026-07-03
  worktree=/abs/path/to/repo-integration
  base=main
  integrated=speculative/a,speculative/b   # squash 統合できた feature
  conflicted=speculative/c                 # 衝突してスキップした feature
  missing=speculative/d                    # 存在しなかったブランチ
  empty=speculative/e                      # base との差分が無かった feature
  commit_failed=speculative/f              # 差分があるのに commit できなかった（フック拒否等）
  CONFLICT: speculative/c: <衝突ファイル一覧>   # conflicted の詳細（1行/feature）

exit code（3値）:
  0 = 全 feature 統合成功
  1 = ERROR（base 不在・worktree 作成失敗などの前提不成立、または commit_failed あり —
      差分の握り潰しは silent にしない）
  2 = WARNING（conflicted / missing / empty が1件以上。統合ブランチ自体は生成済み）

なお [speculation].enable の判定は行わない（それは投機を「新規に開始する」ゲートで
speculate-guard.py の責務。本スクリプトは既存 speculative/ ブランチへの明示的な統合操作）。
"""
import argparse
import datetime
import os
import subprocess
import sys

GIT_ID = ['-c', 'user.name=addf-speculate', '-c', 'user.email=speculate@addf.local']


def run(args, cwd=None):
    return subprocess.run(['git'] + args, cwd=cwd, capture_output=True, text=True)


def die(msg):
    print(f'ERROR: {msg}')
    sys.exit(1)


def branch_exists(name):
    return run(['rev-parse', '--verify', '--quiet', f'refs/heads/{name}']).returncode == 0


def detect_default_branch():
    """origin の default branch を検出する。検出できなければ NOTE を出して main にフォールバックする。

    remote 名は origin 固定を前提とする（fork ワークフローでは --base を明示指定）。
    検出した <name> のローカルブランチが無い場合（fetch 済み・ローカルブランチ無しの
    CI/コンテナ環境）は remote-tracking ref の origin/<name> を返す。
    """
    prefix = 'refs/remotes/origin/'
    head = run(['symbolic-ref', '--quiet', 'refs/remotes/origin/HEAD'])
    ref = head.stdout.strip()
    if head.returncode == 0 and ref.startswith(prefix):
        name = ref[len(prefix):]
        if branch_exists(name):
            return name
        if run(['rev-parse', '--verify', '--quiet', f'origin/{name}']).returncode == 0:
            return f'origin/{name}'
        return name
    print('NOTE: origin の default branch を検出できず main を既定値として使用'
          '（誤りなら --base で明示指定）')
    return 'main'


def force_remove_worktree(path):
    """worktree を除去する。未コミットの変更は破棄されるため、あれば警告してから消す"""
    dirty = run(['status', '--porcelain'], cwd=path)
    if dirty.returncode == 0 and dirty.stdout.strip():
        print(f'WARNING: {path} の未コミット変更を破棄して作り直す（integration は使い捨て。'
              f' 残したい調査結果等は worktree 内に置かないこと）')
    return run(['worktree', 'remove', '--force', path])


def remove_worktree_of_branch(branch):
    """指定ブランチをチェックアウトしている worktree があれば除去する"""
    result = run(['worktree', 'list', '--porcelain'])
    path = None
    for line in result.stdout.splitlines():
        if line.startswith('worktree '):
            path = line[len('worktree '):]
        elif line == f'branch refs/heads/{branch}' and path:
            force_remove_worktree(path)
    run(['worktree', 'prune'])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', default=None,
                        help='統合の起点ブランチ。省略時は origin の default branch を自動検出'
                             '（remote 名は origin 固定 — fork ワークフロー等 origin が権威で'
                             'ない構成では明示指定する。検出不能時は NOTE を出して main）')
    parser.add_argument('--name', default=None)
    parser.add_argument('features', nargs='+')
    opts = parser.parse_args()

    name = opts.name or f'integration/loop-{datetime.date.today():%Y-%m-%d}'

    toplevel = run(['rev-parse', '--show-toplevel'])
    if toplevel.returncode != 0:
        die('git リポジトリ外で実行された')
    repo_root = toplevel.stdout.strip()

    if opts.base is None:
        opts.base = detect_default_branch()

    if run(['rev-parse', '--verify', '--quiet', opts.base]).returncode != 0:
        die(f'base ブランチ {opts.base} が存在しない')

    # feature の存在確認（無いものは missing として続行）
    missing = [f for f in opts.features if not branch_exists(f)]
    targets = [f for f in opts.features if f not in missing]

    # 既存の integration ブランチ・worktree を除去して作り直す（使い捨て）
    remove_worktree_of_branch(name)
    if branch_exists(name):
        if run(['branch', '-D', name]).returncode != 0:
            die(f'既存の {name} を削除できない')

    wt_path = os.path.join(os.path.dirname(repo_root),
                           f'{os.path.basename(repo_root)}-integration')
    if os.path.exists(wt_path):
        # git 管理の worktree 残骸なら除去できる。それ以外は勝手に消さない
        if force_remove_worktree(wt_path).returncode != 0:
            die(f'{wt_path} が既に存在し、git worktree として除去もできない。'
                f' 手で退避・削除してから再実行すること')
        run(['worktree', 'prune'])

    result = run(['worktree', 'add', '-b', name, wt_path, opts.base])
    if result.returncode != 0:
        die(f'integration worktree を作成できない: {result.stderr.strip()}')

    integrated, conflicted, empty, commit_failed = [], [], [], []
    conflict_details = []
    for feature in targets:
        merge = run(['merge', '--squash', feature], cwd=wt_path)
        if merge.returncode != 0:
            files = run(['diff', '--name-only', '--diff-filter=U'], cwd=wt_path)
            conflict_details.append(
                f"CONFLICT: {feature}: {', '.join(files.stdout.splitlines()) or '(不明)'}")
            conflicted.append(feature)
            # 衝突の残骸を worktree 内だけで巻き戻す
            run(['reset', '--hard', 'HEAD'], cwd=wt_path)
            run(['clean', '-fd'], cwd=wt_path)
            continue
        if run(['diff', '--cached', '--quiet'], cwd=wt_path).returncode == 0:
            # 本当に差分なし（base に取り込み済み等）。統合失敗ではないので empty として報告
            empty.append(feature)
            run(['reset', '--hard', 'HEAD'], cwd=wt_path)
            continue
        commit = run(GIT_ID + ['commit', '-m', f'[統合] {feature} を squash 統合'],
                     cwd=wt_path)
        if commit.returncode != 0:
            # 差分があるのに commit できない（フック拒否等）。変更の握り潰しを
            # 「差分なし」と偽らない — commit_failed として ERROR で報告する
            commit_failed.append(feature)
            run(['reset', '--hard', 'HEAD'], cwd=wt_path)
            run(['clean', '-fd'], cwd=wt_path)
            continue
        integrated.append(feature)

    print(f'branch={name}')
    print(f'worktree={wt_path}')
    print(f'base={opts.base}')
    print(f"integrated={','.join(integrated)}")
    print(f"conflicted={','.join(conflicted)}")
    print(f"missing={','.join(missing)}")
    print(f"empty={','.join(empty)}")
    print(f"commit_failed={','.join(commit_failed)}")
    for line in conflict_details:
        print(line)

    if commit_failed:
        print(f"ERROR: 差分があるのに commit できなかった feature がある"
              f"（{','.join(commit_failed)}）。commit フックの拒否等が疑われる。"
              f" 原因を解消してから再実行すること")
        sys.exit(1)
    sys.exit(2 if (conflicted or missing or empty) else 0)


if __name__ == '__main__':
    main()
