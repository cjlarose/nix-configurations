{
  description = "NixOS-based development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-22.05";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    fzfVim.url = "github:cjlarose/fzf.vim";
    fzfVim.inputs.nixpkgs.follows = "nixpkgs";
    fzfProject.url = "github:cjlarose/fzf-project";
    fzfProject.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, fzfVim, fzfProject }: {
    nixosConfigurations.dev = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ({ pkgs, ... }: {
          imports = [ ./hardware-configuration.nix ];

          networking.hostName = "nixos-dev";

          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = true;

          system.stateVersion = "22.05";

          networking.firewall.allowedTCPPorts = [ 3000 ];

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

          security.sudo.extraConfig = ''
            Defaults timestamp_timeout=60
          '';

          services.openssh = {
            enable = true;
            passwordAuthentication = false;
            permitRootLogin = "no";
          };

          programs.ssh.startAgent = true;

          programs.zsh.enable = true;

          services.avahi = {
            enable = true;
            publish = {
              enable = true;
              addresses = true;
            };
          };

          users.mutableUsers = false;

          users.users.cjlarose = {
            isNormalUser = true;
            home = "/home/cjlarose";
            extraGroups = [ "wheel" ];
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
          home-manager.users.cjlarose = import ./home.nix;
        }
      ];
    };
  };
}
