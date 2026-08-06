#!/usr/bin/env bash
# Create a workspace: one directory, one linked worktree per repo, each branched
# from a source repo that has just been brought up to date.
#
# The freshness step is not a nicety. git worktree add branches from whatever
# the source repo currently has, so pulling afterwards is a rebase and
# pulling beforehand is free.
#
# Naming is applied mechanically here (repo alone for a single-owner workspace,
# <owner>-<repo> for every worktree in a mixed-owner one) because it is a rule
# about paths. It is NOT the whole naming convention: whether this task is even
# allowed an unprefixed <task> name is a house rule that lives in your
# CLAUDE.md, and this script cannot see it. Settle the task name there first.
#
# Usage: new-workspace.sh [--dry-run] [--branch <name>] <task> <owner/repo>...
# Exit:  0 created, 1 refused (with the reason), 2 usage.
set -uo pipefail

REPOS_ROOT="${REPOS_ROOT:-$HOME/repos}"
WORKSPACES_ROOT="${WORKSPACES_ROOT:-$HOME/workspaces}"
dry=0
branch=""
task=""
repos=()

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --branch) shift; branch="${1:-}" ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) if [ -z "$task" ]; then task="$1"; else repos+=("$1"); fi ;;
  esac
  shift
done

[ -n "$task" ] && [ ${#repos[@]} -gt 0 ] || {
  echo "usage: new-workspace.sh [--dry-run] [--branch <name>] <task> <owner/repo>..." >&2
  exit 2
}
branch="${branch:-$task}"

ws="$WORKSPACES_ROOT/$task"
[ -e "$ws" ] && {
  echo "workspace already exists: $ws" >&2
  echo "To add a repo to it, use the adding-a-repo-to-a-workspace skill instead." >&2
  exit 1
}

# Mixed-owner workspaces prefix EVERY worktree, not only the colliding one, so
# the listing stays uniform. Decide once, up front: discovering it later means
# renaming what is already there.
owners=$(printf '%s\n' "${repos[@]}" | cut -d/ -f1 | sort -u)
mixed=0
[ "$(printf '%s\n' "$owners" | wc -l)" -gt 1 ] && mixed=1

default_branch() {
  local d
  if d=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null); then
    echo "${d#refs/remotes/origin/}"; return
  fi
  if d=$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p') && [ -n "$d" ]; then
    echo "$d"; return
  fi
  for d in main master trunk; do
    git show-ref --quiet "refs/remotes/origin/$d" && { echo "$d"; return; }
  done
  echo ""
}

# Validate and refresh every source repo BEFORE creating anything. A
# half-built workspace -- two worktrees of five, the rest refused -- is worse
# than none, because the next run cannot tell the difference between a
# deliberate partial workspace and a failed one.
declare -a plan_src plan_dir plan_repo
for r in "${repos[@]}"; do
  case "$r" in
    */*) : ;;
    *) echo "expected <owner>/<repo>, got: $r" >&2; exit 2 ;;
  esac
  src="$REPOS_ROOT/$r"
  [ -d "$src/.git" ] || { echo "no repo at $src -- clone it there first" >&2; exit 1; }

  cd "$src" || exit 1
  db=$(default_branch)
  cur=$(git rev-parse --abbrev-ref HEAD)
  [ -n "$db" ] || { echo "$r: cannot determine the default branch" >&2; exit 1; }
  [ "$cur" = "$db" ] || {
    echo "$r: repo is on '$cur', not '$db'." >&2
    echo "  Branching from it would base your work on someone's parked branch." >&2
    echo "  Use the refreshing-a-repo skill first." >&2
    exit 1
  }
  if [ -n "$(git status --porcelain)" ]; then
    echo "$r: working tree is not clean:" >&2
    git status --short | sed 's/^/    /' >&2
    echo "  Sort this out before branching from it." >&2
    exit 1
  fi
  git show-ref --quiet "refs/heads/$branch" && {
    echo "$r: branch '$branch' already exists in this repo." >&2
    exit 1
  }

  if [ "$dry" = 1 ]; then
    echo "would: git -C $src pull --ff-only"
  else
    git fetch --quiet --all 2>/dev/null
    git merge --ff-only "origin/$db" --quiet 2>/dev/null || {
      echo "$r: cannot fast-forward to origin/$db -- the repo has diverged." >&2
      exit 1
    }
  fi

  if [ "$mixed" = 1 ]; then dir="${r%%/*}-${r##*/}"; else dir="${r##*/}"; fi
  plan_src+=("$src"); plan_dir+=("$dir"); plan_repo+=("$r")
done

echo "workspace: $ws"
echo "branch:    $branch"
[ "$mixed" = 1 ] && echo "naming:    mixed-owner -- every worktree prefixed <owner>-<repo>"

for i in "${!plan_src[@]}"; do
  target="$ws/${plan_dir[$i]}"
  if [ "$dry" = 1 ]; then
    echo "would: git -C ${plan_src[$i]} worktree add -b $branch $target"
    continue
  fi
  if git -C "${plan_src[$i]}" worktree add -b "$branch" "$target" --quiet; then
    echo "  ${plan_repo[$i]} -> $target"
  else
    echo "  FAILED: ${plan_repo[$i]}" >&2
    exit 1
  fi
done

[ "$dry" = 1 ] && exit 0

echo
echo "Next: create the herdr space rooted at $ws, with one pane per worktree."
echo "Use the herdr skill for the commands -- the installed binary is the authority."
