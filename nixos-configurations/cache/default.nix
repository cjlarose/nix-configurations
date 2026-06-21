{ nixpkgs, sharedOverlays, additionalPackages, home-manager, stateVersion, impermanence, disko, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    (import ./disk-config.nix { inherit disko; })
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion system; })
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
          {
            directory = "/var/lib/acme";
            user = "acme";
            group = "acme";
            mode = "0755";
          }
          {
            # Persist the tailscale node identity across the impermanence
            # @blank rollback; without this every reboot drops the host off
            # the tailnet and requires a re-auth from the console. Every other
            # impermanence host in this repo persists this.
            directory = "/var/lib/tailscale";
            user = "root";
            group = "root";
            mode = "0700";
          }
        ];
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
