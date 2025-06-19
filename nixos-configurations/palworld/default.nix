{ nixpkgs, sharedOverlays, additionalPackages, home-manager, stateVersion, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    ({ pkgs, ... }: {
      boot.loader.systemd-boot.enable = true;
    })
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion; })
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.cjlarose = (import ../../home/cjlarose) {
        inherit system stateVersion additionalPackages;
        include1Password = false;
        includeDockerClient = false;
        includeGnuSed = true;
        includeCoder = false;
        includeCopilotVim = false;
      };
    }
  ];
}
