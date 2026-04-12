{ microvm, nix-minecraft, ... }: {
  imports = [
    microvm.nixosModules.microvm
    nix-minecraft.nixosModules.minecraft-servers
    ./configuration.nix
  ];

  microvm.hypervisor = "qemu";
  microvm.vcpu = 6;
  microvm.mem = 25600;

  microvm.interfaces = [{
    type = "tap";
    id = "vm-mc-mellow";
    mac = "02:00:00:00:00:02";
  }];

  microvm.writableStoreOverlay = "/nix/.rw-store";

  microvm.shares = [
    {
      tag = "persist-nix-rw-store";
      source = "nix-rw-store";
      mountPoint = "/nix/.rw-store";
      proto = "virtiofs";
    }
    {
      tag = "persist-minecraft";
      source = "minecraft";
      mountPoint = "/srv/minecraft";
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
  ];
}
