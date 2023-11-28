{ nixpkgs, home-manager, fzfVim, fzfProject, tfenv, nixos-generators, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    ({ pkgs, ... }: {
      imports = [
        nixos-generators.nixosModules.all-formats
      ];

      formatConfigs.proxmox = { config, ... }: {
        proxmox.qemuConf = {
          name = "nixos-builder";
        };
      };
    })
    ({ pkgs, ... }: {
      networking.hostName = "builder";

      system.stateVersion = "23.05";

      nix = {
        package = pkgs.nixFlakes;
        extraOptions = ''
          experimental-features = nix-command flakes
        '';
        registry.nixpkgs.flake = nixpkgs;
      };

      nixpkgs.overlays = [
        fzfProject.overlay
        fzfVim.overlay
        tfenv.overlays.default
      ];

      security.sudo.wheelNeedsPassword = false;

      environment.systemPackages = with pkgs; [
        iotop
        lsof
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
        inherit system;
        server = true;
      };
    }
  ];
}
