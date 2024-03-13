{
  description = "NixOS-based development environment";

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-23.11";
    };
    nixpkgs-23-05 = {
      url = "github:nixos/nixpkgs/nixos-23.05";
    };
    nixpkgs-unstable = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };
    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fzfVim = {
      url = "github:cjlarose/fzf.vim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fzfProject = {
      url = "github:cjlarose/fzf-project";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    tfenv = {
      url = "github:cjlarose/tfenv-nix";
    };
    pce = {
      url = "git+ssh://git@github.com/cjlarose/pixel-cats-end-automation";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    bundix = {
      url = "github:cjlarose/bundix";
      flake = false;
    };
  };

  outputs = {
    bundix,
    darwin,
    disko,
    fzfProject,
    fzfVim,
    home-manager,
    impermanence,
    nixpkgs,
    nixpkgs-23-05,
    nixpkgs-unstable,
    pce,
    self,
    tfenv,
  }:
    let
      additionalPackages = system: {
        go_1_22 = nixpkgs-unstable.legacyPackages.${system}.go_1_22;
        bundix = import "${bundix}/default.nix" { pkgs = nixpkgs.legacyPackages.${system}; };
        python39 = nixpkgs-23-05.legacyPackages.${system}.python39;
      };
      sharedOverlays = [
        fzfProject.overlay
        fzfVim.overlay
        tfenv.overlays.default
      ];
    in {
      nixosConfigurations = (
        import ./nixos-configurations {
          inherit nixpkgs sharedOverlays additionalPackages home-manager pce impermanence disko;
        }
      );

      darwinConfigurations = (
        import ./darwin-configurations {
          inherit nixpkgs sharedOverlays additionalPackages darwin home-manager;
        }
      );
    };
}
