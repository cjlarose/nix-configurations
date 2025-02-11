{ pkgs, ... }:

let
  gitMakePatchCommand = pkgs.writeShellScriptBin "git-make-patch-command" ''
    DIFF=$(git diff)
    echo 'git apply <<'"'"'PATCH'"'"
    echo "$DIFF"
    echo 'PATCH'
  '';

  runUntilFailure = pkgs.writeShellScriptBin "run-until-failure" ''
    while "$@"; do :; done
  '';

  runUntilSuccess = pkgs.writeShellScriptBin "run-until-success" ''
    while ! "$@"; do :; done
  '';
in {
  home.packages = [
    gitMakePatchCommand
    runUntilFailure
    runUntilSuccess
  ];
}
