# DNS Host 26.05 Upgrade + Disk Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the `dns` host (Proxmox VM 116) from NixOS 25.11 → 26.05, replace its per-directory home impermanence with a dedicated persistent `tank/home` ZFS dataset, and migrate `~/workspace/$user/$repo` → `~/worktrees/$user/$repo/default` — in a single push-deploy plus one reboot, with the nix store preserved.

**Architecture:** Two parts. **Part 1 (Tasks 1–5)** is pure nix-config refactoring on branch `dns-26-05-disk-restructure` in this worktree, validated by building the dns system closure on ns1010301 (no live host touched). **Part 2 (Tasks 6–10)** is operational: unlike the cache/bots playbook there is **no pool grow and no installer ISO** — `tank` has ample free space, so `tank/home` is created live with the pool imported. The committed 26.05 closure is built on ns1010301, `nix copy`-ed to the live host, activated with `switch-to-configuration boot`, and the host is rebooted once.

**Tech Stack:** NixOS 26.05 flakes, `disko` (declarative, inert here), ZFS (lz4, legacy mountpoints), `impermanence`, `rsync`, push-deploy via `nix copy` over `ssh-ng`.

## Global Constraints

- **Preserve the nix store** (`tank/nix`) — never wipe; nothing is repartitioned.
- **Never write vdb / `/persistence`** — it holds the SSH host keys and `/etc/nixos`. The Task-6 backup is read-only insurance; the migration only *reads* from `/persistence`.
- **No pool grow, no ISO, no `qm` surgery.** `tank` is 55.5 G / 53% used (25.6 G free); a 26.05 closure fits. `tank/home` is created online with `zfs create`.
- **Deploy source is the committed branch tree.** Flakes only see git-tracked files; commit each config task before building. No push to origin is required to deploy — the build reads the local committed worktree.
- Host: `dns`, PVE VM **116** on `pve`. `system.stateVersion = "23.11"` (do **not** change). `hostId = "3889a1e4"` (pinned).
- DNS is the LAN resolver (`192.168.2.104` AdGuard + `192.168.2.105` dnsmasq). The single reboot is a ~1–2 min LAN-wide DNS pause — run it off-hours.
- Agent-free access from ns1010301 (avoids the lock-prone 1Password agent): `SSH_AUTH_SOCK= ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes cjlarose@192.168.2.104`. For `nix copy`: `export NIX_SSHOPTS="-i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes"`.
- Commit after each config task on branch `dns-26-05-disk-restructure`. Per repo convention, commit messages carry **no** conventional-commit type and **no** area-scope prefix. End each with the `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` trailer.

---

## Part 1 — Nix config changes (branch `dns-26-05-disk-restructure`, no live host touched)

### Task 1: Bump dns to the 26.05 channel

**Files:**
- Modify: `nixos-configurations/default.nix` (the `"dns"` block)

**Interfaces:**
- Produces: the `dns` nixosConfiguration evaluated against `nixpkgs-26-05` / `home-manager-26-05`. Consumed by every later build (`.#nixosConfigurations.dns`).

- [ ] **Step 1: Edit the dns block**

In `nixos-configurations/default.nix`, the `"dns"` block currently reads:
```nix
    "dns" = (
      import ./dns {
        inherit sharedOverlays additionalPackages impermanence disko self;
        nixpkgs = nixpkgs-25-11;
        home-manager = home-manager-25-11;
        stateVersion = "23.11";
      }
    );
```
Change the two channel bindings (leave `stateVersion = "23.11"` untouched):
```nix
    "dns" = (
      import ./dns {
        inherit sharedOverlays additionalPackages impermanence disko self;
        nixpkgs = nixpkgs-26-05;
        home-manager = home-manager-26-05;
        stateVersion = "23.11";
      }
    );
```
(The `nixpkgs-26-05` / `home-manager-26-05` bindings already exist — the `media` block uses them.)

- [ ] **Step 2: Verify it still evaluates**

