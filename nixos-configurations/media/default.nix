{ microvm, ... }: {
  imports = [
    microvm.nixosModules.microvm
    ./configuration.nix
  ];

  microvm.hypervisor = "qemu";
  microvm.vcpu = 4;
  microvm.mem = 4096;

  microvm.interfaces = [{
    type = "tap";
    id = "vm-media";
    mac = "02:00:00:00:00:03";
  }];

  microvm.storeOnDisk = false;
  microvm.writableStoreOverlay = "/nix/.rw-store";

  microvm.volumes = [
    {
      image = "docker.img";
      mountPoint = "/var/lib/docker";
      size = 65536; # 64 GiB
      fsType = "xfs";
      label = "docker";
    }
    # Disk-backed /tmp so nix build scratch spills to disk instead of the
    # RAM-backed tmpfs root. Sparse image: costs only what's used.
    {
      image = "tmp.img";
      mountPoint = "/tmp";
      size = 32768; # 32 GiB
      fsType = "ext4";
      label = "tmp";
    }
  ];

  microvm.shares = [
    {
      tag = "ro-store";
      source = "/nix/store";
      mountPoint = "/nix/.ro-store";
      proto = "virtiofs";
    }
    {
      tag = "persist-nix-rw-store";
      source = "nix-rw-store";
      mountPoint = "/nix/.rw-store";
      proto = "virtiofs";
    }
    {
      tag = "persist-ssh";
      source = "ssh";
      mountPoint = "/persistence/ssh";
      proto = "virtiofs";
    }
    {
      tag = "persist-home";
      source = "home";
      mountPoint = "/home";
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
      tag = "persist-acme";
      source = "acme";
      mountPoint = "/var/lib/acme";
      proto = "virtiofs";
    }
    {
      tag = "persist-jellyfin";
      source = "jellyfin";
      mountPoint = "/var/lib/jellyfin";
      proto = "virtiofs";
    }
    {
      tag = "persist-media";
      source = "media";
      mountPoint = "/persistence/media";
      proto = "virtiofs";
    }
  ];
}
