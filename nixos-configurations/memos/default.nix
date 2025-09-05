{ nixpkgs, sharedOverlays, additionalPackages, home-manager, stateVersion, impermanence, disko, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    (import ./disk-config.nix { inherit disko; })
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion system; })
    ({ pkgs, config, ... } : {
      imports = [
        impermanence.nixosModules.impermanence
      ];
      environment.persistence = {
        "/persistence" = {
          hideMounts = true;
          directories = [
            {
              directory = "/etc/nixos";
            }
            {
              directory = "/var/lib/acme";
              user = config.users.users.acme.name;
              group = config.users.users.acme.group;
              mode = "0755";
            }
            {
              directory = "/var/lib/scriberr";
              user = config.users.users.scriberr.name;
              group = config.users.users.scriberr.group;
              mode = "0755";
            }
            {
              directory = "/var/lib/tailscale";
              user = "root";
              group = "root";
              mode = "0700";
            }
          ];
          users = {
            cjlarose = {
              directories = [
                ".ssh"
                "workspace"
              ];
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
