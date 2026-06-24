{ nixpkgs, sharedOverlays, stateVersion, config, pkgs, lib, ... }: {
  imports = [
    ./hardware-configuration.nix
  ];

  networking = {
    hostName = "splitpro";
    hostId = "d202c7d5";
    firewall = {
      allowedTCPPorts = [
        80 # nginx
        443 # nginx
      ];
      interfaces = {
        podman0 = {
          allowedTCPPorts = [
            5432 # postgresql
            9000 # minio
          ];
        };
      };
    };
  };

  system.stateVersion = stateVersion;

  nix = {
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    registry.nixpkgs.flake = nixpkgs;
    nixPath = [ "nixpkgs=${nixpkgs.outPath}" ];
    gc = {
      automatic = true;
      options = "--delete-older-than 14d";
    };
    settings = {
      # Allow the operator to push closures here (push-deploy via
      # `nixos-rebuild --target-host` / `nix copy`). cjlarose already has
      # passwordless sudo, so trusting the nix user grants no additional privilege.
      trusted-users = [ "root" "cjlarose" ];
      substituters = [
        "https://nixcache.toothyshouse.com"
      ];
      trusted-public-keys = [
        "nixcache.toothyshouse.com:kAyteiBuGtyLHPkrYNjDY8G5nNT/LHYgClgTwyVCnNQ="
      ];
    };
  };

  nixpkgs.overlays = sharedOverlays;

  # minio was abandoned by upstream and is flagged insecure in nixpkgs 26.05
  # (multiple unfixed CVEs). Kept deliberately until the splitpro stack migrates
  # off it (e.g. to Garage/SeaweedFS). Predicate form so it survives version bumps.
  nixpkgs.config.allowInsecurePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "minio"
    ];

  security.sudo.wheelNeedsPassword = false;

  security.acme = {
    acceptTerms = true;
    defaults.email = "cjlarose@gmail.com";
    certs = {
      "splitpro.toothyshouse.com" = {
        dnsPropagationCheck = false;
        dnsProvider = "digitalocean";
        dnsResolver = "1.1.1.1:53";
        domain = "splitpro.toothyshouse.com";
        environmentFile = "/persistence/acme/digitalocean.secret";
      };
      "splitpro-assets.toothyshouse.com" = {
        dnsPropagationCheck = false;
        dnsProvider = "digitalocean";
        dnsResolver = "1.1.1.1:53";
        domain = "splitpro-assets.toothyshouse.com";
        environmentFile = "/persistence/acme/digitalocean.secret";
      };
    };
  };

  environment.systemPackages = with pkgs; [
    iotop
    lsof
    minio-client
  ];

  services.minio = {
    enable = true;
    configDir = "/persistence/minio/config";
    dataDir = ["/persistence/minio/data"];
  };

  services.nginx = {
    enable = true;
    virtualHosts = {
      "splitpro.toothyshouse.com" = {
        enableACME = true;
        acmeRoot = null;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:3000";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };
      "splitpro-assets.toothyshouse.com" = {
        enableACME = true;
        acmeRoot = null;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:9000";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
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

  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    authentication = ''
      # Allow any user on the local system to connect to any database with
      # any database user name using Unix-domain sockets (the default for local
      # connections).
      #
      # TYPE  DATABASE        USER            ADDRESS                 METHOD
      local   all             all                                     trust

      # Require password authentication when accessing over TCP/IP, all addresses
      #
      # TYPE  DATABASE        USER            ADDRESS                 METHOD
      host    all             all             0.0.0.0/0               scram-sha-256
    '';
    dataDir = "/persistence/postgresql";
  };

  services.restic.backups = {
    backblaze = {
      initialize = true;

      environmentFile = "/persistence/restic/backblaze/env";
      repositoryFile = "/persistence/restic/backblaze/repo";
      passwordFile = "/persistence/restic/backblaze/password";

      paths = [
        "/persistence/splitpro/.env"
        "/persistence/splitpro-sql-dumps"
        "/persistence/minio"
      ];

      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
      ];

      backupPrepareCommand = ''
        mkdir -p /persistence/splitpro-sql-dumps
        chown ${config.users.users.postgres.name}:${config.users.users.postgres.name} /persistence/splitpro-sql-dumps
        current_date=$(date +%Y-%m-%d)
        file_name="/persistence/splitpro-sql-dumps/splitpro-$current_date.sql"
        /run/wrappers/bin/su - postgres -c "pg_dump splitpro > $file_name"
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

  # acme is dynamically allocated but owns the persistent /var/lib/acme certs.
  # /var/lib/nixos (the uid/gid map) lives on the impermanence-rolled-back root,
  # so pin acme's ids to their current on-disk values to keep cert ownership
  # stable across reboots (same approach as media's jellyfin pin). postgres (71)
  # and minio (280) already have static nixpkgs-assigned ids, so need no pin.
  users.users.acme.uid = 995;
  users.groups.acme.gid = 993;

  users.users = {
    cjlarose = {
      # Pin the uid: /home is now a persistent tank/home dataset owned by 1000,
      # but /var/lib/nixos is rolled back each boot, so an unpinned uid could be
      # reassigned and break home ownership. Matches the cache/bots/dns hosts.
      uid = 1000;
      isNormalUser = true;
      home = "/home/cjlarose";
      extraGroups = [ "wheel" ];
      shell = pkgs.zsh;
      hashedPassword = "$6$YLrfXTwu61JGE.v8$kR5ZdMso2lcnyy7s7GXkIb.kLDyQ2UW3aDyGerQYni96g2kPC1MIY48Y9Q3SdYe2ycuVCrKgH6DlOjUUsK02s0";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFtA/9w60OssA+Eji+Ygvd1XCJk/zw/uYLdiiaevELu cjlarose"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILXv1L7zwTqnZJUfqOUVvAe7HI8CoAbVAHBPJhQsohxw cjlarose@ns1010301"
      ];
    };
  };

  virtualisation.oci-containers = {
    containers = {
      splitpro = {
        image = "ossapps/splitpro:v1.4.3";
        environmentFiles = [
          "/persistence/splitpro/.env"
        ];
        ports = [
          "127.0.0.1:3000:3000"
        ];
      };
    };
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };
}
