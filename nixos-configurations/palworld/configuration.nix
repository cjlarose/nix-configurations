{ nixpkgs, sharedOverlays, stateVersion, ... }: { pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "palworld";

  system.stateVersion = stateVersion;

  networking.firewall.allowedUDPPorts = [
    8211 # palworld game server
  ];

  nix = {
    package = pkgs.nixFlakes;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    registry.nixpkgs.flake = nixpkgs;
    nixPath = [ "nixpkgs=${nixpkgs.outPath}" ];
  };

  nixpkgs.overlays = sharedOverlays;

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    iotop
    lsof
  ];

  virtualisation.docker = {
    enable = true;
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  services.cron = {
    enable = true;
    systemCronJobs = [
      "0 2,8,14,20 * * * root ${pkgs.systemd}/bin/systemctl try-restart palworld-server"
    ];
  };

  systemd.services."palworld-server" = {
    description = "Palworld server";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "exec";
      StandardInput = "null";
      StandardOutput = "journal";
      StandardError = "journal";
      WorkingDirectory = "/home/pals/palworld";
      ExecStart = ''
        ${pkgs.docker}/bin/docker compose up --remove-orphans
      '';
      ExecStop = ''
        ${pkgs.docker}/bin/docker compose down
      '';
      User = "pals";
      Restart = "always";
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

  users.users.pals = {
    isNormalUser = true;
    home = "/home/pals";
    extraGroups = [ "docker" ];
  };
}