Run from this worktree:
```bash
nix eval --raw .#nixosConfigurations.dns.config.system.nixos.release
```
Expected: `26.05` (a bare-string release; if it errors, the channel bindings are wrong).

- [ ] **Step 3: Commit**

```bash
git add nixos-configurations/default.nix
git commit -m "$(printf 'Bump dns to the 26.05 channel\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 2: Rework `dns/disk-config.nix` for 26.05 + `tank/home`

**Files:**
- Modify: `nixos-configurations/dns/disk-config.nix`

**Interfaces:**
- Consumes: the `disko` flake input (already passed via `default.nix`).
- Produces: a `boot` config with a systemd-initrd `rollback-root` oneshot and `forceImportRoot = false`, and a `tank/home` dataset declaration. `pkgs` is now needed in the module signature for `pkgs.zfs`.

- [ ] **Step 1: Add `pkgs` to the module signature**

Change line 1 from:
```nix
{ disko }: { lib, ... }:
```
to:
```nix
{ disko }: { lib, pkgs, ... }:
```

- [ ] **Step 2: Replace the boot block (scripted rollback → systemd-initrd oneshot + forceImportRoot)**

Replace this block:
```nix
    boot = {
      loader.systemd-boot.enable = true;
      zfs.devNodes = "/dev/disk/by-label/tank";
      initrd.postDeviceCommands = lib.mkAfter ''
        zfs rollback -r tank/root@blank
      '';
    };
