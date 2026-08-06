# Repo layout

This machine uses a task-keyed layout. Git's own vocabulary maps onto it
exactly: `~/repos` holds each repository's **main worktree**, `~/workspaces`
holds **linked worktrees** of those same repositories.

The rules are here. The mechanics — commands, decision trees, scripts — are in
the skills named at each gate below; reach for them there rather than
improvising.

## ~/repos — read only

`~/repos/<owner>/<repo>` sits on that repo's default branch, named for the
**canonical** owner (a fork lives under the upstream owner's name, with `origin`
= the fork and `upstream` = canonical).

**Never edit, commit, or create worktrees here.** Read and grep freely.

Nothing mechanically stops you — this is convention, and you are expected to
keep it. In particular, do not let a worktree be created under `~/repos`:
`.claude/worktrees/` there is litter, and it is invisible to `git status`
because `.claude` is globally ignored. If you need somewhere to write, make a
workspace (below).

Git does enforce one half by itself: because the default branch is checked out
here, no workspace worktree can check it out too, so committing to `main` from
a workspace is impossible rather than merely discouraged.

### Confirm a repo is current before you read it

"Read and grep freely" assumes what is on disk is what is on the remote. Before
exploring a repo here, confirm all three: working tree clean, on the repo's
default branch, `git pull`ed so it matches the remote. Once per repo per
session, before the first read — not after you have already formed an opinion
from it.

The check is unconditional because nothing about a stale repo looks wrong. A
branch left over from a hurried debugging session, or a `main` last pulled three
weeks ago, greps exactly as convincingly as a current one — so the answer you
give is confidently wrong about the current state of the code, and neither you
nor the person reading it has any signal that it was. There is nothing to
suspect, so a check that fires on suspicion never fires.

**Use the `refreshing-a-repo` skill**, which also covers what to do when a repo
is dirty, parked on someone's branch, or diverged. None of that is yours to
clean up silently.

## ~/workspaces — where work happens

A task gets one directory holding one linked worktree per repo it touches:

    ~/workspaces/<task>/<repo>

A task spanning several repos is one directory, one herdr space, one cwd — that
is the point of the layout. Adding a second repo mid-task needs no
restructuring.

**Use the `starting-a-workspace` skill** to create one, and the
`adding-a-repo-to-a-workspace` skill when a task grows another repo mid-flight.

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
match, via `git worktree move` so git rewrites its own bookkeeping instead of
being left pointing at a path that is gone.

### The branch starts where the main worktree is

`git worktree add` branches from whatever `~/repos/<owner>/<repo>` currently
has, so pull it first. Pulling before the branch exists costs nothing; pulling
after it has commits on it costs a rebase, or a review against the wrong base.

### herdr

**Use the `herdr` skill for the mechanics** — creating the space, splitting
panes, starting agents. Do not improvise the commands from memory; the installed
binary is the authority and the skill knows its current syntax.

It will not invent topology on its own: by default it starts an agent in a
sibling pane in the *current* tab and cwd. So state the topology explicitly —
**one space per task, one linked worktree per repo, agents as panes in that
space.**

**The space's cwd is `~/workspaces/<task>` itself, never a worktree inside it —
including when the task has only one repo.** A space is bound to its cwd at
creation time rather than continuously, so a space rooted one level too deep is
not something you can cd your way out of; it has to be recreated. The
single-worktree case is where the temptation lives, and it is exactly the case
that changes: a task that grows a second owner has every worktree renamed
underneath it, moving the directory such a space was pointed at.

### Tearing down

Tear down when the work has landed — and "landed" is not what `git branch
--merged` says. Ancestry misses every squash-merge, rebase and cherry-pick, so
it reports shipped branches as unmerged and invites you to keep or delete the
wrong ones. **Use the `tearing-down-a-workspace` skill**, which runs the tests
that catch those.

Removal itself goes through `git worktree remove`, never `rm -rf`: it refuses
when the tree is dirty, so teardown doubles as a safety check. Close the herdr
space too — nothing prunes it automatically.

## .claude/worktrees

Fine and **encouraged inside a workspace** — that is how parallel agents on one
task get isolation without cluttering `~/workspaces` with pseudo-tasks.

Forbidden under `~/repos`, per the convention above.
