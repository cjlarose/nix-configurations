{ pkgs, ... }:

let
  wrappedJq = pkgs.writeShellScriptBin "jqp" ''
    if [ -t 1 ]; then
      ${pkgs.jq}/bin/jq --color-output "$@" | less
    else
      ${pkgs.jq}/bin/jq "$@"
    fi
  '';

  wrappedRg = pkgs.writeShellScriptBin "rg" ''
    if [ -t 1 ]; then
      ${pkgs.ripgrep}/bin/rg --hidden --glob '!.git' --sort path --pretty "$@" | less
    else
      ${pkgs.ripgrep}/bin/rg --hidden --glob '!.git' --sort path "$@"
    fi
  '';
in {
  home.packages = [
    pkgs.git-absorb
    pkgs.htop
    pkgs.jq
    pkgs.kubectl
    pkgs.nil
    pkgs.nodePackages.bash-language-server
    pkgs.tfenv
    pkgs.tmux
    pkgs.tree
    pkgs.unixtools.watch
    pkgs.wrk
    pkgs.yq-go
    wrappedJq
    wrappedRg
  ];
}
