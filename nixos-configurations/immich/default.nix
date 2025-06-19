{ nixpkgs, sharedOverlays, additionalPackages, home-manager, stateVersion, impermanence, disko, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    (import ./disk-config.nix { inherit disko; })
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion system; })
    ({ pkgs, config, ... } : {
      imports = [
        impermanence.nixosModules.impermanence
      ];
      environment.persistence = {
        "/persistence" = {
          hideMounts = true;
          directories = [
            {
              directory = "/etc/nixos";
            }
            {
              directory = "/var/lib/acme";
              user = "acme";
              group = "acme";
              mode = "0755";
            }
            {
              directory = config.services.postgresql.dataDir;
              user = config.users.users.postgres.name;
              group = config.users.users.postgres.group;
              mode = "0700";
            }
            {
              directory = "/var/lib/tailscale";
              user = "root";
              group = "root";
              mode = "0700";
            }
            {
              directory = config.services.redis.servers.immich.settings.dir;
              user = config.services.redis.servers.immich.user;
              group = config.services.redis.servers.immich.group;
              mode = "0700";
            }
          ];
          users = {
            cjlarose = {
              directories = [
                ".ssh"
                "workspace"
              ];
            };
          };
        };

        "/library" = {
          hideMounts = true;
          directories = [
            {
              directory = config.services.immich.mediaLocation;
              user = config.users.users.immich.name;
              group = config.users.users.immich.group;
              mode = "0700";
            }
            {
              directory = "/var/cache/restic-backups-backblaze";
              user = "root";
              group = "root";
              mode = "0700";
            }
          ];
        };
      };
    })
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.cjlarose = (import ../../home/cjlarose) {
        inherit system stateVersion additionalPackages;
        include1Password = false;
        includeDockerClient = false;
        includeGnuSed = true;
        includeCoder = false;
        includeCopilotVim = false;
      };
    }
  ];
}
