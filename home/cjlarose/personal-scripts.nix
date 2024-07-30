{ pkgs, ... }:

let
  wrappedRg = pkgs.writeShellScriptBin "rgp" ''
    if [ -t 1 ]; then
      ${pkgs.ripgrep}/bin/rg --pretty --sort path "$@" | less
    else
      ${pkgs.ripgrep}/bin/rg --sort path "$@"
    fi
  '';

  runUntilFailure = pkgs.writeShellScriptBin "run-until-failure" ''
    while "$@"; do :; done
  '';

  runUntilSuccess = pkgs.writeShellScriptBin "run-until-success" ''
    while ! "$@"; do :; done
  '';
in {
  home.packages = [
    wrappedRg
    runUntilFailure
    runUntilSuccess
  ];
}
