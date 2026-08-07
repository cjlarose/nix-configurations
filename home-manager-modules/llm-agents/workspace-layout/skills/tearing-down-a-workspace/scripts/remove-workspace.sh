#!/usr/bin/env bash
# Remove a workspace: every linked worktree first, from its own source repo, then
# the directory itself.
#
# Runs check-landed.sh first and refuses on anything it does not call SAFE. That
# refusal is the point of the script -- `rm -rf` on a workspace is one keystroke
# and takes unpushed commits with it.
#
# Usage: remove-workspace.sh [--dry-run] [--force] <workspace-dir>
# Exit:  0 removed, 1 refused, 2 usage.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dry=0
force=0
ws=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --force) force=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) [ -z "$ws" ] || {
         echo "unexpected extra argument: $1" >&2
         echo "This removes things; a stray argument is a typo, not a second target." >&2
         exit 2
       }
       ws="$1" ;;
  esac
  shift
done

[ -n "$ws" ] || { echo "usage: remove-workspace.sh [--dry-run] [--force] <workspace-dir>" >&2; exit 2; }
[ -d "$ws" ] || { echo "no such workspace: $ws" >&2; exit 2; }
ws="$(cd "$ws" && pwd)"

if [ "$force" = 1 ]; then
  echo "--force: skipping the landed check entirely."
else
  if ! "$here/check-landed.sh" "$ws"; then
    echo
    echo "REFUSING to remove $ws -- see the verdicts above."
    echo "Resolve them, or re-run with --force if you have decided the work is"
    echo "genuinely disposable. --force is a decision, not a retry."
    exit 1
  fi
  echo
fi

# Default branch as this repo understands it. origin/HEAD is a local ref, so
# this needs no network; when it is missing (a clone made with --no-checkout, or
# an older git) fall back to asking the remote, then to the usual names.
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


