# DNS VM Disk Restructure + 26.05 Upgrade — Design

**Date:** 2026-06-23
**Host:** `dns` — Proxmox VM **116** on `pve` (montero-iSCSI-backed)
**Repo:** `cjlarose/nix-configurations`, work on `main`, push-deployed from ns1010301
**Status:** approved approach, pending implementation plan

## Goal

Bring the `dns` VM in line with the storage convention already applied to
`bots` and `cache`: a dedicated persistent `tank/home` ZFS dataset replacing
per-directory home impermanence, the `~/workspace/$user/$repo` →
`~/worktrees/$user/$repo/default` checkout migration, and a NixOS 25.11 → 26.05
upgrade — all in a single push-deploy + one reboot, preserving the warm nix
store.

## Context: how DNS differs from the bots/cache playbook

This mirrors [[bots NixOS 26.05 Upgrade and Disk Restructure]] and
[[Cache Host Disk Restructure]], but is materially **lighter** because three of
their cost drivers do not apply:

1. **No pool grow.** `tank` is 55.5 G, 53% used, **25.6 G free**. cache/bots
   booted the 26.05 ISO and ran `sgdisk`/`zpool online -e` *only* to grow a
   near-full pool. A 26.05 closure fits on DNS as-is, so there is **no
   partition surgery and no ISO boot**. Adding `tank/home` to an existing,
   imported pool is a live online `zfs create` — the pool never needs exporting.
   (Per [[Cache Host Disk Restructure]], a disko block is *inert* unless disko
   runs; the dataset is created by hand and `disk-config.nix` merely declares
   the accurate truth.)

2. **Push-deploy already bootstrapped.** Commit `4a8b975` already added
   `trusted-users = [ "root" "cjlarose" ]` and the `cjlarose@ns1010301` SSH key
   to DNS. Unlike bots (which needed a bootstrap 25.11 rebuild first), DNS can
   receive a pushed closure now. See
   [[Push-Deploy NixOS Closures from a Strong Host]].

3. **Three of the four cache/bots 26.05 blockers do not apply.**
   - No-AVX claude-code: already handled via `claudeUseNodeRuntime = true`.
   - No tailscale on DNS → no tailnet identity churn.
   - No postgres on DNS → no glibc collation reindex.
   The one 26.05 change that *does* bite: 26.05 defaults to systemd stage-1
   initrd, which **silently ignores** the current scripted
   `boot.initrd.postDeviceCommands` rollback. It must become the systemd-initrd
   `rollback-root` oneshot (the pattern from
   [[Cache Host NixOS 26.05 Upgrade]] / [[ns1010301 ZFS Block Cloning Boot Deadlock]]).

## Current state (verified on the live host)

- NixOS **25.11** (flake pins `nixpkgs-25-11`, `stateVersion = "23.11"`).
- `tank` datasets: `tank/root` (`/`, rolled back to `@blank` each boot) and
  `tank/nix` (`/nix`). **No `tank/home`.**
- `/home/cjlarose` lives on the ephemeral `tank/root`. Only `~/.ssh` and
  `~/workspace` survive reboots, bind-mounted from `/persistence` (ext4 on vdb)
  via per-dir impermanence (`default.nix` → `users.cjlarose.directories = [".ssh", "workspace"]`).
- Home content of note: `~/workspace/cjlarose/nix-configurations` (~11 M, a
  **stale** single clone — still contains long-removed hosts: `memos`, `coder`,
  `unifi`, `palworld`, `builder`, `monicahung`, darwin configs). Everything else
  in home is HM-generated and ephemeral.
- `/persistence` (vdb1) source dir `/persistence/home/cjlarose/` holds: `.ssh`,
  `gc-roots`, `workspace`.
- VM 116: `virtio0` 64 G (vda: ESP 500 M / `tank` zfs `end=-8G` / 8 G swap) on
  `montero-vm-filesystem-roots-thin`; `virtio1` 64 G iSCSI (`montero-dns-persistence-16k`)
  = ext4 `/persistence`. **vdb is never touched.**
