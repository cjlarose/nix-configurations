#!/usr/bin/env bash
# Report whether a repo under ~/repos can be trusted to answer questions about the
# current state of the code, and optionally bring it up to date.
#
# Trustworthy means all three of: working tree clean, on the repo's default
# branch, and level with the remote. A repo failing any of these reads
# exactly as convincingly as one that passes -- which is why this is a script
# and not a habit.
#
# Usage: repo-status.sh [--pull] [<owner>/<repo> | <path>]...
#        no arguments      -> every repo under ~/repos
#        --pull            -> fast-forward when it is safe and unambiguous
# Exit:  0 every repo named is trustworthy, 1 at least one is not, 2 usage.
set -uo pipefail

REPOS_ROOT="${REPOS_ROOT:-$HOME/repos}"
pull=0
targets=()

for arg in "$@"; do
  case "$arg" in
    --pull) pull=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    */*) [ -d "$arg" ] && targets+=("$arg") || targets+=("$REPOS_ROOT/$arg") ;;
    *) targets+=("$arg") ;;
  esac
done

if [ ${#targets[@]} -eq 0 ]; then
  while IFS= read -r d; do targets+=("$(dirname "$d")"); done \
    < <(find "$REPOS_ROOT" -mindepth 3 -maxdepth 3 -name .git 2>/dev/null | sort)
fi

# See check-landed.sh for why this is duplicated rather than shared: each skill
# directory is installed as a self-contained unit, and a script that reaches
# into a sibling skill breaks the moment that skill is not installed.
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

status=0

for repo in "${targets[@]}"; do
  name="${repo#"$REPOS_ROOT"/}"
  if [ ! -d "$repo/.git" ]; then
    echo "=== $name"
    echo "    NOT A CHECKOUT: $repo"
    status=1
    continue
  fi
  cd "$repo" || continue

  echo "=== $name"
  problems=()
  # Reset per repo: these are read below through ${x:-0}, which only defends
  # against being UNSET. Left over from the previous iteration they are set, and
  # a repo with no origin/<default> would be judged on its predecessor's counts.
  ahead=0
  behind=0
  fetch_ok=1

  git fetch --all --quiet 2>/dev/null \
    || { fetch_ok=0; problems+=("fetch failed -- remote state unknown, everything below describes a possibly-stale ref"); }

  db=$(default_branch)
  branch=$(git rev-parse --abbrev-ref HEAD)

  # Dirty. Note untracked files count: a stray scratch file is not dangerous to
  # read past, but it means somebody was working here, which makes the branch
  # and the commit worth a second look.
  if [ -n "$(git status --porcelain)" ]; then
    problems+=("working tree not clean")
    git status --short | sed 's/^/      /'
  fi

  # Parked on the wrong branch.
  if [ -n "$db" ] && [ "$branch" != "$db" ]; then
    problems+=("on '$branch', not the default branch '$db'")
    local_only=$(git rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)
    [ "$local_only" = "0" ] || \
      problems+=("'$branch' has $local_only commit(s) that exist on no remote -- do not discard it")
  fi

  # Behind, or diverged.
  if [ -n "$db" ] && git show-ref --quiet "refs/remotes/origin/$db"; then
    behind=$(git rev-list --count "HEAD..origin/$db" 2>/dev/null || echo 0)
    ahead=$(git rev-list --count "origin/$db..HEAD" 2>/dev/null || echo 0)
    [ "$behind" = "0" ] || problems+=("$behind commit(s) behind origin/$db")
    [ "$ahead" = "0" ] || problems+=("$ahead commit(s) ahead of origin/$db")
  else
    problems+=("no origin/$db to compare against")
  fi

  if [ ${#problems[@]} -eq 0 ]; then
    echo "    TRUSTWORTHY: clean, on $db, level with origin/$db."
    continue
  fi

  for p in "${problems[@]}"; do echo "    - $p"; done

  # Only the boring case is automated. Anything needing a judgement call --
  # whose work is this, does it matter, may it be thrown away -- is the user's,
  # and doing it silently here is how work disappears.
  #
  # fetch_ok gates the whole thing. Fast-forwarding to a ref the fetch failed to
  # update moves onto a stale commit and then reports it as current, which is
  # the precise false confidence this script exists to prevent -- worse than
  # doing nothing, because it looks like it worked.
  if [ "$pull" = 1 ] && [ "$fetch_ok" = 1 ] \
     && [ -z "$(git status --porcelain)" ] \
     && [ "$branch" = "$db" ] \
     && [ "$ahead" = "0" ] && [ "$behind" != "0" ]; then
    if git merge --ff-only "origin/$db" --quiet 2>/dev/null; then
      echo "    PULLED: fast-forwarded to origin/$db. Now trustworthy."
      continue
    fi
    echo "    could not fast-forward"
  elif [ "$pull" = 1 ] && [ "$fetch_ok" = 0 ]; then
    echo "    NOT pulling: the fetch failed, so origin/$db is whatever was last"
    echo "    seen. Fix the network or the remote and run this again."
  fi

  echo "    NOT TRUSTWORTHY -- do not answer questions from this repo yet."
  status=1
done

exit $status
