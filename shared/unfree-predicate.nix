{ nixpkgs }:

let
  allUnfreePackages = import ./unfree-packages.nix;

in pkg: builtins.elem (nixpkgs.lib.getName pkg) allUnfreePackages
