---
name: nixos-rebuild
description: Build and switch NixOS configuration for ns1010301 (and its microvm guests) with rollback support
---

# nixos-rebuild

Required for changes to NixOS system config, microvm settings, or nixpkgs version bumps. Run from the **cjlarose** nix-configurations worktree on ns1010301.

Switching the host config does **not** restart microvms — it only activates host-level changes. The switch output will list which microvm units changed but were not restarted (e.g. `NOT restarting the following changed units: microvm@media.service`).

## Build and switch

Record the rollback path, then build and switch in one step:

```sh
cd ~/worktrees/cjlarose/nix-configurations/<branch>
ROLLBACK_PATH="$(readlink -f /nix/var/nix/profiles/system)"
sudo nixos-rebuild switch --flake .#ns1010301
```

To build with changes from a guest flake input (including unpushed ones), override the input to a local path:

```sh
sudo nixos-rebuild switch --flake .#ns1010301 \
  --override-input <input-name> path:<local-path>
```

## After switching

If the switch output lists microvm units that changed but were not restarted, **ask the user** whether they want to restart those microvms. Do not restart them automatically — the user may be actively working on them.

To restart a microvm:

```sh
sudo systemctl restart microvm@<name>.service
```

## Rollback (if something goes wrong)

```sh
sudo "$ROLLBACK_PATH/bin/switch-to-configuration" switch
```

This instantly reverts the host configuration. No rebuild needed.

## Serial console (OVH)

ns1010301 has serial console on **ttyS1** (not ttyS0) at 115200 baud, accessible via OVH IPMI SoL. This is the only recovery path if networking breaks.
