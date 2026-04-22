# Minecraft Backblaze B2 Backup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically back up the minecraft-mellowcatfe world data to Backblaze B2 daily using ZFS snapshots for consistency and restic for transport/dedup/encryption.

**Architecture:** A daily systemd timer on the ns1010301 host uses mcrcon to safely quiesce the Minecraft server (save-off), takes a ZFS snapshot of the minecraft dataset, backs up the snapshot to B2 via restic, re-enables saves, and prunes old ZFS snapshots beyond 30 days. RCON credentials are stored in a new `secrets` ZFS dataset shared to the guest via virtiofs. The nix-minecraft `environmentFile` option and `@VAR@` substitution inject the RCON password into `server.properties` at runtime.

**Tech Stack:** NixOS, ZFS, restic, Backblaze B2, mcrcon, nix-minecraft, microvm/virtiofs

---

## File Structure

- **Modify:** `nixos-configurations/ns1010301/configuration.nix` — add secrets ZFS dataset mount, restic backup job with mcrcon + ZFS snapshot lifecycle
- **Modify:** `nixos-configurations/ns1010301/default.nix` — persist restic cache directory across reboots
- **Modify:** `nixos-configurations/minecraft-mellowcatfe/default.nix` — add secrets virtiofs share to guest
- **Modify:** `nixos-configurations/minecraft-mellowcatfe/configuration.nix` — enable RCON with `@RCON_PASSWORD@` placeholder, set environmentFile

---

### Task 1: Add secrets ZFS dataset and virtiofs share

**Files:**
- Modify: `nixos-configurations/ns1010301/configuration.nix:170-173`
- Modify: `nixos-configurations/minecraft-mellowcatfe/default.nix:52-58`

- [ ] **Step 1: Add the secrets dataset mount on the host**

In `nixos-configurations/ns1010301/configuration.nix`, after the `minecraft-mellowcatfe/home` fileSystems entry (line 170-173), add:

```nix
  fileSystems."/var/lib/microvms/minecraft-mellowcatfe/secrets" = {
    device = "tank/microvms/minecraft-mellowcatfe/secrets";
    fsType = "zfs";
  };
```

- [ ] **Step 2: Add the secrets virtiofs share to the guest**

In `nixos-configurations/minecraft-mellowcatfe/default.nix`, add a new entry to the `microvm.shares` list, after the `persist-tailscale` entry:

```nix
    {
      tag = "persist-secrets";
      source = "secrets";
      mountPoint = "/persistence/secrets";
      proto = "virtiofs";
    }
```

- [ ] **Step 3: Commit**

```bash
git add nixos-configurations/ns1010301/configuration.nix nixos-configurations/minecraft-mellowcatfe/default.nix
git commit -m "Add secrets ZFS dataset and virtiofs share for minecraft-mellowcatfe"
```

---

### Task 2: Enable RCON on the Minecraft server with secret injection

**Files:**
- Modify: `nixos-configurations/minecraft-mellowcatfe/configuration.nix:70-118`

The nix-minecraft module supports `@VAR@` substitution in generated files using environment variables loaded from `environmentFile`. We use this to inject the RCON password at runtime from a file on the secrets dataset, keeping it out of the nix store.

- [ ] **Step 1: Set the environmentFile for minecraft-servers**

In `nixos-configurations/minecraft-mellowcatfe/configuration.nix`, add `environmentFile` to `services.minecraft-servers`:

```nix
  services.minecraft-servers = {
    enable = true;
    eula = true;
    environmentFile = "/persistence/secrets/minecraft-env";
```

- [ ] **Step 2: Open RCON port in the guest firewall**

In `nixos-configurations/minecraft-mellowcatfe/configuration.nix`, add port 25575 to `allowedTCPPorts`:

```nix
      allowedTCPPorts = [
        25565 # minecraft
        25575 # rcon
      ];
```

- [ ] **Step 3: Add RCON properties to serverProperties**

In the `serverProperties` attrset within `servers.mellowcatfe`, add these three lines after `max-tick-time = -1;`:

```nix
        enable-rcon = true;
        "rcon.port" = 25575;
        "rcon.password" = "@RCON_PASSWORD@";
```

The `@RCON_PASSWORD@` placeholder is substituted at service start time by nix-minecraft's awk-based `ExecStartPre` script using the environment variable from the file.

- [ ] **Step 4: Commit**

```bash
git add nixos-configurations/minecraft-mellowcatfe/configuration.nix
git commit -m "Enable RCON on minecraft-mellowcatfe with runtime secret injection"
```

---

