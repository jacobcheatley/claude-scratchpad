---
name: dump-work
description: Use when the user wants a worktree's outputs packaged for sharing — "dump this worktree", "export the work dir", "package this up to share", "zip up the results", "send this investigation to someone", or /dump-work.
---

# dump-work

Export a session worktree's `work/` dir as a shareable archive via `scripts/dump-work.sh` at the main checkout root (from inside a worktree that's `$(git rev-parse --path-format=absolute --git-common-dir)/../scripts/dump-work.sh`). Never hand-roll `zip`/`tar`/`git archive` for this.

## Steps

1. **Resolve the slug.** Inside a worktree, omit it (the script infers from cwd). Otherwise use the worktree named by the user; if ambiguous, check `git worktree list` and ask.
2. **Map the request to flags** (see table). Default with no qualifiers: plain zip, no history, gitignored files excluded.
3. **If using `--history` and `work/` has uncommitted changes** (`git status -- work/`), offer to commit them first so the shipped history matches the shipped files; uncommitted files still ride along as untracked either way.
4. **Run the script** and report the printed archive path (and the stderr size summary) to the user. Heed any size warning — confirm before sharing 100 MB+.

## Flag map

| User says | Flags |
|---|---|
| "with (git) history", "so they can see how it evolved" | `--history` — archive unpacks to a real repo rooted at work/ with only its commits |
| "everything", "include the data/downloads", "ignored files too" | `--all` |
| "tarball", "tar.gz" | `--tgz` |
| names a destination | `-o <path>` |

Flags compose. Archives land in `dumps/` (gitignored) as `<slug>-work-<YYYYMMDD>[-HHMM].zip` — never commit them. A pruned worktree still works: the script archives tracked files from the surviving branch.

## Common mistakes

- Hand-rolling `zip -r` / `cp -r` when this script exists — loses gitignore filtering and history support.
- Forgetting `--history` when the user asked for history — the default archive has no `.git`.
- Reaching for `--all` "to be safe" — it can pull in multi-GB gitignored data; use it only when asked.
