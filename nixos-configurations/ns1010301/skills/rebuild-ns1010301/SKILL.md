---
name: rebuild-ns1010301
description: Use when deploying a nix-configurations change to the ns1010301 host or one of its microvm guests (pt-docker-cjlarose, media, hermes, minecraft-mellowcatfe) — a host system change, a guest system or home-manager change, or a flake.lock bump — and especially when a pt-docker-cjlarose change lives in picktrace/nix-configurations and must reach the guest through cjlarose's picktrace-nix-configurations input. Triggers on "rebuild ns1010301", "deploy to the guest", "nixos-rebuild", "bring the microvm forward", "switch the host", "roll out to pt-docker".
---

# Rebuild ns1010301 (host, microvms, home-manager)

Apply a `cjlarose/nix-configurations` change — or, for `pt-docker-cjlarose`, a `picktrace/nix-configurations` change — to the ns1010301 host and bring its microvm guests to parity **without rebooting them**.

## When to use

- A change that must go live on ns1010301: host system config, a microvm guest's system config, or a per-user home-manager profile.
- A `flake.lock` bump that needs deploying.
- A `pt-docker-cjlarose` change that landed in `picktrace/nix-configurations` — see **Cross-repo deploy** below first.
- After a host switch prints `NOT restarting the following changed units: microvm@*.service` and a guest should be brought forward live.

**Not** for `bots`, `cache`, `dns`, `splitpro` — separate Proxmox VMs on `pve` with their own `/nix/var/nix/profiles/system`, no `microvm@<host>` unit, absent from `/var/lib/microvms/`. They use push-deploy: `nix build` here → `nix copy --to ssh-ng://cjlarose@<fqdn> --no-check-sigs` → `sudo nix-env -p /nix/var/nix/profiles/system --set <top>` + `sudo <top>/bin/switch-to-configuration switch` on the target.

## Prerequisites

- Run **on ns1010301** as `cjlarose` (Determinate Nix 3.17.1 / Nix 2.33.3). cjlarose has passwordless sudo and SSH to all four guests.
- **Author changes in `~/workspaces/<task>/<repo>` and land them via PR.** `~/repos` is read-only for editing. Building `main` from `~/repos/cjlarose/nix-configurations` is allowed and expected — your workspace worktrees are on feature branches and git refuses to check `main` out twice.
- **New/untracked files must be `git add`ed** before building — nix will not see them otherwise. They need not be committed.
- All private flake inputs are `git+ssh://`, so `ssh-agent` must have the key loaded. In `cjlarose/nix-configurations`: `pce`, `cs-automation`, `intranetHosts`, `picktrace-nix-configurations`, `cjlarose-llm-wiki`. In `picktrace/nix-configurations`: `cjlarose-home-manager-modules`, `cjlarose-llm-wiki`, `cjlarose-darwin-modules`.

---

## Cross-repo deploy: a pt-docker-cjlarose change that lives in picktrace/nix-configurations

The `pt-docker-cjlarose` guest is built from `picktrace/nix-configurations`, but the ns1010301 host embeds it through cjlarose's **`picktrace-nix-configurations` flake input**. A change merged to picktrace `main` is invisible here until that input moves. So a picktrace-side guest change deploys in two landings, picktrace first, cjlarose second.

1. **Land the change in `picktrace/nix-configurations`** (its own PR). Note the merge commit — that is the rev the guest needs.

2. **Confirm the host's input is behind it.** Read the currently-pinned rev and check whether it already contains the target commit:

   ```sh
   cd ~/repos/cjlarose/nix-configurations
   PIN=$(nix eval --impure --raw --expr \
     'let l = builtins.fromJSON (builtins.readFile ./flake.lock); in l.nodes.${l.nodes.${l.root}.inputs.picktrace-nix-configurations}.locked.rev')
   git -C ~/repos/picktrace/nix-configurations merge-base --is-ancestor <merge-sha> "$PIN" \
     && echo "already deployed" || echo "needs bump"
   ```

