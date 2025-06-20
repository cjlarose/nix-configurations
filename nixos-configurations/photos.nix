{ nixpkgs, stateVersion, sharedOverlays, additionalPackages, home-manager, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    ({ pkgs, ... }: {
      imports = [ ./photos-hardware.nix ];

      networking.hostName = "photos";

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      system.stateVersion = stateVersion;

      networking.firewall.allowedTCPPorts = [
        80 # ingress-nginx
        443 # ingress-nginx
        6443 # k8s API
        10250 # k8s node API
      ];

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
      security.pam.loginLimits = [
        {
          domain = "*";
          type = "soft";
          item = "nofile";
          value = "65536";
        }
      ];

      environment.systemPackages = with pkgs; [
        iotop
        lsof
      ];

      services.openiscsi = {
        enable = true;
        name = "iqn.2020-08.org.linux-iscsi.toothyshouse:photos";
        enableAutoLoginOut = true;
        discoverPortal = "192.168.2.102:3261";
        extraConfigFile = "/home/cjlarose/workspace/cjlarose/nixos-dev-env/iscsid.conf";
      };

      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          PermitRootLogin = "no";
        };
      };

      services.tailscale = {
        enable = true;
      };

      programs.ssh.startAgent = true;

      programs.zsh.enable = true;

      services.k3s = {
        enable = true;
        role = "server";
        extraFlags = toString [
          "--disable traefik"
          "--disable servicelb"
        ];
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
      home-manager.users.cjlarose = (import ../home/cjlarose) {
        inherit system stateVersion additionalPackages;
      };
    }
  ];
}
