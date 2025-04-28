{ nixpkgs, sharedOverlays, stateVersion, system, ... }: { pkgs, config, ... }: {
  imports = [
    ./hardware-configuration.nix
  ];

  networking = {
    hostName = "immich";
    hostId = "1467d75a";
    firewall = {
      enable = true;
      allowedTCPPorts = [ 80 443 ];
    };
  };

  system.stateVersion = stateVersion;

  nix = {
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    registry.nixpkgs.flake = nixpkgs;
    nixPath = [ "nixpkgs=${nixpkgs.outPath}" ];
    settings = {
      substituters = [
        "https://nixcache.toothyshouse.com"
      ];
      trusted-public-keys = [
        "nixcache.toothyshouse.com:kAyteiBuGtyLHPkrYNjDY8G5nNT/LHYgClgTwyVCnNQ="
      ];
    };
  };

  nixpkgs.overlays = sharedOverlays;

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    iotop
    lsof
  ];

  security.acme = {
    acceptTerms = true;
    defaults.email = "cjlarose@gmail.com";
    certs = {
      "immich.toothyshouse.com" = {
        dnsPropagationCheck = false;
        dnsProvider = "digitalocean";
        dnsResolver = "1.1.1.1:53";
        domain = "immich.toothyshouse.com";
        environmentFile = "/persistence/acme/digitalocean.secret";
      };
    };
  };

  services.immich = {
    enable = true;
  };

  services.nginx = {
    enable = true;
    virtualHosts = {
      "immich.toothyshouse.com" = {
        enableACME = true;
        acmeRoot = null;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://[::1]:${toString config.services.immich.port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
          extraConfig = ''
            client_max_body_size 50000M;
            proxy_read_timeout   600s;
            proxy_send_timeout   600s;
            send_timeout         600s;
          '';
        };
      };
    };
  };

  services.openssh = {
    enable = true;
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

  services.restic.backups = {
    backblaze = {
      initialize = true;

      timerConfig = {
        OnCalendar = "02:00 America/Los_Angeles";
        Persistent = true;
      };

      environmentFile = "/persistence/restic/backblaze/env";
      repositoryFile = "/persistence/restic/backblaze/repo";
      passwordFile = "/persistence/restic/backblaze/password";

      paths = [
        "/persistence/immich-sql-dumps"
        "/var/lib/immich"
      ];

      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
      ];

      backupPrepareCommand = ''
        mkdir -p /persistence/immich-sql-dumps
        chown ${config.users.users.postgres.name}:${config.users.users.postgres.group} /persistence/immich-sql-dumps
        current_date=$(date +%Y-%m-%d)
        file_name="/persistence/immich-sql-dumps/immich-$current_date.sql"
        /run/wrappers/bin/su - postgres -c "pg_dumpall --clean --if-exists > $file_name"
      '';
    };
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    port = 41643;
  };

  services.zfs.expandOnBoot = "all";

  programs.ssh.startAgent = true;

  programs.zsh.enable = true;

  users.mutableUsers = false;

  users.users = {
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
}
