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
    --branch) shift; branch="${1:-}"
              [ -n "$branch" ] || { echo "--branch needs a value" >&2; exit 2; } ;;
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

# Reject a repo named twice before anything is created. Up-front validation
# cannot catch every mid-loop failure, but this one it can: the same repo twice
# passes every per-repo check and then fails at the SECOND `worktree add` with
# "a branch named X already exists", leaving the first worktree on disk and the
# workspace directory in the way of a retry.
dupes=$(printf '%s\n' "${repos[@]}" | sort | uniq -d)
[ -z "$dupes" ] || {
  echo "the same repo is listed more than once:" >&2
  printf '  %s\n' $dupes >&2
  exit 2
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
    # A failed fetch means the ff-merge below compares against whatever was last
    # seen, so the branch would be cut from a stale base while this script
    # reports having refreshed it. Refuse instead: the header of this file
    # promises the branch starts current, and that promise is the whole point.
    git fetch --quiet --all 2>/dev/null || {
      echo "$r: fetch failed -- cannot confirm $src is current, so not" >&2
      echo "  branching from it. Fix the network and run this again." >&2
      exit 1
    }
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

# Which herdr space is rooted at a given directory.
#
# herdr records this itself: session.json holds identity_cwd per space, set when
# the space is created. That is the real association, and it is exact -- unlike
# the label, which defaults to the cwd basename and is neither unique nor owned
# by the task, so closing by label can take an unrelated space's panes with it.
#
# It is also PRIVATE state with an undocumented schema, and the socket API does
# not expose identity_cwd (workspace list/get return the label only). So every
# assumption about the file is checked before it is used, and anything
# unexpected returns non-zero rather than a guess: the caller then declines to
# act instead of acting on a misread.
space_for_cwd() {
  local cwd="$1"
  local f="${XDG_CONFIG_HOME:-$HOME/.config}/herdr/session.json"

  if [ ! -f "$f" ]; then
    echo "herdr session file not found at $f -- cannot tell which space, if" >&2
    echo "  any, belongs to this workspace." >&2
    return 1
  fi
  if ! jq -e '.workspaces | type == "array"' "$f" >/dev/null 2>&1; then
    echo "herdr session file has no .workspaces array: $f" >&2
    echo "  The format has changed; not guessing which space to act on." >&2
    return 1
  fi
  # An empty list is a fine answer (no spaces open). A NON-empty list in which
  # nothing carries both keys means the fields moved, which is the case worth
  # refusing on -- otherwise every lookup silently returns "no match" and the
  # scripts quietly stop managing spaces at all.
  if [ "$(jq -r '.workspaces | length' "$f" 2>/dev/null)" != "0" ] \
     && ! jq -e '[.workspaces[] | select(has("id") and has("identity_cwd"))] | length > 0' "$f" >/dev/null 2>&1; then
    echo "herdr session entries lack id/identity_cwd: $f" >&2
    echo "  The format has changed; not guessing which space to act on." >&2
    return 1
  fi

  # Match on identity_cwd. herdr rewrites it to "<path> (deleted)" once the
  # directory is gone, so tolerate that suffix -- a re-run after a partial
  # teardown still has to find the space it left open.
  local match
  match=$(jq -r --arg c "$cwd" \
    '.workspaces[] | select((.identity_cwd | sub(" \\(deleted\\)$"; "")) == $c) | .id' \
    "$f" 2>/dev/null | head -1)
  if [ -n "$match" ]; then
    echo "$match"
    return 0
  fi

  # No match. That is either "no space for this directory" or "the file has not
  # caught up yet" -- the server writes it a moment after the fact. Tell them
  # apart by asking whether the server knows a space the file does not: if so
  # the read is stale and a confident "nothing to close" would be wrong.
  if [ -n "${HERDR_ENV:-}" ] && command -v herdr >/dev/null 2>&1; then
    local unknown
    unknown=$(herdr workspace list 2>/dev/null \
      | jq -r --slurpfile s "$f" \
        '[.result.workspaces[]?.workspace_id] - [$s[0].workspaces[].id] | join(",")' 2>/dev/null)
    if [ -n "$unknown" ]; then
      echo "herdr session file has not caught up: the server knows space(s)" >&2
      echo "  $unknown that $f does not list yet." >&2
      echo "  Not concluding anything from a stale read; try again in a moment." >&2
      return 1
    fi
  fi
  return 0
}


herdr_space() {
  # One space per task, cwd at the workspace ROOT -- never a worktree inside it.
  # A space is bound to its cwd at creation time, so this is not something that
  # can be corrected later by moving; and adding a second owner renames the
  # worktrees underneath, which would strand a space rooted in one of them.
  local label="$1" cwd="$2"

  if [ "$dry" = 1 ]; then
    echo "would: herdr workspace create --cwd $cwd --label $label --no-focus"
    return 0
  fi

  if [ -z "${HERDR_ENV:-}" ] || ! command -v herdr >/dev/null 2>&1; then
    echo "Not running under herdr, so no space was created. When you are:"
    echo "    herdr workspace create --cwd $cwd --label $label --no-focus"
    return 0
  fi

  # `workspace create` will happily make a SECOND space for the same directory,
  # so ask first -- by CWD, which is the association herdr itself records, not
  # by label, which is neither unique nor owned by the task.
  local existing
  existing=$(space_for_cwd "$cwd") || return 0
  if [ -n "$existing" ]; then
    echo "herdr space already exists for $cwd ($existing) -- left alone"
    return 0
  fi

  # --no-focus: this runs from inside some other space, and yanking the user
  # out of it to look at an empty one is not what they asked for.
  if herdr workspace create --cwd "$cwd" --label "$label" --no-focus >/dev/null 2>&1; then
    echo "herdr space created: $label (cwd $cwd)"
  else
    echo "could not create the herdr space; do it by hand:" >&2
    echo "    herdr workspace create --cwd $cwd --label $label --no-focus" >&2
  fi
}

herdr_space "$task" "$ws"

[ "$dry" = 1 ] && exit 0

echo
echo "Panes: start one agent per worktree inside that space. Use the herdr skill"
echo "for pane and agent commands -- only the space itself is handled here."
