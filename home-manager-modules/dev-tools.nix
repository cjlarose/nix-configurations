{ config, lib, pkgs, ... }:

let
  cfg = config.cjlarose.devTools;

  # Shared with packages/, which exports these same two wrappers for consumers
  # outside this repo. One definition: a wrapper's behaviour is its definition,
  # so a second copy is a thing to keep in step by hand.
  inherit (import ./shell-wrappers.nix { inherit pkgs; }) wrappedJq wrappedRg;
in {
  options.cjlarose.devTools.ghStack = {
    enable = lib.mkEnableOption ''
      github/gh-stack, GitHub's official stacked-PR gh CLI extension. Registers
      it with gh so `gh stack ...` works; the binary is reached through that
      extension mechanism and is deliberately not put on PATH separately. This
      is a human CLI tool -- the agent SKILL.md that upstream ships in the same
      package is installed separately by the llm-agents module
    '';

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "The gh-stack package. Required when ghStack.enable is set.";
    };
  };

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

  config.assertions = [
    {
      assertion = !cfg.ghStack.enable || cfg.ghStack.package != null;
      message = "cjlarose.devTools.ghStack.enable is true but cjlarose.devTools.ghStack.package is unset.";
    }
  ];

  config.programs.gh = {
    enable = true;
    package = cfg.ghPackage;

    # gh discovers extensions by directory layout, not PATH -- it looks for
    # ~/.local/share/gh/extensions/gh-<name>/. This option does exactly that
    # (a linkFarm keyed on pname into xdg.dataFile "gh/extensions"), which is
    # the reason gh is managed through programs.gh at all rather than just
    # dropped into home.packages.
    extensions = lib.optional (cfg.ghStack.enable && cfg.ghStack.package != null)
      cfg.ghStack.package;
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

  # gh-stack is deliberately NOT here. It is invoked as `gh stack ...` through
  # the extension mechanism above; a bare gh-stack on PATH would just be a
  # second spelling of the same command.
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
