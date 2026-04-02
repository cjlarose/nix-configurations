{
  description = "Shared darwin modules";

  outputs = { self }: {
    darwinModules = {
      tailscale-dns = import ./tailscale-dns.nix;
    };
  };
}
