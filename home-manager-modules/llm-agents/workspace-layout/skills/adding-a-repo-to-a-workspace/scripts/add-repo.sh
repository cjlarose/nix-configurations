#!/usr/bin/env bash
# Add a repo to an existing workspace, renaming the worktrees already there if
# this is the repo that makes the workspace mixed-owner.
#
# The rename is the whole reason this is a script. Adding globex/widget beside
# acme/widget does not just need a prefix on the new worktree -- it needs one on
# EVERY worktree in the workspace, so the listing stays uniform. And the rename
# has to go through `git worktree move` from each source repo, so git
# rewrites its own bookkeeping; moving the directory by hand leaves a worktree
# pointing at a path that no longer exists, which git only notices later.
#
# Usage: add-repo.sh [--dry-run] [--branch <name>] <task> <owner/repo>
# Exit:  0 added, 1 refused (with the reason), 2 usage.
set -uo pipefail

REPOS_ROOT="${REPOS_ROOT:-$HOME/repos}"
WORKSPACES_ROOT="${WORKSPACES_ROOT:-$HOME/workspaces}"
dry=0
branch=""
task=""
repo=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --branch) shift; branch="${1:-}"
              [ -n "$branch" ] || { echo "--branch needs a value" >&2; exit 2; } ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) if [ -z "$task" ]; then task="$1"; else repo="$1"; fi ;;
  esac
  shift
done

[ -n "$task" ] && [ -n "$repo" ] || {
  echo "usage: add-repo.sh [--dry-run] [--branch <name>] <task> <owner/repo>" >&2
  exit 2
}
case "$repo" in */*) : ;; *) echo "expected <owner>/<repo>, got: $repo" >&2; exit 2 ;; esac

ws="$WORKSPACES_ROOT/$task"
[ -d "$ws" ] || { echo "no such workspace: $ws" >&2; exit 1; }
branch="${branch:-$task}"
new_owner="${repo%%/*}"
new_name="${repo##*/}"

# What is already here, and where did each worktree come from? The source repo
# is the main worktree of the same repository, which git will name for us --
# more reliable than parsing it out of the directory name we are about to
# change.
# Explicit empty assignment, not just `declare -a`: under `set -u` a declared
# but unassigned array makes ${#arr[@]} an "unbound variable" error, which
# skips BOTH sides of the `||` guard below and lets the script carry on.
cur_dir=()
cur_src=()
cur_owner=()
cur_repo=()
for wt in "$ws"/*/; do
  [ -e "$wt/.git" ] || continue
  src=$(git -C "$wt" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
  [ -n "$src" ] || continue
  rel="${src#"$REPOS_ROOT"/}"
  # A worktree whose source repo is not under REPOS_ROOT leaves `rel` absolute,
  # so ${rel%%/*} is the EMPTY string -- which then counts as its own "owner" in
  # the sort below, spuriously making the workspace look mixed and proposing a
  # rename to "-<repo>". Skip it and say so rather than guessing an owner.
  case "$src" in
    "$REPOS_ROOT"/*/*) : ;;
    *) echo "skipping $(basename "$wt"): its repo ($src) is not under $REPOS_ROOT," >&2
       echo "  so it has no <owner>/<repo> name to prefix with." >&2
       continue ;;
  esac
  cur_dir+=("$(basename "$wt")")
  cur_src+=("$src")
  cur_owner+=("${rel%%/*}")
  cur_repo+=("${rel##*/}")
done

