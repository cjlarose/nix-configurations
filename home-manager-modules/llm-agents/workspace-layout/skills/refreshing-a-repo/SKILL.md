---
name: refreshing-a-repo
description: Use when about to read, grep, explore or answer a question from a repo under ~/repos, or branch from one — before the first read, not after. Also use when a repo there is dirty, parked on a non-default branch, behind origin, or of unknown freshness.
---

# Refreshing a repo

`~/repos/<owner>/<repo>` is only worth reading if it still matches the remote.
Confirm that before the first read, not after forming an opinion.

**Trustworthy = all three:** working tree clean, on the repo's default branch,
level with `origin/<default>`.

## Why this is unconditional

Nothing about a stale repo looks wrong. A branch left over from a hurried
debugging session, or a `main` last pulled three weeks ago, greps exactly as
convincingly as a current one. The answer you give is confidently wrong about
the current state of the code, and neither you nor the person reading it gets
any signal. There is nothing to suspect, so a check that fires on suspicion
never fires.

Once per repo per session, before the first read.

## Check

```
scripts/repo-status.sh <owner>/<repo>     # one repo
scripts/repo-status.sh                    # everything under ~/repos
scripts/repo-status.sh --pull <owner>/<repo>
```

Exit 0 means trustworthy. `--pull` fast-forwards **only** the unambiguous case:
clean, on the default branch, behind and not ahead.

## When it is not trustworthy

Everything below is somebody's work. None of it is yours to discard.

| State | Do |
|---|---|
| Behind, otherwise clean | `--pull`, then proceed |
| Untracked or modified files | Report what is there and ask. Do not clean, checkout or reset |
| On a non-default branch | Check `git rev-list --count HEAD --not --remotes` first. Non-zero means commits exist nowhere else — ask before moving |
| Diverged from origin | Ask. Do not force, reset or rebase a repo you are only reading |
| Fetch failed | Say so. Answer with the stale state named as stale, or not at all |

**Never `git stash` here.** `refs/stash` is a single global stack shared by
every worktree of the repo, and `pop` is positional — stashing to "get a clean
tree" can silently collide with work parked from another worktree.

## If you must read it anyway

Sometimes the user says go ahead. Then say which state you read: "answering
from `acme/widget` as of 3 weeks ago, on branch `debug-parked`". A stale answer
labelled stale is useful; a stale answer labelled nothing is a trap.

## Common mistakes

- Reading first, checking later. The check is a gate, not a footnote.
- Treating "no output from `git status`" as sufficient — clean says nothing
  about which branch you are on or how far behind it is.
- Cleaning up someone's parked branch on the way past.
- Doing this in a `~/workspaces` worktree. Wrong skill: those are supposed to
  be dirty and on a feature branch.
