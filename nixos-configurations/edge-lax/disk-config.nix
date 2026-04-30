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
      memSize = 2048;
      enableConfig = false;
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
                  end = "-3G";
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
              persistence = {
                type = "zfs_fs";
                mountpoint = "/persistence";
                options.mountpoint = "legacy";
              };
              home = {
                type = "zfs_fs";
                mountpoint = "/home";
                options.mountpoint = "legacy";
              };
            };
          };
        };
      };
    };
  };
}
