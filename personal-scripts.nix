{ pkgs, ... }:

let
  nvrEditInSplitWindow = pkgs.writeShellScriptBin "nvr-edit-in-split-window" ''
    if [ -z "$NVIM_LISTEN_ADDRESS" ]; then
      nvim "$@"
    else
      nvr -cc split --remote-wait +'set bufhidden=wipe' "$@"
    fi
  '';

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
    nvrEditInSplitWindow
    wrappedRg
    runUntilFailure
    runUntilSuccess
  ];
}
