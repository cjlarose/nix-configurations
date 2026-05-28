# nix-configurations

## Worktree Structure

```
~/worktrees/cjlarose/nix-configurations/default       # main branch
~/worktrees/cjlarose/nix-configurations/<branch>      # feature work
```

## Disabling the Private Nix Cache

If `nixcache.toothyshouse.com` is unavailable, add:

```sh
--option substituters "https://cache.nixos.org"
```
