# nix-configurations

This repository contains a [Nix](https://nixos.org/) [flake](https://nixos.wiki/wiki/Flakes) that describe the configurations for several NixOS VMs and a few [`nix-darwin`](https://github.com/LnL7/nix-darwin) machines I use. Most of the work in this repository is not usable out-of-the-box for anyone but myself, but the patterns contained within can be of use to anyone looking to learn how to organize a bunch of Nix configurations or how to set up their own NixOS or `nix-darwin` machines.

## NixOs Configurations

Some NixOS configurations in the repository of note:

* `.#nixosConfigurations.cache` is used as a Nix [substituter (binary cache)](https://nixos.wiki/wiki/Binary_Cache). I have many machines on my LAN that download the same set of packages, and they're all configured to use this machine as a cache before hitting `cache.nixos.org`.
* `.#nixosConfigurations.dns` provides two DNS servers on two different addresses. One is an [Adguard Home](https://github.com/AdguardTeam/AdGuardHome) instance and the other is Dnsmasq server that acts as the authority for hosts on my LAN.
* `.#nixosConfigurations.media` runs Plex and `transmission`.
* `.#nixosConfigurations.photos` runs [Photoprism](https://www.photoprism.app/) inside a single-node k3s cluster.

## nix-darwin Configurations

`.#darwinConfigurations.LaRose-MacBook-Pro` is the configuration for my daily driver macOS machine. It doesn't do anything too fancy: it just sets up my shell, the Nix package manager, and my user/home directory configuration (described in the next section).

## Home Manager configuration

My [Home Manager](https://github.com/nix-community/home-manager) configuration is available at [`home/cjlarose/default.nix`](home/cjlarose/default.nix). It manages

* My Nix profile, including all of the programs I want to be available on my `$PATH`
* My `neovim` configuration, together with all of my plugins, themselves managed via Nix
* My `git` configuration
* My `zsh` configuration, including my `$PATH`, prompt, aliases, and some environment variables

I use the same home configuration on all of my NixOS VMs as well as on my Mac, so I have a consistent experience across all machines I interact with regularly.
