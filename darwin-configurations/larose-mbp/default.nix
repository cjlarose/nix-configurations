{
  additionalPackages,
  darwin,
  home-manager,
  homeManagerStateVersion,
  nixDarwinStateVersion,
  nixpkgs,
  primaryUser,
  sharedOverlays
}:
let
  system = "aarch64-darwin";
  allowUnfreePredicate = import ../../shared/unfree-predicate.nix { inherit nixpkgs; };
in darwin.lib.darwinSystem {
  inherit system;
  modules = [
    ({ ... }: {
      environment.etc = {
        "sysctl.conf" = {
          enable = true;
          text = ''
            kern.maxfiles=131072
            kern.maxfilesperproc=65536
          '';
        };
      };
      environment.systemPackages = [
        additionalPackages.${system}.wrappedTailscale
        additionalPackages.${system}.wrappedWireshark
      ];
      programs.zsh = {
        enable = true;
        promptInit = "";
      };

      system.stateVersion = nixDarwinStateVersion;
      system.primaryUser = primaryUser;
      system.defaults.NSGlobalDomain.AppleShowAllFiles = true;

      nix = {
        extraOptions = ''
          experimental-features = nix-command flakes
        '';
        registry.nixpkgs.flake = nixpkgs;
        settings = {
          substituters = [
            "https://nixcache.toothyshouse.com"
          ];
          trusted-public-keys = [
            "nixcache.toothyshouse.com:kAyteiBuGtyLHPkrYNjDY8G5nNT/LHYgClgTwyVCnNQ="
          ];
        };
        nixPath = [
          "nixpkgs=${nixpkgs}"
          "darwin=${darwin}"
        ];
      };
      nixpkgs = {
        overlays = sharedOverlays ++ [
          (final: prev: {
            nodejs = nixpkgs.legacyPackages.${system}.nodejs_22;
          })
        ];
        config.allowUnfreePredicate = allowUnfreePredicate;
      };

      services.yabai = {
        enable = true;
        config = {
          layout = "stack";
        };
        extraConfig = ''
          yabai -m rule --add app="System Settings" manage=off
          yabai -m rule --add app="Vysor" manage=off
          yabai -m rule --add app="GIMP" manage=off
        '';
      };

      users.users.${primaryUser} = {
        home = "/Users/${primaryUser}";
      };
    })
    home-manager.darwinModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.${primaryUser} = (import ../../home/cjlarose) {
        inherit system additionalPackages;
        stateVersion = homeManagerStateVersion;
        include1Password = true;
        includeGnuSed = false;
        includeCoder = true;
        includeCopilotVim = true;
      };
    }
  ];
}
