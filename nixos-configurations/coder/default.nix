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
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion system additionalPackages; })
    ({ pkgs, config, ... } : {
      imports = [
        impermanence.nixosModules.impermanence
      ];
      environment.persistence."/persistence" = {
        hideMounts = true;
        directories = [
          {
            directory = "/var/lib/postgresql/${config.services.postgresql.package.psqlSchema}";
            user = "postgres";
            group = "postgres";
            mode = "0700";
          }
          "/var/lib/rancher"
          {
            directory = "/var/lib/kubelet";
            mode = "0750";
          }
        ];
        users = {
          cjlarose = {
            directories = [
              ".kube"
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
        include1Password = false;
      };
    }
  ];
}
