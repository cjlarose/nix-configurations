{ microvm, ... }: {
  imports = [
    microvm.nixosModules.microvm
    ./configuration.nix
  ];

  microvm.hypervisor = "qemu";
  microvm.vcpu = 1;
  microvm.mem = 256;

  microvm.interfaces = [{
    type = "tap";
    id = "vm-intranet-dns";
    mac = "02:00:00:00:00:05";
  }];

  microvm.storeOnDisk = false;
  microvm.writableStoreOverlay = "/nix/.rw-store";

  microvm.shares = [
    {
      tag = "ro-store";
      source = "/nix/store";
      mountPoint = "/nix/.ro-store";
      proto = "virtiofs";
      readOnly = true;
    }
    {
      tag = "persist-nix-rw-store";
      source = "nix-rw-store";
      mountPoint = "/nix/.rw-store";
      proto = "virtiofs";
    }
    {
      tag = "persist-tailscale";
      source = "tailscale";
      mountPoint = "/var/lib/tailscale";
      proto = "virtiofs";
    }
    {
      tag = "persist-secrets";
      source = "secrets";
      mountPoint = "/persistence/secrets";
      proto = "virtiofs";
    }
    {
      # The guest root is tmpfs, so without this share /var/lib/nixos (the
      # uid/gid maps) is rebuilt on every boot and users without a pinned id
      # can be renumbered when the set of system users changes, leaving files
      # on the other persistent shares owned by the old numbers. It is in
      # nixpkgs' pathsNeededForBoot, so it mounts in the initrd before users
      # are created.
      tag = "persist-nixos";
      source = "nixos";
      mountPoint = "/var/lib/nixos";
      proto = "virtiofs";
    }
  ];
}
