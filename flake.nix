{
  description = "NixOS-based development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-23.05";
    darwin.url = "github:lnl7/nix-darwin/master";
    darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-23.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    fzfVim.url = "github:cjlarose/fzf.vim";
    fzfVim.inputs.nixpkgs.follows = "nixpkgs";
    fzfProject.url = "github:cjlarose/fzf-project";
    fzfProject.inputs.nixpkgs.follows = "nixpkgs";
    tfenv.url = "github:cjlarose/tfenv-nix";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, darwin, home-manager, fzfVim, fzfProject, tfenv, nixos-generators }:
    let
      sharedOverlays = [
        fzfProject.overlay
        fzfVim.overlay
        tfenv.overlays.default
      ];
    in {
      nixosConfigurations = (
        import ./nixos-configurations {
          inherit nixpkgs sharedOverlays home-manager nixos-generators;
        }
      );

      darwinConfigurations = (
        import ./darwin-configurations {
          inherit nixpkgs sharedOverlays darwin home-manager;
        }
      );
    };
}
