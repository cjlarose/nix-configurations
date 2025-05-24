{ nixpkgs-24-05, nixpkgs-24-11, sharedOverlays, additionalPackages, home-manager, home-manager-24-11, pce, impermanence, disko, ... }: {
  "builder" = (
    import ./builder {
      inherit sharedOverlays additionalPackages home-manager;
      nixpkgs = nixpkgs-24-05;
      stateVersion = "23.05";
    }
  );
  "bootstrap" = (
    import ./bootstrap {
      inherit sharedOverlays disko impermanence;
      nixpkgs = nixpkgs-24-11;
      stateVersion = "24.11";
    }
  );
  "bots" = (
    import ./bots {
      inherit home-manager sharedOverlays additionalPackages pce impermanence;
      nixpkgs = nixpkgs-24-05;
      stateVersion = "23.11";
    }
  );
  "cache" = (
    import ./cache {
      inherit sharedOverlays additionalPackages impermanence;
      nixpkgs = nixpkgs-24-11;
      home-manager = home-manager-24-11;
      stateVersion = "24.05";
    }
  );
  "coder" = (
    import ./coder {
      inherit home-manager sharedOverlays additionalPackages impermanence;
      nixpkgs = nixpkgs-24-05;
      stateVersion = "24.05";
    }
  );
  "dns" = (
    import ./dns {
      inherit sharedOverlays additionalPackages impermanence home-manager;
      nixpkgs = nixpkgs-24-05;
      stateVersion = "23.11";
    }
  );
  "immich" = (
    import ./immich {
      inherit sharedOverlays additionalPackages impermanence disko;
      nixpkgs = nixpkgs-24-11;
      home-manager = home-manager-24-11;
      stateVersion = "24.11";
    }
  );
  "media" = (
    import ./media {
      inherit sharedOverlays additionalPackages impermanence home-manager;
      nixpkgs = nixpkgs-24-05;
      stateVersion = "23.11";
    }
  );
  "palworld" = (
    import ./palworld {
      inherit sharedOverlays additionalPackages home-manager;
      nixpkgs = nixpkgs-24-05;
      stateVersion = "23.11";
    }
  );
  "pt-dev" = (
    import ./pt-dev.nix {
      inherit sharedOverlays additionalPackages home-manager;
      nixpkgs = nixpkgs-24-05;
      stateVersion = "23.05";
    }
  );
  "photos" = (
    import ./photos.nix {
      inherit sharedOverlays additionalPackages home-manager;
      nixpkgs = nixpkgs-24-05;
      stateVersion = "23.05";
    }
  );
  "splitpro" = (
    import ./splitpro {
      inherit sharedOverlays additionalPackages impermanence;
      nixpkgs = nixpkgs-24-11;
      home-manager = home-manager-24-11;
      stateVersion = "24.11";
    }
  );
  "unifi" = (
    import ./unifi {
      inherit sharedOverlays additionalPackages impermanence;
      nixpkgs = nixpkgs-24-11;
      home-manager = home-manager-24-11;
      stateVersion = "24.11";
    }
  );
}
