{ config, lib, pkgs, ... }:

let
  cfg = config.cjlarose.devTools;

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
  options.cjlarose.devTools.ghPackage = lib.mkOption {
    type = lib.types.package;
    default = pkgs.gh;
    defaultText = lib.literalExpression "pkgs.gh";
    description = ''
      The GitHub CLI to install. Overridable because the host's own nixpkgs can
      lag behind the current gh release, and gh is one of the tools where that
      matters -- it gains subcommands (agent skills, extension management) at a
      pace the stable channels do not track.
    '';
  };

  config.programs.gh = {
    enable = true;
    package = cfg.ghPackage;

    # home-manager generates ~/.config/gh/config.yml from this. Note that gh
    # CANNOT fill in defaults it is missing: the generated file is a read-only
    # store symlink, so anything omitted here is simply absent. aliases.co is
    # one of gh's own defaults rather than a personal addition, but it has to be
    # restated for that reason -- drop it and `gh co` stops working.
    #
    # hosts.yml is deliberately NOT managed: home-manager only writes it when
    # programs.gh.hosts is set, and it holds the oauth token.
    settings = {
      # ssh, not gh's https default. The https default was inert anyway --
      # programs.git rewrites url."https://github.com/" to ssh://git@github.com/
      # via insteadOf, so gh-generated remotes already ended up over ssh. Saying
      # ssh here makes the intent explicit instead of relying on that rewrite.
      git_protocol = "ssh";
      aliases.co = "pr checkout";
    };
  };

  config.home.packages = [
    pkgs.csvtool
    pkgs.dig
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
    pkgs.bash-language-server
    pkgs.typescript-language-server
    pkgs.vscode-langservers-extracted
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