3. **Bump the input in a cjlarose workspace, land via PR.** From `~/workspaces/<task>/cjlarose-nix-configurations`:

   ```sh
   nix flake update picktrace-nix-configurations
   ```

   This moves `picktrace-nix-configurations` to picktrace `main`, and — because it follows picktrace's own lock — usually advances the nested `picktrace-nix-configurations/cjlarose-home-manager-modules` pin as well. **Review the full `flake.lock` diff**: confirm both revs are the intended ones and nothing else moved. The nested modules pin reaches this host only through the picktrace guest, not through the host's own home config.

4. **Merge, then deploy with Step 1 onward.** The cjlarose repo has no CI — verify by building the host toplevel (Step 1) *before* merging rather than merging blind. Then rebuild the host and bring the guest forward (Steps 1–4).

**`pt-docker-cjlarose` runs as user `picktrace`, and `useUserPackages = true`** — so a change that adds or changes a *package* (not just a dotfile) needs a **guest system switch**, not a home-manager activate. See the `useUserPackages` gotcha.

---

## Step 0 — capture a rollback handle (always, first)

```sh
ROLLBACK_PATH="$(readlink -f /nix/var/nix/profiles/system)"
```

## Step 1 — build and switch the host (skip-root-eval)

**The unconditional default opener. Do not try `sudo nixos-rebuild` first.**

```sh
TOP=$(nix build .#nixosConfigurations.ns1010301.config.system.build.toplevel \
        --no-link --print-out-paths)
sudo nix-env -p /nix/var/nix/profiles/system --set "$TOP"
sudo "$TOP/bin/switch-to-configuration" switch
```

Pre-switch closure-identity check (cheap; the only check that works before switching):

```sh
nix-store -qR "$TOP" | grep -i nixos-system-pt-docker-cjlarose
```

### Why not `sudo nixos-rebuild`

`sudo nixos-rebuild switch` **re-evaluates the flake as root**, and root has neither the user's SSH agent/`known_hosts` (for `git+ssh://` private inputs) nor a gh token. Building as the user first only caches the *output*; `nixos-rebuild` still makes root re-fetch the *input* at eval time. Driving activation off the user-built toplevel with `nix-env --set` + `switch-to-configuration` bypasses root eval entirely. A `flake.lock` change of any kind busts root's eval cache, so "the lock moved" ⇒ "the input is new from root's view".

Escape hatch, only if you genuinely need `nixos-rebuild`'s eval: override **every** private input (one override busts root's cache for the others), each pointed at its already-fetched in-store `…-source`:

```sh
nix flake archive --json | jq -r '.. | objects | select(has("path")) | .path'
sudo nixos-rebuild switch --flake .#ns1010301 \
  --override-input cjlarose-llm-wiki path:/nix/store/<a>-source \
  --override-input picktrace-nix-configurations/cjlarose-llm-wiki path:/nix/store/<b>-source
```

## Step 2 — handle changed-but-not-restarted microvms

The switch ends with e.g. `NOT restarting the following changed units: microvm@pt-docker-cjlarose.service, microvm@media.service`. **Ask the user per guest — never restart automatically.** A `microvm@` restart is a real ~12 s reboot that kills in-guest sessions; the same holds for bouncing `hermes-agent.service`.

**Diff the closure first — the size of your change tells you nothing about the size of the activation.** Guests are routinely booted well behind `main`, so an in-place switch reconciles all accumulated drift and can restart unrelated units.

```sh
nix store diff-closures "$(readlink -f /var/lib/microvms/<name>/booted)" "$TOPLEVEL" 2>/dev/null \
  || ssh <user>@<ip> "nix store diff-closures /run/current-system $TOPLEVEL"
```

Then pick per guest:

