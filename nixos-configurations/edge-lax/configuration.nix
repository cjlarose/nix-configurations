{ pkgs, config, lib, modulesPath, nixpkgs, sharedOverlays, stateVersion, system, intranetHosts, ... }: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./hardware-configuration.nix
  ];

  networking = {
    hostName = "edge-lax";
    hostId = "ca194f09";
    extraHosts = builtins.readFile "${intranetHosts}/hosts";
    firewall.interfaces."tailscale0".allowedTCPPorts = [
      80   # nginx HTTP to HTTPS redirects
      443  # nginx SNI stream proxy
    ];
  };

  boot.kernelParams = [ "console=ttyS1,115200n8" "console=tty0" ];
  systemd.services."serial-getty@ttyS1".enable = true;

  system.stateVersion = stateVersion;

  nix = {
    registry.nixpkgs.flake = nixpkgs;
  };

  nixpkgs.overlays = sharedOverlays;

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    iotop
    lsof
  ];

  services.openssh = {
    enable = true;
    openFirewall = false;
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

  services.resolved.enable = true;

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  # SNI-based TCP proxy to backend services over Tailscale.
  # TLS termination is handled by the backend hosts.
  services.nginx = {
    enable = true;

    # Redirect HTTP to HTTPS
    virtualHosts."jellyfin.cjlarose.dev" = {
      listen = [{ addr = "0.0.0.0"; port = 80; }];
      locations."/".return = "301 https://$host$request_uri";
    };
    virtualHosts."transmission.cjlarose.dev" = {
      listen = [{ addr = "0.0.0.0"; port = 80; }];
      locations."/".return = "301 https://$host$request_uri";
    };

    streamConfig = ''
      resolver 127.0.0.53;

      map $ssl_preread_server_name $backend {
        jellyfin.cjlarose.dev    media.cjlarose.dev:443;
        transmission.cjlarose.dev media.cjlarose.dev:443;
      }

      server {
        listen 443;
        proxy_pass $backend;
        ssl_preread on;
      }
    '';
  };

  programs.zsh.enable = true;

  users.mutableUsers = false;

  users.users = {
    cjlarose = {
      uid = 1000;
      isNormalUser = true;
      home = "/home/cjlarose";
      extraGroups = [ "wheel" ];
      shell = pkgs.zsh;
      hashedPassword = "$6$YLrfXTwu61JGE.v8$kR5ZdMso2lcnyy7s7GXkIb.kLDyQ2UW3aDyGerQYni96g2kPC1MIY48Y9Q3SdYe2ycuVCrKgH6DlOjUUsK02s0";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFtA/9w60OssA+Eji+Ygvd1XCJk/zw/uYLdiiaevELu cjlarose"
      ];
    };
  };
}
