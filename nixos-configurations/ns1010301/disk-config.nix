{ disko }: { lib, pkgs, ... }:

{
  imports = [
    disko.nixosModules.disko
  ];

  config = {
    boot = {
      loader.systemd-boot.enable = true;
      # Both mirror members share the fs label "tank", so by-label/tank resolves
      # to only one device and ZFS faults the other (pool DEGRADED). The
      # partlabels (disk-nvme0-zfs / disk-nvme1-zfs) are unique.
      zfs.devNodes = "/dev/disk/by-partlabel";
      # Don't force-import the root pool on hostid mismatch. networking.hostId
      # is pinned declaratively, this box has no shared-disk peer, and a hard
      # failure on mismatch is safer than silently winning a race against
      # another system. Matches the new default in NixOS 26.11.
      zfs.forceImportRoot = false;
      # Roll the root dataset back to a pristine snapshot on every boot
      # (impermanence). Under systemd stage-1 initrd this is a oneshot
      # service ordered after the pool import and before the root mount;
      # the scripted-initrd `boot.initrd.postResumeCommands` form is not
      # supported by systemd initrd.
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
                # Required for virtiofs shares to work with non-root systemd services
                options.acltype = "posixacl";
                options."xattr" = "sa";
              };
              home = {
                type = "zfs_fs";
                mountpoint = "/home";
                options.mountpoint = "legacy";
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
