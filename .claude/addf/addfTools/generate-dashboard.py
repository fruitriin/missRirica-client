#!/usr/bin/env python3
"""ADDF ローカルダッシュボード生成（Plan 0058）。

リポジトリの状態（TODO テーブル・Plan の owner_feedback フィールド・Questions.md・
Progress.md・Progresses/・git 投機ブランチ・gh PR）から、VitePress でサーブできる
2ページのダッシュボード（要フィードバック・計画 / 進行中タスク）と
プランビューア（Plan 本文コピー）を `.claude/addf/dashboard/` に生成する。

- 出力ディレクトリ全体が生成物（.gitignore 対象）。単一ソースは常にリポジトリ側
- stdlib のみ。gh 不在・未認証は空リスト＋注記のフェイルセーフ
- owner_feedback フィールド未記入の未完了 Plan は「要判断（詳細は Plan 本文参照）」に
  フォールバック表示する（完全性を生成の前提にしない）

実行: python3 .claude/addf/addfTools/generate-dashboard.py（uv run でも動く）
閲覧: npm run dashboard:dev（ADDF 本体）。package.json に dashboard:* が無い
      ダウンストリームでは `npx vitepress dev .claude/addf/dashboard` で閲覧できる
      起動前に既存の dev サーバーが残っていないか確認する（`lsof -i :5180`）—
      複数プロセスが同じ DashboardComments.json に書き込む状態を避ける
テスト用: 環境変数 ADDF_DASHBOARD_ROOT でリポジトリルートを上書きできる
        （テストがサンドボックスに合成リポジトリを作って検証するためのフック）
"""

import datetime
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# --- リポジトリ検出 -----------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent
# .claude/addf/addfTools/ の3階層上。テストは ADDF_DASHBOARD_ROOT で上書きする
REPO_ROOT = Path(os.environ.get("ADDF_DASHBOARD_ROOT") or SCRIPT_DIR.parent.parent.parent).resolve()
ADDF_DIR = REPO_ROOT / ".claude" / "addf"
OUT_DIR = ADDF_DIR / "dashboard"

# upstream（ADDF 本体）は plans-add/TODO.addf.md、ダウンストリームは plans/TODO.md
if (ADDF_DIR / "plans-add" / "TODO.addf.md").exists():
    PLANS_DIR = ADDF_DIR / "plans-add"
    TODO_PATH = PLANS_DIR / "TODO.addf.md"
else:
    PLANS_DIR = ADDF_DIR / "plans"
    TODO_PATH = REPO_ROOT / "TODO.md"

QUESTIONS_PATH = ADDF_DIR / "Questions.md"
PROGRESS_PATH = ADDF_DIR / "Progress.md"
PROGRESSES_DIR = ADDF_DIR / "Progresses"
# アンカーコメントの単一ソース（Plan 0058 フェーズC。コミット対象の共有チャンネル）
COMMENTS_PATH = ADDF_DIR / "DashboardComments.json"
# crit（https://crit.md/）のレビューファイル置き場。テストは環境変数で上書きする
CRIT_REVIEWS_DIR = Path(
    os.environ.get("ADDF_CRIT_REVIEWS_DIR") or Path.home() / ".crit" / "reviews"
)

TODAY = datetime.date.today()

# --- 抽出: TODO テーブル -------------------------------------------------------

TODO_ROW_RE = re.compile(
    r"^\|\s*(?P<prio>[^|]+?)\s*\|\s*(?P<phase>[^|]+?)\s*\|\s*(?P<file>[^|]+?)\s*\|\s*(?P<state>.+?)\s*\|\s*$"
)


def parse_todo_rows():
    """TODO テーブルから (優先度, ファイルパス, 状態文字列) を返す。ヘッダ行等は除外。"""
    rows = []
    if not TODO_PATH.exists():
        return rows
    for line in TODO_PATH.read_text(encoding="utf-8").splitlines():
        m = TODO_ROW_RE.match(line)
        if not m:
            continue
        file_cell = m.group("file")
        pm = re.search(r"`([^`]+\.md)`", file_cell)
        if not pm:
            continue
        rows.append(
            {
                "prio": m.group("prio").strip("* "),
                "path": pm.group(1),
                "state": m.group("state"),
            }
        )
    return rows


# --- 抽出: Plan ヘッダ・FB フィールド ------------------------------------------

FIELD_RE = re.compile(r"^(owner_feedback|feedback_ask|feedback_since):\s*(.+?)\s*$")


def parse_plan(path: Path):
    """Plan ファイルからタイトル・実装状況・FB フィールドを抽出する。"""
    info = {
        "title": path.stem,
        "status_line": "",
        "owner_feedback": None,
        "feedback_ask": None,
        "feedback_since": None,
    }
    if not path.exists():
        return info
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("# ") and info["title"] == path.stem:
            info["title"] = re.sub(r"^Plan \d+:\s*", "", line[2:]).strip()
        elif line.startswith("## 実装状況:"):
            info["status_line"] = line[len("## 実装状況:") :].strip()
        else:
            m = FIELD_RE.match(line)
            if m:
                info[m.group(1)] = m.group(2)
    return info


def wait_days(since: str):
    try:
        d = datetime.date.fromisoformat(since)
        return (TODAY - d).days
    except (ValueError, TypeError):
        return None


# --- 抽出: Questions.md --------------------------------------------------------


def parse_questions():
    """未回答 Question のリストと回答済み件数を返す。"""
    unanswered, answered = [], []
    if not QUESTIONS_PATH.exists():
        return unanswered, answered
    text = QUESTIONS_PATH.read_text(encoding="utf-8")
    sections = re.split(r"^## ", text, flags=re.M)
    for sec in sections:
        is_open = sec.startswith("未回答")
        is_closed = sec.startswith("回答済み")
        if not (is_open or is_closed):
            continue
        for qm in re.finditer(r"^### (Q\d+): (.+?)$\n(.*?)(?=^### |\Z)", sec, re.M | re.S):
            qid, title, body = qm.group(1), qm.group(2).strip(), qm.group(3)
            dm = re.search(r"投下日時:\s*(\d{4}-\d{2}-\d{2})", body)
            pm = re.search(r"Plan (\d{4})", title)
            q = {
                "id": qid,
                "title": title,
                "since": dm.group(1) if dm else None,
                "plan": pm.group(1) if pm else None,
                "body": body.strip(),
            }
            (unanswered if is_open else answered).append(q)
    return unanswered, answered


# --- 抽出: Progress.md ---------------------------------------------------------


def parse_progress():
    """現在のタスク（タイトル・チェックリスト・最新日記）を返す。無ければ None。"""
    if not PROGRESS_PATH.exists():
        return None
    text = PROGRESS_PATH.read_text(encoding="utf-8")
    tm = re.search(r"^### 現在のタスク: (.+?)$(.*)", text, re.M | re.S)
    if not tm:
        return None
    title, body = tm.group(1).strip(), tm.group(2)
    # チェックリスト集計は「#### サブタスクチェックリスト」節に限定する
    # （日記本文に例示のチェックボックス記法が書かれても誤集計しない）
    cm = re.search(r"^#### サブタスクチェックリスト$(.*?)(?=^#### |\Z)", body, re.M | re.S)
    checklist_src = cm.group(1) if cm else body
    checklist = re.findall(r"^- \[([ x])\] (.+)$", checklist_src, re.M)
    diaries = re.findall(r"^##### (.+?)$\n(.*?)(?=^##### |\Z)", body, re.M | re.S)
    latest_diary = None
    if diaries:
        head, dbody = diaries[-1]
        latest_diary = {"head": head.strip(), "body": dbody.strip()}
    return {"title": title, "checklist": checklist, "diary": latest_diary}


def recent_progresses(n=5):
    if not PROGRESSES_DIR.exists():
        return []
    files = sorted(PROGRESSES_DIR.glob("*.md"), reverse=True)
    return [f.stem for f in files[:n]]


# --- 抽出: アンカーコメント・crit レビュー --------------------------------------