| Mode | Use when |
|---|---|
| **system switch in-place** (Steps 3–4) | the guest's system config or any *package* changed (`useUserPackages`, below) |
| **home-manager switch** | strictly `home.file`/dotfile-only change |
| **restart unit** (`sudo systemctl restart microvm@<name>.service`) | kernel, initrd, a new virtiofs share, a new `microvm.volumes` block device, network/static IP, or qemu args — none hot-apply |
| **skip** | cosmetic host-wrapper drift. The flake `self` rev advances on *any* commit, so every guest gets a new store path regardless. **Skip is the right default** — it takes effect on the next restart at no downtime. Flag out-of-scope siblings rather than switching them into a stale-guest reconcile. |

`current` is updated by the host switch even when the unit is not restarted, so `current` is what the host *intends*; only `booted`, or `/run/current-system` inside the guest, is what runs.

## Step 3 — sync the closure into the guest's nix DB

The guest's `/nix/store` is a virtiofs share of the host store, so the files are **already there**; only the guest's nix database lacks the metadata records.

**Guests have no name resolution** — use bridge IPs on the `microvm` bridge (`10.0.0.1/24`); the login user differs per guest:

| Guest | Address | Flake |
|---|---|---|
| `pt-docker-cjlarose` | `picktrace@10.0.0.2` | `picktrace/nix-configurations` |
| `minecraft-mellowcatfe` | `cjlarose@10.0.0.3` | `cjlarose/nix-configurations` |
| `media` | `cjlarose@10.0.0.4` | `cjlarose/nix-configurations` |
| `hermes` | `cjlarose@10.0.0.5` | `cjlarose/nix-configurations` |

Re-derive if in doubt: `ip neigh show dev microvm`, then `ssh -o ConnectTimeout=3 -o BatchMode=yes cjlarose@<ip> hostname`.

Find the path to register:

```sh
# system switch: resolve the guest toplevel from the host's current spec
CLOSURE_ROOT=/var/lib/microvms/<name>/current
GUEST_TOP=$(sudo sed -nE 's|.*init=(/nix/store/[^ ]+)/init.*|\1|p' \
  "$CLOSURE_ROOT/bin/microvm-run" | head -1)

# home-manager switch: there is NO homeConfigurations."<user>@<vm>" output —
# always reach guest home-manager through nixosConfigurations
GUEST_TOP=$(nix build \
  .#nixosConfigurations.<guest>.config.home-manager.users.<user>.home.activationPackage \
  --no-link --print-out-paths)
```

Dump-db → scp → load-db. **Never pipe `nix-store --dump-db` straight through nested ssh/sudo** — the binary format corrupts (CRLF/pty buffering) and `--load-db` fails with `name 'foo\n' contains illegal character '\n'`. Stage via a tempfile (scp uses SFTP, which does not mangle binary):

```sh
DUMP=$(mktemp /tmp/nix-db-dump.XXXXXX)
nix-store --dump-db $(nix-store -qR "$GUEST_TOP") > "$DUMP"
scp -q "$DUMP" <user>@<ip>:"$DUMP"
ssh <user>@<ip> "sudo nix-store --load-db < $DUMP && rm $DUMP"
rm "$DUMP"
ssh <user>@<ip> "nix-store --check-validity $GUEST_TOP && echo VALID"
```

DB metadata is tiny (~440 bytes/path) versus hundreds of MB for `--export | --import`, which needlessly rewrites file content the guest already has.

## Step 4 — activate inside the guest

```sh
# system switch
ssh <user>@<ip> "sudo $GUEST_TOP/bin/switch-to-configuration switch"

# home-manager switch (no sudo — activates into the user's profile)
ssh <user>@<ip> "$GUEST_TOP/activate"
```

`Warning: do not know how to make this configuration bootable` is **normal and benign** — the host's qemu wrapper owns the boot path. `switch-to-configuration switch` updates `/run/current-system` only; uptime is preserved.

