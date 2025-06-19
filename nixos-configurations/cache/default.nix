{ nixpkgs, sharedOverlays, additionalPackages, home-manager, stateVersion, impermanence, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    ({ pkgs, lib, ... }: {
      boot = {
        loader.systemd-boot.enable = true;
        zfs.devNodes = "/dev/disk/by-label/tank";
        initrd.postDeviceCommands = lib.mkAfter ''
          zfs rollback -r tank/root@blank
        '';
      };
    })
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
        ];
        users = {
          cjlarose = {
            directories = [
              ".ssh"
              "gc-roots"
              "workspace"
            ];
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
