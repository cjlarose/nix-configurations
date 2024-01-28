{
  description = "NixOS-based development environment";

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/release-23.11";
    };
    nixpkgs-23-05 = {
      url = "github:nixos/nixpkgs/release-23.05";
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
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pce = {
      url = "git+ssh://git@github.com/monicahung/flightrising?ref=nix&dir=pixel_cats_end";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
    };
  };

  outputs = {
    darwin,
    fzfProject,
    fzfVim,
    home-manager,
    impermanence,
    nixos-generators,
    nixpkgs,
    nixpkgs-23-05,
    pce,
    self,
    tfenv,
  }:
    let
      additionalPackages = system: {
        go_1_18 = nixpkgs-23-05.legacyPackages.${system}.go_1_18;
        nodejs_20 = nixpkgs.legacyPackages.${system}.nodejs_20;
      };
      sharedOverlays = [
        fzfProject.overlay
        fzfVim.overlay
        tfenv.overlays.default
      ];
    in {
      nixosConfigurations = (
        import ./nixos-configurations {
          inherit nixpkgs sharedOverlays additionalPackages home-manager nixos-generators pce impermanence;
        }
      );

      darwinConfigurations = (
        import ./darwin-configurations {
          inherit nixpkgs sharedOverlays additionalPackages darwin home-manager;
        }
      );
    };
}
