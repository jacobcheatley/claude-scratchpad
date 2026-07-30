# Worktree Session Workflow — Design

**Status:** Active

## Purpose

The repo hosts short investigative or code tasks unrelated to any specific project. Goals, in priority order: isolation between concurrent sessions, history/auditability of what each session produced, and a clean repo root. Each session's generated files are tracked in a git worktree named after the session's premise.

Worktrees use Claude Code's native `--worktree` convention — directory `.claude/worktrees/<slug>`, branch `worktree-<slug>`. Sessions launch via `cs -w <slug> [prompt]` (passthrough to `claude --worktree`), which creates, reuses, or reattaches to the branch automatically.

## Repository layout

```
claude-scratchpad/         # repo root, branch: main — stays pristine
├── CLAUDE.md              # workflow rules (this design, operationalized)
├── .gitignore             # .claude/worktrees/, junk patterns
├── docs/                  # design docs
├── scripts/
│   ├── enforce-work-dir.sh  # PreToolUse hook: work/ containment
│   └── prune-worktrees.sh   # explicit-call cleanup
└── .claude/worktrees/     # gitignored; one worktree per topic
    └── <topic-slug>/      # branch worktree-<topic-slug>, forked from main
```

## Workflow rules (contents of CLAUDE.md)

### 1. Worktree acquisition at session start

- Derive a kebab-case slug (2–4 words) from the session premise, taken from the first message(s).
- If the first message is too vague to name (e.g., "brainstorm time"), create **no files** until the premise is clear enough to produce a slug.
- Check `git worktree list` for an existing worktree matching the topic:
  - Match **less than 1 week old** (last commit date): ask the user to confirm reuse before attaching.
  - Match **older than 1 week**: ignore it unless the user explicitly asks to resume it.
- No usable match: create via the EnterWorktree tool or `git worktree add .claude/worktrees/<slug> -b worktree-<slug> main`.
- Sessions launched with `cs -w <slug>` start inside the worktree already — the above applies only to sessions started at the repo root.

### 2. Work location

All session files are created inside `.claude/worktrees/<slug>/work/`. The worktree root holds infra checked out from main (CLAUDE.md, docs/, scripts/, .gitignore); keeping session output in `work/` makes it exportable as a single folder (`cp -r work/ <dest>`). Nothing is written to the repo root except infra maintenance (CLAUDE.md, README.md, `.gitignore`, `scripts/`, `docs/`).

### 3. Commit cadence

Milestone commits: when a deliverable is produced, an investigation step lands, or the session ends. Normal commit-message style.

### 4. Junk rules

- Cloned third-party repos go in `external/` inside the worktree (gitignored) — prevents nested-repo commits.
- Never committed: virtualenvs, `node_modules`, caches, logs, large binaries (>5 MB guideline).

### 5. Pivot rule

If the session premise changes substantially mid-session, ask the user: rename the worktree (branch + directory) or start a new one.

### 6. Cleanup

Never automatic. `scripts/prune-worktrees.sh` runs only on explicit request: lists worktrees with age, removes selected ones (by slug, or in bulk via `--older-than <age>`, e.g. `7d`/`2w`), always keeps branches (content stays recoverable).

## Enforcement

`scripts/enforce-work-dir.sh` (PreToolUse hook in `.claude/settings.json`, matcher `Write|Edit|NotebookEdit`) blocks writes inside worktrees outside `work/` and `external/`, and blocks `work/` at the repo root. Remaining gap: Bash-mediated writes (redirects, `cp`) aren't intercepted — CLAUDE.md instructs not to bypass.

## VSCode workspace sync

`scripts/sync-workspace.sh` (bash + jq) mirrors session worktrees into a multi-root workspace file at `../claude-scratchpad.code-workspace`: one folder entry per worktree `work/` dir, plus a seeded root folder. Managed-folders-only semantics — it rewrites only entries whose path matches `claude-scratchpad/.claude/worktrees/*/work`, preserving user-added folders and the workspace file's own `settings` block. Triggered by a SessionStart hook and after removal runs of `prune-worktrees.sh`; unparseable (non-plain-JSON) workspace files are left untouched with an error. The committed `work/.gitkeep` on main gives new worktrees their `work/` dir at creation. Worktrees created before this landed don't carry the hook — their entries refresh on the next main-checkout session.

## Accepted residual risks

- Branches accumulate indefinitely — by design; they are the history.

## Out of scope

- Merging session branches back to main.
- Automatic staleness pruning.
