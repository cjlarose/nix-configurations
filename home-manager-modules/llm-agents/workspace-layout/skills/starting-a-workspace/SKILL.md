---
name: starting-a-workspace
description: Use when work is about to begin on a task and no ~/workspaces/<task>/ directory exists yet — before the first edit to any repo, or when asked to start work on an issue, set up a workspace, or branch a repo for a change.
---

# Starting a workspace

A task gets one directory holding one linked worktree per repo it touches:
`~/workspaces/<task>/<repo>`. Never edit under `~/repos`.

## Settle the name first

The script cannot see your naming rules — read them in your CLAUDE.md before
running it. On some hosts a task with no issue key is a **stop and ask**, not a
free choice.

Two rules the script does apply:

- One owner → name each worktree for the repo alone (`web-api`).
- More than one owner → prefix **every** worktree `<owner>-<repo>`, not just the
  colliding one, so the listing stays uniform.

## Create it

```
scripts/new-workspace.sh --dry-run <task> <owner>/<repo>...
scripts/new-workspace.sh [--branch <name>] <task> <owner>/<repo>...
```

Branch defaults to the task name. The script refreshes each source repo before
branching and refuses the whole workspace if any repo is dirty, parked on a
non-default branch, already has the branch, or is listed twice — the checks it
can make up front, it makes before creating anything. A `worktree add` that
fails partway still leaves what came before it, and says so.

If it refuses on repo state, use the **refreshing-a-repo** skill; that is a
decision about someone's work, not a retry.

## The herdr space

`new-workspace.sh` creates it — no separate step, and nothing to look up:

```
herdr workspace create --cwd ~/workspaces/<task> --label <task> --no-focus
```

**The cwd is `~/workspaces/<task>` itself, never a worktree inside it**, even
when the task has one repo. A space is bound to its cwd at creation time, so one
rooted a level too deep cannot be fixed by cd'ing later — it has to be
recreated. The single-repo case is both the tempting one and the fragile one:
adding a second owner renames every worktree underneath, moving the directory
such a space pointed at.

The label is set explicitly so the sidebar shows the task rather than whatever
the cwd basename happens to be; it is *not* how teardown finds the space again.
That lookup goes through the `identity_cwd` herdr records per space, since
labels are neither unique nor owned by the task. The script skips creation if a
space is already rooted at this directory, and prints the command instead of
running it when you are not inside herdr.

Panes are still yours to place: **use the `herdr` skill** for pane and agent
commands. Only the space itself is handled here.

## Why pull before `git worktree add`

`worktree add` branches from whatever the source repo currently has. Pulling
first is free; pulling afterwards is a rebase, or a review against the wrong
base.

## Common mistakes

- Creating the directory by hand and adding worktrees later — the naming
  decision depends on the full repo list, and mixed-owner is decided up front.
- Adding a repo to a workspace that already exists. Different skill:
  **adding-a-repo-to-a-workspace**, which handles the rename cascade.
- Creating a worktree under `~/repos`, including `.claude/worktrees/` there.
  Inside a workspace `.claude/worktrees/` is fine and encouraged.
- Naming a workspace before establishing whether the task has an issue key.
