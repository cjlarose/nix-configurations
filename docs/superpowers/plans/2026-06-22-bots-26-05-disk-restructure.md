# bots 26.05 Upgrade + Cache-Style Disk Restructure — Implementation Plan

> **For agentic workers:** This is an **operations runbook**, not a TDD code plan. Steps are sequential and many are **destructive / irreversible on a live host**. Execute phase-by-phase, honor every GO/NO-GO gate, and stop on any unexpected output. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the `bots` VM (PCE discord bot host) from NixOS 25.11 → 26.05, growing its full `tank` ZFS pool and moving home to a persistent `tank/home` dataset — mirroring the proven [[Cache Host Disk Restructure]] / [[Growing a ZFS Pool In-Place]] playbook.

**Architecture:** In-place partition surgery on `vda` only (never touches `vdb`/`/persistence`, which holds the live **postgres PCE database**), done offline from a NixOS 26.05 minimal ISO. The nix store is *not* preserved (bots is a consumer, not a cache) but is grown in place anyway; the surgery is identical to cache's. Repo config changes are already committed; the live work follows.

**Tech Stack:** Proxmox VE (`pve`, VM 117), ZFS-on-root with per-boot rollback, disko (declarative-only, `enableConfig = false`), impermanence, NixOS flakes.

## Global Constraints

- **Host:** bots = PVE VM **117** on `pve`. `qm`/root SSH to pve: `SSH_AUTH_SOCK= ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes root@pve.toothyshouse.com` (from ns1010301) or plain `root@pve.toothyshouse.com` if your key is authorized. App SSH: `cjlarose@bots.toothyshouse.com` (passwordless sudo, wheel).
- **virtio0 (vda)** = root/nix disk, backing `montero-vm-filesystem-roots-thin` (lvmthin, ~1.67 TB free, thin). **virtio1 (vdb)** = `/persistence` ext4 (postgres, ssh host keys, acme, /etc/nixos) — **NEVER touch during surgery**.
- **vda2 start sector = `1026048`** (verified 2026-06-22). The pool's vdev is stored at path **`/dev/disk/by-label/tank`** (matters for `zpool online -e`).
- Target disk size: **128 G** (thin; only sets the pool ceiling).
- `tank/root` is ephemeral (rolls back to `tank/root@blank` each boot); `tank/nix` persistent; **`tank/home` is new**.
- Repo: `cjlarose/nix-configurations`, branch **`bots-26-05-upgrade`**, worktree `~/worktrees/cjlarose/nix-configurations/bots-26-05-upgrade`.
- **Downtime:** Phases 3–7 take bots offline (PCE discord bot, rails, worker, id-watcher, postgres). Schedule a maintenance window.

---

## Phase 0 — Repo config changes ✅ DONE (commit `9e78fd4`)

Already committed on the branch and **verified to evaluate on 26.05** (`nixos-system-bots-26.05.20260611`, warnings only). For reference, this commit:

- `nixos-configurations/default.nix`: bots → `nixpkgs-26-05` / `home-manager-26-05` (stateVersion stays `23.11`).
- `bots/disk-config.nix`: `boot.initrd.postDeviceCommands` → systemd-initrd `rollback-root` oneshot; add `tank/home` dataset.
- `bots/hardware-configuration.nix`: `fileSystems."/home" = { device = "tank/home"; fsType = "zfs"; }`.
- `bots/default.nix`: drop per-dir home impermanence for `bot`+`cjlarose` (system dirs stay in `/persistence`).
- `bots/configuration.nix`: `nix.settings.trusted-users = [ "root" "cjlarose" ]` (enables push-deploy post-bootstrap).

> ⚠️ This config is **not bootable until `tank/home` exists on the host** (Phase 5). It is deployed only in Phase 7. Until then it lives only on the branch.

- [ ] **Step 0.1 — Confirm the branch state**

Run: `cd ~/worktrees/cjlarose/nix-configurations/bots-26-05-upgrade && git log --oneline -2`
Expected: `9e78fd4 bots: upgrade to 26.05 …` on top of `27e363d Remove monicahung …`

---

## Phase 1 — Pre-flight safety (no downtime)

**GATE:** Do not proceed past this phase without verified off-host backups.

- [ ] **Step 1.1 — Dump the postgres PCE database off-host**

