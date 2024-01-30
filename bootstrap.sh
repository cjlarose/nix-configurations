#!/usr/bin/env bash

set -e

partition_and_format() {
  local blockdevice=$1
  parted -s "${blockdevice}" -- mklabel gpt

  # 512MiB boot partition at the beginning
  parted "${blockdevice}" -- mkpart ESP fat32 1MiB 512MiB
  parted "${blockdevice}" -- set 1 esp on

  # root partition starts after the boot partition and goes until the end of the disk
  parted "${blockdevice}" -- mkpart primary 512MiB 100%

  # boot partition
  mkfs.fat -F 32 -n boot "${blockdevice}1"

  # initialize ext4 filesystem and label it
  mkfs.ext4 -L nixos "${blockdevice}2"
}

mount_block_devices() {
  mount /dev/disk/by-label/nixos /mnt
  mkdir -p /mnt/boot
  mount /dev/disk/by-label/boot /mnt/boot
}

write_nixos_config() {
  nixos-generate-config --root /mnt
  cat > /mnt/etc/nixos/configuration.nix <<EOF
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  system.stateVersion = "22.05";

  services.openssh = {
    enable = true;
    passwordAuthentication = true;
    permitRootLogin = "yes";
  };
  users.users.root.initialPassword = "root";

  nix = {
    package = pkgs.nixFlakes;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };
}
EOF
}

main() {
  local blockdevice=$1
  partition_and_format "$blockdevice"
  mount_block_devices
  write_nixos_config
}

main "$1"
