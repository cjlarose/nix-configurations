{ nixpkgs, sharedOverlays, stateVersion, system, additionalPackages, ... }: { pkgs, config, lib, ... }: {
  imports = [
    ./hardware-configuration.nix
  ];

  networking = {
    hostName = "ns1010301";
    hostId = "eae273e3";
    firewall = {
      enable = true;
      interfaces."enp1s0f0" = {
        allowedTCPPorts = [
          80     # nginx for minecraft.mellowcatfe.com
          443    # nginx for minecraft.mellowcatfe.com
          8443   # nginx proxy for pt-docker-cjlarose guest
          25565  # minecraft for minecraft-mellowcatfe guest
        ];
        allowedUDPPorts = [
          41642  # tailscale for pt-docker-cjlarose guest
          41643  # tailscale for minecraft-mellowcatfe guest
          41644  # tailscale for media guest
        ];
      };
      interfaces."microvm".allowedUDPPorts = [
        67  # DHCP server for microvm bridge (bridge interface only)
      ];
    };
    nat = {
      enable = true;
      externalInterface = "enp1s0f0";
      internalInterfaces = [ "microvm" ];
      forwardPorts = [
        {
          destination = "10.0.0.2:41642";
          proto = "udp";
          sourcePort = 41642;
        }
        {
          destination = "10.0.0.2:8443";
          proto = "tcp";
          sourcePort = 8443;
        }
        {
          destination = "10.0.0.3:25565";
          proto = "tcp";
          sourcePort = 25565;
        }
        {
          destination = "10.0.0.3:41643";
          proto = "udp";
          sourcePort = 41643;
        }
        {
          destination = "10.0.0.4:41644";
          proto = "udp";
          sourcePort = 41644;
        }
      ];
    };
  };

  systemd.network.enable = true;

  # Bridge for microvm guests
  systemd.network.netdevs."10-microvm".netdevConfig = {
    Kind = "bridge";
    Name = "microvm";
  };

  systemd.network.networks."10-microvm" = {
    matchConfig.Name = "microvm";
    networkConfig = {
      DHCPServer = true;
      IPv6SendRA = true;
    };
    addresses = [{
      Address = "10.0.0.1/24";
    }];
  };

  # Attach all VM TAP interfaces to the bridge
  systemd.network.networks."11-microvm" = {
    matchConfig.Name = "vm-*";
    networkConfig.Bridge = "microvm";
  };

  # No ports are forwarded — all guest services are accessed via SSH tunnel:
  # ssh -L 8443:10.0.0.2:8443 -L 9000:10.0.0.2:9000 -L 2376:10.0.0.2:2376 cjlarose@ns1010301.cjlarose.dev

  boot.kernelParams = [ "console=ttyS1,115200" ];
  systemd.services."serial-getty@ttyS1".enable = true;

  system.stateVersion = stateVersion;

  nix = {
    registry.nixpkgs.flake = nixpkgs;
  };

  nixpkgs.overlays = sharedOverlays;

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    iotop
    lsof
  ];

  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
    hostKeys = [
      {
        path = "/persistence/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/persistence/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    port = 41641;
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "cjlarose@gmail.com";
  };

  services.nginx = {
    enable = true;
    virtualHosts = {
      "minecraft.mellowcatfe.com" = {
        enableACME = true;
        forceSSL = true;
        root = "${additionalPackages.${system}.minecraft-mods-zip}";
      };
    };
  };

  fileSystems."/var/lib/microvms/pt-docker-cjlarose/acme" = {
    device = "tank/microvms/pt-docker-cjlarose/acme";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/pt-docker-cjlarose/ssh" = {
    device = "tank/microvms/pt-docker-cjlarose/ssh";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/pt-docker-cjlarose/home" = {
    device = "tank/microvms/pt-docker-cjlarose/home";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/pt-docker-cjlarose/secrets" = {
    device = "tank/microvms/pt-docker-cjlarose/secrets";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/pt-docker-cjlarose/tailscale" = {
    device = "tank/microvms/pt-docker-cjlarose/tailscale";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/pt-docker-cjlarose/nix-rw-store" = {
    device = "tank/microvms/pt-docker-cjlarose/nix-rw-store";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/minecraft-mellowcatfe/minecraft" = {
    device = "tank/microvms/minecraft-mellowcatfe/minecraft";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/minecraft-mellowcatfe/ssh" = {
    device = "tank/microvms/minecraft-mellowcatfe/ssh";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/minecraft-mellowcatfe/tailscale" = {
    device = "tank/microvms/minecraft-mellowcatfe/tailscale";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/minecraft-mellowcatfe/nix-rw-store" = {
    device = "tank/microvms/minecraft-mellowcatfe/nix-rw-store";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/minecraft-mellowcatfe/home" = {
    device = "tank/microvms/minecraft-mellowcatfe/home";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/minecraft-mellowcatfe/secrets" = {
    device = "tank/microvms/minecraft-mellowcatfe/secrets";
    fsType = "zfs";
  };

  fileSystems."/var/lib/microvms/media/nix-rw-store" = {
    device = "tank/microvms/media/nix-rw-store";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/media/ssh" = {
    device = "tank/microvms/media/ssh";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/media/home" = {
    device = "tank/microvms/media/home";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/media/tailscale" = {
    device = "tank/microvms/media/tailscale";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/media/secrets" = {
    device = "tank/microvms/media/secrets";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/media/acme" = {
    device = "tank/microvms/media/acme";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/media/jellyfin" = {
    device = "tank/microvms/media/jellyfin";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/media/media" = {
    device = "tank/microvms/media/media";
    fsType = "zfs";
  };

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
        # Clean up stale snapshot from a previous failed run
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

  # PrivateTmp creates a private mount namespace, which prevents the
  # ZFS snapshot mount in backupPrepareCommand from being visible to
  # the restic backup process in ExecStart.
  systemd.services.restic-backups-minecraft-mellowcatfe.serviceConfig.PrivateTmp = lib.mkForce false;

  services.openiscsi = {
    enable = true;
    name = "iqn.2026-04.dev.cjlarose:ns1010301";
  };

  services.zfs.expandOnBoot = "all";

  programs.ssh.startAgent = true;

  programs.zsh.enable = true;

  users = {
    mutableUsers = false;
    users = {
      cjlarose = {
        uid = 1000;
        isNormalUser = true;
        home = "/home/cjlarose";
        extraGroups = [ "wheel" ];
        shell = pkgs.zsh;
        hashedPassword = "$6$YLrfXTwu61JGE.v8$kR5ZdMso2lcnyy7s7GXkIb.kLDyQ2UW3aDyGerQYni96g2kPC1MIY48Y9Q3SdYe2ycuVCrKgH6DlOjUUsK02s0";
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFtA/9w60OssA+Eji+Ygvd1XCJk/zw/uYLdiiaevELu cjlarose"
        ];
      };
    };
  };
}