def parse_dashboard_comments():
    """DashboardComments.json から (未解決コメント, 下書き件数) を返す。

    下書き（status: "draft"）は「レビューを送信」前の見直し用ステージング —
    GitHub の PR レビューと同じメンタルモデルで、送信までエージェントの
    読み取り・キュー集約の対象にしない。不在は空、壊れは WARN + 空。
    """
    if not COMMENTS_PATH.exists():
        return [], 0
    try:
        data = json.loads(COMMENTS_PATH.read_text(encoding="utf-8"))
    except Exception:  # 壊れた JSON だけでなく PermissionError 等の OSError も生成は止めない
        print(f"WARN: {COMMENTS_PATH.name} が読めません（コメント表示をスキップします）")
        return [], 0
    comments = data.get("comments") if isinstance(data, dict) else None
    if not isinstance(comments, list):
        return [], 0
    valid = [c for c in comments if isinstance(c, dict)]
    unresolved = [c for c in valid if c.get("status") not in ("resolved", "draft")]
    drafts = sum(1 for c in valid if c.get("status") == "draft")
    return unresolved, drafts


def parse_crit_reviews():
    """crit レビューファイル群から未解決コメントを集める。crit 不在・壊れは空リスト。"""
    items = []
    if not CRIT_REVIEWS_DIR.is_dir():
        return items
    for rj in sorted(CRIT_REVIEWS_DIR.glob("*/review.json")):
        try:
            data = json.loads(rj.read_text(encoding="utf-8"))
        except Exception:
            continue
        files = data.get("files") if isinstance(data, dict) else None
        if not isinstance(files, dict):
            continue
        for fpath, finfo in files.items():
            # crit は ADDF が制御しない外部フォーマット — 「有効な JSON だが想定外の形状」
            # でも単一エントリのスキップに留め、生成全体を落とさない（レビュー2体が独立指摘）
            if not isinstance(finfo, dict):
                continue
            comments = finfo.get("comments")
            if not isinstance(comments, list):
                continue
            for c in comments:
                if not isinstance(c, dict) or c.get("resolved"):
                    continue
                items.append(
                    {
                        "session": rj.parent.name,
                        "file": fpath,
                        "body": c.get("body", ""),
                        "anchor": c.get("anchor", ""),
                        "author": c.get("author", ""),
                        "created_at": c.get("created_at", ""),
                    }
                )
    return items


# --- 抽出: git / gh ------------------------------------------------------------


def run_cmd(args, timeout=10):
    try:
        r = subprocess.run(
            args, cwd=REPO_ROOT, capture_output=True, text=True, timeout=timeout
        )
        return r.stdout if r.returncode == 0 else None
    except Exception:  # 非UTF-8ロケールの UnicodeDecodeError 等も含めフェイルセーフ
        return None


def speculative_branches():
    out = run_cmd(["git", "branch", "--list", "speculative/*", "--format=%(refname:short)"])
    branches = []
    for name in (out or "").split():
        cnt = run_cmd(["git", "rev-list", "--count", f"main..{name}"])
        branches.append({"name": name, "ahead": int(cnt) if cnt else None})
    return branches


def open_prs():
    """PR リストを返す。gh 不在・未認証・失敗時は None（呼び出し側で注記表示）。"""
    out = run_cmd(["gh", "pr", "list", "--state", "open", "--json", "number,title,createdAt,url"], timeout=8)
    if out is None:
        return None
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return None


# --- ページ生成 -----------------------------------------------------------------


def _fence_outside_lines(text: str):
    """コードフェンス外の行だけを yield する（esc_vue と同じ CommonMark 準拠の開閉判定）。"""
    fence_char, fence_len = None, 0
    for line in text.splitlines():
        fm = re.match(r"^\s*(`{3,}|~{3,})", line)
        if fm:
            delim = fm.group(1)
            if fence_char is None:
                fence_char, fence_len = delim[0], len(delim)
                continue
            if delim[0] == fence_char and len(delim) >= fence_len:
                fence_char, fence_len = None, 0
                continue
        if fence_char is None:
            yield line


def _collapse_tags_status(text: str):
    """フェンス外の <details>/<summary> タグの (出現有無, バランス成立) を返す。

    閉じ忘れの <details> は Vue コンパイルの "Element is missing end tag" で
    ダッシュボード全体（全ページ・全プランビューア）を巻き込むため、
    バランスが取れている場合のみパススルーを許可する（不成立時は全エスケープへ
    フォールバック — 欠如・壊れ＝フェイルセーフの設計に合わせる）。
    インラインコード内の言及もカウントに含まれるが、不均衡と誤判定された場合も
    「折りたたみにならず原文表示される」だけで表示は壊れない（安全側）。
    """
    opens_d = closes_d = opens_s = closes_s = 0
    for line in _fence_outside_lines(text):
        opens_d += len(re.findall(r"<details(?:\s[^<>]*)?>", line))
        closes_d += len(re.findall(r"</details\s*>", line))
        opens_s += len(re.findall(r"<summary(?:\s[^<>]*)?>", line))
        closes_s += len(re.findall(r"</summary\s*>", line))
    has = bool(opens_d or closes_d or opens_s or closes_s)
    balanced = opens_d == closes_d and opens_s == closes_s
    return has, balanced


def esc_vue(text: str, src: str = None) -> str:
    """Plan 原文を VitePress（Vue コンパイル）で安全に通すエスケープ。

    コードフェンス内は不変。フェンス外では、インラインコード区間を除き
    HTML コメント以外の `<`（例: `<番号>`・`speculative/<concept>`）と
    Vue 展開 `{{` をエスケープする。Plan 原文が意図的に使う生 HTML は
    `<!-- human-judgment -->` 等のコメントと、折りたたみ用の
    `<details>` / `<summary>`（フェーズC — GitHub 表示と両立する折りたたみ構文。
    開きタグ・閉じタグをペアで書くこと。閉じ忘れは Vue コンパイルエラーになる）のみ
    という前提（原文の忠実表示が目的）。VitePress ネイティブの
    `::: details タイトル` 構文は `<` を含まないためそのまま通る（第一推奨）。

    - フェンスは CommonMark 準拠で「同じ文字種・同じ長さ以上」でのみ閉じる
      （``` の中の ~~~ で誤って閉じない）
    - インラインコードは CommonMark 準拠で「同じ連長の閉じバッククォートが後に
      実在する場合のみコードスパン」とする先読みマッチング。閉じが無い単発
      バッククォートはリテラル扱いになり、以降のテキストは通常どおり
      エスケープされる（奇数バッククォート行でエスケープが免除される事故を防ぐ）。
      スパンは段落内（空行まで）なら行を跨いでよい
    """

    has_collapse, collapse_balanced = _collapse_tags_status(text)
    allow_collapse = has_collapse and collapse_balanced
    if has_collapse and not collapse_balanced:
        print(
            f"WARN: {src or 'テキスト'} の <details>/<summary> が閉じていません — "
            "折りたたみを無効化して全エスケープしました"
        )

    def esc_text(seg: str) -> str:
        # <!-- コメント --> と、タグバランスが取れている場合のみ <details>/<summary>
        # （属性付き・閉じタグ含む）を生 HTML として通す。
        # 限界（意図的に許容）: 属性値内の生 `>`（<details title="a>b">）は早期マッチで
        # 素通しする。<details/>（自己終了）・<Details>（大文字）は通さない（安全側）
        if allow_collapse:
            seg = re.sub(r"<(?!!--|/?(?:details|summary)(?:\s[^<>]*)?>)", "&lt;", seg)
        else:
            seg = re.sub(r"<(?!!--)", "&lt;", seg)
        return seg.replace("{{", "&#123;&#123;")

    def esc_paragraph(para: str) -> str:
        parts = re.split(r"(`+)", para)
        out, i = [], 0
        while i < len(parts):
            p = parts[i]
            if p and p == "`" * len(p):
                # 同じ連長の閉じデリミタを先読み
                j = i + 1
                while j < len(parts):
                    q = parts[j]
                    if q and q == "`" * len(q) and len(q) == len(p):
                        break
                    j += 1
                if j < len(parts):
                    out.extend(parts[i : j + 1])  # コードスパン: 不変
                    i = j + 1
                else:
                    out.append(p)  # 閉じ無し: リテラル。後続は通常エスケープ
                    i += 1
            else:
                out.append(esc_text(p))
                i += 1
        return "".join(out)

    out_lines = []
    para_buf = []  # フェンス外の段落バッファ（インラインコードスパンは段落内で解決）
    fence_char, fence_len = None, 0

    def flush_para():
        if para_buf:
            out_lines.append(esc_paragraph("\n".join(para_buf)))
            para_buf.clear()

    for line in text.splitlines():
        fm = re.match(r"^\s*(`{3,}|~{3,})", line)
        if fm:
            delim = fm.group(1)
            if fence_char is None:
                flush_para()
                fence_char, fence_len = delim[0], len(delim)
                out_lines.append(line)
                continue
            if delim[0] == fence_char and len(delim) >= fence_len:
                fence_char, fence_len = None, 0
                out_lines.append(line)
                continue
        if fence_char is not None:
            out_lines.append(line)
            continue
        if not line.strip():
            flush_para()
            out_lines.append(line)
            continue
        para_buf.append(line)
    flush_para()
    return "\n".join(out_lines)


