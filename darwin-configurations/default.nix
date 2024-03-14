{ nixpkgs, sharedOverlays, additionalPackages, darwin, home-manager }: {
  "LaRose-MacBook-Pro" = (
    import ./larose-mbp {
      inherit additionalPackages darwin home-manager nixpkgs sharedOverlays;
    }
  );
  "Monica-MacBook-Pro" = (
    import ./monica-mbp {
      inherit additionalPackages darwin home-manager nixpkgs sharedOverlays;
    }
  );
}
