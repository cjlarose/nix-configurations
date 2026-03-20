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
      enableConfig = false; # disable setting filesystems.* automatically
      extraRootModules = [ "zfs" ];
      devices = {
        disk = {
          nvme0 = {
            device = "/dev/nvme0n1";
            type = "disk";
            content = {
              type = "gpt";
              partitions = {
                ESP = {
                  type = "EF00";
                  size = "512M";
                  content = {
                    type = "filesystem";
                    format = "vfat";
                  };
                };
                zfs = {
                  end = "-8G";
                  content = {
                    type = "zfs";
                    pool = "tank";
                  };
                };
                swap = {
                  size = "100%";
                  content = {
                    type = "swap";
                  };
                };
              };
            };
          };
          nvme1 = {
            device = "/dev/nvme1n1";
            type = "disk";
            content = {
              type = "gpt";
              partitions = {
                ESP = {
                  type = "EF00";
                  size = "512M";
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot";
                  };
                };
                zfs = {
                  end = "-8G";
                  content = {
                    type = "zfs";
                    pool = "tank";
                  };
                };
                swap = {
                  size = "100%";
                  content = {
                    type = "swap";
                  };
                };
              };
            };
          };
        };

        zpool = {
          tank = {
            type = "zpool";
            mode = "mirror";
            rootFsOptions = {
              compression = "lz4";
              canmount = "off";
            };
            datasets = {
              root = {
                type = "zfs_fs";
                mountpoint = "/";
                options.mountpoint = "legacy";
                options.reservation = "4G";
                postCreateHook = "zfs snapshot tank/root@blank";
              };
              nix = {
                type = "zfs_fs";
                mountpoint = "/nix";
                options.mountpoint = "legacy";
                options.quota = "64G";
              };
              persistence = {
                type = "zfs_fs";
                mountpoint = "/persistence";
                options.mountpoint = "legacy";
              };
            };
          };
        };
      };
    };
  };
}
