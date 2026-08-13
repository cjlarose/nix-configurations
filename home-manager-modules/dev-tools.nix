# Development tools, one option per tool, all off until a host asks.
#
# Nothing here is installed by importing the module. A host names the tools it
# wants, so a package in a profile can be traced to the line that asked for it,
# and a host that gets a tool from somewhere else -- a company toolchain module,
# a system package set -- can decline this copy rather than carrying two.
#
# Every tool also takes a `package`, which is what makes declining unnecessary
# in the common case: a host installing the same tool from two modules points
# both at one derivation instead of shipping two that collide over the same
# binary. gh is the standing example, and jq, shellcheck, tfenv and yq-go are
# the same shape wherever a picktrace home enables the shared toolchain.
#
# gh is the one tool here that is not merely a package: it is managed through
# programs.gh so that gh extensions work at all, which is a directory layout gh
# discovers rather than anything on PATH.
{ config, lib, pkgs, ... }:

let
  cfg = config.cjlarose.devTools;

  # enable + package for one tool. The package option exists on every tool
  # rather than only where a version currently matters, so that pointing a tool
  # at another module's derivation never needs a change here first.
  mkTool = description: package: {
    enable = lib.mkEnableOption description;

    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      defaultText = lib.literalExpression "pkgs.<the tool>";
      description = ''
        The package to install for this tool. Overridable so a host that also
        gets this tool from another module can name one derivation for both
        rather than installing two that provide the same binary.
      '';
    };
  };

  # The tools that are plain packages, in the order they appear as options.
  # Kept as a list so `config` does not repeat the enable/package pairing
  # twenty-odd times; each entry is exactly what an option set produces.
  simpleTools = [
    cfg.csvtool
    cfg.dig
    cfg.gitAbsorb
    cfg.gitFilterRepo
    cfg.htop
    cfg.jq
    cfg.jqPager
    cfg.ripgrep
    cfg.shellcheck
    cfg.tfenv
    cfg.tmux
    cfg.tree
    cfg.watch
    cfg.wget
    cfg.wrk
    cfg.yqGo
    cfg.kubernetes.kubectl
    cfg.kubernetes.helm
    cfg.kubernetes.kubeseal
    cfg.kubernetes.kustomize
    cfg.languageServers.bash
    cfg.languageServers.kotlin
    cfg.languageServers.nix
    cfg.languageServers.python
    cfg.languageServers.typescript
    cfg.languageServers.web
  ];

  # jqp rather than jq: a second name for jq, so it sits alongside the real one
  # instead of shadowing it. Paged and coloured only when stdout is a terminal,
  # so a pipeline still gets plain json.
  jqPagerPackage = pkgs.writeShellScriptBin "jqp" ''
    if [ -t 1 ]; then
      ${pkgs.jq}/bin/jq --color-output "$@" | less
    else
      ${pkgs.jq}/bin/jq "$@"
    fi
  '';

  # rg, deliberately shadowing plain ripgrep: hidden files searched, .git
  # skipped, results ordered by path, paged when stdout is a terminal. A host
  # that wants stock ripgrep behaviour leaves this off and installs
  # pkgs.ripgrep itself.
  ripgrepPackage = pkgs.writeShellScriptBin "rg" ''
    if [ -t 1 ]; then
      ${pkgs.ripgrep}/bin/rg --hidden --glob '!.git' --sort path --pretty "$@" | less
    else
      ${pkgs.ripgrep}/bin/rg --hidden --glob '!.git' --sort path "$@"
    fi
  '';
