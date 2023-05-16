{
  description = "NixOS-based development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-22.05";
    darwin.url = "github:lnl7/nix-darwin/master";
    darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    fzfVim.url = "github:cjlarose/fzf.vim";
    fzfVim.inputs.nixpkgs.follows = "nixpkgs";
    fzfProject.url = "github:cjlarose/fzf-project";
    fzfProject.inputs.nixpkgs.follows = "nixpkgs";
    pinpox.url = "github:cjlarose/pinpox-nixos";
    pinpox.inputs.nixpkgs.follows = "nixpkgs";
    kmonad.url = "git+https://github.com/kmonad/kmonad?submodules=1&dir=nix";
    kmonad.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, darwin, home-manager, fzfVim, fzfProject, pinpox, kmonad }: {
    nixosConfigurations = (
      import ./nixos-configurations {
        inherit nixpkgs home-manager fzfVim fzfProject pinpox;
      }
    );
    darwinConfigurations = (
      import ./darwin-configurations {
        inherit nixpkgs darwin home-manager fzfVim fzfProject pinpox kmonad;
      }
    );
  };
}
