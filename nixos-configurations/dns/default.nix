{ nixpkgs, sharedOverlays, additionalPackages, stateVersion, impermanence, home-manager, disko, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    (import ./disk-config.nix { inherit disko; })
    ({ pkgs, ... } : {
      imports = [
        impermanence.nixosModules.impermanence
      ];
      environment.persistence."/persistence" = {
        hideMounts = true;
        directories = [
          {
            directory = "/etc/nixos";
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
    })
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion system additionalPackages; })
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.cjlarose = (import ../../home/cjlarose) {
        inherit system stateVersion additionalPackages;
      };
    }
  ];
}
