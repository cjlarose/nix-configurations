{ nixpkgs, sharedOverlays, additionalPackages, home-manager, stateVersion, pce, impermanence, disko, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    (import ./disk-config.nix { inherit disko; })
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion pce system additionalPackages; })
    ({ ... } : {
      imports = [
        impermanence.nixosModules.impermanence
      ];
      # Home now lives on the persistent tank/home dataset (see
      # hardware-configuration.nix + disk-config.nix), not per-dir impermanence.
      # Only system dirs are cherry-picked into /persistence here.
      environment.persistence."/persistence" = {
        hideMounts = true;
        directories = [
          {
            directory = "/etc/nixos";
          }
          {
            directory = "/var/lib/acme";
            user = "acme";
            group = "acme";
            mode = "0755";
          }
        ];
      };
    })
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.cjlarose = (import ../../home/cjlarose) {
        inherit system stateVersion additionalPackages;
        claudeUseNodeRuntime = true;
      };
    }
  ];
}
