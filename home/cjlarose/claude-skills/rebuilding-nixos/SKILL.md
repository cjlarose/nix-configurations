---
name: rebuilding-nixos
description: Use when applying any nix-configurations change to ns1010301 — host system, microvm system, or per-user home-manager — including without restarting affected guests
---

# rebuilding-nixos

Apply nix-configurations changes to ns1010301 and its microvm guests. Run from the **cjlarose** nix-configurations worktree on the host.

> **Scope — this skill is ns1010301 only.** The standalone push-deploy hosts (`bots`, `cache`, `dns`, `splitpro` — all Proxmox VMs on `pve`) are **separate machines** with their own `/nix/var/nix/profiles/system`, not ns1010301 microvm guests; there is no `microvm@<host>` unit for them and they don't appear under `/var/lib/microvms/`. Running `sudo nixos-rebuild`/host `switch` here does **nothing** for those hosts — it just deploys unrelated pending ns1010301 changes. Deploy them via the push-deploy pattern (`nix build` here → `nix copy --no-check-sigs` to the host FQDN → `nix-env --set` + `switch-to-configuration switch` on the target); query `wiki:querying-notes` for `[[Push-Deploy NixOS Closures from a Strong Host]]`.

Switching the host config does **not** restart microvms — it only activates host-level changes. The switch output lists changed-but-not-restarted guest units. For each, the user picks how to bring it up to parity: full system switch in-place, home-manager switch only, restart, or skip. The first two avoid downtime because the guest's `/nix/store` is a virtiofs share — closure files are already on disk; only the guest's nix DB needs to learn about them.

> **Reference knowledge for this skill lives in the LLM wiki** — query it (`wiki:querying-notes`; the index is injected at session start) for the why behind these mechanics:
> - **`[[Microvm No-Downtime Activation]]`** — why a host switch doesn't restart guests, and the `nix-store --dump-db`/`--load-db` closure-sync recipe (Steps 3–4) including the CRLF-corruption-via-`sudo`-pty gotcha.
> - **`[[Private Flake Inputs and nixos-rebuild as Root]]`** — the full treatment of the git+ssh-input-as-root problem and every fix (see Step 1).
> - **`[[NixOS Host Upgrade Process]]`** — the version-bump runbook this skill is the everyday subset of.

## Step 1: rebuild the host

```sh
cd ~/workspaces/<task>/<repo>          # e.g. ~/workspaces/claude-fullscreen-tui/cjlarose-nix-configurations
ROLLBACK_PATH="$(readlink -f /nix/var/nix/profiles/system)"
sudo nixos-rebuild switch --flake .#ns1010301
```

(ns1010301 uses the task-keyed layout: writable worktrees live under `~/workspaces/<task>/`, never `~/repos`. Query `wiki:querying-notes` for `[[Task-Keyed Repos and Workspaces Layout]]`.)

**Private `git+ssh` inputs that root can't fetch.** `sudo nixos-rebuild` re-evaluates the flake **as root**, which lacks the deploy key / `known_hosts` for private inputs (e.g. `picktrace-nix-configurations`, `cjlarose-llm-wiki`, the transitive `picktrace/cjlarose-llm-wiki`). For an **already-locked** input **whose lock has not moved**, pre-building as the user first is enough — root reuses the realized store path:

```sh
nix build .#nixosConfigurations.ns1010301.config.system.build.toplevel --no-link
sudo nixos-rebuild switch --flake .#ns1010301
```

The pre-build does **not** help for a **brand-new** private input root has never evaluated — and, confirmed 2026-08-03, it also does not help **whenever the lock changed at all**: any `flake.lock` bump busts root's eval cache, and a nested private input reached through the newly-bumped source is new *from root's point of view*. Treat "the lock moved" as equivalent to "the input is new". In practice on ns1010301, **start from the skip-root-eval route** rather than trying `sudo nixos-rebuild` first. Two routes — full detail and trade-offs in `[[Private Flake Inputs and nixos-rebuild as Root]]`:

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

**First, diff the closure — do not assume a small change means a small activation.** Guests are often booted well behind `main`, so an in-place switch reconciles *all* accumulated drift at once (restarting unrelated services). Get the pending toplevel as in Step 3, then:

```sh
nix store diff-closures "$(readlink -f /var/lib/microvms/<name>/booted)" "$TOPLEVEL" 2>/dev/null \
  || ssh <user>@<ip> "nix store diff-closures /run/current-system $TOPLEVEL"
```

Show the user the result before they choose. (2026-08-03: a one-line wrapper change staged all four guests; pt-docker's diff included `claude-code 2.1.172 → 2.1.220`, `bash 5.2 → 5.3p15`, `binutils` and `fzf` added.)

- **system switch in-place** — activate the new NixOS config inside the running guest (matches a guest-side `nixos-rebuild switch`). Use when the change touched the guest's system config.
- **home-manager switch** — activate only a user's HM profile. Use when the change is HM-only (packages, dotfiles, shell, Claude config).
- **restart unit** — `sudo systemctl restart microvm@<name>.service`. Brief downtime; cleanest.
- **skip** — leave it. The change takes effect on next restart.

## Step 3: sync the closure into the guest's nix DB

> **`<user>@<vm>` below means `<user>@<ip>` — guests have NO name resolution.** There is no
> `/etc/hosts` entry, no `~/.ssh/config` block, and no DNS for them; `ssh picktrace@pt-docker-cjlarose`
> fails with `Could not resolve hostname`. They are reachable only by IP on the host's `microvm`
> bridge (`10.0.0.1/24`), and the SSH **user differs per guest**:
>
> | Guest | Address |
> |---|---|
> | `pt-docker-cjlarose` | `picktrace@10.0.0.2` |
> | `minecraft-mellowcatfe` | `cjlarose@10.0.0.3` |
> | `media` | `cjlarose@10.0.0.4` |
> | `hermes` | `cjlarose@10.0.0.5` |
>
> A guest with an `intranetHosts` entry is *also* reachable by that name over the tailnet —
> `picktrace@pt-docker.cjlarose.dev` works — but its **microvm name never resolves**. The bridge
> IP is the route that doesn't depend on Tailscale being up.
>
> Resolve it yourself if the table looks stale: `ip neigh show dev microvm` lists live guest IPs,
> and `ssh -o ConnectTimeout=3 -o BatchMode=yes cjlarose@<ip> hostname` maps IP → name. The
> addresses are also in each `nixos-configurations/<guest>/configuration.nix` (`Address =`) and in
> the port-forward `destination =` entries in `nixos-configurations/ns1010301/configuration.nix`.

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

  > **This form does not exist for `pt-docker-cjlarose`** (confirmed 2026-08-03).
  > `nix eval .#homeConfigurations --apply builtins.attrNames` there lists only
  > `["coder-envbox","coder-x86_64-linux-hm-state-version-24.11"]` — the guest's
  > home-manager lives **inside its NixOS config**, not as a standalone
  > `homeConfigurations` output. Reach it through `nixosConfigurations` instead, and
  > note the **user is `picktrace`, not `cjlarose`**, even though the guest is named
  > `pt-docker-cjlarose`:
  >
  > ```sh
  > nix eval .#nixosConfigurations.pt-docker-cjlarose.config.home-manager.users.picktrace.programs.claude-code.package
  > ```
  >
  > Because that guest also sets `home-manager.useUserPackages = true`, a package
  > change there needs a **system** switch anyway, not an HM activate.

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
