{
  nixpkgs-24-05,
  nixpkgs-24-11,
  nixpkgs-25-05,
  sharedOverlays,
  additionalPackages,
  darwin,
  home-manager-24-05,
  home-manager-24-11,
  home-manager-25-05
}: {
  "Christophers-MacBook-Pro" = (
    import ./larose-mbp {
      inherit additionalPackages darwin sharedOverlays;
      nixpkgs = nixpkgs-25-05;
      home-manager = home-manager-25-05;
      primaryUser = "cjlarose";
      homeManagerStateVersion = "25.05";
      nixDarwinStateVersion = 6;
    }
  );
  "LaRose-MacBook-Pro" = (
    import ./larose-mbp {
      inherit additionalPackages darwin sharedOverlays;
      nixpkgs = nixpkgs-25-05;
      home-manager = home-manager-25-05;
      primaryUser = "chrislarose";
      homeManagerStateVersion = "23.05";
      nixDarwinStateVersion = 4;
    }
  );
  "Monica-MacBook-Pro-Home" = (
    import ./monica-mbp {
      inherit additionalPackages darwin sharedOverlays;
      nixpkgs = nixpkgs-25-05;
      home-manager = home-manager-25-05;
    }
  );
  "Monica-MacBook-Pro-Work" = (
    import ./monica-mbp-work {
      inherit additionalPackages darwin sharedOverlays;
      nixpkgs = nixpkgs-25-05;
      home-manager = home-manager-25-05;
    }
  );
}
