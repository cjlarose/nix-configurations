{ nixpkgs }:

let
  # All unfree packages used across configurations
  allUnfreePackages = [
    "1password-cli"
    "claude-code"
    "coder"
    "plexmediaserver"
    "terraform"
  ];

in pkg: builtins.elem (nixpkgs.lib.getName pkg) allUnfreePackages