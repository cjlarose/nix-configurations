---
name: nixos-rebuild
description: Build and switch NixOS configuration for ns1010301 (and its microvm guests) with rollback support
---

# nixos-rebuild

Required for changes to NixOS system config, microvm settings, or nixpkgs version bumps. Run from the **cjlarose** nix-configurations worktree on ns1010301.

This is a **two-step process** — build first, then switch only after the user approves. The guest uses the host's `/nix/store` via virtiofs (no erofs disk image), so builds are fast. The switch restarts the VM.

## Step 1: Build (no disruption to the running VM)

```sh
cd ~/worktrees/cjlarose/nix-configurations/<branch>
sudo nixos-rebuild build --flake .#ns1010301
```

To build with changes from a guest flake input (including unpushed ones), override the input to a local path:

```sh
sudo nixos-rebuild build --flake .#ns1010301 \
  --override-input <input-name> path:<local-path>
```

Run the build as a background task. **After it completes, notify the user and wait for their approval before proceeding to Step 2.** The user may be actively working on the VM and needs to choose when it restarts.

## Step 2: Switch (restarts the VM — requires user approval)

Before switching, record the current system profile so rollback is instant:

```sh
ROLLBACK_PATH="$(readlink -f /nix/var/nix/profiles/system)"
echo "Rollback path: $ROLLBACK_PATH"
```

Then switch:

```sh
cd ~/worktrees/cjlarose/nix-configurations/<branch>
sudo nixos-rebuild switch --flake .#ns1010301
```

(Include the same `--override-input` flags used in Step 1 if applicable.)

## Rollback (if something goes wrong)

```sh
sudo "$ROLLBACK_PATH/bin/switch-to-configuration" switch
```

This instantly reverts the host and restarts the VM with the previous configuration. No rebuild needed.

## Serial console (OVH)

ns1010301 has serial console on **ttyS1** (not ttyS0) at 115200 baud, accessible via OVH IPMI SoL. This is the only recovery path if networking breaks.
