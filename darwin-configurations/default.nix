{ nixpkgs, darwin, home-manager, fzfVim, fzfProject, pinpox }:
let
  system = "x86_64-darwin";
in {
  "LaRose-MacBook-Pro" = darwin.lib.darwinSystem {
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
        home-manager.users.chrislarose = import ../home;
        home-manager.extraSpecialArgs = {
          inherit system pinpox;
          server = false;
        };
      }
    ];
  };
}
