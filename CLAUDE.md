# nix-configurations

## Checkout structure

This repo is checked out on hosts using **two different layouts**. The
user-level `~/.claude/CLAUDE.md` states which one a given machine uses; when it
describes `~/repos` and `~/workspaces`, that is the task-keyed layout.

Task-keyed (ns1010301, pt-docker-cjlarose):

```
~/repos/cjlarose/nix-configurations                   # default branch, read only
~/workspaces/<task>/nix-configurations                # feature work
~/workspaces/<task>/cjlarose-nix-configurations       # ...if the workspace also
~/workspaces/<task>/picktrace-nix-configurations      #    holds the picktrace repo
```

Worktree (every other host):

```
~/worktrees/cjlarose/nix-configurations/default       # main branch
~/worktrees/cjlarose/nix-configurations/<branch>      # feature work
```

Under the task-keyed layout the `~/repos` checkout is **read only** — never
commit or create worktrees there. Because its default branch is checked out,
git itself refuses to check that branch out anywhere else, so committing to
`main` from a workspace fails rather than silently succeeding.

## Disabling the Private Nix Cache

If `nixcache.toothyshouse.com` is unavailable, add:

```sh
--option substituters "https://cache.nixos.org"
```