```
with:
```nix
    boot = {
      loader.systemd-boot.enable = true;
      # Single disk — no duplicate-label mirror issue, by-label is fine.
      zfs.devNodes = "/dev/disk/by-label/tank";
      # hostId is pinned and storage is single-tenant; the 26.11 default.
      zfs.forceImportRoot = false;
      # Roll the root dataset back to a pristine snapshot on every boot
      # (impermanence). 26.05 defaults to systemd stage-1 initrd, which
      # silently ignores the old `boot.initrd.postDeviceCommands` form, so this
      # is a oneshot ordered after the pool import and before the root mount.
      initrd.systemd.services.rollback-root = {
        description = "Roll back tank/root to its blank snapshot";
        wantedBy = [ "initrd.target" ];
        after = [ "zfs-import-tank.service" ];
        before = [ "sysroot.mount" ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        path = [ pkgs.zfs ];
        script = ''
          zfs rollback -r tank/root@blank
        '';
      };
    };
```

- [ ] **Step 3: Drop the disko image-build params**

These two lines only matter when building a disko VM *image* (inert for a deployed host) and the bots/cache host-specific disk-configs omit them. Delete `memSize = 2048; # megabytes` from the `disko = { … }` block:
```nix
    disko = {
      memSize = 2048; # megabytes      # <-- DELETE THIS LINE
      enableConfig = false; # disable setting filesystems.* automatically
```
and delete `imageSize = "4G";` from the `disk.main` block:
```nix
          main = {
            imageSize = "4G";          # <-- DELETE THIS LINE
            device = "/dev/vda";
```

- [ ] **Step 4: Add the `home` dataset**

In `zpool.tank.datasets`, after the `nix` dataset, add `home`:
```nix
              nix = {
                type = "zfs_fs";
                mountpoint = "/nix";
                options.mountpoint = "legacy";
              };
              home = {
                type = "zfs_fs";
                mountpoint = "/home";
                options.mountpoint = "legacy";
              };
```

- [ ] **Step 5: Verify the closure still evaluates**

```bash
nix eval .#nixosConfigurations.dns.config.system.build.toplevel.drvPath
```
Expected: prints a `/nix/store/….drv` path (eval succeeds). If it errors with `pkgs` undefined, Step 1 was missed.

- [ ] **Step 6: Commit**

```bash
git add nixos-configurations/dns/disk-config.nix
git commit -m "$(printf 'dns disk-config: 26.05 systemd-initrd rollback + tank/home dataset\n\nReplace the scripted-initrd postDeviceCommands ZFS rollback (silently\nignored under 26.05 systemd stage-1) with a rollback-root oneshot, add the\npersistent tank/home dataset, set forceImportRoot=false, and drop the inert\ndisko image-build params.\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 3: Mount `tank/home` and enable swap in `hardware-configuration.nix`

**Files:**
- Modify: `nixos-configurations/dns/hardware-configuration.nix`

**Interfaces:**
- Consumes: the `tank/home` dataset declared in Task 2 and created in Task 7.
- Produces: `fileSystems."/home"` mounting `tank/home`; an active swap device.

- [ ] **Step 1: Add the `/home` filesystem**

After the `/nix` block:
```nix
  fileSystems."/nix" =
    { device = "tank/nix";
      fsType = "zfs";
    };
```
insert:
```nix
  fileSystems."/home" =
    { device = "tank/home";
      fsType = "zfs";
    };
```

- [ ] **Step 2: Enable the existing swap partition**

Change:
```nix
  swapDevices = [ ];
```
to:
```nix
  swapDevices = [
    { device = "/dev/disk/by-partlabel/disk-main-swap"; }
  ];
```

- [ ] **Step 3: Verify**

```bash
nix eval --raw .#nixosConfigurations.dns.config.fileSystems.\"/home\".device
```
Expected: `tank/home`.

- [ ] **Step 4: Commit**

```bash
git add nixos-configurations/dns/hardware-configuration.nix
git commit -m "$(printf 'dns hardware-config: mount tank/home and enable swap\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 4: Drop per-directory home impermanence in `dns/default.nix`

**Files:**
- Modify: `nixos-configurations/dns/default.nix`

**Interfaces:**
- Produces: the `environment.persistence."/persistence"` block with only the system-level `/etc/nixos` directory; home is now the persistent `tank/home` dataset. SSH stays safe because authorized keys are declared in NixOS (`users.users.cjlarose.openssh.authorizedKeys.keys`), not sourced from the persisted `.ssh`.

- [ ] **Step 1: Remove the `users.cjlarose` persistence block**

The block currently reads:
```nix
      environment.persistence."/persistence" = {
        hideMounts = true;
        directories = [
          {
            directory = "/etc/nixos";
          }
        ];
        users = {
          cjlarose = {
            directories = [
              ".ssh"
              "workspace"
            ];
          };
        };
      };
```
Delete the `users = { … };` sub-block, leaving:
```nix
      environment.persistence."/persistence" = {
        hideMounts = true;
        directories = [
          {
            directory = "/etc/nixos";
          }
        ];
      };
```

- [ ] **Step 2: Verify the persisted user dirs are gone**

```bash
nix eval --json .#nixosConfigurations.dns.config.environment.persistence.\"/persistence\".users
```
Expected: `{}` (no per-user persistence).

- [ ] **Step 3: Commit**

```bash
git add nixos-configurations/dns/default.nix
git commit -m "$(printf 'dns: drop per-dir home impermanence in favor of tank/home\n\nHome is now the persistent tank/home dataset; only /etc/nixos stays in\n/persistence. SSH is unaffected (authorized keys are declared in NixOS).\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

### Task 5: Build the dns closure on ns1010301 (validation gate)

**Files:** none (build only).

**Interfaces:**
- Consumes: the committed Tasks 1–4.
- Produces: a built `toplevel` store path, reused verbatim in Task 8.

- [ ] **Step 1: Build the toplevel**

From this worktree on ns1010301:
```bash
nix build .#nixosConfigurations.dns.config.system.build.toplevel \
  --print-out-paths --no-link
```
Expected: a single `/nix/store/…-nixos-system-dns-26.05…` path, no eval/build errors. Record it as `$TOPLEVEL` for Task 8.

- [ ] **Step 2: Sanity-check the release and the rollback unit are in the closure**

```bash
TOPLEVEL=$(nix build .#nixosConfigurations.dns.config.system.build.toplevel --print-out-paths --no-link)
cat "$TOPLEVEL/nixos-version"        # expect 26.05…
ls "$TOPLEVEL"/initrd                # exists; systemd-initrd image
```
Expected: `nixos-version` starts `26.05`; the build is reproducible (re-running prints the same path).

- [ ] **Step 3: No commit** (build artifact only). Part 1 is complete; the live host is still untouched and still on 25.11.

---

## Part 2 — Operational migration (live host `dns`, from ns1010301)

> Run everything below from ns1010301 using the agent-free key. All live-host commands assume `SSH_AUTH_SOCK=` and `-i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes`. Nothing here writes to `/persistence`.

### Task 6: Off-host safety backup of `/persistence`

**Files:** none (operational).

- [ ] **Step 1: Tar `/persistence` read-only and pull it to ns1010301**

```bash
mkdir -p ~/dns-migration-backup
SSH_AUTH_SOCK= ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes cjlarose@192.168.2.104 \
  'sudo tar -C /persistence -czf - .' > ~/dns-migration-backup/persistence-20260623.tar.gz
```

- [ ] **Step 2: Verify the SSH host keys are inside the tarball**

```bash
tar -tzf ~/dns-migration-backup/persistence-20260623.tar.gz | grep -E 'ssh/ssh_host_(ed25519|rsa)_key$'
```
Expected: both `./ssh/ssh_host_ed25519_key` and `./ssh/ssh_host_rsa_key` listed. This is insurance only — vdb is never written by this migration.

---

### Task 7: Create + populate `tank/home` live (host still on 25.11)

**Files:** none (operational).

**Interfaces:**
- Consumes: the running 25.11 host with `tank` imported and `/persistence` mounted.
- Produces: a populated `tank/home` dataset (unmounted), ready to be mounted at `/home` by the 26.05 generation on reboot.

- [ ] **Step 1: Create the dataset and mount it temporarily**

```bash
SSH_AUTH_SOCK= ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes cjlarose@192.168.2.104 'sudo bash -s' <<'REMOTE'
set -euo pipefail
zfs create -o mountpoint=legacy tank/home
mkdir -p /mnt/newhome
mount -t zfs tank/home /mnt/newhome
REMOTE
```

- [ ] **Step 2: Populate from `/persistence` with rsync (`nix shell` provides rsync)**

`rsync` is not in the host's default packages; run it via `nix shell nixpkgs#rsync`. Note the trailing slash on the `nix-configurations/` source so its *contents* land in the `default/` worktree.

**CRITICAL — the dataset mounts at `/home`, so the user's home is `/home/cjlarose`. Populate under a `cjlarose/` subdirectory (`DST=/mnt/newhome/cjlarose`), NOT at the dataset root.** Populating at the root yields `/home/.ssh` etc. with no `/home/cjlarose`, which fails `home-manager-cjlarose.service` ("cd: /home/cjlarose: No such file or directory") and leaves the user with no home dir on the next boot.
```bash
SSH_AUTH_SOCK= ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes cjlarose@192.168.2.104 'sudo nix shell nixpkgs#rsync -c bash -s' <<'REMOTE'
set -euo pipefail
SRC=/persistence/home/cjlarose
DST=/mnt/newhome/cjlarose          # the user's home dir within the dataset
mkdir -p "$DST"
rsync -aHAX "$SRC/.ssh"     "$DST/"
rsync -aHAX "$SRC/gc-roots" "$DST/"
mkdir -p "$DST/worktrees/cjlarose/nix-configurations"
rsync -aHAX "$SRC/workspace/cjlarose/nix-configurations/" \
            "$DST/worktrees/cjlarose/nix-configurations/default/"
chown -R 1000:100 "$DST"
chmod 700 "$DST"
REMOTE
```

- [ ] **Step 3: Drop stale agent sockets, verify layout, unmount**

```bash
SSH_AUTH_SOCK= ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes cjlarose@192.168.2.104 'sudo bash -s' <<'REMOTE'
set -euo pipefail
find /mnt/newhome -type s -delete 2>/dev/null || true
echo "--- dataset root (expect a single cjlarose/ dir) ---"; ls -la /mnt/newhome
echo "--- user home ---"; ls -la /mnt/newhome/cjlarose
echo "--- worktree ---";  ls -la /mnt/newhome/cjlarose/worktrees/cjlarose/nix-configurations/default | head
umount /mnt/newhome
rmdir /mnt/newhome
REMOTE
```
Expected: the dataset root contains exactly `cjlarose/`; `/mnt/newhome/cjlarose` contains `.ssh`, `gc-roots`, `worktrees/`; the `default/` worktree contains a `.git` and `flake.nix`. `tank/home` lives in pool state, so it survives the `tank/root@blank` rollback on reboot.

---

### Task 8: Push-deploy the 26.05 closure + single reboot

**Files:** none (operational).

**Interfaces:**
- Consumes: `$TOPLEVEL` from Task 5 and the populated `tank/home` from Task 7.

- [ ] **Step 1: Copy the closure to the live host**

```bash
export NIX_SSHOPTS="-i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes"
TOPLEVEL=$(nix build .#nixosConfigurations.dns.config.system.build.toplevel --print-out-paths --no-link)
SSH_AUTH_SOCK= nix copy --to "ssh-ng://cjlarose@192.168.2.104" --no-check-sigs "$TOPLEVEL"
echo "$TOPLEVEL"
```
Expected: copy completes (cjlarose is in `trusted-users` on dns, so `--no-check-sigs` is accepted).

- [ ] **Step 2: Activate as the boot generation**

```bash
SSH_AUTH_SOCK= ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes cjlarose@192.168.2.104 \
  "sudo nix-env -p /nix/var/nix/profiles/system --set $TOPLEVEL && \
   sudo $TOPLEVEL/bin/switch-to-configuration boot"
```
Expected: `switch-to-configuration boot` succeeds. Use **`boot`**, not `switch` — the new kernel and the `/home` → `tank/home` mount only take effect on reboot. (A benign `dbus-broker` exit code 4 across the systemd version bump is acceptable; it does not occur for `boot` activation, which does not reload running units.)

- [ ] **Step 3: Reboot (the only outage; ~1–2 min DNS pause)**

```bash
SSH_AUTH_SOCK= ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes cjlarose@192.168.2.104 'sudo systemctl reboot' || true
```
The connection drops as the host reboots; `|| true` swallows the expected SIGHUP.

- [ ] **Step 4: Wait for it to come back**

```bash
until SSH_AUTH_SOCK= ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes -o ConnectTimeout=5 \
  cjlarose@192.168.2.104 'nixos-version' 2>/dev/null; do sleep 5; done
```
Expected: prints a `26.05…` version once SSH is back.

**Recovery:** if the host does not return, the prior 25.11 generation is still in the bootloader (the host was upgraded in place, never wiped). Select it from the Proxmox console (`pve` VM 116) to recover; `tank/home` sitting unmounted under the old generation is harmless.

---

### Task 9: Verify the migrated host

**Files:** none (verification).

- [ ] **Step 1: OS, datasets, and mounts**

```bash
SSH_AUTH_SOCK= ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes cjlarose@192.168.2.104 'bash -s' <<'REMOTE'
echo "=== version ==="; nixos-version
echo "=== datasets ==="; zfs list -o name,mountpoint
echo "=== /home mount ==="; mount | grep ' /home '
echo "=== no per-dir bind mounts ==="; mount | grep -E '/home/cjlarose/(\.ssh|workspace)' || echo "none (good)"
echo "=== home contents ==="; ls -la /home/cjlarose
echo "=== worktree ==="; ls /home/cjlarose/worktrees/cjlarose/nix-configurations/default >/dev/null && echo OK
echo "=== swap ==="; swapon --show
echo "=== units ==="; systemctl is-system-running; systemctl --failed --no-legend
echo "=== rollback ran ==="; journalctl -b -u rollback-root --no-pager | tail -n 5
REMOTE
```
Expected: version `26.05`; `tank/{root,nix,home}` present; `/home` is `tank/home`; **no** `/home/cjlarose/.ssh` or `/home/cjlarose/workspace` ext4 bind mounts; home has `.ssh` + `gc-roots` + `worktrees/…/default`, no `workspace`; swap active; `is-system-running` = `running` with zero failed units; the `rollback-root` oneshot completed.

- [ ] **Step 2: DNS service health**

```bash
SSH_AUTH_SOCK= ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes cjlarose@192.168.2.104 'bash -s' <<'REMOTE'
echo "=== adguard :53 ==="; ss -lunp | grep ':53 ' | grep 192.168.2.104 || echo MISSING
echo "=== dnsmasq :53 ==="; ss -lunp | grep ':53 ' | grep 192.168.2.105 || echo MISSING
echo "=== intranet host via dnsmasq ==="; dig +short @192.168.2.105 ns1010301.toothyshouse.com 2>/dev/null || true
echo "=== external via adguard DoH ==="; dig +short @192.168.2.104 example.com 2>/dev/null || true
REMOTE
```
Expected: both resolvers listening on their respective IPs; the intranet name resolves through dnsmasq; an external name resolves through AdGuard. (Confirm one resolution from a LAN client too.)

- [ ] **Step 3: In-place no-op rebuild from the canonical checkout**

```bash
SSH_AUTH_SOCK= nix copy --to "ssh-ng://cjlarose@192.168.2.104" --no-check-sigs \
  "$(nix build .#nixosConfigurations.dns.config.system.build.toplevel --print-out-paths --no-link)"
```
Expected: a no-op copy (closure already present) — confirms the deployed generation matches the committed config byte-for-byte.

---

### Task 10: Merge to `main`, push, and clean up

**Files:** none (git + cleanup).

- [ ] **Step 1: Fast-forward `main` to the branch and push**

From the `default` worktree:
```bash
cd /home/cjlarose/worktrees/cjlarose/nix-configurations/default
git fetch origin
git checkout main && git merge --ff-only dns-26-05-disk-restructure
git push origin main
```
Expected: fast-forward merge (rebase onto `origin/main` first if it has advanced), then push succeeds.

- [ ] **Step 2: Reconcile the migrated checkout on dns (optional housekeeping)**

The carried-over `~/worktrees/cjlarose/nix-configurations/default` on dns is the old stale clone; `git -C … fetch && git -C … reset --hard origin/main` (or convert to the canonical worktree layout) at the operator's discretion. Not load-bearing for the host.

- [ ] **Step 3: Remove the feature worktree and branch**

```bash
cd /home/cjlarose/worktrees/cjlarose/nix-configurations/default
git worktree remove /home/cjlarose/worktrees/cjlarose/nix-configurations/dns-26-05-disk-restructure
git branch -d dns-26-05-disk-restructure
```

- [ ] **Step 4: Retain then delete the safety backup**

Keep `~/dns-migration-backup/persistence-20260623.tar.gz` on ns1010301 until dns runs clean for a few days, then `rm` it.

---

## Self-review notes

- **Spec coverage:** every spec phase (A safety / B config / C populate / D deploy / E verify) maps to Tasks 6 / 1–5 / 7 / 8 / 9; rollback + cleanup are Tasks 8-recovery and 10.
- **No pool grow / no ISO / no `qm`** — consistent with the spec's central simplification throughout.
- **`tank/home` name and `/home` device** (`tank/home`) are consistent across Tasks 2, 3, 7, 9.
- **`switch-to-configuration boot` (not `switch`)** is consistent with the one-reboot design and the `/home` + kernel change.