- Pre-existing nit: `hardware-configuration.nix` sets `swapDevices = [ ]` even
  though vda3 is an 8 G swap partition — swap is currently unused.

## Approach (approved): live in-place + push-deploy + one reboot

No ISO. No pool export. The pool stays imported the whole time; `tank/home` is
created live alongside the running system, populated, then mounted at `/home` by
the new 26.05 generation on the single reboot.

### Phase A — Safety backup

`cp -a`/tar read-only `/persistence` off-host to ns1010301
(`~/dns-migration-backup/`). Belt-and-suspenders only; vdb is untouched by this
procedure. Verify SSH host keys present in the tarball.

### Phase B — Config changes (committed on `main`, push-deploy source)

- **`nixos-configurations/default.nix`:** dns → `nixpkgs-26-05` /
  `home-manager-26-05`; pass `disko` (already passed). `stateVersion` stays `23.11`.
- **`nixos-configurations/dns/disk-config.nix`:**
  - Replace the scripted `boot.initrd.postDeviceCommands` ZFS rollback with a
    systemd-initrd `rollback-root` oneshot (`wantedBy = [ "initrd.target" ]`,
    `after = [ "zfs-import-tank.service" ]`, `before = [ "sysroot.mount" ]`,
    `Type = oneshot`, `zfs rollback -r tank/root@blank`).
  - Add the `home` dataset: `tank/home`, `type = zfs_fs`, `mountpoint = "/home"`,
    `options.mountpoint = "legacy"`.
  - Add `boot.zfs.forceImportRoot = false` (matches the fleet; safe — hostId
    pinned, single-tenant; the 26.11 default, see [[ZFS forceImportRoot]]).
  - Drop the now-inaccurate `imageSize` / `memSize` disko image-build params for
    consistency with the bots/cache host-specific disk-configs (inert either way).
- **`nixos-configurations/dns/hardware-configuration.nix`:**
  - Add `fileSystems."/home" = { device = "tank/home"; fsType = "zfs"; };`
  - Enable the existing swap partition:
    `swapDevices = [ { device = "/dev/disk/by-partlabel/disk-main-swap"; } ];`
    (consistency with bots/cache; fixes the standing nit).
- **`nixos-configurations/dns/default.nix`:** delete the
  `environment.persistence."/persistence".users.cjlarose` block (home is now the
  persistent `tank/home` dataset). Keep the system-level `/etc/nixos`
  persistence. (SSH stays safe because authorized keys are declared in NixOS via
  `users.users.cjlarose.openssh.authorizedKeys.keys`, not sourced from the
  persisted `.ssh` — same reasoning as [[Cache Host Disk Restructure]].)

Validate by building the dns closure on ns1010301
(`nix build .#nixosConfigurations.dns.config.system.build.toplevel`). New
`disk-config.nix` content is already tracked, but any newly-created file must be
`git add`-ed before the flake will see it.

### Phase C — Create + populate `tank/home` (live, on DNS, still 25.11)

`rsync` is not in the 25.11 host's default packages; run it via
`nix shell nixpkgs#rsync -c rsync …` (nix is available on the host). Use
`-aHAX` for full attribute/xattr fidelity; rsync is restartable if interrupted.

**The dataset mounts at `/home`, so the user's home is `/home/cjlarose`. Populate under a `cjlarose/` subdirectory, NOT at the dataset root** — otherwise the new generation boots with `/home/.ssh` but no `/home/cjlarose`, and `home-manager-cjlarose.service` fails (`cd: /home/cjlarose: No such file or directory`).

```
zfs create -o mountpoint=legacy tank/home
mount -t zfs tank/home /mnt              # temporary
mkdir -p /mnt/cjlarose                   # the user's home dir within the dataset
nix shell nixpkgs#rsync -c sh -c '
  rsync -aHAX /persistence/home/cjlarose/.ssh     /mnt/cjlarose/
  rsync -aHAX /persistence/home/cjlarose/gc-roots /mnt/cjlarose/   # keep path stable for /nix gcroots
  mkdir -p /mnt/cjlarose/worktrees/cjlarose/nix-configurations
  rsync -aHAX /persistence/home/cjlarose/workspace/cjlarose/nix-configurations/ \
              /mnt/cjlarose/worktrees/cjlarose/nix-configurations/default/
'
chown -R 1000:100 /mnt/cjlarose
chmod 700 /mnt/cjlarose
umount /mnt
```

