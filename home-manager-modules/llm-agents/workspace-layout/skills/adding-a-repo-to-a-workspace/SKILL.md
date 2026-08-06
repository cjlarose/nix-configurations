---
name: adding-a-repo-to-a-workspace
description: Use when work already under way in a ~/workspaces/<task>/ directory turns out to need another repo — a second service, a shared library, a config repo — especially when the new repo belongs to a different owner than the worktrees already there.
---

# Adding a repo to a workspace

A task spanning several repos stays one directory, one herdr space, one cwd.
Adding a repo needs no restructuring — except for the name.

## The rename cascade

If the new repo introduces a **second owner**, every worktree in the workspace
gets an `<owner>-<repo>` prefix, not just the new one. Uniform listing is the
whole point of the rule.

Renames go through `git worktree move`, run from each worktree's own source
repo, so git rewrites its own bookkeeping. Moving directories by hand leaves
git pointing at paths that no longer exist — and it will not notice until
something else fails confusingly later.

## Do it

```
scripts/add-repo.sh --dry-run <task> <owner>/<repo>
scripts/add-repo.sh [--branch <name>] <task> <owner>/<repo>
```

Dry-run first when a rename is involved: it prints every move before any
happens. The script renames before adding, so a failure leaves a workspace with
consistent names rather than a half-converted one.

Branch defaults to the task name; an existing branch of that name is checked out
rather than recreated, which is usually what you want when the other worktrees
are already on it.

## After a rename

The herdr space and any open panes still point at the old paths. Nothing
updates them for you — fix them, or they will write to directories that are
gone. Use the **herdr** skill for the commands.

## Common mistakes

- Prefixing only the new worktree. The rule is all-or-nothing.
- `mv` instead of `git worktree move`.
- Cloning the second repo into the workspace instead of adding a worktree from
  its `~/repos` repo.
- Starting over with a new workspace because the name no longer fits. Rename;
  the branches and their history are fine where they are.
