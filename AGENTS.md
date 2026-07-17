# AGENTS.md — AutomatonDevDrive Framework

> This file enables Codex (and other AGENTS.md-compatible tools) to use ADDF.
> For Claude Code, see CLAUDE.md (the primary instruction file).

## Boot Sequence

On session start, read these files in order:

1. `.claude/addf/Feedback.md` — Check for unresolved improvement actions
   - 1.5. `.claude/addf/Questions.md` — If the owner answered pending questions, apply the answers to plans and move them to "answered"
   - 1.6. If `.claude/addf/Dashboard.md` exists, present its contents first (summary of unattended autonomous work). Delete it only after the owner has acknowledged it; re-present next session otherwise
   - 1.7. If `.claude/addf/DashboardComments.json` exists and contains comments with `status: "unresolved"`, read them — anchor comments the owner left on the HTML dashboard (owner-initiated contextual feedback). Decide and execute a response, write it to `resolution`, and update `status` to `"resolved"`. If a comment amounts to an answer to an open Question, transcribe it to the Answer field in Questions.md before resolving (Questions.md is always the source of truth — avoid dual channels). Comments with `status: "draft"` are the owner's unsubmitted review drafts — do not read or touch them
2. `TODO.md` — Review task backlog and priorities
3. `.claude/addf/Progress.md` — Continue in-progress tasks or select next
   - If the in-progress task has a diary (日記) section, read the last 3 entries to pick up the predecessor's situation, judgments, and concerns before starting (see Progress.md operating rules for the diary format)
4. If no pending tasks:
   - If `.claude/addf/plans/` has no plan files (first-time project): scan the project, then ask the owner to choose: (A) guided Q&A (what to build, pain points, target platform, why existing tools don't work) or (B) free-form explanation. Create 2-3 initial plan files (following `.claude/addf/templates/PlanTemplate.md`), register in TODO.md, and generate project-specific `CLAUDE.repo.md` (as downstream "ADDF利用プロジェクト")
   - Otherwise: ask the owner for the next task
5. Before starting a plan, read relevant files in `.claude/addf/knowhow/` directly

## Development Process

- **Plan-driven**: Review plans, not code. Good plans are accepted; AI ensures implementation quality
- **70% rule (stop-or-go doctrine)**: Proceed when ~70% confident the direction matches the plan's intent. Below threshold, drop a question into `.claude/addf/Questions.md` and move to another task instead of guessing or halting. See the stop-or-go doctrine section in CLAUDE.md (Japanese) for the full three-axis doctrine (trust / responsiveness / image clarity)
- **Plans directory**: `.claude/addf/plans/` (downstream) or `.claude/addf/plans-add/` (ADDF development)
- **Knowhow**: Implementation insights are stored in `.claude/addf/knowhow/`
- **Quality gate**: Build/Lint/Test → Code review → Commit

## Commit Convention

Write commit messages in Japanese:

```
[領域] 変更内容の要約

詳細説明（必要な場合）
```

## Codex-Specific Notes

This project is designed for Claude Code but can be used with Codex with limitations.
See `.claude/addf/guides/codex-setup.md` for detailed Codex setup instructions.

### What works with Codex

- Plan-driven development workflow (Markdown-based, agent-agnostic)
- Knowhow system (`.claude/addf/knowhow/` — plain Markdown files)
- Quality gate process (manual execution of review steps)
- Progress tracking (`.claude/addf/Progress.md`)

### Note for ADDF framework development

This repository (ADDF itself) is primarily developed with Claude Code.
If you're contributing to ADDF, Claude Code is recommended.

### What requires Claude Code

- Skills (`/addf-*` commands) — Codex skills use a different format (`.agents/skills/`)
- Hooks (turn counter, session start) — Limited Codex equivalent
- Automated quality gate (parallel agent team) — Different subagent architecture
- GUI testing (addfTools) — Requires macOS, not available in Codex sandbox
