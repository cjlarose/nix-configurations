{ home-manager, stateVersion, additionalPackages, system, impermanence, disko, determinate, microvm, picktrace-nix-configurations, cjlarose-llm-wiki, cjlarose-home-manager-modules, mattpocock-skills, superpowers, self, ... }: {
  imports = [
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
      microvm.vms."hermes" = {
        flake = self;
      };
      microvm.autostart = [ "pt-docker-cjlarose" "minecraft-mellowcatfe" "media" "hermes" ];
    })
    determinate.nixosModules.default
    (import ./disk-config.nix { inherit disko; })
    ./configuration.nix
    ({ pkgs, config, ... }: {
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
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFtA/9w60OssA+Eji+Ygvd1XCJk/zw/uYLdiiaevELu cjlarose"
        ];
      };
    })
    home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.cjlarose = {
        imports = [
          ((import ../../home/cjlarose) {
            inherit system stateVersion additionalPackages mattpocock-skills superpowers;
            llm-wiki-path = "/home/cjlarose/worktrees/cjlarose/llm-wiki/default";
            llm-wiki-module = cjlarose-llm-wiki.homeManagerModules.default;
          })
        ];
        # Browser automation for cjlarose's sessions on this host. The shared
        # home/cjlarose profile defaults enablePlaywrightMcp off so the chromium
        # closure only lands where it's wanted; scope the enable to ns1010301
        # here rather than in home/cjlarose (which fans out to every linux host).
        cjlarose.claude.enablePlaywrightMcp = true;
      };
      home-manager.users.picktrace = picktrace-nix-configurations.homeManagerModules.picktrace-cjlarose;
      home-manager.extraSpecialArgs = {
        stateVersion = "25.11";
        inherit cjlarose-home-manager-modules;
      };
    }
  ];
}
