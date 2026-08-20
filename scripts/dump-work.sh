#!/usr/bin/env bash
# Export a session worktree's work/ dir as a shareable archive, for handing
# investigation outputs and data to other people.
#
# Usage:
#   dump-work.sh [<slug>] [--history] [--all] [--tgz] [-o <path>]
#
#   <slug>       worktree under .claude/worktrees/; inferred from cwd when
#                run inside one. If the worktree was pruned but its branch
#                survives, tracked files are archived from the branch.
#   --history    embed the git history of just work/ as a real repo: the
#                archive unpacks to a browsable repo with work/ as its root
#                (via git subtree split in a temp clone — never mutates
#                this repo). Uncommitted session files ride along untracked.
#   --all        include gitignored files too (external/, venvs, big data);
#                default is the working tree minus gitignored files.
#   --tgz        write tar.gz instead of zip.
#   -o <path>    write the archive there instead of the default
#                dumps/<slug>-work-<YYYYMMDD>[-HHMM].zip at the repo root.
#
# Prints the archive path on stdout (script-friendly); summary and warnings
# go to stderr. Warns when the archive exceeds $DUMP_WORK_WARN_MB (100) MB.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

slug="" all=0 fmt=zip out_override="" history=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --all) all=1 ;;
        --history) history=1 ;;
        --tgz) fmt=tgz ;;
        -o) out_override="${2:?-o requires a path}"; shift ;;
        -*) echo "unknown option: $1" >&2; exit 1 ;;
        *) slug="$1" ;;
    esac
    shift
done
# No slug given: infer from cwd when inside a session worktree.
if [[ -z "$slug" && "$PWD/" == "$repo_root/.claude/worktrees/"?* ]]; then
    rest="${PWD#"$repo_root"/.claude/worktrees/}"
    slug="${rest%%/*}"
fi
[[ -n "$slug" ]] || {
    echo "usage: dump-work.sh <slug> [--history] [--all] [--tgz] [-o <path>] (slug required outside a worktree)" >&2
    exit 1
}
wt_path="$repo_root/.claude/worktrees/$slug"
branch="worktree-$slug"
mode=worktree
if [[ ! -d "$wt_path" ]]; then
    git -C "$repo_root" show-ref -q --verify "refs/heads/$branch" || {
        echo "no worktree or branch for slug '$slug'" >&2
        exit 1
    }
    mode=branch
    echo "note: worktree is pruned — archiving tracked files from branch $branch" >&2
    [[ $all -eq 1 ]] && echo "note: --all has no effect in branch mode (only tracked files survive)" >&2
fi

ext=zip
[[ "$fmt" == tgz ]] && ext=tar.gz
if [[ -n "$out_override" ]]; then
    out="$out_override"
else
    out="$repo_root/dumps/$slug-work-$(date +%Y%m%d).$ext"
    # Same-day rerun: disambiguate with a time suffix instead of overwriting.
    [[ -e "$out" ]] && out="$repo_root/dumps/$slug-work-$(date +%Y%m%d-%H%M).$ext"
fi
mkdir -p "$(dirname "$out")"
rm -f "$out"   # zip appends into an existing archive; always start fresh

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
staging="$tmp/staging"
mkdir -p "$staging"

# Default: working tree of work/ minus gitignored files (tracked +
# untracked-unignored). --all: everything under work/.
list_files() {
    if [[ $all -eq 1 ]]; then
        find work -type f -printf '%P\n' | sed 's:^:work/:'
    else
        git ls-files --cached --others --exclude-standard -- work/
    fi
}

if [[ "$mode" == branch ]]; then
    git -C "$repo_root" archive "$branch" work | tar -x -C "$staging" --strip-components=1
else
    (
        cd "$wt_path"
        list_files | while IFS= read -r f; do
            [[ -f "$f" ]] || continue   # skip tracked-but-deleted
            dest="$staging/${f#work/}"
            mkdir -p "$(dirname "$dest")"
            cp -p "$f" "$dest"
        done
    )
fi

[[ -n "$(ls -A "$staging")" ]] || {
    echo "work/ in '$slug' is empty — nothing to archive" >&2
    exit 1
}

# --history: ship a real git repo whose root is work/ with only its commits.
# All rewriting happens in a temp clone — the real repo is never touched.
if [[ $history -eq 1 ]]; then
    git clone -q --branch "worktree-$slug" --single-branch "$repo_root" "$tmp/clone"
    git -C "$tmp/clone" subtree split -q --prefix=work -b __work_split >/dev/null
    # Fresh repo holding only the split branch's objects, as branch "main".
    git init -q -b main "$tmp/ship"
    git -C "$tmp/ship" fetch -q "$tmp/clone" __work_split
    git -C "$tmp/ship" update-ref refs/heads/main FETCH_HEAD
    git -C "$tmp/ship" reset -q   # index = HEAD, so the unpacked tree reads clean
    cp -r "$tmp/ship/.git" "$staging/.git"
fi

if [[ "$fmt" == tgz ]]; then
    tar -czf "$out" -C "$staging" .
else
    (cd "$staging" && zip -qr "$out" .)
fi

size_bytes="$(stat -c%s "$out")"
warn_mb="${DUMP_WORK_WARN_MB:-100}"
if (( size_bytes > warn_mb * 1024 * 1024 )); then
    echo "warning: archive exceeds ${warn_mb} MB — check for datasets/venvs you didn't mean to share" >&2
fi
echo "wrote $out ($(numfmt --to=iec --suffix=B "$size_bytes"))" >&2
echo "$out"