Verify: `ssh <user>@<ip> "readlink -f /run/current-system"` matches `$GUEST_TOP`.

## Rollback

```sh
sudo "$ROLLBACK_PATH/bin/switch-to-configuration" switch     # host
```

Guest: restart its `microvm@<name>.service` (returns to the host's current spec), or re-run a system switch against the previous closure path.

---

## Gotchas

- **`useUserPackages = true` everywhere in this fleet** — ns1010301, `media`, `hermes`, `minecraft-mellowcatfe`, and picktrace's `pt-docker-cjlarose`. `home.packages` route to `/etc/profiles/per-user/<name>`, part of the **system** closure — so an HM-only `activate` is a **no-op for packages** and relinks dotfiles only. Any package, wrapped binary, or content a package carries needs a **system** switch. Even for a pure `home.file` change, a system switch is the safe default here.
- **Host-user HM changes ride the host switch.** A change to the `cjlarose` HM profile *on ns1010301 itself* goes live via Step 1 — the host switch restarts `home-manager-cjlarose.service`. No separate host-side HM step.
- **Fleet-shared inputs stage sibling guests.** `nixpkgs-unstable` is shared, so bumping it for one guest re-derives all four. Leave out-of-scope siblings un-activated and flag it.
- **`diff-closures` hides config-only changes.** It dedups by package name+version, so a guest system that changed only config (same nixpkgs) shows an empty diff even though its store path moved. Confirm the intended content directly (e.g. `nix-store -qR "$GUEST_TOP" | grep <the-thing>`) rather than trusting an empty diff.
- **ZFS quota.** `/nix` is a `tank/nix` ZFS dataset with a quota. A large build (e.g. an accidental aarch64-darwin closure) can fill it, and the daemon's socket bind then fails with `EDQUOT` — the daemon reads as wedged. The pool has headroom: `sudo zfs set quota=<bigger> tank/nix`, kill orphaned `nix-daemon` workers holding the socket, `sudo systemctl reset-failed nix-daemon.*`, start `nix-daemon.socket`, `nix store gc`, then restore the quota.
- **ZFS block cloning.** virtiofsd's `copy_file_range` triggers ZFS block cloning, which with `zfs_bclone_enabled=1` can deadlock `txg_sync` on VM start. ns1010301 disables it host-wide.
- **Hermes self-restart.** Restarting the hermes guest from inside it is blocked by the agent runtime. Workaround: a detached tmux session on ns1010301 that sleeps a few seconds then `systemctl restart microvm@hermes`.
- **Serial console** is on **ttyS1** (not ttyS0) at 115200 via OVH IPMI SoL — the only recovery path if networking breaks.

## Host / fleet specifics

- **Host:** `ns1010301`, x86_64-linux, nixpkgs 26.05, stateVersion 25.11, 16 cores.
- **Attribute paths:**
  - Host toplevel: `.#nixosConfigurations.ns1010301.config.system.build.toplevel`
  - Guest toplevel (cjlarose flake): `.#nixosConfigurations.{media,hermes,minecraft-mellowcatfe}.config.system.build.toplevel`
  - Guest toplevel (picktrace flake): `.#nixosConfigurations.pt-docker-cjlarose.config.system.build.toplevel`
  - Per-user HM activation: `.#nixosConfigurations.<host-or-guest>.config.home-manager.users.<user>.home.activationPackage`
- **Microvms** (`nixos-configurations/ns1010301/default.nix`): `pt-docker-cjlarose` (`flake = picktrace-nix-configurations`), `minecraft-mellowcatfe`, `media`, `hermes` (all `flake = self`).
- **Users:** host and `media`/`hermes`/`minecraft-mellowcatfe` → `cjlarose`; `pt-docker-cjlarose` → **`picktrace`**, despite the guest name.
- **Paths:** `/var/lib/microvms/<name>/{current,booted}`, `.../current/bin/microvm-run`, `/nix/var/nix/profiles/system` (host only).
