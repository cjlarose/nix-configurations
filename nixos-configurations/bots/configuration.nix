{ nixpkgs, sharedOverlays, stateVersion, ... }: { pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "bots";

  system.stateVersion = stateVersion;

  nix = {
    package = pkgs.nixFlakes;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    registry.nixpkgs.flake = nixpkgs;
    buildMachines = [
      {
        hostName = "builder";
        system = "x86_64-linux";
        protocol = "ssh-ng";
        maxJobs = 4;
        speedFactor = 2;
        supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
        mandatoryFeatures = [ ];
      }
    ];
    distributedBuilds = true;
  };

  nixpkgs.overlays = sharedOverlays;

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    iotop
    lsof
    tigervnc
    xorg.xauth
    xterm
  ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  systemd.services."tigervnc-server" = {
    description = "TigerVNC Server";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      StandardError = "journal";
      ExecStart = ''
        ${pkgs.bash}/bin/bash -c '${pkgs.xorg.xauth}/bin/xauth -f ~/.Xauthority source - <<< "add :1 . $(${pkgs.util-linux}/bin/mcookie)" ; \
        trap "exit 0" USR1; \
        (trap "" USR1 && exec ${pkgs.tigervnc}/bin/Xvnc :1 -rfbauth ~/.vnc/passwd -desktop :1 -geometry 1600x1200) & wait ; \
        exit 1'
      '';
      Type = "forking";
      User = "cjlarose";
      Restart = "always";
      RestartSec = "10s";
    };
  };

  programs.ssh.startAgent = true;

  programs.zsh.enable = true;

  users.mutableUsers = false;

  users.users.cjlarose = {
    isNormalUser = true;
    home = "/home/cjlarose";
    extraGroups = [ "docker" "wheel" ];
    shell = pkgs.zsh;
    hashedPassword = "$6$YLrfXTwu61JGE.v8$kR5ZdMso2lcnyy7s7GXkIb.kLDyQ2UW3aDyGerQYni96g2kPC1MIY48Y9Q3SdYe2ycuVCrKgH6DlOjUUsK02s0";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFtA/9w60OssA+Eji+Ygvd1XCJk/zw/uYLdiiaevELu cjlarose"
    ];
  };
}
