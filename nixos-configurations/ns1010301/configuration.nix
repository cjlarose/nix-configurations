{ nixpkgs, sharedOverlays, stateVersion, system, additionalPackages, nix-minecraft, ... }:
let
  allowUnfreePredicate = import ../../shared/unfree-predicate.nix { inherit nixpkgs; };
in { pkgs, config, ... }: {
  imports = [
    ./hardware-configuration.nix
  ];

  networking = {
    hostName = "ns1010301";
    hostId = "eae273e3";
    firewall = {
      enable = true;
      allowedTCPPorts = [ 25565 ];
    };
  };

  system.stateVersion = stateVersion;

  nix = {
    registry.nixpkgs.flake = nixpkgs;
  };

  nixpkgs.overlays = sharedOverlays ++ [ nix-minecraft.overlays.default ];
  nixpkgs.config.allowUnfreePredicate = allowUnfreePredicate;

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    iotop
    lsof
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
    port = 41641;
  };

  services.minecraft-servers = {
    enable = true;
    eula = true;
    servers.mellowcatfe = {
      enable = true;
      package = pkgs.minecraftServers.fabric-1_20_1;
      symlinks = {
        mods = "${additionalPackages.${system}.minecraft-modpack}/mods";
      };
      serverProperties = {
        server-port = 25565;
        difficulty = "hard";
        gamemode = "survival";
        motd = "mellowcatfe";
        white-list = true;
        view-distance = 6;
        spawn-protection = 0;
        max-tick-time = -1;
      };
      whitelist = {
        "360NoScopeSWAG" = "6c6fc1f9-055e-4865-9527-bf65f3424b31";
        "366_TKM" = "00056bf3-a18b-46d9-aa0e-6134be60968c";
        Drakladow = "b522eab1-ec39-4e85-ad79-80222c5ec7a6";
        HotdogJesus = "c3228821-c579-4a84-90b2-fc6915f6f3ad";
        HyoNereus = "35c8231f-f26d-450a-aaeb-aca2c4035af2";
        itisover9k = "0b04229f-2f6f-4a45-a2ea-0de0dbf2e7bc";
        k055 = "77481ba6-4e06-43d0-8bfb-3c8e1538a52a";
        linnbunni = "13e3d020-8035-4899-af20-4de5630f812c";
        MellowTheButler = "5f6dde40-c8dc-46c3-93ac-01f18183a175";
        Obelisk69 = "2c2d34ef-b368-4934-925e-ed4d55db3eb1";
        OliverKween = "83834820-d8dc-4c17-b970-072d287b5f19";
        StrawberryBloons = "8480183e-52b2-43e7-8beb-2fa50836099e";
        TheFreinder = "8cefc33b-0d9e-4fed-b22b-62bc3e8f0a71";
        TheKingOEmeralds = "fcdbe0c6-43e2-45c5-839e-293cd894c8bf";
      };
      operators = {
        "360NoScopeSWAG" = {
          uuid = "6c6fc1f9-055e-4865-9527-bf65f3424b31";
          level = 4;
          bypassesPlayerLimit = false;
        };
        MellowTheButler = {
          uuid = "5f6dde40-c8dc-46c3-93ac-01f18183a175";
          level = 4;
          bypassesPlayerLimit = false;
        };
      };
    };
  };

  services.zfs.expandOnBoot = "all";

  programs.ssh.startAgent = true;

  programs.zsh.enable = true;

  users = {
    mutableUsers = false;
    users = {
      minecraft = {
        uid = 900;
      };
      cjlarose = {
        uid = 1000;
        isNormalUser = true;
        home = "/home/cjlarose";
        extraGroups = [ "wheel" "minecraft" ];
        shell = pkgs.zsh;
        hashedPassword = "$6$YLrfXTwu61JGE.v8$kR5ZdMso2lcnyy7s7GXkIb.kLDyQ2UW3aDyGerQYni96g2kPC1MIY48Y9Q3SdYe2ycuVCrKgH6DlOjUUsK02s0";
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFtA/9w60OssA+Eji+Ygvd1XCJk/zw/uYLdiiaevELu cjlarose"
        ];
      };
    };
    groups = {
      minecraft = {
        gid = 900;
      };
    };
  };
}
