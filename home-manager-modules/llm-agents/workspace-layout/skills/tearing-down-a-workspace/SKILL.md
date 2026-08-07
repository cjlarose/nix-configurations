---
name: tearing-down-a-workspace
description: Use when a task is finished, abandoned or merged and its ~/workspaces/<task>/ directory should go away — and whenever deciding whether a branch has already landed, whether a worktree still holds unpushed work, or whether a workspace is safe to delete.
---

# Tearing down a workspace

Remove the worktrees through git, from each source repo, then the directory.
The hard part is not removal — it is knowing the work actually landed.

## Ancestry does not answer "did it land"

`git merge-base --is-ancestor` and `git branch --merged` answer *"is this exact
commit object reachable"*. That is false for every squash-merge, rebase-merge
and cherry-pick — i.e. for most of how work actually lands. Asking only that
question produces confident false negatives: an audit of 18 worktrees called
three already-shipped branches unmerged.

There are four tests, and you want the strongest evidence any of them finds:

| Test | Catches |
|---|---|
| `merge-base --is-ancestor HEAD origin/main` | fast-forward and merge commits |
| `git diff --quiet origin/main HEAD` (tree-identical) | **squash merges** |
| `git cherry origin/main HEAD` (patch-ids, all `-`) | rebases and cherry-picks |
| subjects and content compared by hand | a squash onto a branch that moved on |

## Do it

```
scripts/check-landed.sh <workspace>       # verdict per worktree, changes nothing
scripts/remove-workspace.sh --dry-run <workspace>
scripts/remove-workspace.sh <workspace>
```

`remove-workspace.sh` runs the check first and refuses anything not SAFE.
`--force` skips the check: that is a decision that the work is disposable, not a
retry.

## Reading the verdicts

- **SAFE** — landed by one of the tests above. Pre-landing commits that exist on
  no remote are *expected* after a squash or rebase; they are not lost work.
- **DIRTY** — uncommitted or untracked files. Resolve deliberately; never
  `git stash` (`refs/stash` is one global stack shared across worktrees).
- **REVIEW BY HAND** — no test proved it landed. That is **not** proof it did
  not. Compare subjects against the default branch and check whether the code it
  adds is already there, then decide.

## Removal rules

- `git worktree remove`, never `rm -rf` — git prunes its own admin files, and it
  refuses a worktree with modified or untracked files. It does **not** refuse
  IGNORED ones, which is why `check-landed.sh` looks for nested worktrees
  separately: `.claude/worktrees/` is ignored, so a worktree containing one
  reads as perfectly clean and would be deleted wholesale.
- Run it from the worktree's source repo under `~/repos`.
- `rmdir` the workspace, so leftovers surface instead of being deleted silently.
- The herdr space is closed for you — `remove-workspace.sh` finds the space
  whose `identity_cwd` is this workspace and closes that one by ID, never a
  space matched by label. If it cannot read herdr's session file, or the format
  is not what it expects, it says so and closes nothing. Nothing prunes it
  otherwise.

One case it will not do for you: if the space being torn down is the one the
script is *running in*, it says so and leaves it open, because closing it kills
the pane mid-teardown. Move to another space and close it by hand.

## The source repos are now behind

Work landing is exactly what makes `~/repos/<owner>/<repo>` stale, and teardown
is the one moment that is *known* rather than suspected — the landed verdict is
the evidence. `remove-workspace.sh` therefore fast-forwards each source repo it
removed a worktree from, and reports which.

Only the boring case: clean, on its default branch, behind and not ahead. A
parked branch, a dirty tree or a diverged history is somebody's judgement call
and is listed as left alone — see **refreshing-a-repo**.

## The branch outlives the worktree

Removing a worktree leaves its branch behind. Deleting that branch runs into the
same blind spot one step later: `git branch -d` uses ancestry, so on a
squash-merged branch it fails with **"the branch 'x' is not fully merged"** even
though every line of it is on `origin/main`.

`-D` is the correct answer *once check-landed.sh has said SAFE* — the check is
the evidence `-d` cannot see. Reaching for `-D` because `-d` complained, without
that evidence, is how unlanded work disappears. (Both refuse while the worktree
still exists, so remove it first.)

## Common mistakes

- Declaring a branch unmerged from `git branch --merged` alone.
- Treating post-squash local-only commits as unpushed work and refusing forever.
- Checking against a stale tracking ref — fetch **every** remote first;
  `@{u}..HEAD` trusts one possibly-stale ref and is meaningless with no upstream.
- Deleting the directory while the herdr space still has panes cwd'd into it.