The surgery never touches `vdb`/`/persistence` (where postgres lives), but this is the load-bearing asset — back it up anyway.

```sh
ssh cjlarose@bots.toothyshouse.com 'sudo -u postgres pg_dumpall' \
  > ~/bots-migration-backup/bots-pg_dumpall-20260622.sql
ls -lh ~/bots-migration-backup/bots-pg_dumpall-20260622.sql   # expect non-trivial size
head -5 ~/bots-migration-backup/bots-pg_dumpall-20260622.sql  # expect "PostgreSQL database cluster dump"
```

- [ ] **Step 1.2 — Tar `/persistence` off-host (belt-and-suspenders)**

```sh
ssh cjlarose@bots.toothyshouse.com 'sudo tar -czf - -C / persistence' \
  > ~/bots-migration-backup/bots-persistence-20260622.tar.gz
tar -tzf ~/bots-migration-backup/bots-persistence-20260622.tar.gz | head   # verify readable
```

- [ ] **Step 1.3 — Record current state for rollback reference**

```sh
ssh cjlarose@bots.toothyshouse.com '
  echo "=== current generation ==="; sudo nix-env --list-generations -p /nix/var/nix/profiles/system | tail -3
  echo "=== pool ==="; zpool list tank
  echo "=== vda2 start (MUST be 1026048) ==="; cat /sys/block/vda/vda2/start
  echo "=== nixos-version ==="; nixos-version
'
```
Expected: current gen noted; pool ~55.5G; **vda2 start = 1026048**; version `25.11…`.

- [ ] **Step 1.4 — Confirm the NixOS 26.05 minimal ISO is on pve**

```sh
ssh root@pve.toothyshouse.com 'ls -lh /var/lib/vz/template/iso/ | grep -i "nixos.*26.05\|nixos-minimal"'
```
Expected: a `nixos-minimal-26.05*.iso` present. **If absent:** download it to that dir (`wget` the 26.05 minimal x86_64 ISO from nixos.org) before continuing.

---

## Phase 2 — Enter maintenance window: stop, shut down, grow disk  ⛔ DOWNTIME BEGINS

