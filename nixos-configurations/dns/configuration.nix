{ nixpkgs, sharedOverlays, stateVersion, system, additionalPackages, ... }: { pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
  ];

  networking = {
    hostName = "dns";
    hostId = "d202c7d5";
    firewall = {
      enable = true;
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };
    nameservers = [ "192.168.2.1" ];
    defaultGateway = {
      address = "192.168.2.1";
      interface = "ens18";
    };
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

  services.adguardhome = {
    enable = true;
    mutableSettings = false;
    settings = {
      dns = {
        bind_hosts = ["192.168.2.104"];
        port = 53;
        bootstrap_dns = ["1.1.1.1" "1.0.0.1"];
        upstream_dns = [
          "[/picktrace.dev/]192.168.2.105"
          "[/toothyshouse.com/]192.168.2.105"
        ];
      };
    };
  };

  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    settings = {
      addn-hosts = "${(additionalPackages system).intranetHosts}/hosts";
      bind-interfaces = true;
      bogus-priv = true;
      domain-needed = true;
      listen-address = ["192.168.2.105"];
      no-resolv = true;
      server = [];
    };
  };

  programs.ssh.startAgent = true;

  programs.zsh.enable = true;

  users.mutableUsers = false;

  users.users.cjlarose = {
    isNormalUser = true;
    home = "/home/cjlarose";
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
    hashedPassword = "$6$YLrfXTwu61JGE.v8$kR5ZdMso2lcnyy7s7GXkIb.kLDyQ2UW3aDyGerQYni96g2kPC1MIY48Y9Q3SdYe2ycuVCrKgH6DlOjUUsK02s0";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFtA/9w60OssA+Eji+Ygvd1XCJk/zw/uYLdiiaevELu cjlarose"
    ];
  };
}
