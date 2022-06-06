{
  description = "NixOS-based development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-22.05";
  };

  outputs = { self, nixpkgs }: {
    nixosConfigurations.dev = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        ({ pkgs, ... }: {
          imports = [ ./hardware-configuration.nix ];

          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = true;

          system.stateVersion = "22.05";

          nix = {
            package = pkgs.nixFlakes;
            extraOptions = ''
              experimental-features = nix-command flakes
            '';
          };

          services.openssh = {
            enable = true;
            passwordAuthentication = true;
            permitRootLogin = "yes";
          };
          users.users.root.initialPassword = "root";
        })
      ];
    };
  };
}
