{ config, lib, pkgs, modulesPath, ... }:

{
  boot.initrd.availableKernelModules = [ "nvme" "ahci" "xhci_pci" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  fileSystems."/" =
    { device = "tank/root";
      fsType = "zfs";
    };

  fileSystems."/nix" =
    { device = "tank/nix";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-partlabel/disk-nvme1-ESP";
      fsType = "vfat";
    };

  fileSystems."/persistence" =
    { device = "tank/persistence";
      neededForBoot = true;
      fsType = "zfs";
    };

  swapDevices = [
    { device = "/dev/disk/by-partlabel/disk-nvme0-swap"; }
    { device = "/dev/disk/by-partlabel/disk-nvme1-swap"; }
  ];

  networking.interfaces.enp1s0f0.useDHCP = true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
