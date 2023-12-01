{ nixpkgs, sharedOverlays, home-manager, nixos-generators, ... }: {
  "builder" = (
    import ./builder {
      inherit nixpkgs sharedOverlays home-manager nixos-generators;
      stateVersion = "23.05";
    }
  );
  "pt-dev" = (
    import ./pt-dev.nix {
      inherit nixpkgs sharedOverlays home-manager;
      stateVersion = "23.05";
    }
  );
  "photos" = (
    import ./photos.nix {
      inherit nixpkgs sharedOverlays home-manager;
      stateVersion = "23.05";
    }
  );
}
