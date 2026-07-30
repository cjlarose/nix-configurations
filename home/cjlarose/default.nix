{ system, additionalPackages, stateVersion, mattpocock-skills ? null, superpowers ? null, llm-wiki-path ? null, llm-wiki-module ? null, claudeUseNodeRuntime ? false }:
{ pkgs, lib, ... }: {
  # All LLM-agent tooling lives behind the single llm-agents module. Claude Code
  # itself is unconditional there; the rest is opted into here for the whole
  # cjlarose fleet, or per-host where the closure cost warrants it. The module
  # takes no additionalPackages arg -- every package is named explicitly here.
  cjlarose.llmAgents = {
    claude.mattpocock-skills = mattpocock-skills;
    claude.superpowers-skills = superpowers;
    claude.remoteControlAtStartup = true;
    phxWorkflow.enable = true;

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
  ] ++ lib.optionals (llm-wiki-module != null) [
    llm-wiki-module
    ../../home-manager-modules/llm-agents/wiki-bridge.nix
  ];

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
