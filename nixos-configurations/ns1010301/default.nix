{ nixpkgs, sharedOverlays, additionalPackages, home-manager, stateVersion, impermanence, disko, determinate, nix-minecraft, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    determinate.nixosModules.default
    nix-minecraft.nixosModules.minecraft-servers
    (import ./disk-config.nix { inherit disko; })
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion system additionalPackages nix-minecraft; })
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
            {
              directory = "/srv/minecraft";
              user = "minecraft";
              group = "minecraft";
              mode = "0770";
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