def sv(value) -> str:
    """1行の自由記述文字列（タイトル・feedback_ask・状態注記等）用の安全化。

    Plan 本文コピーと同じエスケープ規則を通す — 「本文は escape するが
    タイトル欄はしない」という非対称を作らないための共通ヘルパー。
    """
    return esc_vue(str(value)) if value is not None else ""


def chip(kind: str, label: str) -> str:
    return f'<span class="chip {kind}">{label}</span>'


def fb_chip(fb):
    if fb == "待ち":
        return chip("wait", "FB 待ち")
    if fb == "済":
        return chip("ok", "FB 済")
    if fb == "不要":
        return chip("neutral", "FB 不要")
    return chip("wait", "FB 未記入")


def days_label(since):
    d = wait_days(since)
    if d is None:
        return "—"
    return "本日" if d == 0 else f"{d}日"


def state_group(state: str) -> str:
    if state.startswith("未着手"):
        return "未着手"
    if state.startswith("要確認"):
        return "要確認"
    if state.startswith("進行中"):
        return "進行中"
    return "一部完了"


def build():
    todo_rows = parse_todo_rows()
    unanswered_qs, answered_qs = parse_questions()
    progress = parse_progress()
    branches = speculative_branches()
    prs = open_prs()
    dash_comments, dash_drafts = parse_dashboard_comments()
    crit_comments = parse_crit_reviews()

    # 未完了 Plan（完了以外）を収集
    backlog = []
    for row in todo_rows:
        if row["state"].startswith("完了"):
            continue
        plan_path = REPO_ROOT / row["path"]
        info = parse_plan(plan_path)
        num_m = re.search(r"(\d{4})", plan_path.name)
        backlog.append(
            {
                **row,
                **info,
                "num": num_m.group(1) if num_m else "????",
                "stem": plan_path.stem,
                "group": state_group(row["state"]),
            }
        )

    # 着手可能: FB が済んでいる（済 / 不要）未完了 Plan — フィードバックが済むと
    # ここが増える（キューと同じページで見せる楽しさの演出 — オーナー要望）
    ready = [b for b in backlog if b["owner_feedback"] in ("済", "不要")]

    # 要フィードバックキュー: owner_feedback=待ち または フィールド未記入。
    # TODO 状態が「進行中」でも待ちなら載せる（進行中×判断待ちの握りつぶし防止）
    queue = []
    plan_nums_in_queue = set()
    for b in backlog:
        fb = b["owner_feedback"]
        if fb not in ("待ち", "済", "不要", None):
            print(f"WARN: Plan {b['num']} の owner_feedback が未知の値です: {fb!r}（待ち扱いにします）")
        if fb in ("済", "不要"):
            continue
        ask = b["feedback_ask"] or "要判断（詳細は Plan 本文参照）"
        queue.append({**b, "ask": ask, "days": wait_days(b["feedback_since"])})
        plan_nums_in_queue.add(b["num"])
    # Plan に紐づかない未回答 Question は独立エントリとして加える
    orphan_qs = [q for q in unanswered_qs if q["plan"] not in plan_nums_in_queue]
    queue.sort(key=lambda e: (-(e["days"] if e["days"] is not None else -1)))

    # ---- 出力ディレクトリ更新 ----
    # 3階層決め打ちの REPO_ROOT 導出が壊れた場合に無関係のディレクトリを触らない防御
    assert OUT_DIR.name == "dashboard" and OUT_DIR.parent.name == "addf", OUT_DIR
    (OUT_DIR / "plans").mkdir(parents=True, exist_ok=True)
    (OUT_DIR / ".vitepress" / "theme").mkdir(parents=True, exist_ok=True)

    # 差分書き込み: 内容が変わったファイルだけ書く。dev サーバー起動中の再生成で
    # 無変更ファイルまで HMR を発火させない（全ファイル書き換えはページリロードになり、
    # オーナーの入力中コメントを消す — 実測フィードバック）。rmtree もしない
    # （.vitepress/cache 等 dev サーバーの生成物を巻き込むため）
    written = set()

    def write_out(path: Path, content: str):
        written.add(path)
        if path.exists() and path.read_text(encoding="utf-8") == content:
            return
        path.write_text(content, encoding="utf-8")

    # Plan 本文コピー（プランビューア。完了 Plan も含む — 番号リンクで辿れるように）
    plan_sidebar = []
    for f in sorted(PLANS_DIR.glob("[0-9]*.md")):
        write_out(
            OUT_DIR / "plans" / f.name,
            esc_vue(f.read_text(encoding="utf-8"), src=f.name),
        )
        plan_sidebar.append({"text": f.stem, "link": f"/plans/{f.stem}"})

    # ---- ページ: 要フィードバック（index.md）----
    longest = max((e["days"] for e in queue if e["days"] is not None), default=0)
    lines = [
        "---",
        "title: 要フィードバック",
        "---",
        "",
        "# 要フィードバック",
        "",
        "あなたの判断・レビュー・回答を待っているもの（待ちが長い順）と、計画バックログ。",
        "フィードバックが済むと下の「着手可能」が増えます。",
        "",
        '<div class="stats">',
        f'<div class="stat hot"><div class="label">判断待ち</div><div class="value">{len(queue) + len(orphan_qs)}<small>件</small></div></div>',
        f'<div class="stat"><div class="label">投機ブランチ</div><div class="value">{len(branches)}<small>本</small></div></div>',
        f'<div class="stat"><div class="label">オープン PR</div><div class="value">{len(prs) if prs is not None else "?"}<small>件</small></div></div>',
        f'<div class="stat hot"><div class="label">最長の待ち</div><div class="value">{longest}<small>日</small></div></div>',
        f'<div class="stat ready"><div class="label">着手可能</div><div class="value">{len(ready)}<small>件</small></div></div>',
        f'<div class="stat{" hot" if dash_comments or crit_comments else ""}"><div class="label">未解決コメント</div><div class="value">{len(dash_comments) + len(crit_comments)}<small>件</small></div></div>',
        "</div>",
        "",
        f"## オーナー判断待ちの Plan — {len(queue)}件",
        "",
    ]
    for e in queue:
        q_note = ""
        for q in unanswered_qs:
            if q["plan"] == e["num"]:
                q_note = f"（{q['id']} と同件）"
        lines += [
            f"::: details <span class=\"days\">{days_label(e['feedback_since'])}</span> "
            f"`{e['num']}` **{sv(e['title'])}** — {sv(e['ask'])} {fb_chip(e['owner_feedback'])}",
            "",
            f"- 状態: {sv(e['state'])}",
            f"- 待ちの起点: {e['feedback_since'] or '未記入（起点不明のため末尾に表示）'}{q_note}",
            f"- [Plan 本文を読む](/plans/{e['stem']})",
            "",
            ":::",
            "",
        ]
    if not queue:
        lines += ["> 判断待ちの Plan はありません 🎉", ""]

    if orphan_qs:
        lines += [f"## Plan に紐づかない未回答 Question — {len(orphan_qs)}件", ""]
        for q in orphan_qs:
            lines += [
                f"::: details <span class=\"days\">{days_label(q['since'])}</span> `{q['id']}` **{sv(q['title'])}**",
                "",
                esc_vue(q["body"]),
                "",
                ":::",
                "",
            ]

    # アンカーコメント（オーナー発 → エージェント対応待ち。方向がキューと逆なので別セクション）
    if dash_drafts:
        lines += [
            f"> ✏️ 送信待ちのコメントが {dash_drafts}件 あります"
            "（ダッシュボードの「レビューを送信」で確定するまでエージェントは読みません）",
            "",
        ]
    if dash_comments:
        lines += [
            f"## あなたが置いたコメント（エージェント対応待ち） — {len(dash_comments)}件",
            "",
            "次のセッションのブートシーケンスでエージェントが読み、対応後に resolved 化します。",
            "",
        ]
        for c in dash_comments:
            page = c.get("page") or "?"
            anchor = (c.get("anchor") or "").strip()
            if len(anchor) > 80:
                anchor = anchor[:80] + "…"
            lines += [
                f"::: details `{sv(page)}` — {sv(c.get('body', ''))}",
                "",
            ]
            if anchor:
                lines += [f"> {sv(anchor)}", ""]
            lines += [
                f"- 投稿: {sv(c.get('created_at', '?'))} / id: `{sv(c.get('id', '?'))}`",
                "",
                ":::",
                "",
            ]
    if crit_comments:
        lines += [
            f"## crit レビューの未解決コメント — {len(crit_comments)}件",
            "",
            "`~/.crit/reviews/` から集約。`crit --session <id>` で再接続できます。",
            "",
        ]
        for c in crit_comments:
            lines.append(
                f"- `{sv(c['file'])}` — {sv(c['body'])}（session `{c['session']}`）"
            )
        lines.append("")

    lines += [f"## 投機ブランチ — {len(branches)}本", ""]
    if branches:
        for br in branches:
            ahead = br["ahead"]
            if ahead == 0:
                note = "main との差分 0 コミット（全て回収済み）— ブランチ削除の判断待ち"
            elif ahead is None:
                note = "main との差分を取得できませんでした（main ブランチの有無を確認）"
            else:
                note = f"main より {ahead} コミット先行（未回収）"
            lines.append(f"- `{br['name']}` — {note}")
    else:
        lines.append("> 投機ブランチはありません")
    lines.append("")

    lines += ["## オープン PR", ""]
    if prs is None:
        lines.append("> gh が利用できないため PR は取得できませんでした（`gh auth status` を確認）")
    elif not prs:
        lines.append("> レビュー待ちの PR はありません")
    else:
        for pr in prs:
            lines.append(f"- [#{pr['number']} {pr['title']}]({pr['url']})")
    lines.append("")

    # ---- 未実施の計画（統合 — 要フィードバックと同じページで「済むと増える」を見せる）----
    waiting_nums = {b["num"] for b in backlog if b["owner_feedback"] not in ("済", "不要")}
    lines += [
        f"## 未実施の計画 — 着手可能 {len(ready)}件 / 判断待ち {len(waiting_nums)}件",
        "",
    ]
    if ready:
        lines += [f"### ✅ 着手可能（フィードバック済み・不要） — {len(ready)}件", ""]
        for group in ("未着手", "要確認", "一部完了", "進行中"):
            for b in (x for x in ready if x["group"] == group):
                lines += [
                    f"- `{b['num']}` [{sv(b['title'])}](/plans/{b['stem']}) "
                    f"{fb_chip(b['owner_feedback'])}",
                    f"  - 優先度 {b['prio']} / {sv(b['state'])}",
                ]
        lines.append("")
    else:
        lines += ["> 着手可能な計画はありません — 上のキューへのフィードバックで増えます", ""]
    if waiting_nums:
        lines += [
            f"### ⏳ フィードバック待ち — {len(waiting_nums)}件（詳細は上のキュー）",
            "",
        ]
        for b in backlog:
            if b["num"] in waiting_nums:
                lines.append(f"- `{b['num']}` [{sv(b['title'])}](/plans/{b['stem']})")
        lines.append("")

    if answered_qs:
        lines += [
            f"## 回答済み Questions アーカイブ — {len(answered_qs)}件",
            "",
        ]
        for q in answered_qs:
            lines.append(f"- `{q['id']}` {q['title']}")
        lines.append("")

    write_out(OUT_DIR / "index.md", "\n".join(lines))

    # ---- ページ: 進行中タスク（active.md）----
    lines = ["---", "title: 進行中タスク", "---", "", "# 進行中タスク", ""]
    if progress:
        done = sum(1 for s, _ in progress["checklist"] if s == "x")
        total = len(progress["checklist"])
        lines += [
            f"## {sv(progress['title'])}",
            "",
            f"**サブタスク {done} / {total}**",
            "",
        ]
        for stat, item in progress["checklist"]:
            mark = "x" if stat == "x" else " "
            lines.append(f"- [{mark}] {esc_vue(item)}")
        lines.append("")
        if progress["diary"]:
            lines += [
                f"### 最新の日記 — {progress['diary']['head']}",
                "",
                esc_vue(progress["diary"]["body"]),
                "",
            ]
    else:
        lines += [
            "> 進行中のタスクはありません — 次の /addf-dev 起動時にバックログから選定されます",
            "",
        ]
    # TODO 上で「進行中」の Plan（Progress.md の現在タスクと並行しうる）もここに列挙する
    in_progress_plans = [b for b in backlog if b["group"] == "進行中"]
    if in_progress_plans:
        lines += [f"## 進行中の Plan（TODO より） — {len(in_progress_plans)}件", ""]
        for b in in_progress_plans:
            lines += [
                f"- `{b['num']}` [{sv(b['title'])}](/plans/{b['stem']}) "
                f"{fb_chip(b['owner_feedback'])}",
                f"  - {sv(b['state'])}",
            ]
        lines.append("")
    recents = recent_progresses()
    if recents:
        lines += [f"## 直近の完了タスク — {len(recents)}件", ""]
        for stem in recents:
            lines.append(f"- `{stem}`")
        lines.append("")
    write_out(OUT_DIR / "active.md", "\n".join(lines))



    # ---- VitePress 設定・テーマ ----
    sidebar_json = json.dumps(plan_sidebar, ensure_ascii=False, indent=2)

    # アンカーコメント API（Vite dev サーバーミドルウェア — Plan 0058 フェーズC 決定C-1）。
    # f-string の {} エスケープ地獄を避けるため、JS 部分はプレースホルダ置換で組み立てる
    api_ts = """
// ---- アンカーコメント API（generate-dashboard.py が生成 — 編集しない）----
// dev サーバー専用。静的ビルド（dashboard:build）ではコメント投稿は動かない
// （レビューは npm run dashboard:dev で行う）。書き込み先は COMMENTS_PATH の
// 1ファイル固定（クライアント入力からパスを組み立てない）
const COMMENTS_PATH = __COMMENTS_PATH__
const PLANS_REL = __PLANS_REL__

function readComments() {
  try {
    const d = JSON.parse(fs.readFileSync(COMMENTS_PATH, 'utf-8'))
    return d && Array.isArray(d.comments) ? d : { comments: [] }
  } catch { return { comments: [] } }
}

function writeComments(data) {
  fs.writeFileSync(COMMENTS_PATH, JSON.stringify(data, null, 2) + '\\n', 'utf-8')
}

function readReqBody(req) {
  return new Promise((resolve, reject) => {
    let buf = ''
    req.on('data', (c) => { buf += c })
    req.on('end', () => { try { resolve(JSON.parse(buf || '{}')) } catch (e) { reject(e) } })
    req.on('error', reject)
  })
}

function newId(prefix) {
  return prefix + '_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6)
}

// read-modify-write を直列化するキュー。並行リクエスト（複数タブ・複数 dev サーバー
// ではなく同一プロセス内の並行）で後勝ち上書きによるコメント消失を防ぐ
let opQueue = Promise.resolve()
function enqueue(fn) {
  const p = opQueue.then(fn)
  opQueue = p.catch(() => {})
  return p
}

const commentsApi = {
  name: 'addf-comments-api',
  configureServer(server) {
    server.middlewares.use('/api/comments', async (req, res) => {
      res.setHeader('Content-Type', 'application/json')
      try {
        if (req.method === 'GET') {
          res.end(JSON.stringify(readComments()))
          return
        }
        if (req.method === 'POST') {
          const b = await readReqBody(req)
          if (!b.body || !b.page) {
            res.statusCode = 400
            res.end('{"error":"body and page required"}')
            return
          }
          const page = String(b.page)
          // source_path はサーバー側で導出する（クライアント入力を信用しない）
          const m = page.match(/^\\/plans\\/([\\w.-]+)$/)
          const c = {
            id: newId('dc'),
            page,
            source_path: m ? PLANS_REL + '/' + m[1] + '.md' : null,
            anchor: String(b.anchor || ''),
            anchor_occurrence: Math.max(0, Number(b.anchor_occurrence) || 0),
            body: String(b.body),
            author: String(b.author || 'owner'),
            created_at: new Date().toISOString(),
            // GitHub の PR レビューと同じく「Submit まではドラフト」— 全体を見回して
            // 訂正できるように、送信操作までエージェントの読み取り対象にしない
            status: 'draft',
            resolution: null,
            replies: [],
          }
          await enqueue(() => {
            const data = readComments()
            data.comments.push(c)
            writeComments(data)
          })
          res.end(JSON.stringify(c))
          return
        }
        if (req.method === 'PATCH') {
          const b = await readReqBody(req)
          if (b.action === 'submit_all') {
            const n = await enqueue(() => {
              const data = readComments()
              let count = 0
              for (const c of data.comments) {
                if (c.status === 'draft') {
                  c.status = 'unresolved'
                  count++
                }
              }
              if (count) writeComments(data)
              return count
            })
            res.end(JSON.stringify({ submitted: n }))
            return
          }
          if (b.action === 'discard') {
            const ok = await enqueue(() => {
              const data = readComments()
              const i = data.comments.findIndex((x) => x.id === b.id && x.status === 'draft')
              if (i < 0) return false
              data.comments.splice(i, 1)
              writeComments(data)
              return true
            })
            if (!ok) {
              res.statusCode = 404
              res.end('{"error":"draft not found"}')
              return
            }
            res.end('{"discarded":true}')
            return
          }
          const c = await enqueue(() => {
            const data = readComments()
            const target = data.comments.find((x) => x.id === b.id)
            if (!target) return null
            if (b.status === 'resolved' || b.status === 'unresolved') target.status = b.status
            if (b.reply) {
              target.replies = target.replies || []
              target.replies.push({
                id: newId('rp'),
                body: String(b.reply),
                author: String(b.author || 'owner'),
                created_at: new Date().toISOString(),
              })
            }
            writeComments(data)
            return target
          })
          if (!c) {
            res.statusCode = 404
            res.end('{"error":"comment not found"}')
            return
          }
          res.end(JSON.stringify(c))
          return
        }
        res.statusCode = 405
        res.end('{"error":"method not allowed"}')
      } catch (e) {
        res.statusCode = 500
        res.end(JSON.stringify({ error: String((e && e.message) || e) }))
      }
    })
  },
}
""".replace("__COMMENTS_PATH__", json.dumps(str(COMMENTS_PATH))).replace(
        "__PLANS_REL__", json.dumps(str(PLANS_DIR.relative_to(REPO_ROOT)))
    )

    config = f"""import {{ defineConfig }} from 'vitepress'
import fs from 'node:fs'
{api_ts}
export default defineConfig({{
  title: {json.dumps(REPO_ROOT.name + ' ダッシュボード', ensure_ascii=False)},
  description: 'ローカルレビューダッシュボード（生成物 — 編集しない）',
  lang: 'ja',
  ignoreDeadLinks: true,
  markdown: {{
    config(md) {{
      // インラインコードに v-pre を付ける。VitePress はフェンスコードにしか
      // v-pre を付けないため、Plan 原文のインラインコード内 Vue 展開
      // （例: crit の Go template 変数 `{{{{.review_path}}}}`）が SFC コンパイルで
      // interpolation 解釈されるのを防ぐ（esc_vue はコードスパン不変ポリシーのため
      // 生成側ではなくレンダラ側で保護する）
      md.renderer.rules.code_inline = (tokens, idx) =>
        '<code v-pre>' + md.utils.escapeHtml(tokens[idx].content) + '</code>'
    }},
  }},
  // config の port は CLI の --port より優先されるため、テスト等の別ポート起動は
  // 環境変数 ADDF_DASHBOARD_PORT で上書きする
  vite: {{
    server: {{ port: Number(process.env.ADDF_DASHBOARD_PORT) || 5180 }},
    plugins: [commentsApi],
  }},
  themeConfig: {{
    sidebar: {{
      '/': [
        {{
          text: 'ダッシュボード',
          items: [
            {{ text: '要フィードバック・計画', link: '/' }},
            {{ text: '進行中タスク', link: '/active' }},
          ],
        }},
        {{ text: 'プランビューア', collapsed: true, items: {sidebar_json} }},
      ],
    }},
    outline: {{ label: 'このページ' }},
    footer: {{ message: '生成: {TODAY.isoformat()} · generate-dashboard.py（Plan 0058）' }},
  }},
}})
"""
    write_out(OUT_DIR / ".vitepress" / "config.mts", config)

    theme = """import DefaultTheme from 'vitepress/theme'
import Layout from './Layout.vue'
import './custom.css'
export default { extends: DefaultTheme, Layout }
"""
    write_out(OUT_DIR / ".vitepress" / "theme" / "index.mts", theme)

    # アンカーコメント UI（Plan 0058 フェーズC 決定C-7）。anchor はブロック原文の
    # 正規化テキスト（crit の「行原文保持」を踏襲 — 再生成で位置がずれても原文一致で復元）
    layout_vue = r"""<script setup>
// generate-dashboard.py が生成 — 編集しない（単一ソースはリポジトリ側）
import DefaultTheme from 'vitepress/theme'
import { useRoute, useData, onContentUpdated } from 'vitepress'
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from 'vue'

const VPLayout = DefaultTheme.Layout
const route = useRoute()
const { site } = useData()

const available = ref(false) // コメント API が生きているか（dev サーバーのみ true）
const comments = ref([])
const panelOpen = ref(false)
const panelAnchor = ref('')
const panelThread = ref([])
const draft = ref('')
const sending = ref(false)
const orphans = ref([])
const btn = ref({ visible: false, top: 0, left: 0 })
const hoverAnchor = ref('')
const hoverOcc = ref(0)
const panelOcc = ref(0)
const submitting = ref(false)
const guidanceOpen = ref(false)
const submittedCount = ref(0)

// 全ページ横断のドラフト数（送信バーの表示判定）
const stackList = computed(() => comments.value.filter((c) => c.status === 'draft'))
const draftCount = computed(() => stackList.value.length)
const stackOpen = ref(false)
const GUIDANCE_PROMPT = 'ダッシュボードのコメントに対応して'

// tr はコンテンツモデル上 button を直接置けないため td/th 単位にする
const BLOCK_SEL =
  '.vp-doc p, .vp-doc li, .vp-doc h1, .vp-doc h2, .vp-doc h3, .vp-doc h4, ' +
  '.vp-doc pre, .vp-doc td, .vp-doc th, .vp-doc blockquote, .vp-doc summary'

function normText(s) {
  return (s || '').replace(/\s+/g, ' ').trim()
}

function pagePath() {
  let p = route.path.replace(/\.html$/, '')
  if (p.endsWith('/index')) p = p.slice(0, -('index'.length))
  return p || '/'
}

function blockText(block) {
  if (block.dataset.addfText !== undefined) return block.dataset.addfText
  const clone = block.cloneNode(true)
  clone.querySelectorAll('.addf-cbadge').forEach((el) => el.remove())
  return normText(clone.textContent)
}

async function fetchComments() {
  try {
    const r = await fetch('/api/comments', { headers: { accept: 'application/json' } })
    if (!r.ok) throw new Error('api unavailable')
    const d = await r.json()
    comments.value = Array.isArray(d.comments) ? d.comments : []
    available.value = true
  } catch {
    available.value = false
    comments.value = []
  }
}

function decorate() {
  if (typeof document === 'undefined') return
  document.querySelectorAll('.addf-cbadge').forEach((el) => el.remove())
  document
    .querySelectorAll('.addf-commented')
    .forEach((el) => el.classList.remove('addf-commented'))
  orphans.value = []
  if (!available.value) return
  const p = pagePath()
  const list = comments.value.filter((c) => c.page === p && c.status !== 'resolved')
  const blocks = Array.from(document.querySelectorAll(BLOCK_SEL))
  // 同一テキストのブロックが複数ある場合に区別するため出現番号（0始まり）も振る
  const occCount = {}
  for (const b of blocks) {
    const t = normText(b.textContent)
    b.dataset.addfText = t
    occCount[t] = (occCount[t] ?? -1) + 1
    b.dataset.addfOcc = String(occCount[t])
  }
  const byAnchor = new Map()
  for (const c of list) {
    const key = normText(c.anchor)
    const occ = Math.max(0, Number(c.anchor_occurrence) || 0)
    const mapKey = occ + ':' + key
    if (!byAnchor.has(mapKey)) byAnchor.set(mapKey, [])
    byAnchor.get(mapKey).push(c)
  }
  const matched = new Set()
  for (const [mapKey, cs] of byAnchor) {
    const sep = mapKey.indexOf(':')
    const occ = mapKey.slice(0, sep)
    const key = mapKey.slice(sep + 1)
    if (!key) continue
    const block = blocks.find(
      (b) => b.dataset.addfText === key && b.dataset.addfOcc === occ
    )
    if (!block) continue
    cs.forEach((c) => matched.add(c.id))
    block.classList.add('addf-commented')
    const badge = document.createElement('button')
    badge.className = 'addf-cbadge'
    badge.type = 'button'
    badge.textContent = '💬' + cs.length
    badge.addEventListener('click', (e) => {
      e.stopPropagation()
      openPanel(key, Number(occ))
    })
    block.appendChild(badge)
  }
  orphans.value = list.filter((c) => !matched.has(c.id))
}

function refreshThread() {
  const p = pagePath()
  panelThread.value = comments.value.filter(
    (c) =>
      c.page === p &&
      normText(c.anchor) === panelAnchor.value &&
      Math.max(0, Number(c.anchor_occurrence) || 0) === panelOcc.value
  )
}

// 入力中テキストの永続化 — 再生成による HMR リロードやパネルの開閉で
// 入力が消えないよう localStorage に退避する（実測フィードバック）。
// スロットは (page, anchor, occ) 別のマルチスロット: 別のアンカーを開いても
// 他の書きかけは消えない
const DRAFTS_KEY = 'addf-comment-drafts'

function loadDraftSlots() {
  try {
    const a = JSON.parse(localStorage.getItem(DRAFTS_KEY) || '[]')
    return Array.isArray(a) ? a : []
  } catch {
    return []
  }
}

function saveDraftSlots(list) {
  try {
    if (list.length) localStorage.setItem(DRAFTS_KEY, JSON.stringify(list))
    else localStorage.removeItem(DRAFTS_KEY)
  } catch { /* localStorage 不可の環境では諦める */ }
}

function slotMatch(d, page, anchor, occ) {
  return d.page === page && d.anchor === anchor && Number(d.occ) === Number(occ)
}

function persistDraft() {
  if (!panelOpen.value) return
  const page = pagePath()
  const list = loadDraftSlots().filter(
    (d) => !slotMatch(d, page, panelAnchor.value, panelOcc.value)
  )
  if (draft.value.trim()) {
    list.push({
      page,
      anchor: panelAnchor.value,
      occ: panelOcc.value,
      text: draft.value,
      updated: Date.now(),
    })
  }
  saveDraftSlots(list)
}

function findDraftSlot(anchor, occ) {
  return (
    loadDraftSlots().find((d) => slotMatch(d, pagePath(), anchor, occ)) || null
  )
}

function removeDraftSlot(anchor, occ) {
  const page = pagePath()
  saveDraftSlots(loadDraftSlots().filter((d) => !slotMatch(d, page, anchor, occ)))
}

watch(draft, persistDraft)

function openPanel(anchorKey, occ) {
  panelAnchor.value = anchorKey
  panelOcc.value = Math.max(0, Number(occ) || 0)
  refreshThread()
  const saved = findDraftSlot(anchorKey, panelOcc.value)
  draft.value = saved ? saved.text : ''
  panelOpen.value = true
  btn.value.visible = false
}

// ブロック→ボタン間の隙間を渡る途中で消えないよう、消灯は遅延させる
// （即時消灯だとボタンに到達できない — オーナー実測フィードバック dc_mrnkj871vbru）
let hideTimer = null
function scheduleHide() {
  clearTimeout(hideTimer)
  hideTimer = setTimeout(() => {
    btn.value.visible = false
  }, 300)
}

function onMouseOver(e) {
  if (!available.value || panelOpen.value) return
  const t = e.target
  if (!(t instanceof Element)) return
  if (t.closest('.addf-panel, .addf-hoverbtn, .addf-orphans')) {
    clearTimeout(hideTimer)
    return
  }
  const block = t.closest(BLOCK_SEL)
  if (!block) {
    scheduleHide()
    return
  }
  clearTimeout(hideTimer)
  const r = block.getBoundingClientRect()
  hoverAnchor.value = blockText(block)
  hoverOcc.value = Number(block.dataset.addfOcc || 0)
  btn.value = {
    visible: true,
    top: r.top + window.scrollY,
    left: Math.max(6, r.left + window.scrollX - 34),
  }
}

// パネル外クリックで閉じる（閉じないと他のアンカーコメントを開けない —
// オーナー実測フィードバック dc_mrnkr91zqhy5）
function onDocClick(e) {
  if (!panelOpen.value) return
  const t = e.target
  if (t instanceof Element && t.closest('.addf-panel, .addf-cbadge, .addf-hoverbtn, .addf-stack, .addf-submitbar')) return
  panelOpen.value = false
}

async function refreshAll() {
  await fetchComments()
  decorate()
  if (panelOpen.value) refreshThread()
}

async function submit() {
  const body = draft.value.trim()
  if (!body || sending.value) return
  sending.value = true
  try {
    const r = await fetch('/api/comments', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        page: pagePath(),
        anchor: panelAnchor.value,
        anchor_occurrence: panelOcc.value,
        body,
      }),
    })
    if (r.ok) {
      draft.value = ''
      removeDraftSlot(panelAnchor.value, panelOcc.value)
      await refreshAll()
    }
  } finally {
    sending.value = false
  }
}

async function markResolved(id) {
  await fetch('/api/comments', {
    method: 'PATCH',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ id, status: 'resolved' }),
  })
  await refreshAll()
}

async function discardDraft(id) {
  await fetch('/api/comments', {
    method: 'PATCH',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ id, action: 'discard' }),
  })
  await refreshAll()
}

async function submitReview() {
  if (submitting.value || !draftCount.value) return
  submitting.value = true
  try {
    const r = await fetch('/api/comments', {
      method: 'PATCH',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ action: 'submit_all' }),
    })
    if (r.ok) {
      const d = await r.json()
      submittedCount.value = d.submitted || 0
      panelOpen.value = false
      guidanceOpen.value = true
    }
  } finally {
    submitting.value = false
    await refreshAll()
  }
}

async function copyGuidance() {
  try {
    await navigator.clipboard.writeText(GUIDANCE_PROMPT)
  } catch {
    /* クリップボード不可の環境では手動コピーに任せる */
  }
}

onMounted(async () => {
  await fetchComments()
  await nextTick()
  decorate()
  document.addEventListener('mouseover', onMouseOver)
  document.addEventListener('click', onDocClick)
  // 旧・単一スロットキー（addf-comment-draft）からの移行
  try {
    const legacy = JSON.parse(localStorage.getItem('addf-comment-draft') || 'null')
    if (legacy && legacy.text) {
      const list = loadDraftSlots().filter(
        (d) => !slotMatch(d, legacy.page, legacy.anchor, legacy.occ)
      )
      list.push({ ...legacy, updated: Date.now() })
      saveDraftSlots(list)
    }
    localStorage.removeItem('addf-comment-draft')
  } catch { /* noop */ }
  // リロード前にこのページで入力していたコメントがあればパネルごと復元する
  // （複数あれば最後に触っていたもの。他のスロットは該当アンカーを開けば復元される）
  const mine = loadDraftSlots().filter((d) => d.page === pagePath() && d.text)
  if (mine.length) {
    const latest = mine.reduce((a, b) => ((a.updated || 0) > (b.updated || 0) ? a : b))
    openPanel(latest.anchor, latest.occ)
  }
})

onUnmounted(() => {
  if (typeof document !== 'undefined') {
    document.removeEventListener('mouseover', onMouseOver)
    document.removeEventListener('click', onDocClick)
  }
})

onContentUpdated(() => decorate())

watch(
  () => route.path,
  () => {
    panelOpen.value = false
    btn.value.visible = false
  }
)
</script>

<template>
  <VPLayout>
    <template #nav-bar-content-before>
      <a class="addf-navtitle" href="/" :title="site.title">{{ site.title }}</a>
    </template>
  </VPLayout>
  <ClientOnly>
    <button
      v-if="available && btn.visible"
      class="addf-hoverbtn"
      type="button"
      title="この箇所にコメントする"
      :style="{ top: btn.top + 'px', left: btn.left + 'px' }"
      @click="openPanel(hoverAnchor, hoverOcc)"
    >💬</button>

    <div v-if="panelOpen" class="addf-panel">
      <div class="addf-panel-head">
        <strong>アンカーコメント</strong>
        <button class="addf-x" type="button" @click="panelOpen = false">×</button>
      </div>
      <blockquote v-if="panelAnchor" class="addf-anchor">{{ panelAnchor }}</blockquote>
      <div
        v-for="c in panelThread"
        :key="c.id"
        class="addf-comment"
        :class="{ 'is-resolved': c.status === 'resolved' }"
      >
        <div class="addf-meta">
          {{ c.author }} · {{ (c.created_at || '').slice(0, 16).replace('T', ' ') }}
          <span v-if="c.status === 'resolved'" class="addf-resolved-mark">✓ resolved</span>
          <span v-if="c.status === 'draft'" class="addf-draft-mark">送信待ち</span>
        </div>
        <div class="addf-body">{{ c.body }}</div>
        <div v-if="c.resolution" class="addf-reply">
          <div class="addf-meta">resolution</div>
          <div class="addf-body">{{ c.resolution }}</div>
        </div>
        <div v-for="rp in c.replies || []" :key="rp.id" class="addf-reply">
          <div class="addf-meta">{{ rp.author }}</div>
          <div class="addf-body">{{ rp.body }}</div>
        </div>
        <button
          v-if="c.status === 'draft'"
          class="addf-resolve"
          type="button"
          @click="discardDraft(c.id)"
        >取り下げ</button>
        <button
          v-else-if="c.status !== 'resolved'"
          class="addf-resolve"
          type="button"
          @click="markResolved(c.id)"
        >resolve</button>
      </div>
      <textarea
        v-model="draft"
        class="addf-draft"
        rows="3"
        placeholder="コメントを書く — 送信待ちに積まれ、「レビューを送信」で確定します"
      ></textarea>
      <button
        class="addf-send"
        type="button"
        :disabled="sending || !draft.trim()"
        @click="submit"
      >送信待ちに積む</button>
    </div>

    <div v-if="available && draftCount" class="addf-submitbar">
      <button class="addf-resolve" type="button" @click="stackOpen = !stackOpen">
        送信待ち {{ draftCount }}件
      </button>
      <button class="addf-send" type="button" :disabled="submitting" @click="submitReview">
        レビューを送信
      </button>
    </div>

    <div v-if="stackOpen && stackList.length" class="addf-stack">
      <div class="addf-panel-head">
        <strong>送信待ちのコメント {{ stackList.length }}件</strong>
        <button class="addf-x" type="button" @click="stackOpen = false">×</button>
      </div>
      <div v-for="c in stackList" :key="c.id" class="addf-comment">
        <div class="addf-meta">{{ c.page }}</div>
        <blockquote v-if="c.anchor" class="addf-anchor">{{ c.anchor }}</blockquote>
        <div class="addf-body">{{ c.body }}</div>
        <button class="addf-resolve" type="button" @click="discardDraft(c.id)">取り下げ</button>
      </div>
    </div>

    <div v-if="guidanceOpen" class="addf-modal-backdrop" @click.self="guidanceOpen = false">
      <div class="addf-modal">
        <strong>{{ submittedCount }}件のコメントを送信しました</strong>
        <p>
          コメントはリポジトリの <code>DashboardComments.json</code> に確定保存されました。
          次のセッション開始時に自動で読まれます。すぐ対応してほしい場合は
          Claude Code にこうプロンプトしてください:
        </p>
        <blockquote class="addf-anchor">{{ GUIDANCE_PROMPT }}</blockquote>
        <div class="addf-modal-actions">
          <button class="addf-resolve" type="button" @click="copyGuidance">プロンプトをコピー</button>
          <button class="addf-send" type="button" @click="guidanceOpen = false">閉じる</button>
        </div>
      </div>
    </div>

    <div v-if="available && orphans.length" class="addf-orphans">
      <details>
        <summary>位置を特定できないコメント {{ orphans.length }}件（本文の再生成で対象が変わった可能性）</summary>
        <div v-for="c in orphans" :key="c.id" class="addf-comment">
          <blockquote v-if="c.anchor" class="addf-anchor">{{ c.anchor }}</blockquote>
          <div class="addf-body">{{ c.body }}</div>
          <button class="addf-resolve" type="button" @click="markResolved(c.id)">resolve</button>
        </div>
      </details>
    </div>
  </ClientOnly>
</template>
"""
    write_out(OUT_DIR / ".vitepress" / "theme" / "Layout.vue", layout_vue)

    css = """:root {
  --chip-wait-ink: #8a5300; --chip-wait-bg: #f7ecda;
  --chip-ok-ink: #2c6b3f; --chip-ok-bg: #e5f1e8;
  --chip-neutral-ink: #5b6672; --chip-neutral-bg: #edf0ef;
}
.dark {
  --chip-wait-ink: #f0c380; --chip-wait-bg: #4a3a1c;
  --chip-ok-ink: #a3d9b0; --chip-ok-bg: #1e3a26;
  --chip-neutral-ink: #b6c0c8; --chip-neutral-bg: #333a40;
}
.chip {
  display: inline-block; font-size: 11px; line-height: 20px;
  padding: 0 8px; border-radius: 10px; white-space: nowrap; font-weight: 500;
}
.chip.wait { background: var(--chip-wait-bg); color: var(--chip-wait-ink); }
.chip.ok { background: var(--chip-ok-bg); color: var(--chip-ok-ink); }
.chip.neutral { background: var(--chip-neutral-bg); color: var(--chip-neutral-ink); }
.days {
  font-family: var(--vp-font-family-mono); font-variant-numeric: tabular-nums;
  font-weight: 600; color: var(--chip-wait-ink); margin-right: 4px;
}
.stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 10px; margin: 16px 0 8px; }
.stat { border: 1px solid var(--vp-c-divider); border-radius: 8px; padding: 10px 14px; }
.stat .label { font-size: 12px; color: var(--vp-c-text-2); }
.stat .value { font-family: var(--vp-font-family-mono); font-size: 24px; font-weight: 600; }
.stat .value small { font-size: 12px; font-weight: 400; color: var(--vp-c-text-2); }
.stat.hot .value { color: var(--chip-wait-ink); }
.stat.ready .value { color: var(--chip-ok-ink); }
@media (max-width: 640px) { .stats { grid-template-columns: repeat(2, 1fr); } }

/* サイトタイトル（リポジトリ名）はヘッダー右側のナビコンテンツ（テーマ切り替えの並び）に
   置く（Layout.vue の #nav-bar-content-before slot）。サイドバー上のデフォルトタイトルは
   長いリポジトリ名がはみ出すため非表示にする — ヘッダーの透過構造はデフォルトのまま
   触らない（不透明化はサイドバーのスクロールバー貫通が露呈する）。
   ブラウザタブの表示は config.title のままフル表記 */
.VPNavBarTitle { display: none; }
.addf-navtitle {
  font-weight: 600;
  font-size: 14px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 40vw;
  color: var(--vp-c-text-1);
  margin-right: 16px;
}
.addf-navtitle:hover { color: var(--vp-c-brand-1); }

/* サイドバーはページタブの代替 — 通常項目の視認性と現在ページのコントラストを上げる */
.VPSidebarItem.level-1 .text {
  color: var(--vp-c-text-1);
  font-size: 14px;
}
.VPSidebarItem.level-1.is-active > .item {
  background: var(--vp-c-brand-soft);
  border-radius: 6px;
}
.VPSidebarItem.level-1.is-active > .item .link { padding-left: 8px; }
.VPSidebarItem.level-1.is-active > .item .text {
  color: var(--vp-c-brand-1);
  font-weight: 700;
}

/* ---- アンカーコメント UI（Plan 0058 フェーズC）---- */
.addf-commented {
  background: var(--chip-wait-bg);
  border-radius: 4px;
  box-shadow: 0 0 0 3px var(--chip-wait-bg);
}
.addf-cbadge {
  display: inline-block; margin-left: 6px; padding: 0 6px;
  font-size: 11px; line-height: 18px; border-radius: 9px; cursor: pointer;
  background: var(--chip-wait-ink); color: var(--vp-c-bg); border: none;
  vertical-align: middle;
}
.addf-hoverbtn {
  position: absolute; z-index: 40; width: 28px; height: 24px;
  font-size: 13px; line-height: 22px; padding: 0; text-align: center;
  border: 1px solid var(--vp-c-divider); border-radius: 6px; cursor: pointer;
  background: var(--vp-c-bg-soft);
}
.addf-hoverbtn:hover { background: var(--chip-wait-bg); }
.addf-panel {
  position: fixed; right: 16px; bottom: 16px; z-index: 60;
  width: min(380px, calc(100vw - 32px)); max-height: 70vh; overflow-y: auto;
  background: var(--vp-c-bg); border: 1px solid var(--vp-c-divider);
  border-radius: 10px; box-shadow: var(--vp-shadow-3); padding: 12px 14px;
  font-size: 13px;
}
.addf-panel-head { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }
.addf-x { border: none; background: none; font-size: 16px; cursor: pointer; color: var(--vp-c-text-2); }
.addf-anchor {
  margin: 0 0 10px; padding: 6px 10px; font-size: 12px;
  color: var(--vp-c-text-2); border-left: 3px solid var(--chip-wait-ink);
  background: var(--vp-c-bg-soft); border-radius: 0 6px 6px 0;
  max-height: 80px; overflow-y: auto;
}
.addf-comment { border-top: 1px solid var(--vp-c-divider); padding: 8px 0; }
.addf-comment.is-resolved { opacity: 0.6; }
.addf-meta { font-size: 11px; color: var(--vp-c-text-2); margin-bottom: 2px; }
.addf-resolved-mark { color: var(--chip-ok-ink); }
.addf-body { white-space: pre-wrap; word-break: break-word; }
.addf-reply { margin: 6px 0 0 14px; padding-left: 8px; border-left: 2px solid var(--vp-c-divider); }
.addf-resolve {
  margin-top: 4px; padding: 1px 8px; font-size: 11px; cursor: pointer;
  border: 1px solid var(--vp-c-divider); border-radius: 6px;
  background: var(--vp-c-bg-soft); color: var(--chip-ok-ink);
}
.addf-draft {
  width: 100%; margin-top: 8px; padding: 6px 8px; font-size: 13px;
  font-family: inherit; border: 1px solid var(--vp-c-divider); border-radius: 6px;
  background: var(--vp-c-bg); color: var(--vp-c-text-1); resize: vertical;
}
.addf-send {
  margin-top: 6px; padding: 4px 14px; font-size: 13px; cursor: pointer;
  border: none; border-radius: 6px; background: var(--vp-c-brand-1); color: #fff;
}
.addf-send:disabled { opacity: 0.5; cursor: default; }
.addf-orphans {
  position: fixed; left: 16px; bottom: 16px; z-index: 50;
  width: min(420px, calc(100vw - 32px)); max-height: 40vh; overflow-y: auto;
  background: var(--vp-c-bg); border: 1px solid var(--vp-c-divider);
  border-radius: 10px; box-shadow: var(--vp-shadow-2); padding: 8px 12px;
  font-size: 13px;
}
.addf-orphans summary { cursor: pointer; color: var(--chip-wait-ink); font-size: 12px; }
.addf-draft-mark { color: var(--chip-wait-ink); font-weight: 600; }
.addf-submitbar {
  position: fixed; right: 16px; top: 72px; z-index: 55;
  display: flex; align-items: center; gap: 10px;
  background: var(--vp-c-bg); border: 1px solid var(--chip-wait-ink);
  border-radius: 10px; box-shadow: var(--vp-shadow-2); padding: 8px 12px;
  font-size: 13px; color: var(--chip-wait-ink); font-weight: 600;
}
.addf-modal-backdrop {
  position: fixed; inset: 0; z-index: 80;
  background: rgba(0, 0, 0, 0.4);
  display: flex; align-items: center; justify-content: center;
}
.addf-modal {
  width: min(460px, calc(100vw - 32px));
  background: var(--vp-c-bg); border: 1px solid var(--vp-c-divider);
  border-radius: 12px; box-shadow: var(--vp-shadow-3); padding: 18px 20px;
  font-size: 14px;
}
.addf-modal p { margin: 10px 0; color: var(--vp-c-text-2); font-size: 13px; }
.addf-modal-actions { display: flex; justify-content: flex-end; gap: 10px; margin-top: 12px; }
.addf-stack {
  position: fixed; right: 16px; top: 120px; z-index: 55;
  width: min(400px, calc(100vw - 32px)); max-height: 60vh; overflow-y: auto;
  background: var(--vp-c-bg); border: 1px solid var(--vp-c-divider);
  border-radius: 10px; box-shadow: var(--vp-shadow-3); padding: 10px 14px;
  font-size: 13px;
}
.addf-stack .addf-meta { font-family: var(--vp-font-family-mono); }
"""
    write_out(OUT_DIR / ".vitepress" / "theme" / "custom.css", css)

    # 前回生成の残骸（削除された Plan のコピー等）を掃除する。対象は自分の管理領域
    # （トップ *.md と plans/*.md）のみ — .vitepress/cache 等 dev サーバーの生成物は触らない
    for f in list(OUT_DIR.glob("*.md")) + list((OUT_DIR / "plans").glob("*.md")):
        if f not in written:
            f.unlink()

    # コメント置き場の初期化（API の書き込み先を確実にする。既存があれば触らない）
    if not COMMENTS_PATH.exists():
        COMMENTS_PATH.write_text('{\n  "comments": []\n}\n', encoding="utf-8")

    n_q = len(queue) + len(orphan_qs)
    print(f"OK: dashboard generated at {OUT_DIR.relative_to(REPO_ROOT)}")
    print(
        f"    判断待ち {n_q}件 / 投機ブランチ {len(branches)}本 / "
        f"PR {'取得不可' if prs is None else str(len(prs)) + '件'} / "
        f"バックログ {len(backlog)}件 / Plan コピー {len(plan_sidebar)}件 / "
        f"未解決コメント {len(dash_comments) + len(crit_comments)}件"
    )
    return 0


if __name__ == "__main__":
    sys.exit(build())
