# NixOS Development Environment

This repository contains the configuration for my daily driver development environment. Using NixOS forces me to define the configuration for the system in code. This is great for a number of resasons, in particular,

1. I can set up a new machine for software development quickly
1. I can review the history of the rationale for changes I make to my development environment (assuming I wrote myself nice commit messages)
1. I can experiment with new approaches easily and rollback if I want to

## How I work

I work on a Apple Silion Mac. I use graphical applications, including my web browser, directly on my Mac. I have a terminal emulator installed ([wezterm](https://wezfurlong.org/wezterm/)) on my Mac, but I use it basically only to `ssh` into a VM running my NixOS development environment. I use a single `ssh` session, which is running a single instance of `neovim`. Within `neovim`, I modify text files and run all of my shells.

This work is heavily influenced by [Mitchell Hasimoto's config](https://github.com/mitchellh/nixos-config), but has some major differences, including

1. The VM itself does not have any graphical tools installed (no desktop environment, window manager, etc), since I only interact with the VM over `ssh`.
1. This project only supports running the VM on UTM on an Apple Silion Mac. I'm not interesting in adding support for multiple ISAs or hypervisors.
1. My config is fully [flake](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html)-based.

## Setup

Requirements for the host machine: [UTM](https://mac.getutm.app/) and a terminal emulator that supports 24-bit color (I use [wezterm](https://wezfurlong.org/wezterm/). Other true color terminal emulators are probably fine, but I haven't tested on anything else, and I don't configure any special `terminfo` entries).

1. Download a NixOS minimal ISO from Hydra
   * I browsed the [`release-22.05-aarch64` jobset](https://hydra.nixos.org/jobset/nixos/release-22.05-aarch64/all) and found a `nixos-minimal-22.05-*-aarch64-linux.iso`. The most recent one I've validated is [`nixos-minimal-22.05.545.dcfb7d8aa2e-aarch64-linux.iso`](https://hydra.nixos.org/build/179335250).
2. Create a new VM in UTM
   1. Select "Virtualize" since we’ll be using an ARM64 NixOS build on our ARM64 Mac
   2. Select "Linux"
   3. Select the ISO from your downloads
   4. 8192MB RAM, 4 CPU cores, no Hardware OpenGL Acceleration
   5. 64GiB disk
   6. No shared directories
3. Boot the VM
4. From the VM, get the block device for installation

```sh
lsblk
```

Assuming we’re installing onto the block device `/dev/vda`,

```sh
sudo su -
cd /tmp
curl -L  https://github.com/cjlarose/nixos-dev-env/tarball/master -o nixos-dev-env.tar.gz
tar -zxvf nixos-dev-env.tar.gz
cd cjlarose-nixos-dev-env*
./bootstrap.sh /dev/sda
nixos-install --no-root-password --flake '.#dev'
shutdown -h now
```

5. In the UTM UI, remove the installation media from the CD/DVD drive. Start the VM again.
6. Log in over SSH

```sh
ssh cjlarose@pt-dev.local
```
