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

    ~/workspaces/<task>/<repo>

A task spanning several repos is one directory, one herdr space, one cwd — that
is the point of the layout. Adding a second repo mid-task needs no
restructuring.

### Naming: prefix with the owner only when the workspace is mixed

Name each worktree directory for the **repo alone**. Nearly every task stays
within one owner, and `picktrace-web-api` next to `picktrace-web-client` next to
`picktrace-internal-operations` is just noise repeated in every path you type.

When a workspace holds repos from **more than one owner**, prefix with the owner
— `<owner>-<repo>` — and prefix **every** worktree in that workspace, not only
the colliding one, so the listing stays uniform:

    ~/workspaces/device-sync-batching/web-api          # single-owner task
    ~/workspaces/device-sync-batching/internal-operations

    ~/workspaces/coder-envbox/picktrace-nix-configurations   # mixed: prefix all
    ~/workspaces/coder-envbox/cjlarose-nix-configurations

The mixed case is usually exactly that one: `picktrace/nix-configurations` and
`cjlarose/nix-configurations` in the same workspace, which collide on the bare
repo name and are the reason the prefix exists at all.

If a task grows a second owner mid-flight, rename the existing worktrees to
match — `git worktree move` from the `~/repos` checkout, so git rewrites its own
bookkeeping instead of leaving a stale `.git` pointer behind.

**Use the `herdr` skill for the mechanics** — creating the space, splitting
panes, starting agents. Do not improvise the commands from memory; the
installed binary is the authority and the skill knows its current syntax.

The skill will not invent topology on its own: by default it starts an agent in
a sibling pane in the *current* tab and cwd. So state the topology explicitly —
**one space per task, rooted at `~/workspaces/<task>`, one linked worktree per
repo, agents as panes in that space.** The worktrees themselves are plain `git
worktree add` from the `~/repos` checkout; herdr is only the multiplexer here.

Tear down when the branches have merged:

    git -C ~/repos/<owner>/<repo> worktree remove ~/workspaces/<task>/<repo>
    rmdir ~/workspaces/<task>

Use `git worktree remove`, not `rm -rf`: it refuses when the tree is dirty, so
teardown doubles as a safety check. Close the herdr space too — nothing prunes
it automatically.

## .claude/worktrees

Fine and **encouraged inside a workspace** — that is how parallel agents on one
task get isolation without cluttering `~/workspaces` with pseudo-tasks.

Forbidden under `~/repos`, per the convention above.
