{ pkgs, config, lib, sharedOverlays, stateVersion, system, additionalPackages, home-manager, ... }: {

  imports = [
    home-manager.nixosModules.home-manager
  ];

  networking = {
    hostName = "media";
    useNetworkd = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 80 443 ];
    };
  };

  systemd.network.enable = true;

  systemd.network.networks."20-lan" = {
    matchConfig.MACAddress = "02:00:00:00:00:03";
    networkConfig = {
      Address = ["10.0.0.4/24"];
      Gateway = "10.0.0.1";
      DNS = ["1.1.1.1"];
    };
  };

  time.timeZone = "America/Los_Angeles";

  system.stateVersion = stateVersion;

  # Compressed RAM-backed swap — cushions bursty memory spikes into compressed
  # RAM rather than OOM-killing. zstd backs ~2-3x its real RAM cost.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # /tmp is a disk-backed block volume (see default.nix), not the RAM tmpfs root.
  # Clear it on boot to keep the tmpfs-style clear-on-reboot semantics (and set
  # the 1777 perms a freshly-formatted /tmp lacks).
  boot.tmp.cleanOnBoot = true;

  nixpkgs.overlays = sharedOverlays;

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    iotop
    lsof
    (writeShellScriptBin "jellyfin-refresh" ''
      set -euo pipefail
      source /persistence/secrets/jellyfin.env
      ${curl}/bin/curl -sf -o /dev/null \
        -X POST "http://localhost:8096/Library/Refresh" \
        -H "X-Emby-Token: $JELLYFIN_API_KEY"
      echo "Library scan triggered"
    '')
  ];

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

  services.tailscale = {
    enable = true;
    openFirewall = true;
    port = 41644;
  };

  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      transmission = {
        image = "haugene/transmission-openvpn:5.4.1";
        environment = {
          OPENVPN_PROVIDER = "PIA";
          OPENVPN_CONFIG = "ca_ontario";
        };
        environmentFiles = [
          "/persistence/secrets/transmission-openvpn.env"
        ];
        ports = [
          "127.0.0.1:9091:9091"
        ];
        volumes = [
          "/persistence/media/transmission-openvpn/data:/data"
          "/persistence/media/transmission-openvpn/config:/config"
        ];
        extraOptions = [
          "--cap-add=NET_ADMIN"
        ];
      };
    };
  };

  # OpenVPN's --ping-restart teardown exits 0, so a dropped PIA tunnel looks
  # like a clean stop and oci-containers' Restart=on-failure never brings the
  # container back. On 2026-07-08 that left transmission down for over a month,
  # surfacing only as a 502 from the nginx vhost below.
  systemd.services.docker-transmission.serviceConfig = {
    Restart = lib.mkForce "always";
    RestartSec = 10;
  };

  services.jellyfin = {
    enable = true;
    cacheDir = "/var/lib/jellyfin/cache";
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "cjlarose@gmail.com";
    certs = {
      "transmission.cjlarose.dev" = {
        dnsPropagationCheck = false;
        dnsProvider = "digitalocean";
        dnsResolver = "1.1.1.1:53";
        domain = "transmission.cjlarose.dev";
        environmentFile = "/persistence/secrets/digitalocean.secret";
      };
      "jellyfin.cjlarose.dev" = {
        dnsPropagationCheck = false;
        dnsProvider = "digitalocean";
        dnsResolver = "1.1.1.1:53";
        domain = "jellyfin.cjlarose.dev";
        environmentFile = "/persistence/secrets/digitalocean.secret";
      };
    };
  };

  services.nginx = {
    enable = true;
    virtualHosts = {
      "transmission.cjlarose.dev" = {
        enableACME = true;
        acmeRoot = null;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:9091";
          recommendedProxySettings = true;
        };
      };
      "jellyfin.cjlarose.dev" = {
        enableACME = true;
        acmeRoot = null;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8096";
          recommendedProxySettings = true;
        };
      };
    };
  };

  programs.zsh.enable = true;

  users = {
    mutableUsers = false;
    users = {
      jellyfin.uid = 998;
      cjlarose = {
        uid = 1000;
        isNormalUser = true;
        home = "/home/cjlarose";
        extraGroups = [ "wheel" ];
        shell = pkgs.zsh;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFtA/9w60OssA+Eji+Ygvd1XCJk/zw/uYLdiiaevELu cjlarose"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILXv1L7zwTqnZJUfqOUVvAe7HI8CoAbVAHBPJhQsohxw cjlarose@ns1010301"
        ];
      };
    };
    groups.jellyfin.gid = 998;
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.cjlarose = (import ../../home/cjlarose) {
    inherit system stateVersion additionalPackages;
  };
}
