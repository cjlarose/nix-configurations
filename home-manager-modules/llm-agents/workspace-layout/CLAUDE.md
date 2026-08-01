# Checkout layout

This machine uses a task-keyed layout.

## ~/repos — read only

`~/repos/<owner>/<repo>` is a checkout of that repo's default branch, named for
the **canonical** owner (a fork lives under the upstream owner's name, with
`origin` = the fork and `upstream` = canonical).

**Never edit, commit, or create worktrees here.** Read and grep freely.

Nothing mechanically stops you — this is convention, and you are expected to
keep it. In particular, do not let a worktree be created under `~/repos`:
`.claude/worktrees/` there is litter, and it is invisible to `git status`
because `.claude` is globally ignored. If you need somewhere to write, make a
workspace (below).

Git does enforce one half by itself: because the default branch is checked out
here, no workspace worktree can check it out too, so committing to `main` from
a workspace is impossible rather than merely discouraged.

## ~/workspaces — where work happens

A task gets one directory holding one linked worktree per repo it touches:

    ~/workspaces/<task>/<owner>-<repo>

A task spanning several repos is one directory, one herdr space, one cwd — that
is the point of the layout. Adding a second repo mid-task needs no
restructuring.

**Use the `herdr` skill for the mechanics** — creating the space, splitting
panes, starting agents. Do not improvise the commands from memory; the
installed binary is the authority and the skill knows its current syntax.

The skill will not invent topology on its own: by default it starts an agent in
a sibling pane in the *current* tab and cwd. So state the topology explicitly —
**one space per task, rooted at `~/workspaces/<task>`, one linked worktree per
repo, agents as panes in that space.** The worktrees themselves are plain `git
worktree add` from the `~/repos` checkout; herdr is only the multiplexer here.

Tear down when the branches have merged:

    git -C ~/repos/<owner>/<repo> worktree remove ~/workspaces/<task>/<owner>-<repo>
    rmdir ~/workspaces/<task>

Use `git worktree remove`, not `rm -rf`: it refuses when the tree is dirty, so
teardown doubles as a safety check. Close the herdr space too — nothing prunes
it automatically.

## .claude/worktrees

Fine and **encouraged inside a workspace** — that is how parallel agents on one
task get isolation without cluttering `~/workspaces` with pseudo-tasks.

Forbidden under `~/repos`, per the convention above.
