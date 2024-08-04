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
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion pce system additionalPackages; })
    ({ pkgs, ... } : {
      imports = [
        impermanence.nixosModules.impermanence
      ];
      environment.persistence."/persistence" = {
        hideMounts = true;
        directories = [
          {
            directory = "/var/lib/acme";
            user = "acme";
            group = "acme";
            mode = "0755";
          }
        ];
        users = {
          bot = {
            directories = [
              ".config/chicken-smoothie-automation"
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
          monicahung = {
            directories = [
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
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.monicahung = import ../../home/monicahung;
      home-manager.extraSpecialArgs = {
        inherit system stateVersion additionalPackages;
        server = true;
      };
    }
  ];
}
