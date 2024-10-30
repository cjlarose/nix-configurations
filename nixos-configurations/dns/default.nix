{ nixpkgs, sharedOverlays, additionalPackages, stateVersion, impermanence, home-manager, ... }:
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
    ({ pkgs, ... } : {
      imports = [
        impermanence.nixosModules.impermanence
      ];
      environment.persistence."/persistence" = {
        hideMounts = true;
        users = {
          cjlarose = {
            directories = [
              ".ssh"
              "workspace"
            ];
          };
        };
      };
    })
    ({ config, pkgs, ... }: {
      imports = [
        ../../nixos-modules/proxmox-image.nix
      ];

      proxmox = {
        qemuConf = {
          name = "nixos-${config.networking.hostName}";
          net0 = "virtio=00:00:00:00:00:00,bridge=vmbr1,firewall=1";
          bios = "ovmf";
          boot = "order=virtio0";
          virtio0 = "montero-vm-storage-lvm:vm-9999-disk-0";
          cores = 4;
          memory = 4096;
        };
        qemuExtraConf = {
          localtime = "false";
          sockets = 1;
        };
      };
    })
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion system additionalPackages; })
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.cjlarose = import ../../home/cjlarose;
      home-manager.extraSpecialArgs = {
        inherit system stateVersion additionalPackages;
        include1Password = false;
        includeDockerClient = false;
        includeGnuSed = true;
        includeCoder = false;
      };
    }
  ];
}
