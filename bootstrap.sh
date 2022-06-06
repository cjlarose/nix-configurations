#!/usr/bin/env bash

set -e

partition_and_format() {
  local blockdevice=$1
  parted ${blockdevice} -- mklabel gpt

  # root partition starts after the boot partition and goes until the swap partition
  parted ${blockdevice} -- mkpart primary 512MiB -8GiB

  # 8GiB swap partition at the end
  parted ${blockdevice} -- mkpart primary linux-swap -8GiB 100%

  # 512MiB boot partition at the beginning
  parted ${blockdevice} -- mkpart ESP fat32 1MiB 512MiB
  parted ${blockdevice} -- set 3 esp on

  # initialize ext4 filesystem and label it
  mkfs.ext4 -L nixos "${blockdevice}1"

  # initialize swap
  mkswap -L swap "${blockdevice}2"

  # boot partition
  mkfs.fat -F 32 -n boot "${blockdevice}3"
}

mount_block_devices() {
  mount /dev/disk/by-label/nixos /mnt
  mkdir -p /mnt/boot
  mount /dev/disk/by-label/boot /mnt/boot
  swapon /dev/disk/by-label/swap
}

write_nixos_config() {
  nixos-generate-config --root /mnt
}

main() {
  local blockdevice=$1
  partition_and_format "$blockdevice"
  mount_block_devices
  write_nixos_config
}

main $1
