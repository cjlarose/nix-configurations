{ system, additionalPackages, stateVersion, llm-wikis ? { }, llm-wiki-module ? null, claudeUseNodeRuntime ? false, enableSuperpowers ? true }:
{ pkgs, lib, ... }: {
  # All LLM-agent tooling lives behind the single llm-agents module, which
  # defaults every feature off -- claude included. Everything wanted fleet-wide
  # is opted into here, and the rest per-host where the closure cost warrants
  # it. The module takes no additionalPackages arg -- every package is named
  # explicitly here.
  cjlarose.llmAgents = {
    # Claude Code for the whole cjlarose fleet. Stated here rather than assumed:
    # the module defaults it off like everything else, so this one line is what
    # keeps all seven hosts that import this profile on claude.
    claude.enable = true;
    claude.remoteControlAtStartup = true;

    # obra/superpowers as a namespaced plugin: brainstorming, planning, TDD,
    # code review, worktrees, systematic debugging. Replaces both the vendored
    # single-skill systematic-debugging copy and the phx workflow skills, whose
    # spine upstream covers natively.
    #
    # `enable` and the superpowers-plugin.nix import below are driven off the
    # same enableSuperpowers flag: home-manager 25-11 has no
    # programs.claude-code.plugins option at all, so on those hosts the
    # definition has to be ABSENT rather than merely disabled. One flag, both
    # effects, so they cannot drift apart.
    #
    # The module builds the plugin from this source rather than taking a
    # prebuilt one, because the two customizations below are module options.
    superpowers = {
      enable = enableSuperpowers;
      src = additionalPackages.${system}.superpowers-src;
      # Upstream's SessionStart hook force-feeds the using-superpowers skill
      # into every session, which makes the agent open with a brainstorm on
      # questions that only wanted an answer. Skills stay invocable by name.
      disableHooks = true;
      # Specs are working notes here, not repo history; docs/superpowers is
      # gitignored globally (home-manager-modules/git.nix). Implementation
      # commits are untouched.
      disableSpecCommits = true;
    };

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
    herdr = {
      enable = true;
      package = additionalPackages.${system}.herdr;
      # Upstream's own agent skill, which the module lifts out of the source
      # tree -- the same pin the binary above is built from, so the skill cannot
      # describe subcommands this herdr does not have.
      skillSrc = additionalPackages.${system}.herdr-src;
    };

    # Code review at the keyboard, fleet-wide for the same reason as
    # git-surgeon: a small Rust binary, and reviewing a branch before pushing it
    # is the same job on every host. `reverse` comes from the
    # commit-order-display-option branch of cjlarose/tuicr, which is what the
    # package below is built from -- render the inline commit selector
    # parent -> child for GitHub-PR-style branch review.
    tuicr = {
      enable = true;
      package = additionalPackages.${system}.tuicr;
      settings.reverse = true;
    };

    # Hunk-level git surgery for agents, plus upstream's skill describing it.
    # Fleet-wide rather than host-scoped: it is a small Rust binary with no
    # closure to speak of, and the branch-and-PR workflow it serves is the same
    # everywhere. Not split across dev-tools like gh-stack -- `git-surgeon` is
    # agent tooling, and the interactive equivalents (git add -p, rebase -i) are
    # what a human at the keyboard reaches for.
    gitSurgeon = { enable = true; package = additionalPackages.${system}.git-surgeon; };

    # Skill only, as the name says; the gh extension itself is a human CLI tool
    # enabled via cjlarose.devTools.ghStack below. Same package for both, so the
    # skill always documents the extension that is actually installed.
    ghStackSkill = { enable = true; package = additionalPackages.${system}.gh-stack; };

    # The wiki registry, plus (until the skills move into this module) the
    # wiki flake's own Claude Code plugin and LLM_WIKI_PATH. Only where a wiki
    # checkout actually exists, which is also the only place llm-wiki-module is
    # threaded in below.
    #
    # An attrset rather than a path: wiki identity is a first-class parameter
    # now, because one user can drive several wikis and every skill has to be
    # told which one it is writing to.
    wiki.enable = llm-wikis != { };
    wiki.wikis = llm-wikis;
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

  # Deliberately small. This profile fans out to every cjlarose host, so it
  # carries only things wanted everywhere; per-project toolchains belong in
  # devshells, and picktrace's toolchain lives in that repo's
  # home/modules/picktrace-dev-packages.nix.
  home.packages = [
    pkgs._1password-cli
    additionalPackages.${system}.git-make-apply-command
    pkgs.oha
    pkgs.parallel
    pkgs.socat
    additionalPackages.${system}.trueColorTest
  ];

  programs.git.userName = "Christopher La Rose";
  programs.git.userEmail = "cjlarose@gmail.com";
  # gh is configured with git_protocol = ssh (see dev-tools), but anything else
  # handing out an https github URL still gets rewritten here.
  programs.git.extraConfig = {
    "url \"ssh://git@github.com/\"".insteadOf = "https://github.com/";
  };

  programs.ssh = {
    matchBlocks = {
      "*.toothyshouse.com" = {
        forwardAgent = true;
      };
    };
  };
}
