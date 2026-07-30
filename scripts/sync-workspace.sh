#!/usr/bin/env bash
# Sync session worktrees' work/ dirs into the sibling VSCode multi-root
# workspace file (<repo parent>/claude-scratchpad.code-workspace).
#
# Managed-folders-only semantics: this script owns folder entries whose path
# points at <repo>/.claude/worktrees/<slug>/work — it adds new worktrees and
# drops removed ones. Every other key and folder entry (settings, extensions,
# the root folder, hand-added dirs) passes through untouched.
#
# Idempotent; no arguments; safe to run from hooks or a worktree's scripts/ copy.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
main_root="$(dirname "$(git -C "$script_dir" rev-parse --path-format=absolute --git-common-dir)")"
repo_name="$(basename "$main_root")"
ws_file="$(dirname "$main_root")/$repo_name.code-workspace"

# Managed entries: one per session worktree, path relative to the workspace
# file's directory, sorted by slug for stable ordering.
entries="[]"
while IFS= read -r wt; do
    [[ "$wt" == "$main_root/.claude/worktrees/"* ]] || continue
    [[ -d "$wt" ]] || continue
    slug="$(basename "$wt")"
    mkdir -p "$wt/work"
    entries="$(jq --arg p "$repo_name/.claude/worktrees/$slug/work" --arg n "$slug" \
        '. + [{path: $p, name: $n}]' <<<"$entries")"
done < <(git -C "$main_root" worktree list --porcelain | sed -n 's/^worktree //p')
entries="$(jq 'sort_by(.name)' <<<"$entries")"

if [[ -f "$ws_file" ]]; then
    if ! jq empty "$ws_file" 2>/dev/null; then
        echo "sync-workspace: $ws_file is not plain JSON (comments/trailing commas?) — fix or delete it to regenerate" >&2
        exit 1
    fi
    new="$(jq --argjson managed "$entries" --arg prefix "$repo_name/.claude/worktrees/" '
        def is_managed: (.path? // null) as $p
          | ($p|type) == "string" and ($p|startswith($prefix))
            and ($p|ltrimstr($prefix)|test("^[^/]+/work$"));
        .folders = ((.folders // []) | map(select(is_managed | not)) + $managed)
    ' "$ws_file")"
else
    new="$(jq -n --argjson managed "$entries" --arg root "$repo_name" '
        {folders: ([{path: $root, name: "root (main)"}] + $managed), settings: {}}
    ')"
fi

# Skip the write when nothing changed (avoids VSCode file-watcher reloads).
if [[ -f "$ws_file" ]] && diff -q <(printf '%s\n' "$new") "$ws_file" >/dev/null 2>&1; then
    exit 0
fi

tmp="$(mktemp "$ws_file.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$new" >"$tmp"
chmod 644 "$tmp"
mv "$tmp" "$ws_file"
