{ nixpkgs, sharedOverlays, stateVersion, pce, system, ... }: { pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
  ];

  networking = {
    hostName = "bots";
    hostId = "d202c7d5";
  };

  system.stateVersion = stateVersion;

  nix = {
    package = pkgs.nixFlakes;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    registry.nixpkgs.flake = nixpkgs;
    nixPath = [ "nixpkgs=${nixpkgs.outPath}" ];
  };

  nixpkgs.overlays = sharedOverlays;

  security.sudo.wheelNeedsPassword = false;

  security.acme = {
    acceptTerms = true;
    defaults.email = "cjlarose@gmail.com";
    defaults.server = "https://acme-staging-v02.api.letsencrypt.org/directory";
    certs = {
      "bots.toothyshouse.com" = {
        dnsPropagationCheck = false;
        dnsProvider = "digitalocean";
        domain = "bots.toothyshouse.com";
        environmentFile = "/persistence/acme/digitalocean.secret";
      };
    };
  };

  environment.systemPackages = with pkgs; [
    iotop
    lsof
    tigervnc
    xorg.xauth
    xterm
  ];

  services.zfs.expandOnBoot = "all";

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

  services.nginx = {
    enable = true;
    virtualHosts = {
      "bots.toothyshouse.com" = {
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
    };
  };

  systemd.services."tigervnc-server" = {
    description = "TigerVNC Server";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      StandardError = "journal";
      ExecStart = ''
        ${pkgs.bash}/bin/bash -c '${pkgs.xorg.xauth}/bin/xauth -f ~/.Xauthority source - <<< "add :1 . $(${pkgs.util-linux}/bin/mcookie)" ; \
        trap "exit 0" USR1; \
        (trap "" USR1 && exec ${pkgs.tigervnc}/bin/Xvnc :1 -rfbauth ~/.vnc/passwd -desktop :1 -geometry 1600x1200) & wait ; \
        exit 1'
      '';
      Type = "forking";
      User = "bot";
      Restart = "always";
      RestartSec = "10s";
    };
  };

  systemd.services."pce-discord-bot" = {
    description = "Pixel Cat's End discord bot";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      StandardInput = "null";
      StandardOutput = "journal";
      StandardError = "journal";
      ExecStart = ''
        ${pkgs.bash}/bin/bash -c 'source ~/.config/pce/.pce-env && \
        exec ${pce.packages.${system}.default}/bin/discord_bot'
      '';
      Type = "exec";
      User = "bot";
      Restart = "always";
      RestartSec = "10s";
    };
  };

  systemd.services."pce-worker" = {
    description = "Pixel Cat's End worker process";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      StandardInput = "null";
      StandardOutput = "journal";
      StandardError = "journal";
      ExecStart = ''
        ${pkgs.bash}/bin/bash -c 'source ~/.config/pce/.pce-env && \
        exec ${pce.packages.${system}.default}/bin/worker'
      '';
      Type = "exec";
      User = "bot";
      Restart = "always";
      RestartSec = "10s";
    };
  };

  systemd.services."pce-rails" = {
    description = "Pixel Cat's End Rails server";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      StandardInput = "null";
      StandardOutput = "journal";
      StandardError = "journal";
      PermissionsStartOnly = true;
      RuntimeDirectory = "pce-rails";
      PIDFile = "/run/pce-rails/server.pid";
      ExecStart = ''
        ${pkgs.bash}/bin/bash -c 'echo "RUNTIME_DIRECTORY: $RUNTIME_DIRECTORY"; source ~/.config/pce/.pce-env && \
        exec ${pce.packages.${system}.default}/bin/rails server --pid /run/pce-rails/server.id'
      '';
      Type = "exec";
      User = "bot";
      Restart = "always";
      RestartSec = "10s";
    };
  };

  programs.ssh.startAgent = true;

  programs.zsh.enable = true;

  users.mutableUsers = false;

  users.users = {
    cjlarose = {
      uid = 1000;
      isNormalUser = true;
      home = "/home/cjlarose";
      extraGroups = [ "docker" "wheel" ];
      shell = pkgs.zsh;
      hashedPassword = "$6$YLrfXTwu61JGE.v8$kR5ZdMso2lcnyy7s7GXkIb.kLDyQ2UW3aDyGerQYni96g2kPC1MIY48Y9Q3SdYe2ycuVCrKgH6DlOjUUsK02s0";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFtA/9w60OssA+Eji+Ygvd1XCJk/zw/uYLdiiaevELu cjlarose"
      ];
    };

    bot = {
      uid = 1001;
      isNormalUser = true;
      home = "/home/bot";
    };
  };
}