### Task 3: Create secrets, deploy, and verify RCON connectivity

This task must be performed on ns1010301. It validates that Tasks 1 and 2 work end-to-end before adding the restic backup job.

- [ ] **Step 1: Create the secrets ZFS dataset (if it doesn't exist)**

```bash
sudo zfs list tank/microvms/minecraft-mellowcatfe/secrets 2>/dev/null || sudo zfs create tank/microvms/minecraft-mellowcatfe/secrets
sudo zfs set mountpoint=legacy acltype=posix tank/microvms/minecraft-mellowcatfe/secrets
```

- [ ] **Step 2: Generate the RCON password and write the environment file (if it doesn't exist)**

```bash
if [ ! -f /var/lib/microvms/minecraft-mellowcatfe/secrets/minecraft-env ]; then
  RCON_PASSWORD=$(nix shell nixpkgs#openssl -c openssl rand -hex 16)
  echo "RCON_PASSWORD=$RCON_PASSWORD" | sudo tee /var/lib/microvms/minecraft-mellowcatfe/secrets/minecraft-env
  sudo chmod 600 /var/lib/microvms/minecraft-mellowcatfe/secrets/minecraft-env
  echo "Generated RCON password: $RCON_PASSWORD"
else
  echo "minecraft-env already exists, skipping"
fi
```

- [ ] **Step 3: Deploy the NixOS configuration for both host and guest**

The host needs the new secrets filesystem mount, and the guest needs the virtiofs share and RCON config.

```bash
sudo nixos-rebuild switch --flake .#ns1010301
```

- [ ] **Step 4: Verify RCON connectivity from the host**

After the minecraft server has restarted, test RCON from the host using mcrcon. Install it temporarily if needed:

```bash
RCON_PASSWORD=$(sudo grep -oP 'RCON_PASSWORD=\K.*' /var/lib/microvms/minecraft-mellowcatfe/secrets/minecraft-env)
nix-shell -p mcrcon --run "mcrcon -H 10.0.0.3 -p $RCON_PASSWORD list"
```

Expected: a response like `There are 0 of a max of 20 players online:` (or similar with current player count). If the connection is refused, check that the minecraft server is running and that `server.properties` inside the guest contains the real RCON password (not the `@RCON_PASSWORD@` placeholder).

---

### Task 4: Add restic backup job with ZFS snapshot lifecycle

**Files:**
- Modify: `nixos-configurations/ns1010301/configuration.nix:175`
- Modify: `nixos-configurations/ns1010301/default.nix:27-34`

- [ ] **Step 1: Add the restic backup configuration on the host**

In `nixos-configurations/ns1010301/configuration.nix`, before `services.zfs.expandOnBoot = "all";`, add:

```nix
  services.restic.backups = {
    minecraft-mellowcatfe = {
      initialize = true;

      timerConfig = {
        OnCalendar = "02:00 America/Los_Angeles";
        Persistent = true;
      };

      environmentFile = "/persistence/restic/minecraft-mellowcatfe/env";
      repositoryFile = "/persistence/restic/minecraft-mellowcatfe/repo";
      passwordFile = "/persistence/restic/minecraft-mellowcatfe/password";

      paths = [
        "/mnt/minecraft-mellowcatfe-backup"
      ];

      pruneOpts = [
        "--keep-daily 30"
      ];

      backupPrepareCommand = ''
        # Clean up stale snapshot/mount from a previous failed run
        ${pkgs.util-linux}/bin/umount /mnt/minecraft-mellowcatfe-backup 2>/dev/null || true
        ${pkgs.zfs}/bin/zfs destroy tank/microvms/minecraft-mellowcatfe/minecraft@restic-backup 2>/dev/null || true

        RCON_PASSWORD=$(${pkgs.gnugrep}/bin/grep -oP 'RCON_PASSWORD=\K.*' /var/lib/microvms/minecraft-mellowcatfe/secrets/minecraft-env)
        ${pkgs.mcrcon}/bin/mcrcon -H 10.0.0.3 -p "$RCON_PASSWORD" "save-all flush" "save-off"
        ${pkgs.zfs}/bin/zfs snapshot tank/microvms/minecraft-mellowcatfe/minecraft@restic-backup
        ${pkgs.coreutils}/bin/mkdir -p /mnt/minecraft-mellowcatfe-backup
        ${pkgs.util-linux}/bin/mount -t zfs tank/microvms/minecraft-mellowcatfe/minecraft@restic-backup /mnt/minecraft-mellowcatfe-backup
      '';

      backupCleanupCommand = ''
        # Always re-enable saves, even if the backup failed
        RCON_PASSWORD=$(${pkgs.gnugrep}/bin/grep -oP 'RCON_PASSWORD=\K.*' /var/lib/microvms/minecraft-mellowcatfe/secrets/minecraft-env)
        ${pkgs.mcrcon}/bin/mcrcon -H 10.0.0.3 -p "$RCON_PASSWORD" "save-on" || true

        ${pkgs.util-linux}/bin/umount /mnt/minecraft-mellowcatfe-backup 2>/dev/null || true
        DAILY_NAME="daily-$(${pkgs.coreutils}/bin/date +%Y-%m-%d)"
        ${pkgs.zfs}/bin/zfs destroy "tank/microvms/minecraft-mellowcatfe/minecraft@$DAILY_NAME" 2>/dev/null || true
        ${pkgs.zfs}/bin/zfs rename tank/microvms/minecraft-mellowcatfe/minecraft@restic-backup "tank/microvms/minecraft-mellowcatfe/minecraft@$DAILY_NAME" 2>/dev/null || true
        ${pkgs.zfs}/bin/zfs list -t snapshot -o name -H -S creation tank/microvms/minecraft-mellowcatfe/minecraft | ${pkgs.coreutils}/bin/tail -n +31 | ${pkgs.findutils}/bin/xargs -r -n 1 ${pkgs.zfs}/bin/zfs destroy
      '';
    };
  };
```

The backup flow:
1. **Prepare:** clean up stale snapshot/mount, read RCON password, tell Minecraft to flush and disable saving, take a ZFS snapshot `@restic-backup`, mount it at `/mnt/minecraft-mellowcatfe-backup`
2. **Backup:** restic backs up from `/mnt/minecraft-mellowcatfe-backup` to B2 (separate mount avoids virtiofs conflicts with `.zfs/snapshot`)
3. **Cleanup:** re-enable Minecraft saving, unmount the snapshot, rename `@restic-backup` to `@daily-YYYY-MM-DD` for local retention, prune ZFS snapshots beyond the 30 most recent

- [ ] **Step 2: Persist the restic cache directory**

In `nixos-configurations/ns1010301/default.nix`, add to the `environment.persistence."/persistence".directories` list:

```nix
            {
              directory = "/var/cache/restic-backups-minecraft-mellowcatfe";
              user = "root";
              group = "root";
              mode = "0755";
            }
```

- [ ] **Step 3: Commit**

```bash
git add nixos-configurations/ns1010301/configuration.nix nixos-configurations/ns1010301/default.nix
git commit -m "Add daily restic backup of minecraft world data to Backblaze B2"
```

---

### Task 5: Create Backblaze B2 credentials, deploy, and verify backup

These steps must be performed on ns1010301. They set up the restic credentials and validate the full backup pipeline end-to-end.

- [ ] **Step 1: Create the restic credential files for Backblaze B2**

```bash
sudo mkdir -p /persistence/restic/minecraft-mellowcatfe
echo 'B2_ACCOUNT_ID=<your-account-id>
B2_ACCOUNT_KEY=<your-account-key>' | sudo tee /persistence/restic/minecraft-mellowcatfe/env
echo 'b2:<your-bucket-name>:minecraft-mellowcatfe' | sudo tee /persistence/restic/minecraft-mellowcatfe/repo
echo '<generate-a-restic-encryption-password>' | sudo tee /persistence/restic/minecraft-mellowcatfe/password
sudo chmod 600 /persistence/restic/minecraft-mellowcatfe/{env,repo,password}
```

- [ ] **Step 2: Deploy the NixOS configuration**

```bash
sudo nixos-rebuild switch --flake .#ns1010301
```

- [ ] **Step 3: Verify the timer is registered**

```bash
systemctl list-timers | grep restic
```

Expected: a timer entry for `restic-backups-minecraft-mellowcatfe` scheduled at 02:00.

- [ ] **Step 4: Trigger a manual backup and verify**

```bash
sudo systemctl start restic-backups-minecraft-mellowcatfe.service
sudo journalctl -u restic-backups-minecraft-mellowcatfe.service -f
```

Verify the full flow completed: mcrcon save-off, ZFS snapshot created, restic backup to B2, mcrcon save-on, snapshot renamed.

Check that the `@restic-backup` snapshot was renamed to a dated snapshot:

```bash
zfs list -t snapshot -r tank/microvms/minecraft-mellowcatfe/minecraft
```

Expected: a `@daily-YYYY-MM-DD` snapshot with today's date. The temporary `@restic-backup` snapshot should not be present.
