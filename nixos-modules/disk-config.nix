{ disko }: { lib, ... }:

{
  imports = [
    disko.nixosModules.disko
  ];

  config = {
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
        disk = {
          main = {
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
          persistence = {
            device = "/dev/vdb";
            type = "disk";
            content = {
              type = "gpt";
              partitions = {
                main = {
                  label = "persistence";
                  size = "100%";
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/persistence";
                  };
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

    fileSystems."/" =
      { device = "tank/root";
        fsType = "zfs";
      };

    fileSystems."/nix" =
      { device = "tank/nix";
        fsType = "zfs";
      };

    fileSystems."/boot" =
      { device = "/dev/disk/by-partlabel/disk-main-ESP";
        fsType = "vfat";
      };

    fileSystems."/persistence" =
      { device = "/dev/disk/by-partlabel/persistence";
        neededForBoot = true;
        fsType = "ext4";
      };

  };
}
