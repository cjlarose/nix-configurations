{ pkgs, ... }:

let
  gitMakeApplyCommand = pkgs.writeShellScriptBin "git-make-apply-command" ''
    echo 'git apply <<'"'"'PATCH'"'"
    cat
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
    gitMakeApplyCommand
    runUntilFailure
    runUntilSuccess
  ];
}
