{
  description = "NixOS-based development environment";

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-24.05";
    };
    nixpkgs-23-05 = {
      url = "github:nixos/nixpkgs/nixos-23.05";
    };
    nixpkgs-24-11 = {
      url = "github:nixos/nixpkgs/nixos-24.11";
    };
    nixpkgs-master = {
      url = "github:nixos/nixpkgs/master";
    };
    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager-24-11 = {
      url = "github:nix-community/home-manager/release-24.11";
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
    };
    chicken-smoothie-automation = {
      url = "git+ssh://git@github.com/cjlarose/chicken-smoothie-automation";
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
    nvr = {
      url = "github:cstyles/nvr";
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
    home-manager-24-11,
    impermanence,
    intranetHosts,
    nixpkgs,
    nixpkgs-23-05,
    nixpkgs-24-11,
    nixpkgs-master,
    omnisharpVim,
    pce,
    self,
    tfenv,
    trueColorTest,
    nvr,
    chicken-smoothie-automation,
  }:
    let
      supportedPlatforms = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      additionalPackages = nixpkgs.lib.genAttrs supportedPlatforms (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          packageArgs = {
            inherit pkgs system nixpkgs-master nixpkgs-24-11 nixpkgs-23-05 bundix intranetHosts nvr trueColorTest chicken-smoothie-automation;
          };
        in
          import ./packages packageArgs
      );

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
          inherit nixpkgs nixpkgs-24-11 sharedOverlays additionalPackages home-manager home-manager-24-11 pce impermanence disko;
        }
      );

      darwinConfigurations = (
        import ./darwin-configurations {
          inherit nixpkgs nixpkgs-24-11 sharedOverlays additionalPackages darwin home-manager home-manager-24-11;
        }
      );

      diskoConfigurations = (
        import ./disko-configurations {}
      );

      packages = additionalPackages;
    };
}
