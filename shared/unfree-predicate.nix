{ nixpkgs }:

let
  # All unfree packages used across configurations
  allUnfreePackages = [
    "1password-cli"
    "claude-code"
    "coder"
    "copilot.vim"
    "plexmediaserver"
    "terraform"
  ];

in pkg: builtins.elem (nixpkgs.lib.getName pkg) allUnfreePackages