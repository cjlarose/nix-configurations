{ system, additionalPackages, stateVersion, mattpocock-skills ? null, superpowers ? null, llm-wiki-path ? null, llm-wiki-module ? null, claudeUseNodeRuntime ? false }:
{ pkgs, lib, ... }: {
  _module.args = { inherit additionalPackages system; };
  cjlarose.claude.mattpocock-skills = mattpocock-skills;
  cjlarose.claude.superpowers-skills = superpowers;
  cjlarose.claude.useNodeRuntime = claudeUseNodeRuntime;
  cjlarose.claude.remoteControlAtStartup = true;
  cjlarose.claude.phxWorkflow.enable = true;

  # The cjlarose.lavish module is imported below so the option exists on every
  # cjlarose host, but it defaults off here: lavish-axi is a real Node CLI + a
  # browser review tool, useful only on interactive hosts, so the enable is
  # scoped to ns1010301 in nixos-configurations/ns1010301/default.nix (the same
  # host-scoping pattern as cjlarose.claude.enablePlaywrightMcp).

  # The llm-wiki flake exports a home-manager module (programs.llmWiki) that
  # owns the wiki's skills + index hook as store copies. Both the module and the
  # programs.llmWiki definition it declares are added only where the wiki is
  # threaded in (ns1010301) — defining programs.llmWiki on a host that didn't
  # import the module would be an "option does not exist" error, mkIf or not.
  imports = [
    ../../home-manager-modules/dev-tools.nix
    ../../home-manager-modules/neovim.nix
    ../../home-manager-modules/git.nix
    ../../home-manager-modules/shell.nix
    ../../home-manager-modules/claude
    ../../home-manager-modules/phx-workflow
    ../../home-manager-modules/lavish
    ../../home-manager-modules/opencode
  ] ++ lib.optionals (llm-wiki-module != null) [
    llm-wiki-module
    { programs.llmWiki = lib.mkIf (llm-wiki-path != null) { enable = true; path = llm-wiki-path; }; }
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
    # herdr, a terminal workspace manager for AI coding agents (llm-agents.nix
    # only, not nixpkgs). Deliberately in the shared profile rather than
    # host-scoped like enablePlaywrightMcp/lavish: it manages claude sessions,
    # so it belongs everywhere the claude module lands -- including the no-AVX
    # pve guests. It carries AVX2 code paths, but unlike the Bun claude-code
    # binary those sit behind runtime is_x86_feature_detected! gates (the build
    # sets no target-cpu, so rustc's baseline x86-64 applies to everything
    # else), which is why this needs no useNodeRuntime-style escape hatch.
    additionalPackages.${system}.herdr
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
