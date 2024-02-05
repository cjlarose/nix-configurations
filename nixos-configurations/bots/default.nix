{ nixpkgs, sharedOverlays, additionalPackages, home-manager, nixos-generators, stateVersion, pce, impermanence, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    ({ pkgs, ... }: {
      imports = [
        nixos-generators.nixosModules.all-formats
      ];

      formatConfigs.proxmox = { config, ... }: {
        proxmox.qemuConf = {
          name = "nixos-bots";
          net0 = "virtio=00:00:00:00:00:00,bridge=vmbr1,firewall=1";
          bios = "ovmf";
        };
      };

      boot.loader.systemd-boot.enable = true;
    })
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion pce system; })
    ({ pkgs, ... } : {
      imports = [
        impermanence.nixosModules.impermanence
      ];
      environment.persistence."/persistence" = {
        hideMounts = true;
        users = {
          bot = {
            directories = [
              ".config/chromium/pixel-cats-end"
              ".config/pce"
              ".vnc"
            ];
          };
          cjlarose = {
            directories = [
              ".config/chromium/pixel-cats-end"
              ".ssh"
              "workspace"
            ];
          };
        };
      };
    })
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.cjlarose = import ../../home;
      home-manager.extraSpecialArgs = {
        inherit system stateVersion additionalPackages;
        server = true;
      };
    }
  ];
}
