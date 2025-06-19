{
  additionalPackages,
  darwin,
  home-manager,
  nixpkgs,
  sharedOverlays
}:
let
  system = "aarch64-darwin";
  stateVersion = "23.05";
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
        nixPath = [
          "nixpkgs=${nixpkgs}"
          "darwin=${darwin}"
        ];
      };
      nixpkgs = {
        overlays = sharedOverlays ++ [
          (final: prev: {
            nodejs = nixpkgs.legacyPackages.${system}.nodejs_20;
          })
        ];
        config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [
          "1password-cli"
          "coder"
          "copilot.vim"
          "terraform"
        ];
      };

      services.yabai = {
        enable = true;
        config = {
          layout = "stack";
        };
        extraConfig = ''
          yabai -m rule --add app="System Settings" manage=off
          yabai -m rule --add app="Vysor" manage=off
        '';
      };

      users.users.chrislarose = {
        home = "/Users/chrislarose";
      };
    })
    home-manager.darwinModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.chrislarose = (import ../../home/cjlarose) {
        inherit system stateVersion additionalPackages;
        include1Password = true;
        includeGnuSed = false;
        includeCoder = true;
        includeCopilotVim = true;
      };
    }
  ];
}
