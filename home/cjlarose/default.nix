{ system, additionalPackages, stateVersion, llm-wiki-path ? null, llm-wiki-module ? null, claudeUseNodeRuntime ? false, enableSuperpowers ? true }:
{ pkgs, lib, ... }: {
  # All LLM-agent tooling lives behind the single llm-agents module. Claude Code
  # itself is unconditional there; the rest is opted into here for the whole
  # cjlarose fleet, or per-host where the closure cost warrants it. The module
  # takes no additionalPackages arg -- every package is named explicitly here.
  cjlarose.llmAgents = {
    claude.remoteControlAtStartup = true;

    # obra/superpowers as a namespaced plugin: brainstorming, planning, TDD,
    # code review, worktrees, systematic debugging. Replaces both the vendored
    # single-skill systematic-debugging copy and the phx workflow skills, whose
    # spine upstream covers natively. The package is named on every host; what
    # actually turns it on is importing superpowers-plugin.nix below, because
    # home-manager 25-11 has no programs.claude-code.plugins option at all.
    superpowers.package = additionalPackages.${system}.superpowers;

    # Which claude build is a property of the host, not of the module. The
    # Goldmont-based pve guests have no AVX and segfault on the Bun standalone at
    # launch, so they take the node-pinned build (frozen at npm 2.1.112); every
    # AVX-capable host tracks the latest Bun build from llm-agents.nix.
    claude.package =
      if claudeUseNodeRuntime
      then additionalPackages.${system}.claude-code-node
      else additionalPackages.${system}.claude-code;

    # Both are small CLIs that pair with claude, so they ride the shared profile
    # rather than being host-scoped: opencode as a second agent, herdr to manage
    # claude sessions. herdr reaches the no-AVX pve guests too — its AVX2 paths
    # sit behind runtime is_x86_feature_detected! gates, unlike the Bun
    # claude-code binary that forces the node build above.
    opencode = { enable = true; package = additionalPackages.${system}.opencode; };
    herdr = { enable = true; package = additionalPackages.${system}.herdr; };

    # Skill only, as the name says; the gh extension itself is a human CLI tool
    # enabled via cjlarose.devTools.ghStack below. Same package for both, so the
    # skill always documents the extension that is actually installed.
    ghStackSkill = { enable = true; package = additionalPackages.${system}.gh-stack; };

    # The wiki's Claude Code plugin (skills + SessionStart index hook) and
    # LLM_WIKI_PATH. Only where a wiki worktree actually exists, which is also
    # the only place llm-wiki-module is threaded in below.
    wiki.enable = llm-wiki-path != null;
    wiki.path = llm-wiki-path;
  };

  # lavish and claude.enablePlaywrightMcp are left at their module defaults
  # (off) here and enabled per-host in nixos-configurations/ns1010301: a browser
  # review tool and a chromium closure have no business on the headless guests.
  #
  # llm-wiki-module is the wiki flake's own home-manager module, which is what
  # DECLARES programs.llmWiki. It has to be imported here rather than inside
  # llm-agents because `imports` is resolved before config exists, so it can key
  # off neither an option nor an optional module argument (an arg with a default
  # forces _module.args evaluation, which recurses). wiki-bridge.nix rides along
  # with it: it turns the cjlarose.llmAgents.wiki.* options into a
  # programs.llmWiki definition, and can only be loaded where that option is
  # declared.
  imports = [
    ../../home-manager-modules/dev-tools.nix
    ../../home-manager-modules/neovim.nix
    ../../home-manager-modules/git.nix
    ../../home-manager-modules/shell.nix
    ../../home-manager-modules/llm-agents
  ] ++ lib.optional enableSuperpowers
    ../../home-manager-modules/llm-agents/superpowers-plugin.nix
  ++ lib.optionals (llm-wiki-module != null) [
    llm-wiki-module
    ../../home-manager-modules/llm-agents/wiki-bridge.nix
  ];

  # gh from nixpkgs-unstable (2.96.0) rather than the host's 26-05 (2.93.0);
  # see packages/default.nix.
  cjlarose.devTools.ghPackage = additionalPackages.${system}.gh;

  # GitHub's official stacked-PR extension: `gh stack ...` and a gh-stack on
  # PATH. Useful at the keyboard, independent of any agent -- the SKILL.md that
  # ships in the same package is installed by llm-agents above.
  cjlarose.devTools.ghStack = {
    enable = true;
    package = additionalPackages.${system}.gh-stack;
  };

  cjlarose.shell.nvrPackage = additionalPackages.${system}.nvr;
  cjlarose.shell.kubePrompt = true;
  cjlarose.shell.dockerPrompt = true;

  home.stateVersion = stateVersion;

  home.sessionVariables = {
    THOR_MERGE = "${pkgs.neovim-remote}/bin/nvr -s -d";
  };

  home.packages = [
    pkgs._1password-cli
    additionalPackages.${system}.bundix
    additionalPackages.${system}.git-make-apply-command
    pkgs.nodejs_22
    pkgs.oha
    pkgs.parallel
    pkgs.postgresql
    (additionalPackages.${system}.python39.withPackages (python-pkgs: with python-pkgs; [
      faker
      google-cloud-firestore
      google-cloud-pubsub
      ipython
      psycopg2
      pytz
      requests
      setuptools
      shortuuid
    ]))
    pkgs.ruby
    pkgs.socat
    pkgs.speedtest-cli
    pkgs.stack
    additionalPackages.${system}.trueColorTest
    additionalPackages.${system}.tuicr
  ];

  # Dogfood the `reverse` option from the commit-order-display-option branch
  # of cjlarose/tuicr: render the inline commit selector parent -> child for
  # GitHub-PR-style branch review.
  home.file.".config/tuicr/config.toml".text = ''
    reverse = true
  '';

  programs.git.userName = "Christopher La Rose";
  programs.git.userEmail = "cjlarose@gmail.com";
  programs.git.extraConfig = {
    "url \"git@bitbucket.org:\"".insteadOf = "https://bitbucket.org";
    "url \"ssh://git@github.com/\"".insteadOf = "https://github.com/";
  };

  programs.ssh = {
    matchBlocks = {
      "*.toothyshouse.com" = {
        forwardAgent = true;
      };
    };
  };

  programs.go = {
    enable = true;
    package = additionalPackages.${system}.go_1_22;
    goPrivate = [
      "bitbucket.org/picktrace"
      "github.com/picktrace"
    ];
  };
}
