{ lib, ... }:

let
  allUnfreePackages = import ../shared/unfree-packages.nix;

in {
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) allUnfreePackages;
}
