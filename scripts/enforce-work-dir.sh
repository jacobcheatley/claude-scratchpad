#!/usr/bin/env bash
# PreToolUse hook (Write|Edit|NotebookEdit): enforce session-file containment.
#
# Rules:
#   - Inside a session worktree (.claude/worktrees/<slug>/), files may only be
#     created/edited under work/. Infra files (CLAUDE.md, docs/, scripts/,
#     .gitignore) are edited on the main checkout only.
#   - On the main checkout, work/ is off-limits — session files belong in a
#     worktree. Anything else at the root is infra maintenance and allowed.
#   - Paths outside the repo (scratchpad, memory, etc.) are not our concern.
#
# Exit 2 blocks the tool call and feeds stderr back to Claude.

set -euo pipefail

input="$(cat)"
path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")"
[[ -n "$path" ]] || exit 0

if [[ "$path" != /* ]]; then
    cwd="$(jq -r '.cwd // empty' <<<"$input")"
    path="${cwd:+$cwd/}$path"
fi
path="$(realpath -m "$path")"

# Resolve the main checkout root from wherever this script lives: in a session
# worktree, --git-common-dir points back at the main checkout's .git.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
main_root="$(dirname "$(git -C "$script_dir" rev-parse --path-format=absolute --git-common-dir)")"

# Inside a session worktree?
if [[ "$path" =~ ^"$main_root"/\.claude/worktrees/[^/]+(/.*)?$ ]]; then
    rest="${BASH_REMATCH[1]}"
    [[ "$rest" == /work/* ]] && exit 0
    # external/ holds cloned third-party repos (CLAUDE.md rule 4) — edits there
    # are changes to those repos, not session files.
    [[ "$rest" == /external/* ]] && exit 0
    echo "Blocked by workflow hook: inside a session worktree, create files only under work/ or external/ (CLAUDE.md rules 2 & 4). Infra files are edited on the main checkout at $main_root." >&2
    exit 2
fi

# On the main checkout? Only work/ is off-limits — session files belong in a
# worktree, everything else at the root is infra maintenance.
if [[ "$path" == "$main_root"/work/* ]]; then
    echo "Blocked by workflow hook: session files go in a worktree's work/ dir, not the main checkout (CLAUDE.md rule 1)." >&2
    exit 2
fi

exit 0
