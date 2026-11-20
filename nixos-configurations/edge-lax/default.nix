{ pkgs, lib, sharedOverlays, additionalPackages, home-manager, stateVersion, system, impermanence, disko, intranetHosts, ... }: {
  imports = [
    home-manager.nixosModules.home-manager
    impermanence.nixosModules.impermanence
    (import ./disk-config.nix { inherit disko; })
    ./configuration.nix
  ];

  environment.persistence."/persistence" = {
    hideMounts = true;
    directories = [
      {
        directory = "/etc/nixos";
      }
      {
        directory = "/var/lib/tailscale";
      }
    ];
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.cjlarose = (import ../../home/cjlarose) {
    inherit system stateVersion additionalPackages;
  };
}
