{ pkgs, ... }:

let
  nvrEditInSplitWindow = pkgs.writeShellScriptBin "nvr-edit-in-split-window" ''
    if [ -z "$NVIM_LISTEN_ADDRESS" ]; then
      nvim "$@"
    else
      nvr -cc split --remote-wait +'set bufhidden=wipe' "$@"
    fi
  '';
in {
  home.packages = [
    nvrEditInSplitWindow
  ];
}
