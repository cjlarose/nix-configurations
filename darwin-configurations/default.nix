{ nixpkgs, sharedOverlays, darwin, home-manager }:
let
  system = "x86_64-darwin";
  stateVersion = "23.05";
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
        nixpkgs = {
          overlays = sharedOverlays ++ [
            (final: prev: {
              nodejs = prev.nodejs_16;
            })
          ];
          config.permittedInsecurePackages = [
            "nodejs-16.20.0"
          ];
          config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [
            "1password-cli"
          ];
        };
        users.users.chrislarose = {
          home = "/Users/chrislarose";
        };
      })
      home-manager.darwinModules.home-manager {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.chrislarose = import ../home;
        home-manager.extraSpecialArgs = {
          inherit system stateVersion;
          server = false;
        };
      }
    ];
  };
}
