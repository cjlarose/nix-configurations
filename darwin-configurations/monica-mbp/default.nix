{
  additionalPackages,
  darwin,
  home-manager,
  nixpkgs,
  sharedOverlays
}:
let
  system = "x86_64-darwin";
  stateVersion = "23.11";
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
      };
      users.users.monicahung = {
        home = "/Users/monicahung";
      };
    })
    home-manager.darwinModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.monicahung = import ../../home/monicahung;
      home-manager.extraSpecialArgs = {
        inherit system stateVersion additionalPackages;
        configurationName = "Monica-MacBook-Pro-Home";
        email = "monica.hung11@gmail.com";
      };
    }
  ];
}
