{ nixpkgs, sharedOverlays, additionalPackages, home-manager, pce, impermanence, disko, nixos-generators, ... }: {
  "builder" = (
    import ./builder {
      inherit nixpkgs sharedOverlays additionalPackages home-manager;
      stateVersion = "23.05";
    }
  );
  "bootstrap" = (
    import ./bootstrap {
      inherit nixpkgs sharedOverlays disko impermanence nixos-generators;
      stateVersion = "23.11";
    }
  );
  "bots" = (
    import ./bots {
      inherit nixpkgs home-manager sharedOverlays additionalPackages pce impermanence;
      stateVersion = "23.11";
    }
  );
  "cache" = (
    import ./cache {
      inherit nixpkgs home-manager sharedOverlays additionalPackages impermanence;
      stateVersion = "24.05";
    }
  );
  "coder" = (
    import ./coder {
      inherit nixpkgs home-manager sharedOverlays additionalPackages impermanence;
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
