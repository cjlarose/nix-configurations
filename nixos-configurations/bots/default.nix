{ nixpkgs, sharedOverlays, additionalPackages, home-manager, stateVersion, pce, impermanence, ... }:
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
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion pce system; })
    ({ pkgs, ... } : {
      imports = [
        impermanence.nixosModules.impermanence
      ];
      environment.persistence."/persistence" = {
        hideMounts = true;
        users = {
          bot = {
            directories = [
              ".config/chromium/pixel-cats-end"
              ".config/pce"
              ".vnc"
            ];
          };
          cjlarose = {
            directories = [
              ".config/chromium/pixel-cats-end"
              ".ssh"
              "workspace"
            ];
          };
        };
      };
    })
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.cjlarose = import ../../home/cjlarose;
      home-manager.extraSpecialArgs = {
        inherit system stateVersion additionalPackages;
        server = true;
      };
    }
  ];
}
