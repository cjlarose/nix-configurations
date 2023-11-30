{ nixpkgs, sharedOverlays, home-manager, nixos-generators, ... }: {
  "builder" = (
    import ./builder { inherit nixpkgs sharedOverlays home-manager nixos-generators; }
  );
  "pt-dev" = (
    import ./pt-dev.nix { inherit nixpkgs sharedOverlays home-manager; }
  );
  "photos" = (
    import ./photos.nix { inherit nixpkgs sharedOverlays home-manager; }
  );
}
