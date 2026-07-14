# claude-scratchpad

A scratch workspace for [Claude Code](https://claude.com/claude-code) sessions that aren't tied to any project — quick investigations, one-off scripts, data crunching, prototypes. Instead of littering your home directory (or a pile of `~/tmp` folders), every session's output lands in its own git worktree, named after what the session was about, with full history.

**What you get:**

- **Isolation** — concurrent sessions can't trample each other; each works on its own branch in its own directory.
- **History** — everything a session produced is committed on a branch named after the topic. Months later, `git branch` is a searchable log of everything you've ever asked Claude to poke at.
- **A pristine root** — the repo root holds only the workflow itself (CLAUDE.md, scripts, docs). Session files are confined to `work/` inside each worktree, enforced by a PreToolUse hook.

## How it works

Worktrees follow Claude Code's native `--worktree` convention: directory `.claude/worktrees/<slug>`, branch `worktree-<slug>`.

```
claude-scratchpad/
├── CLAUDE.md                  # workflow rules Claude follows each session
├── scripts/
│   ├── enforce-work-dir.sh    # hook: blocks writes outside work/
│   └── prune-worktrees.sh     # explicit cleanup (keeps branches)
├── docs/design.md             # full design
└── .claude/worktrees/         # gitignored — one worktree per topic
    └── fix-csv-parser/        # branch: worktree-fix-csv-parser
        └── work/              # ← all session files live here
```

`CLAUDE.md` tells Claude to derive a slug from your first message, find or create the matching worktree, keep every file under `work/`, and commit at milestones. The hook makes the containment hard rather than advisory.

## Setup

1. Clone (or fork) this repo somewhere permanent:

   ```sh
   git clone https://github.com/jacobcheatley/claude-scratchpad ~/claude-scratchpad
   ```

2. Add a launcher to your `~/.bashrc` / `~/.zshrc` so scratch sessions are one command from anywhere:

   ```sh
   cs() {
     local prev="$PWD"
     cd ~/claude-scratchpad || return
     claude "$@"
     cd "$prev" || return
   }
   ```

3. (Recommended) Install the [superpowers](https://github.com/obra/superpowers) plugin — its brainstorming/debugging/planning skills pair well with investigative scratch work:

   ```
   claude plugin install superpowers@superpowers-marketplace
   ```

## Usage

```sh
cs                                  # start a session; Claude names the worktree from your first message
cs -w fix-csv-parser                # start (or resume) a named worktree session
cs -w fix-csv-parser "why does pandas choke on this file?"   # with an opening prompt
```

`-w` is Claude Code's `--worktree` flag: it creates the worktree and branch if new, reattaches if they exist.

### Example session

```sh
$ cs -w compare-json-parsers "benchmark orjson vs ujson vs stdlib on a 2GB dump"
```

Claude works inside `.claude/worktrees/compare-json-parsers/work/` — benchmark script, results CSV, findings writeup — and commits on `worktree-compare-json-parsers` as milestones land.

Want the output somewhere else? It's one folder:

```sh
cp -r .claude/worktrees/compare-json-parsers/work/ ~/some-project/benchmarks/
```

Done with the directory? Prune it — the branch (and therefore the content) survives:

```sh
scripts/prune-worktrees.sh                        # list worktrees + age
scripts/prune-worktrees.sh compare-json-parsers   # remove dir, keep branch
cs -w compare-json-parsers                        # ...and it's back
```

## Conventions Claude follows

See `CLAUDE.md` for the full rules; the short version:

- All session files go in `work/` inside the worktree — never the worktree root, never the repo root.
- Third-party repos get cloned into `external/` (gitignored) inside the worktree.
- No committed junk: virtualenvs, `node_modules`, caches, logs, binaries over ~5 MB.
- Commits at milestones, on the worktree's branch.
- Cleanup is explicit-only — nothing is pruned automatically, and pruning never deletes branches.

## License

MIT — see [LICENSE](LICENSE).
