---
name: nixos-rebuild
description: Use when applying any nix-configurations change to ns1010301 — host system, microvm system, or per-user home-manager — including without restarting affected guests
---

# nixos-rebuild

Apply nix-configurations changes to ns1010301 and its microvm guests. Run from the **cjlarose** nix-configurations worktree on the host.

Switching the host config does **not** restart microvms — it only activates host-level changes. The switch output lists changed-but-not-restarted guest units. For each, the user picks how to bring it up to parity: full system switch in-place, home-manager switch only, restart, or skip. The first two avoid downtime because the guest's `/nix/store` is a virtiofs share — closure files are already on disk; only the guest's nix DB needs to learn about them.

> **Reference knowledge for this skill lives in the LLM wiki** — query it (`wiki-query`; the index is injected at session start) for the why behind these mechanics:
> - **`[[Microvm No-Downtime Activation]]`** — why a host switch doesn't restart guests, and the `nix-store --dump-db`/`--load-db` closure-sync recipe (Steps 3–4) including the CRLF-corruption-via-`sudo`-pty gotcha.
> - **`[[Private Flake Inputs and nixos-rebuild as Root]]`** — the full treatment of the git+ssh-input-as-root problem and every fix (see Step 1).
> - **`[[NixOS Host Upgrade Process]]`** — the version-bump runbook this skill is the everyday subset of.

## Step 1: rebuild the host

```sh
cd ~/worktrees/cjlarose/nix-configurations/<branch>
ROLLBACK_PATH="$(readlink -f /nix/var/nix/profiles/system)"
sudo nixos-rebuild switch --flake .#ns1010301
```

**Private `git+ssh` inputs that root can't fetch.** `sudo nixos-rebuild` re-evaluates the flake **as root**, which lacks the deploy key / `known_hosts` for private inputs (e.g. `picktrace-nix-configurations`, `cjlarose-llm-wiki`, the transitive `picktrace/cjlarose-llm-wiki`). For an **already-locked** input, pre-building as the user first is enough — root reuses the realized store path:

```sh
nix build .#nixosConfigurations.ns1010301.config.system.build.toplevel --no-link
sudo nixos-rebuild switch --flake .#ns1010301
```

For a **brand-new** private input root has never evaluated, the pre-build does **not** help (root still re-fetches the *input* at eval time). Two routes — full detail and trade-offs in `[[Private Flake Inputs and nixos-rebuild as Root]]`:

- **Simplest — skip root eval entirely:** build the toplevel as the user, then activate without `nixos-rebuild`:
  ```sh
  TOP=$(nix build .#nixosConfigurations.ns1010301.config.system.build.toplevel --no-link --print-out-paths)
  sudo nix-env -p /nix/var/nix/profiles/system --set "$TOP"
  sudo "$TOP/bin/switch-to-configuration" switch
  ```
- **Or override the private input(s)** so root never fetches them. When **several** private inputs are present, overriding one busts the eval cache and forces root to re-fetch the *others* too — so override them all. Point each at its worktree **only if that worktree is at the locked rev** (content-identical); otherwise point at the already-fetched in-store source (`nix flake archive --json` → its `…-source` path) to stay content-identical without disturbing the worktree:
  ```sh
  sudo nixos-rebuild switch --flake .#ns1010301 \
    --override-input cjlarose-llm-wiki path:/nix/store/<hash>-source \
    --override-input picktrace-nix-configurations/cjlarose-llm-wiki path:/nix/store/<hash>-source
  ```

To build with unpushed changes in a guest flake, override its input to a local path the same way (`--override-input <input-name> path:<local-path>`).

## Step 2: handle changed-but-not-restarted microvms

The switch output ends with something like:

```
NOT restarting the following changed units: microvm@pt-docker-cjlarose.service, microvm@media.service
```

For each listed VM, **ask the user** which mode to apply. Do not act automatically — the user may be working in the guest.

- **system switch in-place** — activate the new NixOS config inside the running guest (matches a guest-side `nixos-rebuild switch`). Use when the change touched the guest's system config.
- **home-manager switch** — activate only a user's HM profile. Use when the change is HM-only (packages, dotfiles, shell, Claude config).
- **restart unit** — `sudo systemctl restart microvm@<name>.service`. Brief downtime; cleanest.
- **skip** — leave it. The change takes effect on next restart.

## Step 3: sync the closure into the guest's nix DB

Find the path to register:

- **system switch:** the new VM wrapper lives at `/var/lib/microvms/<name>/current`. Its `bin/microvm-run` encodes the new toplevel:
  ```sh
  CLOSURE_ROOT=/var/lib/microvms/<name>/current
  TOPLEVEL=$(sed -nE 's|.*init=(/nix/store/[^ ]+)/init.*|\1|p' \
    "$CLOSURE_ROOT/bin/microvm-run" | head -1)
  ```
- **home-manager switch:** build the activation package from the guest's own flake:
  ```sh
  CLOSURE_ROOT=$(nix build <flake-ref>#homeConfigurations.'"<user>@<vm>"'.activationPackage \
    --no-link --print-out-paths)
  ```

Then dump-db on the host, transfer, load-db on the guest. **Do not pipe `nix-store --dump-db` straight through nested SSH/sudo** — the binary format gets corrupted (CRLF or buffering through `sudo`'s pty), and `--load-db` fails with messages like `name 'foo\n' contains illegal character '\n'`. Stage via a tempfile:

```sh
DUMP=$(mktemp /tmp/nix-db-dump.XXXXXX)
nix-store --dump-db $(nix-store -qR "$CLOSURE_ROOT") > "$DUMP"
scp -q "$DUMP" <user>@<vm>:"$DUMP"
ssh <user>@<vm> "sudo nix-store --load-db < $DUMP && rm $DUMP"
rm "$DUMP"
```

DB metadata is small (~450 KB for a full ~1000-path system closure) versus hundreds of MB if you `--export | --import` the NAR stream.

## Step 4: activate inside the guest

**System switch:**

```sh
ssh <user>@<vm> "sudo $TOPLEVEL/bin/switch-to-configuration switch"
```

The warning `do not know how to make this configuration bootable; please enable a boot loader` is normal — the host's qemu wrapper owns the boot path. Only `/run/current-system` is updated; microvms have no `/nix/var/nix/profiles/system` to register against.

**Home-manager switch:**

```sh
ssh <user>@<vm> "$CLOSURE_ROOT/activate"
```

New/untracked source files must be `git add`ed first (nix won't see them otherwise); they don't need to be committed.

## Rollback

Host config:

```sh
sudo "$ROLLBACK_PATH/bin/switch-to-configuration" switch
```

Guest: either restart its microvm unit (returns to the host's current spec) or re-run a system switch with the previous closure path.

## Serial console (OVH)

ns1010301 has serial console on **ttyS1** (not ttyS0) at 115200 baud, via OVH IPMI SoL. This is the only recovery path if networking breaks.
