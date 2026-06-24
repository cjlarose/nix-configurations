{ disko }: { lib, pkgs, ... }:

{
  imports = [
    disko.nixosModules.disko
  ];

  config = {
    boot = {
      loader.systemd-boot.enable = true;
      # Single disk — no duplicate-label mirror issue, by-label is fine.
      zfs.devNodes = "/dev/disk/by-label/tank";
      # hostId is pinned and storage is single-tenant; the 26.11 default.
      zfs.forceImportRoot = false;
      # Roll the root dataset back to a pristine snapshot on every boot
      # (impermanence). 26.05 defaults to systemd stage-1 initrd, which
      # silently ignores the old `boot.initrd.postDeviceCommands` form, so this
      # is a oneshot ordered after the pool import and before the root mount.
      initrd.systemd.services.rollback-root = {
        description = "Roll back tank/root to its blank snapshot";
        wantedBy = [ "initrd.target" ];
        after = [ "zfs-import-tank.service" ];
        before = [ "sysroot.mount" ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        path = [ pkgs.zfs ];
        script = ''
          zfs rollback -r tank/root@blank
        '';
      };
    };

    disko = {
      enableConfig = false; # disable setting filesystems.* automatically
      extraRootModules = [ "zfs" ];
      devices = {
        disk = {
          main = {
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
