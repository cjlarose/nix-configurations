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
    pkgs.corepack
    pkgs.csvtool
    pkgs.dig
    pkgs.gh
    pkgs.git-absorb
    pkgs.git-filter-repo
    pkgs.htop
    pkgs.jq
    pkgs.kotlin-language-server
    pkgs.kubectl
    pkgs.kubernetes-helm
    pkgs.kubeseal
    pkgs.kustomize
    pkgs.nil
    pkgs.nodePackages.bash-language-server
    pkgs.nodePackages.typescript-language-server
    pkgs.nodePackages.vscode-langservers-extracted
    pkgs.pyright
    pkgs.shellcheck
    pkgs.tfenv
    pkgs.tmux
    pkgs.tree
    pkgs.unixtools.watch
    pkgs.wget
    pkgs.wrk
    pkgs.yq-go
    wrappedJq
    wrappedRg
  ];
}
