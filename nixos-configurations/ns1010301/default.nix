{ nixpkgs, sharedOverlays, additionalPackages, home-manager, stateVersion, impermanence, disko, determinate, microvm, picktrace-nix-configurations, cjlarose-home-manager-modules, mattpocock-skills, self, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    microvm.nixosModules.host
    ({ ... }: {
      microvm.vms."pt-docker-cjlarose" = {
        flake = picktrace-nix-configurations;
      };
      microvm.vms."minecraft-mellowcatfe" = {
        flake = self;
      };
      microvm.vms."media" = {
        flake = self;
      };
      microvm.autostart = [ "pt-docker-cjlarose" "minecraft-mellowcatfe" "media" ];
    })
    determinate.nixosModules.default
    (import ./disk-config.nix { inherit disko; })
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion system additionalPackages; })
    ({ pkgs, config, ... } : {
      imports = [
        impermanence.nixosModules.impermanence
      ];
      environment.persistence = {
        "/persistence" = {
          hideMounts = true;
          directories = [
            {
              directory = "/var/lib/tailscale";
              user = "root";
              group = "root";
              mode = "0700";
            }
            {
              directory = "/var/cache/restic-backups-minecraft-mellowcatfe";
              user = "root";
              group = "root";
              mode = "0755";
            }
            {
              directory = "/var/lib/acme";
              user = "acme";
              group = "acme";
              mode = "0755";
            }
          ];
        };
      };
    })
    ({ pkgs, ... }: {
      users.users.picktrace = {
        uid = 10001;
        isNormalUser = true;
        home = "/home/picktrace";
        extraGroups = [ "docker" "wheel" ];
        shell = pkgs.zsh;
        hashedPassword = "$6$YLrfXTwu61JGE.v8$kR5ZdMso2lcnyy7s7GXkIb.kLDyQ2UW3aDyGerQYni96g2kPC1MIY48Y9Q3SdYe2ycuVCrKgH6DlOjUUsK02s0";
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFtA/9w60OssA+Eji+Ygvd1XCJk/zw/uYLdiiaevELu cjlarose"
        ];
      };
    })
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.cjlarose = (import ../../home/cjlarose) {
        inherit system stateVersion additionalPackages mattpocock-skills;
      };
      home-manager.users.picktrace = picktrace-nix-configurations.homeManagerModules.picktrace-cjlarose;
      home-manager.extraSpecialArgs = {
        stateVersion = "25.11";
        inherit cjlarose-home-manager-modules;
      };
    }
  ];
}
