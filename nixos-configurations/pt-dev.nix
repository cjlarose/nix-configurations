{ nixpkgs, stateVersion, sharedOverlays, additionalPackages, home-manager, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    ({ pkgs, ... }: {
      imports = [ ./pt-dev-hardware.nix ];

      networking.hostName = "pt-dev";

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      system.stateVersion = stateVersion;

      networking.firewall.allowedTCPPorts = [
        80 # ingress-nginx
        443 # ingress-nginx
        2376 # docker daemon
        3000 # web-client
        5432 # postgresql
        6443 # k8s API
        8080 # device-sync
        10250 # k8s node API
        34000 # teleport
      ];

      nix = {
        package = pkgs.nixFlakes;
        extraOptions = ''
          experimental-features = nix-command flakes
        '';
        registry.nixpkgs.flake = nixpkgs;
      };

      nixpkgs.overlays = sharedOverlays;

      security.sudo.wheelNeedsPassword = false;
      security.pam.loginLimits = [
        {
          domain = "*";
          type = "soft";
          item = "nofile";
          value = "65536";
        }
      ];

      virtualisation.docker = {
        enable = true;
        listenOptions = [
          "/run/docker.sock"
          "0.0.0.0:2376"
        ];
        liveRestore = false;
      };

      environment.systemPackages = with pkgs; [
        iotop
        lsof
        pg_activity
        teleport
      ];

      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          PermitRootLogin = "no";
        };
      };

      programs.ssh.startAgent = true;

      programs.zsh.enable = true;

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
        extraPlugins = with pkgs.postgresql14Packages; [ postgis ];
        dataDir = "/pt-postgresql";
        settings = {
          shared_buffers = "4096 MB";
          max_wal_senders = "0";
          wal_level = "minimal";
          maintenance_work_mem = "1 GB";
          synchronous_commit = "off";
          max_connections = "1000";
        };
      };

      systemd.services.postgresql.serviceConfig.TimeoutSec = nixpkgs.lib.mkForce 86400;

      services.k3s = {
        enable = true;
        role = "server";
        extraFlags = toString [
          "--disable traefik"
          "--disable servicelb"
        ];
      };

      services.dockerRegistry = {
        enable = true;
      };

      services.openiscsi = {
        enable = true;
        name = "iqn.2020-08.org.linux-iscsi.toothyshouse:pt-dev";
        enableAutoLoginOut = true;
        discoverPortal = "192.168.2.102";
      };

      users.mutableUsers = false;

      users.users.cjlarose = {
        isNormalUser = true;
        home = "/home/cjlarose";
        extraGroups = [ "docker" "wheel" ];
        shell = pkgs.zsh;
        hashedPassword = "$6$YLrfXTwu61JGE.v8$kR5ZdMso2lcnyy7s7GXkIb.kLDyQ2UW3aDyGerQYni96g2kPC1MIY48Y9Q3SdYe2ycuVCrKgH6DlOjUUsK02s0";
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFtA/9w60OssA+Eji+Ygvd1XCJk/zw/uYLdiiaevELu cjlarose"
        ];
      };
    })
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.cjlarose = import ../home;
      home-manager.extraSpecialArgs = {
        inherit system stateVersion additionalPackages;
        server = true;
      };
    }
  ];
}
