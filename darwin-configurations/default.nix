{ nixpkgs, darwin, home-manager, fzfVim, fzfProject, tfenv }:
let
  system = "x86_64-darwin";
in {
  "LaRose-MacBook-Pro" = darwin.lib.darwinSystem {
    inherit system;
    modules = [
      ({ ... }: {
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
        nix = {
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
        users.users.chrislarose = {
          home = "/Users/chrislarose";
        };
      })
      home-manager.darwinModules.home-manager {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.chrislarose = import ../home;
        home-manager.extraSpecialArgs = {
          inherit system;
          server = false;
        };
      }
    ];
  };
}
