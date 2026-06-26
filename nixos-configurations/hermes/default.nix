{ microvm, hermes-agent, ... }: {
  imports = [
    microvm.nixosModules.microvm
    hermes-agent.nixosModules.default
    ./configuration.nix
  ];

  microvm.hypervisor = "qemu";
  microvm.vcpu = 2;
  microvm.mem = 4096;

  microvm.interfaces = [{
    type = "tap";
    id = "vm-hermes";
    mac = "02:00:00:00:00:04";
  }];

  microvm.storeOnDisk = false;
  microvm.writableStoreOverlay = "/nix/.rw-store";

  # Disk-backed /tmp so nix build scratch spills to disk instead of the
  # RAM-backed tmpfs root. Sparse image: costs only what's used.
  microvm.volumes = [{
    image = "tmp.img";
    mountPoint = "/tmp";
    size = 32768; # 32 GiB
    fsType = "ext4";
    label = "tmp";
  }];

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
      tag = "persist-hermes";
      source = "hermes";
      mountPoint = "/var/lib/hermes";
      proto = "virtiofs";
    }
    {
      tag = "persist-acme";
      source = "acme";
      mountPoint = "/var/lib/acme";
      proto = "virtiofs";
    }
  ];
}
