{ nixpkgs, sharedOverlays, stateVersion, system, additionalPackages, pkgs, ... }:
let
  toothyshouseHosts = pkgs.runCommand "toothyshouse-hosts" { } ''
    ${pkgs.gawk}/bin/awk '
      $1 !~ /^#/ {
        for (i = 2; i <= NF; i++) {
          if ($i ~ /\.toothyshouse\.com$/) print $1, $i;
        }
      }
    ' ${additionalPackages.${system}.intranetHosts}/hosts > "$out"
  '';
in
{
  imports = [
    ./hardware-configuration.nix
  ];

  networking = {
    hostName = "dns";
    hostId = "3889a1e4";
    firewall = {
      enable = true;
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };
    nameservers = [ "1.1.1.1" "1.0.0.1" ];
    defaultGateway = {
      address = "192.168.2.1";
      interface = "ens18";
    };
  };

  system.stateVersion = stateVersion;

  nix = {
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    gc = {
      automatic = true;
      options = "--delete-older-than 14d";
    };
    registry.nixpkgs.flake = nixpkgs;
    nixPath = [ "nixpkgs=${nixpkgs.outPath}" ];
    settings = {
      # Allow the operator to push closures here (push-deploy via
      # `nix copy` / `nixos-rebuild --target-host`). cjlarose already has
      # passwordless sudo, so trusting the nix user grants no additional privilege.
      trusted-users = [ "root" "cjlarose" ];
    };
  };

  nixpkgs.overlays = sharedOverlays;

  security.sudo.wheelNeedsPassword = false;

  services.zfs.expandOnBoot = "all";

  # Subnet router for the home LAN, taking over from pfSense (whose Tailscale is
  # off, and which the UniFi migration retires). Every toothyshouse.com name
  # resolves to its LAN address, so LAN-only devices connect directly and tailnet
  # devices reach the same address through this route. Tailscale SNATs forwarded
  # traffic by default, so LAN hosts reply to this VM and need no route back to
  # 100.64.0.0/10. The route must be approved once in the admin console.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";
    extraSetFlags = [ "--advertise-routes=192.168.2.0/24" ];
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
    hostKeys = [
      {
        path = "/persistence/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/persistence/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];
  };

  services.adguardhome = {
    enable = true;
    mutableSettings = false;
    settings = {
      dns = {
        bind_hosts = ["192.168.2.104"];
        port = 53;
        bootstrap_dns = ["1.1.1.1" "1.0.0.1"];
        upstream_dns = [
          "https://dns.cloudflare.com/dns-query"
          "[/toothyshouse.com/]192.168.2.105"
        ];
      };
    };
  };

  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    settings = {
      addn-hosts = "${toothyshouseHosts}";
      bind-dynamic = true;
      bogus-priv = true;
      domain-needed = true;
      interface = [ "tailscale0" ];
      local = [ "/toothyshouse.com/" ];
      listen-address = ["192.168.2.105"];
      no-hosts = true;
      no-resolv = true;
      server = [];
    };
  };

  systemd.services.dnsmasq = {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
  };

  programs.ssh.startAgent = true;

  programs.zsh.enable = true;

  users.mutableUsers = false;

  users.users.cjlarose = {
    # Pin the uid: /home is now a persistent tank/home dataset owned by 1000,
    # but /var/lib/nixos (the uid-map) lives on the ephemeral root and is
    # rolled back each boot, so an unpinned uid could be reassigned and break
    # home ownership. Matches the cache/bots hosts.
    uid = 1000;
    isNormalUser = true;
    home = "/home/cjlarose";
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFtA/9w60OssA+Eji+Ygvd1XCJk/zw/uYLdiiaevELu cjlarose"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILXv1L7zwTqnZJUfqOUVvAe7HI8CoAbVAHBPJhQsohxw cjlarose@ns1010301"
    ];
  };
}
