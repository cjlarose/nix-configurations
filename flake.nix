{
  description = "NixOS-based development environment";

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-23.11";
    };
    nixpkgs-23-05 = {
      url = "github:nixos/nixpkgs/nixos-23.05";
    };
    nixpkgs-24-05 = {
      url = "github:nixos/nixpkgs/nixos-24.05";
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
    home-manager-24-05 = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs-24-05";
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
    intranetHosts = {
      url = "git+ssh://git@github.com/cjlarose/intranet-hosts";
      flake = false;
    };
    omnisharpVim = {
      url = "github:OmniSharp/omnisharp-vim";
      flake = false;
    };
    trueColorTest = {
      url = "git+https://gist.github.com/db6c5654fa976be33808b8b33a6eb861.git";
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
    home-manager-24-05,
    impermanence,
    intranetHosts,
    nixpkgs,
    nixpkgs-23-05,
    nixpkgs-24-05,
    nixpkgs-unstable,
    omnisharpVim,
    pce,
    self,
    tfenv,
    trueColorTest,
  }:
    let
      additionalPackages = system: {
        go_1_22 = nixpkgs-unstable.legacyPackages.${system}.go_1_22;
        bundix = import "${bundix}/default.nix" { pkgs = nixpkgs.legacyPackages.${system}; };
        python39 = nixpkgs-23-05.legacyPackages.${system}.python39;
        inherit intranetHosts;
        trueColorTest = let
          pkgs = import nixpkgs { inherit system; };
        in pkgs.stdenv.mkDerivation {
          name = "true-color-test";
          src = trueColorTest;
          buildPhase = ''
            chmod +x 24-bit-color.sh
          '';
          installPhase = ''
            mkdir -p $out/bin
            cp 24-bit-color.sh $out/bin
          '';
        };
      };
      sharedOverlays = [
        fzfProject.overlay
        fzfVim.overlay
        tfenv.overlays.default
        (final: prev: {
          vimPlugins = prev.vimPlugins // {
            omnisharpVim = with final; vimUtils.buildVimPlugin {
              name = "omnisharp-vim";
              src = omnisharpVim;
            };
          };
        })
      ];
    in {
      nixosConfigurations = (
        import ./nixos-configurations {
          inherit nixpkgs nixpkgs-24-05 sharedOverlays additionalPackages home-manager home-manager-24-05 pce impermanence disko;
        }
      );

      darwinConfigurations = (
        import ./darwin-configurations {
          inherit nixpkgs sharedOverlays additionalPackages darwin home-manager;
        }
      );
    };
}
