{ nixpkgs, sharedOverlays, additionalPackages, home-manager, nixos-generators, pce, impermanence, ... }: {
  "builder" = (
    import ./builder {
      inherit nixpkgs sharedOverlays additionalPackages home-manager;
      stateVersion = "23.05";
    }
  );
  "bots" = (
    import ./bots {
      inherit nixpkgs sharedOverlays additionalPackages home-manager pce impermanence;
      stateVersion = "23.11";
    }
  );
  "palworld" = (
    import ./palworld {
      inherit nixpkgs sharedOverlays additionalPackages home-manager;
      stateVersion = "23.11";
    }
  );
  "pt-dev" = (
    import ./pt-dev.nix {
      inherit nixpkgs sharedOverlays additionalPackages home-manager;
      stateVersion = "23.05";
    }
  );
  "photos" = (
    import ./photos.nix {
      inherit nixpkgs sharedOverlays additionalPackages home-manager;
      stateVersion = "23.05";
    }
  );
}
