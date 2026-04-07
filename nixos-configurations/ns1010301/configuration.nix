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
      allowedTCPPorts = [
        25565  # minecraft (existing)
      ];
      interfaces."enp1s0f0".allowedUDPPorts = [
        41642  # tailscale for pt-docker-cjlarose guest
      ];
      interfaces."microvm".allowedUDPPorts = [
        67  # DHCP server for microvm bridge (bridge interface only)
      ];
    };
    nat = {
      enable = true;
      externalInterface = "enp1s0f0";
      internalInterfaces = [ "microvm" ];
      forwardPorts = [{
        destination = "10.0.0.2:41642";
        proto = "udp";
        sourcePort = 41642;
      }];
    };
  };

  systemd.network.enable = true;

  # Bridge for microvm guests
  systemd.network.netdevs."10-microvm".netdevConfig = {
    Kind = "bridge";
    Name = "microvm";
  };

  systemd.network.networks."10-microvm" = {
    matchConfig.Name = "microvm";
    networkConfig = {
      DHCPServer = true;
      IPv6SendRA = true;
    };
    addresses = [{
      Address = "10.0.0.1/24";
    }];
  };

  # Attach all VM TAP interfaces to the bridge
  systemd.network.networks."11-microvm" = {
    matchConfig.Name = "vm-*";
    networkConfig.Bridge = "microvm";
  };

  # No ports are forwarded — all guest services are accessed via SSH tunnel:
  # ssh -L 8443:10.0.0.2:8443 -L 9000:10.0.0.2:9000 -L 2376:10.0.0.2:2376 cjlarose@ns1010301.cjlarose.dev

  boot.kernelParams = [ "console=ttyS1,115200" ];
  systemd.services."serial-getty@ttyS1".enable = true;

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
      symlinks = let modpack = additionalPackages.${system}.minecraft-modpack; in {
        mods = "${modpack}/mods";
      };
      files = let modpack = additionalPackages.${system}.minecraft-modpack; in {
        "config/aether-common.toml" = "${modpack}/config/aether-common.toml";
        "config/amendments-common.json" = "${modpack}/config/amendments-common.json";
        "config/archers/items_v2.json" = "${modpack}/config/archers/items_v2.json";
        "config/betterendisland-fabric-1_20.toml" = "${modpack}/config/betterendisland-fabric-1_20.toml";
        "config/bewitchment.json" = "${modpack}/config/bewitchment.json";
        "config/biomesoplenty/generation.toml" = "${modpack}/config/biomesoplenty/generation.toml";
        "config/deeperdarker.json5" = "${modpack}/config/deeperdarker.json5";
        "config/DistantHorizons.toml" = "${modpack}/config/DistantHorizons.toml";
        "config/explorerscompass.json" = "${modpack}/config/explorerscompass.json";
        "config/farmersdelight-common.toml" = "${modpack}/config/farmersdelight-common.toml";
        "config/frostiful.json" = "${modpack}/config/frostiful.json";
        "config/goblintraders-entities.toml" = "${modpack}/config/goblintraders-entities.toml";
        "config/lootr.json" = "${modpack}/config/lootr.json";
        "config/magnumtorch-server.toml" = "${modpack}/config/magnumtorch-server.toml";
        "config/mysticsbiomes-common.json" = "${modpack}/config/mysticsbiomes-common.json";
        "config/origins_server.json" = "${modpack}/config/origins_server.json";
        "config/paladins/items_v5.json" = "${modpack}/config/paladins/items_v5.json";
        "config/perfectplushie-loot.toml" = "${modpack}/config/perfectplushie-loot.toml";
        "config/plushie_buddies.json" = "${modpack}/config/plushie_buddies.json";
        "config/rogues/items_v2.json" = "${modpack}/config/rogues/items_v2.json";
        "config/rpg_series/loot_v2.json" = "${modpack}/config/rpg_series/loot_v2.json";
        "config/scorchful.json" = "${modpack}/config/scorchful.json";
        "config/supplementaries-common.json" = "${modpack}/config/supplementaries-common.json";
        "config/ubesdelight.json" = "${modpack}/config/ubesdelight.json";
        "config/universal-graves/config.json" = "${modpack}/config/universal-graves/config.json";
        "config/waystones-common.toml" = "${modpack}/config/waystones-common.toml";
        "config/wizards/items_v4.json" = "${modpack}/config/wizards/items_v4.json";
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

  fileSystems."/var/lib/microvms/pt-docker-cjlarose/docker" = {
    device = "tank/microvms/pt-docker-cjlarose/docker";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/pt-docker-cjlarose/acme" = {
    device = "tank/microvms/pt-docker-cjlarose/acme";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/pt-docker-cjlarose/ssh" = {
    device = "tank/microvms/pt-docker-cjlarose/ssh";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/pt-docker-cjlarose/home" = {
    device = "tank/microvms/pt-docker-cjlarose/home";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/pt-docker-cjlarose/secrets" = {
    device = "tank/microvms/pt-docker-cjlarose/secrets";
    fsType = "zfs";
  };
  fileSystems."/var/lib/microvms/pt-docker-cjlarose/tailscale" = {
    device = "tank/microvms/pt-docker-cjlarose/tailscale";
    fsType = "zfs";
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