The disk is grown while the VM is **powered off** (the surgery is offline anyway, so there's no reason to live-resize).

- [ ] **Step 2.1 — Stop PCE services + postgres cleanly**

```sh
ssh cjlarose@bots.toothyshouse.com 'sudo systemctl stop pce-rails pce-discord-bot pce-worker pce-id-watcher cs-discord-bot 2>/dev/null; sudo systemctl stop postgresql'
```

- [ ] **Step 2.2 — Shut down the VM**

```sh
ssh root@pve.toothyshouse.com 'qm shutdown 117 && sleep 5; qm status 117'
```
Expected: `status: stopped`. (If it hangs, `qm stop 117` after confirming services are down.)

- [ ] **Step 2.3 — Resize virtio0 to 128 G (VM off)**

```sh
ssh root@pve.toothyshouse.com 'qm resize 117 virtio0 128G; qm config 117 | grep virtio0'
```
Expected: `virtio0: …,size=128G`. Ignore the benign `ubuntu-vg` duplicate-VG / `LVMPlugin.pm` warnings.

- [ ] **Step 2.4 — Attach the 26.05 ISO and boot from it**

```sh
ssh root@pve.toothyshouse.com '
  qm set 117 --ide2 local:iso/nixos-26-05-minimal-x86_64-linux.iso,media=cdrom
  qm set 117 --boot order=ide2
  qm start 117
'
```

---

## Phase 3 — Reach the ISO environment

bots' MAC (`a2:ce:70:c6:cc:c2`) is DHCP-reserved, so the ISO comes up at the **same LAN IP `192.168.2.111`**. Tailscale is *not* running in the installer, but this host reaches `192.168.2.111` directly.

- [ ] **Step 3.1 — Operator: set a root password in the PVE console**

In `https://pve.toothyshouse.com:8006` → VM 117 → Console, once the installer prompt is up: run `passwd` and set a password. Put that same password (no trailing newline) into **`/tmp/nixos-iso-password` on the deploy host** (this machine) so I can read it.

- [ ] **Step 3.2 — Connect over SSH with the password**

No local `sshpass`, so use the one from nixpkgs. The installer has a fresh ephemeral host key → bypass known-hosts for installer sessions only.

```sh
nix shell nixpkgs#sshpass --command sshpass -f /tmp/nixos-iso-password \
  ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@192.168.2.111 \
  'nixos-version; which sgdisk zpool zfs'
```
Expected: connects; prints the installer version and the three tool paths (`sgdisk` is in the minimal ISO).

**GATE:** Confirm you are in the ISO (installer `nixos-version`), the pool is **NOT imported** (`zpool list` → "no pools available"), and `/persistence` is **not** mounted, before touching partitions.

---

## Phase 4 — Partition surgery 💥 DESTRUCTIVE (the one irreversible step)

Per [[Growing a ZFS Pool In-Place]]. ZFS reads via the on-partition label, so this is safe **iff** part2's **start stays 1026048** and the end only grows.

- [ ] **Step 4.1 — Relocate the stale GPT backup header to the new disk end**

```sh
sgdisk -e /dev/vda
sgdisk -p /dev/vda    # note last-usable sector now reflects 128 G
```

- [ ] **Step 4.2 — Delete swap, delete zfs, recreate zfs at the SAME start, recreate swap in the tail**

```sh
sgdisk -d 3 /dev/vda                                            # delete swap
sgdisk -d 2 /dev/vda                                            # delete zfs
sgdisk -n 2:1026048:-8G -t 2:8300 -c 2:disk-main-zfs /dev/vda   # SAME start 1026048, end -8G
sgdisk -n 3:0:0       -t 3:8200 -c 3:disk-main-swap /dev/vda    # swap fills tail
partprobe /dev/vda
```

- [ ] **Step 4.3 — VERIFY part2 start is still 1026048 (HARD GATE)**

```sh
sgdisk -p /dev/vda
```
Expected: partition **2** Start (sector) = **`1026048`** exactly. Partition 2 is now ~119 G; partition 3 is 8 G at the tail.
**If start ≠ 1026048: STOP. Do not import.** The pool data is keyed to that offset; an incorrect start means data loss.

- [ ] **Step 4.4 — Remake swap signature**

```sh
mkswap /dev/disk/by-partlabel/disk-main-swap
```

- [ ] **Step 4.5 — Import the pool and expand into the grown partition**

```sh
zpool import -f tank                                  # -f: hostid mismatch under ISO is expected
zpool list tank                                       # EXPANDSZ should show ~120G available
zpool status -P tank | grep by-label                  # confirm vdev path /dev/disk/by-label/tank
zpool online -e tank /dev/disk/by-label/tank          # MUST use the by-label path (cache gotcha)
zpool list tank                                       # SIZE now ~119G (was 55.5G)
```
Expected: `tank` SIZE grows from 55.5G to ~119G. (`online -e tank /dev/vda2` or `…by-partlabel/…` will fail with "couldn't find device in pool" — only the by-label path works.)

**GATE:** Pool is ~119 G, ONLINE, no errors (`zpool status tank`). Datasets intact (`zfs list` shows `tank/{root,nix}` with their data).

---

## Phase 5 — Create and populate `tank/home`

Done from the ISO (services stopped → consistent copy). Source = `/persistence/home/<user>` (the authoritative persisted data). **Skip `monicahung`** (user removed in `27e363d`; its `/persistence/home/monicahung` is now orphaned and stays on `/persistence`).

- [ ] **Step 5.1 — Create the dataset and mount it + persistence (read-only)**

```sh
zfs create -o mountpoint=legacy tank/home
mkdir -p /mnt/home /mnt/persistence
mount -t zfs tank/home /mnt/home
mount -o ro /dev/disk/by-partlabel/persistence /mnt/persistence
ls /mnt/persistence/home    # expect: bot  cjlarose  monicahung
```

- [ ] **Step 5.2 — Copy `bot` (uid 1001) and `cjlarose` (uid 1000) homes**

```sh
cp -a /mnt/persistence/home/bot       /mnt/home/bot
cp -a /mnt/persistence/home/cjlarose  /mnt/home/cjlarose
# Drop stale agent sockets (not valid across reboot)
rm -f /mnt/home/cjlarose/.ssh/agent /mnt/home/cjlarose/.ssh/ssh_auth_sock
```

- [ ] **Step 5.3 — Fix ownership (numeric, since the ISO lacks these users)**

```sh
chown -R 1001:100 /mnt/home/bot        # bot (gid users=100)
chown -R 1000:100 /mnt/home/cjlarose   # cjlarose
```

- [ ] **Step 5.4 — Verify and unmount**

```sh
ls -la /mnt/home/bot /mnt/home/cjlarose
du -sh /mnt/home/*                      # expect ~1.7G bot, ~1.2G cjlarose
test -f /mnt/home/cjlarose/.ssh/id_ed25519 && echo "cjlarose key OK"
test -d /mnt/home/cjlarose/gc-roots && echo "gc-roots OK"
umount /mnt/home /mnt/persistence
```

**GATE:** `tank/home` populated with both homes, correct ownership, cjlarose's `.ssh/id_ed25519` and `gc-roots` present.

---

## Phase 6 — Reboot into the existing (25.11) generation

The host is **preserved**, not reinstalled — it still boots its current generation. The expanded pool imports normally (`forceImportRoot=true` handles the hostid); `tank/home` just sits unmounted under the old config (harmless).

- [ ] **Step 6.1 — Detach ISO, restore boot order**

```sh
ssh root@pve.toothyshouse.com 'qm set 117 --boot order=virtio0; qm set 117 --delete ide2'
```

- [ ] **Step 6.2 — Reboot (from the ISO console: `reboot`)** and wait for bots to come back.

- [ ] **Step 6.3 — Verify the grown pool + healthy old system**

```sh
ssh cjlarose@bots.toothyshouse.com '
  zpool list tank                       # ~119G
  zfs list                              # tank/{root,nix,home}; home unmounted on old gen
  systemctl is-system-running           # running (or degraded — check failed units)
  systemctl is-active postgresql        # active
  sudo -u postgres psql -c "\l" | head  # DB reachable
'
```
**GATE:** Pool ~119 G, postgres up and serving, PCE services healthy (or intentionally still stopped from 3.1 — start them if verifying: `sudo systemctl start postgresql pce-rails pce-discord-bot`). System is back to a known-good 25.11 state with a bigger pool.

---

## Phase 7 — Deploy the 26.05 generation (bootstrap = build on bots)

**Why build on bots, not push-deploy, for *this* deploy:** push-deploy (`nixos-rebuild --target-host`) copies the closure as `cjlarose`, but on the **current** 25.11 config cjlarose is **not** a nix `trusted-user`, so the daemon rejects the unsigned closure (the same signature wall documented for cache). The new config *adds* `trusted-users = [cjlarose]`, but it isn't active yet — chicken-and-egg. So the **first** deploy is a local build on bots; once it activates, push-deploy works for all future deploys.

- [ ] **Step 7.1 — Get the branch onto bots**

Preferred: push the branch and fetch it in cjlarose's checkout on bots.

```sh
# from the worktree (deploy host):
cd ~/worktrees/cjlarose/nix-configurations/bots-26-05-upgrade && git push -u origin bots-26-05-upgrade
# on bots (in cjlarose's nix-configurations checkout; create one if absent):
ssh cjlarose@bots.toothyshouse.com 'cd ~/workspace/cjlarose/nix-configurations 2>/dev/null && git fetch origin && git checkout bots-26-05-upgrade && git reset --hard origin/bots-26-05-upgrade'
```
Fallback (if bots' key isn't GitHub-authorized): `git bundle create /tmp/bots.bundle bots-26-05-upgrade`, `scp` to bots, `git fetch /tmp/bots.bundle bots-26-05-upgrade && git reset --hard FETCH_HEAD` (see [[Cache Host Disk Restructure]]).

- [ ] **Step 7.2 — Build + set as boot generation on bots (mode `boot`, not `switch`)**

`boot` not `switch` because the new `/home` mount (tank/home) and kernel 6.18 only take effect on reboot; switching live would yank `/home` out from under running sessions.

```sh
ssh cjlarose@bots.toothyshouse.com 'cd ~/workspace/cjlarose/nix-configurations && sudo nixos-rebuild boot --flake .#bots'
```
Expected: builds (pce rails app rebuilds against 26.05 ruby; bulk substitutes from cache.nixos.org + nixcache), installs bootloader entry for `…bots-26.05…`. Watch for "no space" — should be impossible now with the grown pool.

- [ ] **Step 7.3 — Reboot into 26.05**

```sh
ssh cjlarose@bots.toothyshouse.com 'sudo reboot' || true
```

---

## Phase 8 — Post-upgrade verification

- [ ] **Step 8.1 — System + storage**

```sh
ssh cjlarose@bots.toothyshouse.com '
  nixos-version                         # 26.05…
  uname -r                              # 6.18.x
  findmnt /home                         # tank/home, zfs
  findmnt /nix                          # tank/nix
  zpool list tank                       # ~119G
  systemctl is-system-running           # running
  systemctl --failed                    # none (dbus-broker exit-4 at switch time is benign)
'
```

- [ ] **Step 8.2 — PCE services + DB + web**

```sh
ssh cjlarose@bots.toothyshouse.com '
  systemctl is-active postgresql pce-rails pce-discord-bot pce-worker
  sudo -u postgres psql -c "\l" | head
'
curl -sS -o /dev/null -w "%{http_code}\n" https://pixelcatsend.toothyshouse.com   # expect 200/redirect
```

- [ ] **Step 8.3 — Home content survived**

```sh
ssh cjlarose@bots.toothyshouse.com 'ls -la /home/bot /home/cjlarose; test -f /home/cjlarose/.ssh/id_ed25519 && echo KEY_OK; test -d /home/bot/.config/chromium && echo CHROMIUM_OK'
```

- [ ] **Step 8.4 — Confirm push-deploy now works (the original goal)**

From the deploy host, a no-op push-deploy should succeed now that `trusted-users` includes cjlarose:

```sh
cd ~/worktrees/cjlarose/nix-configurations/bots-26-05-upgrade
nixos-rebuild test --flake .#bots --target-host cjlarose@bots.toothyshouse.com --use-remote-sudo
```
Expected: closure copies without a signature-wall error and activates as a no-op. **This proves bots is now push-deployable for future changes.**

---

## Phase 9 — Cleanup & follow-ups

- [ ] **Step 9.1 — Merge the branch** once bots is stable (open PR or fast-forward `main`), per `superpowers:finishing-a-development-branch`.
- [ ] **Step 9.2 — Orphaned data on `/persistence`:** `/persistence/home/monicahung` (49M) and the old per-dir `bot`/`cjlarose` trees are now unused (home lives on `tank/home`). Leave for a few days, then `sudo rm -rf` after confirming stability.
- [ ] **Step 9.3 — Delete off-host backups** (`~/bots-migration-backup/*`) after bots runs clean for several days.
- [ ] **Step 9.4 — Optional hardening / cleanup** (separate commits, not blockers):
  - `boot.zfs.forceImportRoot = false;` in `bots/disk-config.nix` (matches ns1010301 `cfc6a4e`; future-proofs the 26.11 default flip — safe: hostId pinned, single-tenant). See [[ZFS forceImportRoot]].
  - `pkgs.xorg.xauth` → `pkgs.xauth` (2 refs in `bots/configuration.nix`: systemPackages + the tigervnc service) to clear the 26.05 deprecation alias.
- [ ] **Step 9.5 — Capture to wiki:** update [[bots]] (storage/home), [[NixOS 26.05 Fleet Upgrade]] (bots done; 8 hosts remain), and note the push-deploy bootstrap.

---

## Risks & rollback

| Risk | Mitigation / rollback |
|---|---|
| Wrong vda2 start sector | HARD GATE 4.3 — verify `1026048` before import; abort if mismatch. |
| Pool won't import after surgery | The pre-surgery pool was unchanged on disk except partition end; re-check start sector. Worst case, `/persistence` (postgres + keys) is intact on untouched `vdb`; could reprovision vda fresh and restore. |
| postgres data loss | `vdb`/`/persistence` is never touched by surgery; plus off-host `pg_dumpall` (1.1) and tar (1.2). |
| 26.05 generation won't boot | Old 25.11 generation remains in the bootloader; select it in the PVE console to roll back (tank/home sitting unmounted is harmless to the old gen). |
| pce build too slow on the Atom | One-time; bulk substitutes from upstream. If unacceptable, build on a fast x86_64-linux host and seed via the cache (requires cjlarose trusted on cache — separate setup). |

## Cross-references

- [[Cache Host Disk Restructure]] — the playbook this mirrors
- [[Growing a ZFS Pool In-Place]] — the surgery procedure + gotchas
- [[NixOS 26.05 Upgrade Breakages]] — the initrd/cascade fixes
- [[bots]], [[pve]] — the host and hypervisor
