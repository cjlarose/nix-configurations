#!/usr/bin/env bash
# Decide, per worktree in a workspace, whether its branch has landed and whether
# the worktree is therefore safe to remove.
#
# The whole point of this script is that "has it landed?" is NOT one question
# with one command. Ancestry (merge-base --is-ancestor) answers "is this exact
# commit object reachable from the default branch", which is false for every
# squash-merge, rebase-merge and cherry-pick -- i.e. for most of how work
# actually lands. Asking only that question produces confident false negatives.
# So: run every test, and report the STRONGEST evidence found.
#
# Usage: check-landed.sh [<workspace-dir>]     (default: cwd)
# Exit:  0 all worktrees safe to remove, 1 at least one needs a human, 2 usage.
set -uo pipefail

ws="${1:-$PWD}"
[ -d "$ws" ] || { echo "no such workspace: $ws" >&2; exit 2; }
ws="$(cd "$ws" && pwd)"

# Default branch as this repo understands it. origin/HEAD is a local ref, so
# this needs no network; when it is missing (a clone made with --no-checkout, or
# an older git) fall back to asking the remote, then to the usual names.
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

status=0
found=0

for wt in "$ws"/*/; do
  [ -e "$wt/.git" ] || continue
  found=1
  name="$(basename "$wt")"
  cd "$wt" || continue

  branch=$(git rev-parse --abbrev-ref HEAD)
  echo "=== $name  [$branch]"

  # 1. Uncommitted work outranks every other question: a clean-looking "landed"
  #    verdict on a dirty tree still throws away edits that were never committed
  #    anywhere. git worktree remove refuses this too, but say why first.
  if [ -n "$(git status --porcelain)" ]; then
    echo "    DIRTY -- uncommitted changes or untracked files:"
    git status --short | sed 's/^/      /'
    echo "    VERDICT: NOT SAFE. Commit, stash or discard deliberately first."
    status=1
    continue
  fi

  # Fetch every remote, not just origin: the landed-ness tests below compare
  # against remote refs, and a stale ref answers about the past.
  git fetch --all --quiet 2>/dev/null

  db=$(default_branch)
  if [ -z "$db" ]; then
    echo "    VERDICT: UNKNOWN -- cannot determine the default branch."
    status=1
    continue
  fi
  base="origin/$db"

  # 2. Commits that exist nowhere but this disk. This is the keep/delete test
  #    that matters: not "is it merged" but "would removing this lose anything".
  #    --remotes (all remotes) rather than @{u}, which trusts one possibly-stale
  #    tracking ref and is wrong when no upstream is configured at all.
  local_only=$(git rev-list --count HEAD --not --remotes 2>/dev/null || echo "?")

  # 3. The three landing shapes, strongest first.
  verdict=""
  if git merge-base --is-ancestor HEAD "$base" 2>/dev/null; then
    verdict="LANDED (ancestor of $base -- fast-forward or merge commit)"
  elif git diff --quiet "$base" HEAD 2>/dev/null; then
    # Tree-identical to the default branch: everything this branch did is
    # already there, whatever the commit SHAs say. This is what a squash-merge
    # looks like, and what ancestry misses.
    verdict="LANDED (tree identical to $base -- squash-merged)"
  elif [ -z "$(git cherry "$base" HEAD 2>/dev/null | grep '^+' || true)" ] \
       && [ -n "$(git cherry "$base" HEAD 2>/dev/null || true)" ]; then
    # git cherry compares patch-ids, so it sees cherry-picked and rebased
    # commits that ancestry misses. All '-' means every commit has an
    # equivalent upstream.
    verdict="LANDED (every commit has an equivalent patch on $base -- rebased or cherry-picked)"
  fi

  if [ -n "$verdict" ]; then
    echo "    $verdict"
    # Local-only commits are EXPECTED once the work has landed by squash or
    # rebase: the originals keep their old SHAs and exist on no remote by
    # definition. Treating that as unpushed work would block teardown of
    # precisely the branches the tests above just proved safe, forever. The
    # count is only evidence of loss when nothing landed -- see below.
    [ "$local_only" = "0" ] || \
      echo "    ($local_only pre-landing commit(s) on no remote -- expected for a squash or rebase)"
    echo "    VERDICT: SAFE to remove."
    continue
  fi

  # 4. No test proved it landed. That is NOT proof it did not: a squash-merge
  #    onto a default branch that has since moved on shows up here too. Hand the
  #    evidence over rather than guessing.
  echo "    No landing evidence found. Unmerged commits vs $base:"
  git log --oneline "$base..HEAD" | sed 's/^/      /'
  echo "    Commits on no remote: $local_only"
  echo "    VERDICT: REVIEW BY HAND. Compare these SUBJECTS against $base"
  echo "      (git log --oneline $base | head -50), and check whether the code"
  echo "      they add is already present -- a squash-merge onto a branch that"
  echo "      moved on defeats every automatic test above."
  status=1
done

[ "$found" = 1 ] || { echo "no git worktrees found in $ws" >&2; exit 2; }
exit $status