# Remove through git, from each worktree's own source repo, so git prunes its
# administrative files instead of being left pointing at a path that is gone.
# It also refuses a dirty tree, which makes teardown double as a last check.
status=0
# Explicit empty assignment, not just `declare -a`: under `set -u` an array
# that was declared but never assigned still trips ${#arr[@]}, which is
# exactly the path a workspace with no worktrees left takes.
left_src=()
left_branch=()
for wt in "$ws"/*/; do
  [ -e "$wt/.git" ] || continue
  wt="${wt%/}"
  src=$(git -C "$wt" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
  br=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -z "$src" ]; then
    echo "cannot find the source repo for $wt -- leaving it alone." >&2
    status=1
    continue
  fi
  if [ "$dry" = 1 ]; then
    echo "would: git -C $src worktree remove $wt"
    continue
  fi
  if git -C "$src" worktree remove "$wt"; then
    echo "removed: $(basename "$wt")"
    [ -n "$br" ] && [ "$br" != "HEAD" ] && { left_src+=("$src"); left_branch+=("$br"); }
  else
    echo "FAILED to remove $wt" >&2
    status=1
  fi
done

if [ "$dry" = 1 ]; then
  echo "would: rmdir $ws"
  exit 0
fi

[ "$status" = 0 ] || { echo "left $ws in place -- some worktrees survived." >&2; exit 1; }

# Look the space up BEFORE the rmdir, while $ws still exists -- and keep the
# lookup's own success separate from "there is no space", since only the first
# is a reason to say nothing further.
space=""
space_lookup_ok=1
space=$(space_for_cwd "$ws") || space_lookup_ok=0

# rmdir, never rm -rf: it fails loudly if anything unexpected is still in there
# (a stray file, a worktree that was never git's to begin with) instead of
# deleting it silently.
if rmdir "$ws" 2>/dev/null; then
  echo "removed: $ws"
else
  echo "worktrees are gone, but $ws is not empty:"
  ls -A "$ws" | sed 's/^/    /'
  echo "Look at what is left and remove it deliberately."
  exit 1
fi

# The work just landed, so every source repo these worktrees came from is now
# behind its remote -- that is what the landed check proved. This is the one
# moment it is known for certain rather than suspected, and refreshing-a-repo's
# gate would not fire again until somebody next reads that repo and remembers
# to. check-landed.sh has already fetched, so the remote-tracking refs are
# current and this is a local fast-forward.
#
# Only the boring case, the same rule repo-status.sh --pull uses: clean, on the
# default branch, behind and not ahead. Anything else is somebody's judgement
# call -- a parked branch, a dirty tree, a diverged history -- and moving it
# silently here is how work disappears.
refreshed=()
behindstill=()
for src in $(printf '%s\n' "${left_src[@]}" | sort -u); do
  db=$(cd "$src" 2>/dev/null && default_branch)
  [ -n "$db" ] || { behindstill+=("$src (cannot determine default branch)"); continue; }
  cur=$(git -C "$src" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ "$cur" != "$db" ] || [ -n "$(git -C "$src" status --porcelain 2>/dev/null)" ]; then
    behindstill+=("$src (on '$cur'$([ -n "$(git -C "$src" status --porcelain 2>/dev/null)" ] && echo ', not clean'))")
    continue
  fi
  ahead=$(git -C "$src" rev-list --count "origin/$db..HEAD" 2>/dev/null || echo 0)
  behind=$(git -C "$src" rev-list --count "HEAD..origin/$db" 2>/dev/null || echo 0)
  [ "$behind" = "0" ] && continue
  if [ "$ahead" = "0" ] && git -C "$src" merge --ff-only "origin/$db" --quiet 2>/dev/null; then
    refreshed+=("$src ($behind commit(s))")
  else
    behindstill+=("$src ($behind behind, $ahead ahead)")
  fi
done

if [ ${#refreshed[@]} -gt 0 ]; then
  echo
  echo "Refreshed, now that the work has landed:"
  printf '    %s\n' "${refreshed[@]}"
fi
if [ ${#behindstill[@]} -gt 0 ]; then
  echo
  echo "Left alone -- these need a judgement call, see the refreshing-a-repo skill:"
  printf '    %s\n' "${behindstill[@]}"
fi

# Branches outlive their worktrees, and the obvious cleanup runs into the same
# ancestry blind spot the landed check exists to work around: `git branch -d`
# refuses a squash-merged branch as "not fully merged". Print the -D commands
# rather than running them -- the check above is what justifies -D, and a script
# that force-deletes branches on its own is one --force away from doing it
# without that justification.
if [ ${#left_branch[@]} -gt 0 ]; then
  echo
  echo "Branches left behind. The landed check above is what justifies -D here;"
  echo "-d will refuse anything that landed by squash. Run these deliberately:"
  for i in "${!left_branch[@]}"; do
    echo "    git -C ${left_src[$i]} branch -D ${left_branch[$i]}"
  done
fi

# $space was looked up above, before the rmdir, by matching this workspace's
# path against the identity_cwd herdr records for each space. Closing is done by
# that ID and never by label: labels default to the cwd basename and are neither
# unique nor owned by the task, so an unrelated space sharing the name would be
# closed instead, panes and all.
if [ -z "${HERDR_ENV:-}" ] || ! command -v herdr >/dev/null 2>&1; then
  echo
  echo "Not running under herdr. Its space for this workspace, if any, is still open:"
  echo "    herdr workspace list        # find the one rooted at $ws"
  echo "    herdr workspace close <id>"
  exit 0
fi

echo
if [ "$space_lookup_ok" = 0 ]; then
  # The lookup already said on stderr what it could not make sense of. Do not
  # fall back to matching on the label: a wrong guess here closes somebody
  # else's panes, which is worse than leaving a space open.
  echo "Not closing any herdr space -- see above. If one was open for this"
  echo "workspace, close it yourself: herdr workspace list"
elif [ -z "$space" ]; then
  echo "No herdr space was rooted at $ws -- nothing to close."
elif [ "$space" = "${HERDR_WORKSPACE_ID:-}" ]; then
  # Closing the space this shell lives in kills the pane mid-script, taking the
  # rest of the teardown with it. Refuse, and let the user do it from elsewhere.
  echo "The herdr space rooted here ($space) is the one this is running in,"
  echo "so it was left open -- closing it would kill this pane. From another space:"
  echo "    herdr workspace close $space"
elif herdr workspace close "$space" >/dev/null 2>&1; then
  echo "herdr space closed: $space (was rooted at $ws)"
else
  echo "could not close the herdr space; do it by hand:" >&2
  echo "    herdr workspace close $space" >&2
fi
