{ nixpkgs, nixpkgs-24-05, sharedOverlays, additionalPackages, home-manager, home-manager-24-05, pce, impermanence, disko, ... }: {
  "builder" = (
    import ./builder {
      inherit nixpkgs sharedOverlays additionalPackages home-manager;
      stateVersion = "23.05";
    }
  );
  "bootstrap" = (
    import ./bootstrap {
      inherit nixpkgs sharedOverlays disko impermanence;
      stateVersion = "23.11";
    }
  );
  "bots" = (
    import ./bots {
      inherit nixpkgs sharedOverlays additionalPackages home-manager pce impermanence;
      stateVersion = "23.11";
    }
  );
  "cache" = (
    import ./cache {
      inherit sharedOverlays additionalPackages impermanence;
      nixpkgs = nixpkgs-24-05;
      home-manager = home-manager-24-05;
      stateVersion = "24.05";
    }
  );
  "dns" = (
    import ./dns {
      inherit nixpkgs sharedOverlays additionalPackages disko impermanence home-manager;
      stateVersion = "23.11";
    }
  );
  "media" = (
    import ./media {
      inherit nixpkgs sharedOverlays additionalPackages disko impermanence home-manager;
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
