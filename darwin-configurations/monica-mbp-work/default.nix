{
  additionalPackages,
  darwin,
  home-manager,
  nixpkgs,
  sharedOverlays
}:
let
  system = "aarch64-darwin";
  stateVersion = "24.05";
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
      services.nix-daemon.enable = true;
      programs.zsh = {
        enable = true;
        promptInit = "";
      };
      system.stateVersion = 4;
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
      };
       nixpkgs = {
        overlays = sharedOverlays ++ [
          (final: prev: {
            nodejs = nixpkgs.legacyPackages.${system}.nodejs_20;
          })
        ];
        config.allowUnfreePredicate = allowUnfreePredicate;
      };
      users.users."monica.hung" = {
        home = "/Users/monica.hung";
      };
    })
    home-manager.darwinModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users."monica.hung" = (import ../../home/monicahung) {
        inherit system stateVersion additionalPackages;
        includeCopilotVim = true;
        configurationName = "Monica-MacBook-Pro-Work";
        email = "monica.hung@agilebits.com";
        yarnOverride = true;
      };
    }
  ];
}
