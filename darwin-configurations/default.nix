{ nixpkgs, sharedOverlays, additionalPackages, darwin, home-manager }: {
  "LaRose-MacBook-Pro" = (
    import ./larose-mbp {
      inherit additionalPackages darwin home-manager nixpkgs sharedOverlays;
    }
  );
  "Monica-MacBook-Pro-Home" = (
    import ./monica-mbp {
      inherit additionalPackages darwin home-manager nixpkgs sharedOverlays;
    }
  );
  "Monica-MacBook-Pro-Work" = (
    import ./monica-mbp-work {
      inherit additionalPackages darwin home-manager nixpkgs sharedOverlays;
    }
  );
}
