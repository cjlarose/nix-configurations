{ nixpkgs, sharedOverlays, additionalPackages, home-manager, stateVersion, impermanence, disko, determinate, microvm, picktrace-nix-configurations, self, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    microvm.nixosModules.host
    ({ ... }: {
      microvm.vms."pt-docker-cjlarose" = {
        flake = picktrace-nix-configurations;
      };
      microvm.vms."minecraft-mellowcatfe" = {
        flake = self;
      };
      microvm.autostart = [ "pt-docker-cjlarose" "minecraft-mellowcatfe" ];
    })
    determinate.nixosModules.default
    (import ./disk-config.nix { inherit disko; })
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion system additionalPackages; })
    ({ pkgs, config, ... } : {
      imports = [
        impermanence.nixosModules.impermanence
      ];
      environment.persistence = {
        "/persistence" = {
          hideMounts = true;
          directories = [
            {
              directory = "/var/lib/tailscale";
              user = "root";
              group = "root";
              mode = "0700";
            }
          ];
          users = {
            cjlarose = {
              home = "/home/cjlarose";
            };
          };
        };
      };
    })
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.cjlarose = (import ../../home/cjlarose) {
        inherit system stateVersion additionalPackages;
      };
    }
  ];
}
