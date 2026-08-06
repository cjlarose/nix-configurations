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
    *) ws="$1" ;;
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

# Remove through git, from each worktree's own source repo, so git prunes its
# administrative files instead of being left pointing at a path that is gone.
# It also refuses a dirty tree, which makes teardown double as a last check.
status=0
declare -a left_src left_branch
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

echo
echo "The herdr space for this task is still open -- nothing prunes it. Close it too."
