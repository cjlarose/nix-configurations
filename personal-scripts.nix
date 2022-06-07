{ pkgs, ... }:

let
  nvrEditInSplitWindow = pkgs.writeShellScriptBin "nvr-edit-in-split-window" ''
    if [ -z "$NVIM_LISTEN_ADDRESS" ]; then
      nvim "$@"
    else
      nvr -cc split --remote-wait +'set bufhidden=wipe' "$@"
    fi
  '';

  wrappedRg = pkgs.writeShellScriptBin "rg" ''
    if [ -t 1 ]; then
      ${pkgs.ripgrep}/bin/rg --pretty --sort path "$@" | less
    else
      ${pkgs.ripgrep}/bin/rg --sort path "$@"
    fi
  '';
  linkedRg = pkgs.symlinkJoin {
    name = "rg";
    paths = [ wrappedRg pkgs.ripgrep ];
  };
in {
  home.packages = [
    nvrEditInSplitWindow
    linkedRg
  ];
}
