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
        # home-manager-25-11 here: its programs.claude-code module has no
        # `plugins` option, so the superpowers plugin cannot be defined at all.
        # Drop this once the host moves to 26.05.
        enableSuperpowers = false;
    inherit system stateVersion additionalPackages;
  };
}