in
{
  imports = [
    # gh grew an enable, so its two existing options move under the same
    # attribute rather than sitting beside it as ghPackage/ghStack. The old
    # names keep working and warn.
    (lib.mkRenamedOptionModule
      [ "cjlarose" "devTools" "ghPackage" ]
      [ "cjlarose" "devTools" "gh" "package" ])
    (lib.mkRenamedOptionModule
      [ "cjlarose" "devTools" "ghStack" "enable" ]
      [ "cjlarose" "devTools" "gh" "stack" "enable" ])
    (lib.mkRenamedOptionModule
      [ "cjlarose" "devTools" "ghStack" "package" ]
      [ "cjlarose" "devTools" "gh" "stack" "package" ])
  ];

  options.cjlarose.devTools = {
    csvtool = mkTool "csvtool, for slicing csv on the command line" pkgs.csvtool;
    dig = mkTool "dig, for dns lookups" pkgs.dig;
    gitAbsorb = mkTool ''
      git-absorb, which turns a fixup into the commit it belongs to
    '' pkgs.git-absorb;
    gitFilterRepo = mkTool ''
      git-filter-repo, for rewriting history wholesale
    '' pkgs.git-filter-repo;
    htop = mkTool "htop, the process viewer" pkgs.htop;
    jq = mkTool "jq, for json on the command line" pkgs.jq;
    jqPager = mkTool ''
      jqp, jq under a second name that colours and pages its output when stdout
      is a terminal. Separate from jq: it is an addition to it, not a
      replacement, and a host can want either without the other
    '' jqPagerPackage;
    ripgrep = mkTool ''
      rg, ripgrep wrapped to search hidden files, skip .git, sort by path, and
      page when stdout is a terminal. This SHADOWS plain ripgrep rather than
      sitting beside it, so a host wanting stock behaviour leaves it off
    '' ripgrepPackage;
    shellcheck = mkTool "shellcheck, the shell linter" pkgs.shellcheck;
    tfenv = mkTool ''
      tfenv, which installs the terraform version a directory pins rather than
      one shared terraform
    '' pkgs.tfenv;
    tmux = mkTool "tmux, the terminal multiplexer" pkgs.tmux;
    tree = mkTool "tree, for looking at a directory layout" pkgs.tree;
    watch = mkTool "watch, for re-running a command on an interval" pkgs.unixtools.watch;
    wget = mkTool "wget, for fetching over http" pkgs.wget;
    wrk = mkTool "wrk, the http load generator" pkgs.wrk;
    yqGo = mkTool ''
      mikefarah/yq, the yaml-native Go implementation -- not the python
      jq wrapper of the same name
    '' pkgs.yq-go;

    kubernetes = {
      kubectl = mkTool "kubectl, the kubernetes cli" pkgs.kubectl;
      helm = mkTool "helm, the kubernetes package manager" pkgs.kubernetes-helm;
      kubeseal = mkTool ''
        kubeseal, the sealed-secrets client, for encrypting a secret against a
        cluster's public key
      '' pkgs.kubeseal;
      kustomize = mkTool "kustomize, for overlaying kubernetes manifests" pkgs.kustomize;
    };

    # One option per server rather than one for the group: a host works in the
    # languages it works in, and a server it has no use for is a download and a
    # binary on PATH for nothing.
    languageServers = {
      bash = mkTool "bash-language-server" pkgs.bash-language-server;
      kotlin = mkTool "kotlin-language-server" pkgs.kotlin-language-server;
      nix = mkTool ''
        nil, a Nix language server. nixd is the other one, and a host wanting
        that installs it from wherever it gets it -- two nix servers on PATH is
        a choice, not a default
      '' pkgs.nil;
      python = mkTool "pyright, the Python language server" pkgs.pyright;
      typescript = mkTool "typescript-language-server" pkgs.typescript-language-server;
      web = mkTool ''
        vscode-langservers-extracted: the html, css, json and eslint servers
        extracted from vscode
      '' pkgs.vscode-langservers-extracted;
    };

    gh = {
      enable = lib.mkEnableOption ''
        the GitHub CLI, managed through programs.gh so that gh extensions work:
        gh finds those by directory layout rather than on PATH, which is the
        whole reason this one tool is not just a package. Enabling it also
        writes ~/.config/gh/config.yml
      '';

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.gh;
        defaultText = lib.literalExpression "pkgs.gh";
        description = ''
          The GitHub CLI to install. Overridable because the host's own nixpkgs
          can lag behind the current gh release, and gh is one of the tools
          where that matters -- it gains subcommands (agent skills, extension
          management) at a pace the stable channels do not track.
        '';
      };

      stack = {
        enable = lib.mkEnableOption ''
          github/gh-stack, GitHub's official stacked-PR gh CLI extension.
          Registers it with gh so `gh stack ...` works; the binary is reached
          through that extension mechanism and is deliberately not put on PATH
          separately. This is a human CLI tool -- the agent SKILL.md that
          upstream ships in the same package is installed separately by the
          llm-agents module
        '';

        package = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = null;
          description = "The gh-stack package. Required when gh.stack.enable is set.";
        };
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.gh.stack.enable -> cfg.gh.stack.package != null;
        message = "cjlarose.devTools.gh.stack.enable is true but cjlarose.devTools.gh.stack.package is unset.";
      }
      {
        assertion = cfg.gh.stack.enable -> cfg.gh.enable;
        message = ''
          cjlarose.devTools.gh.stack.enable is true but cjlarose.devTools.gh.enable
          is false. The extension is registered through programs.gh, so with gh
          off it would be installed and unreachable.
        '';
      }
    ];

    programs.gh = lib.mkIf cfg.gh.enable {
      enable = true;
      package = cfg.gh.package;

      # gh discovers extensions by directory layout, not PATH -- it looks for
      # ~/.local/share/gh/extensions/gh-<name>/. This option does exactly that
      # (a linkFarm keyed on pname into xdg.dataFile "gh/extensions"), which is
      # the reason gh is managed through programs.gh at all rather than just
      # dropped into home.packages.
      extensions = lib.optional (cfg.gh.stack.enable && cfg.gh.stack.package != null)
        cfg.gh.stack.package;
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

    # gh-stack is deliberately not here. It is invoked as `gh stack ...` through
    # the extension mechanism above; a bare gh-stack on PATH would just be a
    # second spelling of the same command.
    home.packages =
      builtins.concatMap (t: lib.optional t.enable t.package) simpleTools;
  };
}
