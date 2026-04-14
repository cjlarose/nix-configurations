---
name: nix-configurations:home-manager-switch
description: Build and activate home-manager config changes on a microvm guest without a full rebuild
---

# home-manager-switch

For changes that only affect the cjlarose home-manager config (packages, shell config, git settings, Claude skills, etc.), apply them without rebuilding the entire microvm. Build on ns1010301 (the host), register the closure in the guest's nix DB, then activate via SSH.

The guest's `/nix/store` is a virtiofs share of the host's nix store, so build outputs are on disk inside the guest immediately. However, the guest's nix database doesn't know about them until they're explicitly registered.

`home-manager` may not be on PATH on the guest. Use `nix build` on the host to build the activation package and then run it in the guest via SSH.

New/untracked files must be `git add`ed first so nix can see them, but they don't need to be committed.

## Step 1: Build on the host

```sh
nix build <flake-ref>#homeConfigurations.'"<user>@<guest>"'.activationPackage --no-link --print-out-paths
```

Save the output path (e.g. `/nix/store/<hash>-home-manager-generation`).

## Step 2: Register the closure in the guest's nix DB

```sh
nix-store --export $(nix-store -qR /nix/store/<hash>-home-manager-generation) | ssh <user>@<guest> "sudo nix-store --import > /dev/null"
```

This exports the full closure from the host's nix DB and imports it into the guest's. Without this, `nix-store --realise` inside the guest fails with "don't know how to build these paths" even though the files exist on disk.

## Step 3: Activate via SSH

```sh
ssh <user>@<guest> /nix/store/<hash>-home-manager-generation/activate
```
