# NixOS Development Environment

This repository contains the configuration for my daily driver development environment. Using NixOS forces me to define the configuration for the system in code. This is great for a number of resasons, in particular,

1. I can set up a new machine for software development quickly
1. I can review the history of the rationale for changes I make to my development environment (assuming I wrote myself nice commit messages)
1. I can experiment with new approaches easily and rollback if I want to

## How I work

I split development work between an Apple Silion Mac and an x86 server. I use graphical applications, including my web browser, directly on my Mac. I also have a terminal emulator installed ([wezterm](https://wezfurlong.org/wezterm/)) on my Mac. From the terminal emulator, I edit files on my Mac in `neovim`. When I want to actually run a service, I build container images remotely (docker client running on the Mac, docker server running on the remote machine), and deploy them to a kubernetes cluster running on the server.

Why do I prefer to edit the files on the Mac instead of just editing them over an `ssh` connection? I have in the past just edited files on the remote machine, but I could never really get copy/paste working in a way I was happy with. Also, I really like to have my editor configured correctly on the Mac itself for when I just want to open up a local log file or CSV file or something and mess with it quickly.

This work is heavily influenced by [Mitchell Hasimoto's config](https://github.com/mitchellh/nixos-config), but has some major differences, including

1. That project configures the NixOS machine as VM installed on a hypervisor running on the Mac. I prefer instead to run the VM on a remote proxmox server.
1. In this project, the VM itself does not have any graphical tools installed (no desktop environment, window manager, etc). If I ever need console access to it, I usually just use `ssh`.
1. This config is fully [flake](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html)-based.

## NixOS binary cache (substituter) and remote builder

To build the image

```sh
nix build .#nixosConfigurations.builder.config.system.build.VMA
```

Copy the image into the `dump` directroy of a proxmox directory configured for VM backups (e.g. `/var/lib/vz/dump`). From the PVE web UI, restore the VM from the backup, taking care to select "Unique" to autogenerate a new MAC.

## Server Setup

First, create a new VM in proxmox. Use OVMF rather than SeaBIOS and attach the NixOS installation ISO. On the EFI disk, remove the preenrolled keys. Configure the EFI boot order to boot from the CD/DVD drive before the hard disk. When the VM boots up, identify the block device to use for installation using `lsblk` (it's `/dev/sda` in my example below). We'll clone the repo and perform the initial install onto that block device.

```sh
sudo su -
cd /tmp
curl -L  https://github.com/cjlarose/nixos-dev-env/tarball/main -o nixos-dev-env.tar.gz
tar -zxvf nixos-dev-env.tar.gz
cd cjlarose-nixos-dev-env*
./bootstrap.sh /dev/sda
nixos-install --no-root-password --flake '.#pt-dev'
shutdown -h now
```

Remove the installation media from the VM and login over SSH.

```sh
ssh cjlarose@pt-dev.local
```

From here, I normally clone the repo again to my home directory. If I make any changes, I execute the following to realize those changes:

```
sudo nixos-rebuild switch --flake '.#pt-dev'
```

## Client Setup (Mac)

Install [nix-darwin](https://github.com/LnL7/nix-darwin). Clone this repo. To rebuild,

```
darwin-rebuild switch --flake .
```
