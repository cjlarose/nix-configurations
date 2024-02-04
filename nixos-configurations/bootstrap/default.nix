{ nixpkgs, sharedOverlays, stateVersion, disko, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    ({ pkgs, lib, ... }: {
      imports = [
        disko.nixosModules.disko
      ];

      boot = {
        loader.systemd-boot.enable = true;
        zfs.devNodes = "/dev/disk/by-label/tank";
        initrd.postDeviceCommands = lib.mkAfter ''
          zfs rollback -r tank/root@blank
        '';
      };

      disko = {
        memSize = 2048; # megabytes
        enableConfig = false; # disable setting filesystems.* automatically
        extraRootModules = [ "zfs" ];
        devices = {
          disk.main = {
            imageSize = "4G";
            device = "/dev/vda";
            type = "disk";
            content = {
              type = "gpt";
              partitions = {
                ESP = {
                  type = "EF00";
                  size = "500M";
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot";
                  };
                };
                zfs = {
                  size = "100%";
                  content = {
                    type = "zfs";
                    pool = "tank";
                  };
                };
              };
            };
          };

          zpool = {
            tank = {
              type = "zpool";
              rootFsOptions = {
                compression = "lz4";
                canmount = "off";
              };
              datasets = {
                root = {
                  type = "zfs_fs";
                  mountpoint = "/";
                  options.mountpoint = "legacy";
                  postCreateHook = "zfs snapshot tank/root@blank";
                };
                nix = {
                  type = "zfs_fs";
                  mountpoint = "/nix";
                  options.mountpoint = "legacy";
                };
              };
            };
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
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion system; })
  ];
}
