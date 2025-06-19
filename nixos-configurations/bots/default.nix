{ nixpkgs, sharedOverlays, additionalPackages, home-manager, stateVersion, pce, impermanence, disko, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    (import ./disk-config.nix { inherit disko; })
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion pce system additionalPackages; })
    ({ pkgs, ... } : {
      imports = [
        impermanence.nixosModules.impermanence
      ];
      environment.persistence."/persistence" = {
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
        ];
        users = {
          bot = {
            directories = [
              ".config/chicken-smoothie-automation"
              ".config/chromium"
              ".config/pce"
              ".local/share/pce-dailies"
              ".vnc"
            ];
          };
          cjlarose = {
            directories = [
              ".config/chromium"
              ".local/share/pce-dailies"
              ".ssh"
              "workspace"
            ];
          };
          monicahung = {
            directories = [
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
      home-manager.users.cjlarose = (import ../../home/cjlarose) {
        inherit system stateVersion additionalPackages;
        includeCopilotVim = true;
      };
    }
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.monicahung = (import ../../home/monicahung) {
        inherit system stateVersion additionalPackages;
        configurationName = "";
        email = "monica.hung11@gmail.com";
      };
    }
  ];
}
