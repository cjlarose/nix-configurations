{ nixpkgs, sharedOverlays, additionalPackages, home-manager, nixos-generators, stateVersion, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    ({ pkgs, ... }: {
      imports = [
        nixos-generators.nixosModules.all-formats
      ];

      formatConfigs.proxmox = { config, ... }: {
        proxmox.qemuConf = {
          name = "nixos-builder";
          net0 = "virtio=00:00:00:00:00:00,bridge=vmbr1,firewall=1";
          bios = "ovmf";
        };
      };

      boot.loader.systemd-boot.enable = true;
    })
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion; })
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.cjlarose = import ../../home;
      home-manager.extraSpecialArgs = {
        inherit system stateVersion additionalPackages;
        server = true;
      };
    }
  ];
}