[ ${#cur_dir[@]} -gt 0 ] || { echo "no worktrees found in $ws" >&2; exit 1; }

# Mixed the moment a second owner appears among the existing ones or with this
# addition.
owners=$(printf '%s\n' "${cur_owner[@]}" "$new_owner" | sort -u)
mixed=0
[ "$(printf '%s\n' "$owners" | wc -l)" -gt 1 ] && mixed=1

src="$REPOS_ROOT/$repo"
[ -d "$src/.git" ] || { echo "no repo at $src -- clone it there first" >&2; exit 1; }

default_branch() {
  local d
  if d=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null); then
    echo "${d#refs/remotes/origin/}"; return
  fi
  # `git remote show` prints "(unknown)" when the remote HEAD is unset, which is
  # non-empty and would sail through every caller's test, so confirm the ref
  # actually exists before trusting it. This branch also hits the network, where
  # the symbolic-ref path above does not.
  if d=$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p') \
     && [ -n "$d" ] && git show-ref --quiet "refs/remotes/origin/$d"; then
    echo "$d"; return
  fi
  for d in main master trunk; do
    git show-ref --quiet "refs/remotes/origin/$d" && { echo "$d"; return; }
  done
  echo ""
}

cd "$src" || exit 1
db=$(default_branch)
cur=$(git rev-parse --abbrev-ref HEAD)
[ -n "$db" ] || { echo "$repo: cannot determine the default branch" >&2; exit 1; }
[ "$cur" = "$db" ] || { echo "$repo: repo is on '$cur', not '$db' -- refresh it first." >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "$repo: working tree is not clean." >&2; exit 1; }

# The rename cascade, before adding anything: if it fails halfway, a workspace
# with mismatched names is at least still a working one, whereas a new worktree
# added under the old scheme would have to be removed again.
if [ "$mixed" = 1 ]; then
  for i in "${!cur_dir[@]}"; do
    want="${cur_owner[$i]}-${cur_repo[$i]}"
    [ "${cur_dir[$i]}" = "$want" ] && continue
    # `git worktree move` into an EXISTING directory does not fail -- it moves
    # the worktree INSIDE it, so widget lands at <ws>/acme-widget/widget and the
    # script would report a successful rename. That worktree is then at a depth
    # nothing else here looks at, which is how it becomes invisible to
    # check-landed.sh and survives teardown unnoticed.
    [ -e "$ws/$want" ] && {
      echo "cannot rename ${cur_dir[$i]} -> $want: $ws/$want already exists." >&2
      echo "Move or remove it first; renaming into it would nest the worktree." >&2
      exit 1
    }
    if [ "$dry" = 1 ]; then
      echo "would: git -C ${cur_src[$i]} worktree move $ws/${cur_dir[$i]} $ws/$want"
      continue
    fi
    if git -C "${cur_src[$i]}" worktree move "$ws/${cur_dir[$i]}" "$ws/$want"; then
      echo "renamed: ${cur_dir[$i]} -> $want"
    else
      echo "FAILED to move ${cur_dir[$i]} -- stopping before adding $repo." >&2
      echo "The workspace is unchanged apart from any renames already reported." >&2
      exit 1
    fi
  done
fi

if [ "$mixed" = 1 ]; then dir="$new_owner-$new_name"; else dir="$new_name"; fi
target="$ws/$dir"
[ -e "$target" ] && { echo "already present: $target" >&2; exit 1; }

if [ "$dry" = 1 ]; then
  echo "would: git -C $src pull --ff-only"
  echo "would: git -C $src worktree add -b $branch $target"
  exit 0
fi

git fetch --quiet --all 2>/dev/null || {
  echo "$repo: fetch failed -- cannot confirm $src is current, so not branching" >&2
  echo "  from it. Fix the network and run this again." >&2
  exit 1
}
git merge --ff-only "origin/$db" --quiet 2>/dev/null || {
  echo "$repo: cannot fast-forward to origin/$db -- the repo has diverged." >&2
  exit 1
}

if git show-ref --quiet "refs/heads/$branch"; then
  echo "$repo: branch '$branch' already exists -- checking it out into the worktree."
  git worktree add "$target" "$branch" --quiet || exit 1
else
  git worktree add -b "$branch" "$target" --quiet || exit 1
fi
echo "added: $repo -> $target"

[ "$mixed" = 1 ] && echo "Reminder: the herdr space and any open panes still refer to the old paths."
exit 0
