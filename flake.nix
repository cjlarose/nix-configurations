{
  description = "NixOS-based development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-22.05";
    darwin.url = "github:lnl7/nix-darwin/master";
    darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    fzfVim.url = "github:cjlarose/fzf.vim";
    fzfVim.inputs.nixpkgs.follows = "nixpkgs";
    fzfProject.url = "github:cjlarose/fzf-project";
    fzfProject.inputs.nixpkgs.follows = "nixpkgs";
    pinpox.url = "github:cjlarose/pinpox-nixos";
    pinpox.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, darwin, home-manager, fzfVim, fzfProject, pinpox }: {
    nixosConfigurations = (
      import ./nixos-configurations {
        inherit nixpkgs home-manager fzfVim fzfProject pinpox;
      }
    );

    darwinConfigurations."LaRose-MacBook-Pro" = darwin.lib.darwinSystem (
      let
        system = "x86_64-darwin";
      in {
        inherit system;
        modules = [
          ({ pkgs, ... }: {
            environment.systemPackages = [
              pkgs.vim
            ];
            environment.etc = {
              "sysctl.conf" = {
                enable = true;
                text = ''
                  kern.maxfiles=131072
                  kern.maxfilesperproc=65536
                '';
              };
            };
            services.nix-daemon.enable = true;
            programs.zsh.enable = true;
            system.stateVersion = 4;
            nixpkgs.overlays = [
              fzfVim.overlay
              fzfProject.overlay
            ];
          })
          home-manager.darwinModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.chrislarose = import ./home.nix;
            home-manager.extraSpecialArgs = {
              inherit system pinpox;
              server = false;
            };
          }
        ];
      }
    );
  };
}
