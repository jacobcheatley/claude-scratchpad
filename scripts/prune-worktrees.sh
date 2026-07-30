#!/usr/bin/env bash
# Explicit-call cleanup for session worktrees (.claude/worktrees/<slug>).
# Removes worktree directories only — branches are always kept, so content
# stays recoverable: `claude --worktree <slug>` reattaches to the surviving branch.
#
# Usage:
#   prune-worktrees.sh                     list worktrees with age of last commit
#   prune-worktrees.sh <slug>...           remove the named worktrees (branches kept)
#   prune-worktrees.sh --older-than <age>  remove worktrees whose last commit is
#                                          older than <age> (e.g. 7d, 2w, 12h, 30m)
#   FORCE=1 prune-worktrees.sh ...         also remove session-locked worktrees

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
wt_dir="$repo_root/.claude/worktrees"
cd "$repo_root"

# Convert an age spec like 7d / 2w / 12h / 30m (bare number = days) to seconds.
age_to_seconds() {
    local spec="$1"
    [[ "$spec" =~ ^([0-9]+)([mhdw]?)$ ]] || {
        echo "invalid age spec: '$spec' (expected e.g. 7d, 2w, 12h, 30m)" >&2
        return 1
    }
    local n="${BASH_REMATCH[1]}" unit="${BASH_REMATCH[2]:-d}"
    case "$unit" in
        m) echo $((n * 60)) ;;
        h) echo $((n * 3600)) ;;
        d) echo $((n * 86400)) ;;
        w) echo $((n * 604800)) ;;
    esac
}

worktree_slugs() {
    git worktree list --porcelain | sed -n 's/^worktree //p' | while IFS= read -r dir; do
        [[ "$dir" == "$wt_dir/"* ]] && basename "$dir"
    done
}

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
    done < <(git worktree list --porcelain | sed -n 's/^worktree //p')
    [[ $found -eq 1 ]] || echo "No session worktrees under .claude/worktrees/"
}

if [[ $# -eq 0 ]]; then
    list_worktrees
    exit 0
fi

targets=()
if [[ "$1" == "--older-than" ]]; then
    [[ $# -eq 2 ]] || { echo "usage: prune-worktrees.sh --older-than <age>" >&2; exit 1; }
    max_age="$(age_to_seconds "$2")" || exit 1
    cutoff=$(( $(date +%s) - max_age ))
    while IFS= read -r slug; do
        last_commit="$(git -C "$wt_dir/$slug" log -1 --format=%ct 2>/dev/null || true)"
        if [[ -z "$last_commit" ]]; then
            echo "skip: $slug has no commits" >&2
            continue
        fi
        (( last_commit < cutoff )) && targets+=("$slug")
    done < <(worktree_slugs)
    if [[ ${#targets[@]} -eq 0 ]]; then
        echo "No worktrees older than $2."
        exit 0
    fi
else
    targets=("$@")
fi

for slug in "${targets[@]}"; do
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

# Keep the VSCode workspace file in step with removals.
"$repo_root/scripts/sync-workspace.sh" || true
