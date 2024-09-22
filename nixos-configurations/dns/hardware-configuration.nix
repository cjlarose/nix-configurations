{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/profiles/qemu-guest.nix")
    ];

  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_blk" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

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

  swapDevices = [ ];

  networking.interfaces.ens18 = {
    ipv4.addresses = [
      {
        address = "192.168.2.104";
        prefixLength = 24;
      }
      {
        address = "192.168.2.105";
        prefixLength = 24;
      }
    ];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
