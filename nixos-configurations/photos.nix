{ nixpkgs, home-manager, fzfVim, fzfProject, pinpox, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    ({ pkgs, ... }: {
      imports = [ ./hardware-configuration.nix ];

      networking.hostName = "photos";

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      system.stateVersion = "22.05";

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
      };

      nixpkgs.overlays = [
        fzfVim.overlay
        fzfProject.overlay
      ];

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
      };

      services.openssh = {
        enable = true;
        passwordAuthentication = false;
        permitRootLogin = "no";
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
      home-manager.users.cjlarose = import ../home;
      home-manager.extraSpecialArgs = {
        inherit system pinpox;
        server = true;
      };
    }
  ];
}
