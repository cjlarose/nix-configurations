{ nixpkgs, sharedOverlays, stateVersion, system, ... }: { pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
  ];

  networking = {
    hostName = "bootstrap";
    hostId = "d202c7d5";
  };

  system.stateVersion = stateVersion;

  nix = {
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    registry.nixpkgs.flake = nixpkgs;
    nixPath = [ "nixpkgs=${nixpkgs.outPath}" ];
    settings = {
      substituters = [
        "https://nixcache.toothyshouse.com"
      ];
      trusted-public-keys = [
        "nixcache.toothyshouse.com:kAyteiBuGtyLHPkrYNjDY8G5nNT/LHYgClgTwyVCnNQ="
      ];
    };
  };

  nixpkgs.overlays = sharedOverlays;

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

  programs.ssh.startAgent = true;

  users.mutableUsers = false;

  users.users.cjlarose = {
    isNormalUser = true;
    home = "/home/cjlarose";
    extraGroups = [ "wheel" ];
    hashedPassword = "$6$YLrfXTwu61JGE.v8$kR5ZdMso2lcnyy7s7GXkIb.kLDyQ2UW3aDyGerQYni96g2kPC1MIY48Y9Q3SdYe2ycuVCrKgH6DlOjUUsK02s0";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFtA/9w60OssA+Eji+Ygvd1XCJk/zw/uYLdiiaevELu cjlarose"
    ];
  };
}
