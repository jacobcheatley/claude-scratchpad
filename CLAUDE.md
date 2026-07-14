# claude-scratchpad — Worktree Session Workflow

This directory hosts short investigative or code tasks not tied to any project. Every session's generated files live in a git worktree named after the session's premise. The repo root stays pristine.

Full design: `docs/design.md`

Worktrees use Claude Code's native convention: directory `.claude/worktrees/<slug>`, branch `worktree-<slug>`. Sessions are usually launched already inside one via `cs -w <slug> [prompt]` (the `--worktree` flag).

## 1. Establish the worktree at session start

- **If cwd is already inside `.claude/worktrees/<slug>/`** (launched with `-w`): you're set — work in cwd, skip the rest of this rule.
- Otherwise derive a kebab-case slug (2–4 words) from the session premise in the first message(s). Too vague to name? Create **no files** until the premise is clear enough to slug.
- Check `git worktree list` for an existing worktree matching the topic:
  - Match with last commit **< 1 week old** → ask the user to confirm reuse before attaching.
  - Match **older than 1 week** → ignore unless the user explicitly asks to resume it.
- No usable match → create with the EnterWorktree tool (preferred) or `git worktree add .claude/worktrees/<slug> -b worktree-<slug> main`.

## 2. All session files go in `work/` inside the worktree

Create every session file under `<worktree>/work/` — never at the worktree root, which holds infra checked out from main (CLAUDE.md, docs/, scripts/, .gitignore). This keeps session output dumpable as one folder: `cp -r work/ <dest>`.

Never write to the repo root either, except to maintain infra (`CLAUDE.md`, `README.md`, `.gitignore`, `scripts/`, `docs/`) — and infra edits happen only on the main checkout, never via a worktree's copy.

Hard-enforced: a PreToolUse hook (`scripts/enforce-work-dir.sh`, wired in `.claude/settings.json`) blocks Write/Edit/NotebookEdit outside `work/` inside worktrees, and blocks `work/` at the repo root. If it blocks you, you're writing to the wrong place — don't work around it via Bash.

## 3. Commit at milestones

Commit (on the worktree's branch) when a deliverable is produced, an investigation step lands, or the session ends. Normal commit-message style.

## 4. Junk rules

- Clone third-party repos into `external/` inside the worktree (gitignored) — never commit nested repos.
- Never commit: virtualenvs, `node_modules`, caches, logs, binaries over ~5 MB.

## 5. Pivot rule

Premise changes substantially mid-session → ask the user: rename the worktree (branch + directory) or start a new one.

## 6. Cleanup — explicit only

Never prune automatically. When the user asks for cleanup, run `scripts/prune-worktrees.sh`. It removes worktree directories but always keeps branches, so content stays recoverable. Worktrees locked by a live session are skipped unless run with `FORCE=1`.
