#!/usr/bin/env bash
# Explicit-call cleanup for session worktrees (.claude/worktrees/<slug>).
# Removes worktree directories only — branches are always kept, so content
# stays recoverable: `claude --worktree <slug>` reattaches to the surviving branch.
#
# Usage:
#   prune-worktrees.sh              list worktrees with age of last commit
#   prune-worktrees.sh <slug>...    remove the named worktrees (branches kept)
#   FORCE=1 prune-worktrees.sh <slug>...   also remove session-locked worktrees

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
wt_dir="$repo_root/.claude/worktrees"
cd "$repo_root"

list_worktrees() {
    local found=0
    while IFS= read -r dir; do
        [[ "$dir" == "$wt_dir/"* ]] || continue
        found=1
        local slug branch age lock
        slug="$(basename "$dir")"
        branch="$(git -C "$dir" branch --show-current)"
        age="$(git -C "$dir" log -1 --format=%cr 2>/dev/null || echo 'no commits')"
        lock=""
        git worktree list --porcelain | grep -A2 "^worktree $dir$" | grep -q '^locked' && lock=" [locked]"
        printf '%-30s branch=%-35s last commit: %s%s\n' "$slug" "$branch" "$age" "$lock"
    done < <(git worktree list --porcelain | awk '/^worktree /{print $2}')
    [[ $found -eq 1 ]] || echo "No session worktrees under .claude/worktrees/"
}

if [[ $# -eq 0 ]]; then
    list_worktrees
    exit 0
fi

for slug in "$@"; do
    path=".claude/worktrees/$slug"
    if [[ ! -d "$path" ]]; then
        echo "skip: $path does not exist" >&2
        continue
    fi
    if [[ "${FORCE:-0}" == "1" ]]; then
        git worktree remove -f -f "$path"
    elif ! git worktree remove --force "$path" 2>/dev/null; then
        echo "skip: $path is locked (live session?). Rerun with FORCE=1 to override." >&2
        continue
    fi
    echo "removed worktree $path (branch kept)"
done
