{ nixpkgs, nixpkgs-24-11, sharedOverlays, additionalPackages, darwin, home-manager, home-manager-24-11 }: {
  "LaRose-MacBook-Pro" = (
    import ./larose-mbp {
      inherit additionalPackages darwin sharedOverlays;
      nixpkgs = nixpkgs-24-11;
      home-manager = home-manager-24-11;
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
