{ nixpkgs, sharedOverlays, stateVersion, system, ... }: { config, pkgs, ... }:
let
  allowUnfreePredicate = import ../../shared/unfree-predicate.nix { inherit nixpkgs; };
in {
  imports = [
    ./hardware-configuration.nix
  ];

  networking = {
    hostName = "media";
    hostId = "d202c7d5";
    firewall = {
      enable = true;
      allowedTCPPorts = [ 80 443 ];
    };
  };

  system.stateVersion = stateVersion;

  nix = {
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    registry.nixpkgs.flake = nixpkgs;
    nixPath = [ "nixpkgs=${nixpkgs.outPath}" ];
  };

  nixpkgs = {
    overlays = sharedOverlays;
    config.allowUnfreePredicate = allowUnfreePredicate;
  };

  environment.systemPackages = with pkgs; [
    git
    tmux
  ];

  security.sudo.wheelNeedsPassword = false;

  services.zfs.expandOnBoot = "all";

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

  services.plex = {
    enable = true;
    dataDir = "/persistence/plex";
    package = pkgs.plex.override {
      plexRaw = pkgs.plexRaw.overrideAttrs (finalAttrs: previousAttrs: {
        version = "1.42.1.10060-4e8b05daf";
        src = pkgs.fetchurl {
          url = "https://downloads.plex.tv/plex-media-server-new/${finalAttrs.version}/debian/plexmediaserver_${finalAttrs.version}_amd64.deb";
          hash = "sha256-OoItvG0IpgUKlZ0JmzDc2WqMtyZrlNCF7MCnUKqBl/Q=";
        };
      });
    };
  };

  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      transmission = {
        image = "haugene/transmission-openvpn";
        environment = {
          OPENVPN_PROVIDER = "PIA";
          OPENVPN_CONFIG = "ca_ontario";
        };
        environmentFiles = [
          "/persistence/transmission-openvpn/.env"
        ];
        ports = [
          "127.0.0.1:9091:9091"
        ];
        volumes = [
          "/persistence/transmission-openvpn/data:/data"
          "/persistence/transmission-openvpn/config:/config"
        ];
        extraOptions = [
          "--cap-add=NET_ADMIN"
        ];
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "cjlarose@gmail.com";
    certs = {
      "media.toothyshouse.com" = {
        dnsPropagationCheck = false;
        dnsProvider = "digitalocean";
        dnsResolver = "1.1.1.1:53";
        domain = "media.toothyshouse.com";
        environmentFile = "/persistence/acme/digitalocean.secret";
      };
      "transmission.toothyshouse.com" = {
        dnsPropagationCheck = false;
        dnsProvider = "digitalocean";
        dnsResolver = "1.1.1.1:53";
        domain = "transmission.toothyshouse.com";
        environmentFile = "/persistence/acme/digitalocean.secret";
      };
      "plex.toothyshouse.com" = {
        dnsPropagationCheck = false;
        dnsProvider = "digitalocean";
        dnsResolver = "1.1.1.1:53";
        domain = "plex.toothyshouse.com";
        environmentFile = "/persistence/acme/digitalocean.secret";
      };
    };
  };

  services.oauth2-proxy = {
    enable = true;
    keyFile = "/persistence/oauth2-proxy/.env";
    reverseProxy = true;
    email = {
      domains = ["*"];
    };
  };

  services.nginx = {
    enable = true;
    virtualHosts = {
      "media.toothyshouse.com" = {
        enableACME = true;
        acmeRoot = null;
        forceSSL = true;
        root = "/persistence/media";
        locations = {
          "/oauth2/" = {
            proxyPass = config.services.oauth2-proxy.httpAddress;
            extraConfig = ''
              proxy_set_header X-Auth-Request-Redirect $scheme://$host$request_uri;
            '';
            recommendedProxySettings = true;
          };

          "= /oauth2/auth" = {
            proxyPass = config.services.oauth2-proxy.httpAddress;
            extraConfig = ''
              proxy_set_header Content-Length   "";
              proxy_pass_request_body           off;
            '';
            recommendedProxySettings = true;
          };

          "/" = {
            extraConfig = ''
              auth_request /oauth2/auth;
              error_page 401 =403 /oauth2/sign_in;
              autoindex on;
              autoindex_exact_size off;
              charset utf-8; # serve the page using utf-8, since some filenames have special characters
            '';
          };
        };
      };

      "transmission.toothyshouse.com" = {
        enableACME = true;
        acmeRoot = null;
        forceSSL = true;
        locations = {
          "/oauth2/" = {
            proxyPass = config.services.oauth2-proxy.httpAddress;
            extraConfig = ''
              proxy_set_header X-Auth-Request-Redirect $scheme://$host$request_uri;
            '';
            recommendedProxySettings = true;
          };

          "= /oauth2/auth" = {
            proxyPass = config.services.oauth2-proxy.httpAddress;
            extraConfig = ''
              proxy_set_header Content-Length   "";
              proxy_pass_request_body           off;
            '';
            recommendedProxySettings = true;
          };

          "/" = {
            proxyPass = "http://127.0.0.1:9091";
            extraConfig = ''
              auth_request /oauth2/auth;
              error_page 401 =403 /oauth2/sign_in;
            '';
            recommendedProxySettings = true;
          };
        };
      };

      "plex.toothyshouse.com" = {
        enableACME = true;
        acmeRoot = null;
        forceSSL = true;
        locations = {
          "/" = {
            proxyPass = "http://127.0.0.1:32400";
            recommendedProxySettings = true;
          };
        };
      };
    };
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    port = 41642;
  };

  programs.ssh.startAgent = true;

  programs.zsh.enable = true;

  users.mutableUsers = false;

  users.users.cjlarose = {
    isNormalUser = true;
    home = "/home/cjlarose";
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
    hashedPassword = "$6$YLrfXTwu61JGE.v8$kR5ZdMso2lcnyy7s7GXkIb.kLDyQ2UW3aDyGerQYni96g2kPC1MIY48Y9Q3SdYe2ycuVCrKgH6DlOjUUsK02s0";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFtA/9w60OssA+Eji+Ygvd1XCJk/zw/uYLdiiaevELu cjlarose"
    ];
  };
}