`rsync` (not `mv`) keeps the `/persistence` source intact, preserving the
"vdb never written" invariant; the stale `workspace` copy on vdb is simply
orphaned once impermanence stops mounting it. Note the trailing slash on the
`nix-configurations/` source so its *contents* land in the `default/` worktree.

`tank/home` lives in pool state, so it survives the `tank/root@blank` rollback
on reboot. Drop any stale agent sockets. The stale `nix-configurations` checkout
is carried over as-is (its `origin` still resolves); a `git fetch` afterward
reconciles it — no need to re-clone.

### Phase D — Deploy + single reboot

Per [[Push-Deploy NixOS Closures from a Strong Host]]:

```
# on ns1010301
nix build .#nixosConfigurations.dns.config.system.build.toplevel \
  --print-out-paths --no-link
nix copy --to ssh-ng://cjlarose@192.168.2.104 --no-check-sigs <toplevel>
# on dns
sudo nix-env -p /nix/var/nix/profiles/system --set <toplevel>
sudo <toplevel>/bin/switch-to-configuration boot
sudo reboot
```

`boot` not `switch` because the new kernel and the `/home` → `tank/home` mount
only take effect on reboot. Use the agent-free `cjlarose@ns1010301` key
(`SSH_AUTH_SOCK= ssh …` / `NIX_SSHOPTS`) to avoid the 1Password agent lock issue.

### Phase E — Verify

- `nixos-version` → 26.05; kernel 6.18.35.
- `zfs list` shows `tank/{root,nix,home}`; `mount` shows `/home` = `tank/home`
  with `.ssh`, `gc-roots`, `worktrees/cjlarose/nix-configurations/default`, **no
  `workspace`**, no `/home/cjlarose/{.ssh,workspace}` ext4 bind mounts.
- `systemctl is-system-running` = `running`, zero failed units; journal shows
  the `rollback-root` oneshot completed.
- DNS service health: AdGuard listening on `192.168.2.104:53`, dnsmasq on
  `192.168.2.105:53`, an intranet host resolves through dnsmasq, an external name
  resolves through AdGuard's DoH upstream.
- swap active (`swapon --show`).
- `nixos-rebuild build --flake .#dns` from the canonical ns1010301 checkout is a
  clean no-op against the deployed generation.

## Rollback / risk

- **Outage:** a single ~1–2 min reboot is the only downtime — a brief LAN-wide
  DNS pause. Schedule off-hours.
- **If the 26.05 generation fails to boot:** the previous 25.11 generation is
  still present in the bootloader (the host is upgraded in place, never wiped);
  select it to recover. `tank/home` sitting unmounted under the old generation is
  harmless.
- **vdb / `/persistence` is never written** by the procedure (SSH host keys,
  `/etc/nixos`); the Phase-A tarball is pure insurance.
- Keep the off-host `/persistence` backup until DNS runs clean for a few days,
  then delete.

## Out of scope

- No pool grow (not needed).
- No reinstall (store preserved).
- No changes to AdGuard/dnsmasq service config or the intranet-hosts pin.

## Cross-references

- [[bots NixOS 26.05 Upgrade and Disk Restructure]] — closest analog (restructure + 26.05 + push-deploy)
- [[Cache Host Disk Restructure]] — the `tank/home` / disk-config pattern; disko-inert insight
- [[Cache Host NixOS 26.05 Upgrade]] — the systemd-initrd `rollback-root` conversion
- [[Push-Deploy NixOS Closures from a Strong Host]] — the deploy model
- [[ZFS forceImportRoot]] — the import-safety flag
- [[NixOS 26.05 Upgrade Breakages]] — the shared eval/activation cascade
