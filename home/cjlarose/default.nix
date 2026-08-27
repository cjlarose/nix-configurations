{ system, additionalPackages, stateVersion, llm-wiki-path ? null, llm-wiki-skill-src ? null, claudeUseNodeRuntime ? false, enableSuperpowers ? true, enablePlaywrightMcp ? false }:
{ pkgs, lib, config, ... }:
let
  # harness-config's lib, re-exported through additionalPackages (see
  # packages/default.nix). Provides wrapClaudeCode (the terminal-env claude
  # wrapper) and mkSuperpowersPlugin (builds obra/superpowers into a plugin from
  # harness-config's own pinned source). Claude Code itself is now stock
  # programs.claude-code, configured here rather than by the llm-agents module.
  harnessConfig = additionalPackages.${system}.harnessConfig;

  # Which claude build is a property of the host, not of the module. The
  # Goldmont-based pve guests have no AVX and segfault on the Bun standalone at
  # launch, so they take the node-pinned build (frozen at npm 2.1.112); every
  # AVX-capable host tracks the latest Bun build from llm-agents.nix.
  claudePkg =
    if claudeUseNodeRuntime
    then additionalPackages.${system}.claude-code-node
    else additionalPackages.${system}.claude-code;

  # obra/superpowers as a namespaced Claude Code plugin, built by harness-config
  # from its own pinned source. Only referenced under `enableSuperpowers`, so the
  # build is never forced on a host that leaves it off. Two customizations: drop
  # upstream's SessionStart hook (which force-feeds using-superpowers into every
  # session, opening with a brainstorm on questions that only wanted an answer)
  # and the brainstorming skill's spec-commit instructions (docs/superpowers is
  # gitignored fleet-wide; implementation commits are untouched).
  superpowersPlugin = harnessConfig.mkSuperpowersPlugin {
    inherit pkgs;
    disableHooks = true;
    disableSpecCommits = true;
  };

  # The statusline command, built at the consumer now that the llm-agents module
  # no longer owns Claude Code. jq + gawk on PATH; body lives beside this file.
  statusline = pkgs.writeShellApplication {
    name = "claude-code-statusline";
    runtimeInputs = [ pkgs.jq pkgs.gawk ];
    text = builtins.readFile ./claude-code-statusline.sh;
  };

  # playwright-mcp 0.0.69 ignores the PLAYWRIGHT_MCP_BROWSER env var nixpkgs
  # sets, so it falls back to the "chrome" channel and tries to provision a
  # chrome-for-testing build by writing into its (read-only) Nix store browsers
  # path -- which fails with ENOENT/mkdir. Point it explicitly at the
  # nix-provided chromium instead (the same playwright-driver.browsers derivation
  # the upstream wrapper already exports, so versions stay in sync). The chromium
  # revision is globbed at runtime to survive nixpkgs bumps. Headless because
  # this targets displayless hosts; isolated keeps the profile in memory.
  playwrightMcp = pkgs.writeShellScriptBin "playwright-mcp-chromium" ''
    chrome=( ${pkgs.playwright-driver.browsers}/chromium-*/chrome-linux*/chrome )
    exec ${pkgs.playwright-mcp}/bin/playwright-mcp \
      --headless --isolated --executable-path "''${chrome[0]}" "$@"
  '';
in
{
  # Stock Claude Code for the whole cjlarose fleet, wrapped by harness-config's
  # lib. The llm-agents module no longer gates it; the siblings that install
  # skills read config.programs.claude-code.enable instead.
  programs.claude-code = {
    enable = true;
    # harness-config's terminal-env wrapper over the host's claude build.
    # home-manager wraps this again with its --plugin-dir flags, so the final
    # chain is: HM plugin wrapper -> env wrapper -> claude-code. Agent-teams is
    # opted in through the wrapper's agentTeams arg, which exports
    # CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS with a :- default -- so an explicit
    # per-session opt-out still wins -- rather than pinning it in settings.env.
    package = harnessConfig.wrapClaudeCode {
      inherit pkgs;
      package = claudePkg;
      trueColorInTmux = true;
      fullscreenTui = true;
      toolShell = "${pkgs.bashInteractive}/bin/bash";
      agentTeams = true;
    };

    # Pinned, self-contained Playwright MCP (chromium baked in). Gated per-host
    # via enablePlaywrightMcp -- ns1010301 only -- so the chromium closure only
    # lands where browser automation is wanted. Merges with the ai-memory MCP
    # entry the ai-memory module defines.
    mcpServers = lib.optionalAttrs enablePlaywrightMcp {
      playwright = {
        type = "stdio";
        command = "${playwrightMcp}/bin/playwright-mcp-chromium";
      };
    };

    settings = {
      # nixd Nix language server, provided by the local marketplace in home.file
      # below (nixd binary from home.packages so bare `nixd` resolves on PATH).
      enabledPlugins."nixd@cjlarose-lsps" = true;
      extraKnownMarketplaces."cjlarose-lsps".source = {
        source = "directory";
        path = "${config.home.homeDirectory}/.claude/lsp-marketplace";
      };
      skipDangerousModePermissionPrompt = true;
      remoteControlAtStartup = true;
      # high, not xhigh: on Opus 4.8 thinking is off unless a request sets
      # thinking.type = "adaptive", and the API rejects xhigh/max while thinking
      # is disabled. Claude Code silently clamps xhigh back to high, so it only
      # ever looked applied. Revisit if thinking gets turned on.
      effortLevel = "high";
      model = "claude-opus-4-8";
      autoMemoryEnabled = false;
      # Keep session transcripts effectively forever (default is 30 days). They
      # are the source for llm-wiki backfill/capture, so retention matters.
      cleanupPeriodDays = 3650;
      permissions.defaultMode = "bypassPermissions";
      statusLine = {
        type = "command";
        command = "${statusline}/bin/claude-code-statusline";
      };
    };
  }
  # The superpowers plugin only where programs.claude-code.plugins exists
  # (home-manager >= 26.05). On HM 25-11 hosts (immich, edge-lax) the option does
  # not exist and defining it -- even [] -- is an eval error, so the whole
  # `plugins` key has to be ABSENT there. Those hosts set enableSuperpowers =
  # false, so gating the key on that flag keeps it absent exactly where it must
  # be. This replaces the old conditional import of superpowers-plugin.nix.
  // lib.optionalAttrs enableSuperpowers {
    plugins = [ superpowersPlugin ];
  };

  # Local LSP plugin marketplace consumed via programs.claude-code.settings
  # above. Ships nixd as the Nix language server so Claude Code gets real
  # diagnostics on .nix edits. nixd itself is added to home.packages below.
  home.file = {
    ".claude/lsp-marketplace/.claude-plugin/marketplace.json".text = builtins.toJSON {
      name = "cjlarose-lsps";
      owner.name = "cjlarose";
      description = "cjlarose local LSP plugins";
      plugins = [{
        name = "nixd";
        source = "./nixd";
        description = "Nix language server (nixd)";
      }];
    };
    ".claude/lsp-marketplace/nixd/.claude-plugin/plugin.json".text = builtins.toJSON {
      name = "nixd";
      description = "Nix language server (nixd)";
      version = "1.0.0";
      author.name = "cjlarose";
    };
    ".claude/lsp-marketplace/nixd/.lsp.json".text = builtins.toJSON {
      nix = {
        command = "nixd";
        extensionToLanguage.".nix" = "nix";
      };
    };
  };

  # superpowers' skills for opencode, through its native skills.paths key (the
  # plugin's /skills subdir). Empty -- and superpowersPlugin never forced -- when
  # superpowers is off.
  programs.opencode.settings.skills.paths =
    lib.optionals enableSuperpowers [ "${superpowersPlugin}/skills" ];

  # opencode itself, through stock programs.opencode with the plain package. It
  # still leans on Claude Code compatibility to read the shared ~/.claude/skills;
  # a later change wraps the package to disable that and installs skills natively.
  programs.opencode.enable = true;
  programs.opencode.package = additionalPackages.${system}.opencode;

  # The rest of the LLM-agent tooling lives behind the single llm-agents module,
  # which defaults every feature off. Everything wanted fleet-wide is opted into
  # here, and the rest per-host where the closure cost warrants it. The module
  # takes no additionalPackages arg -- every package is named explicitly here.
  cjlarose.llmAgents = {
    # herdr is a small CLI that pairs with claude, so it rides the shared profile
    # rather than being host-scoped. herdr reaches the no-AVX pve guests too — its
    # AVX2 paths sit behind runtime is_x86_feature_detected! gates, unlike the Bun
    # claude-code binary that forces the node build above.
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

    # The read-only querying-notes skill (into ~/.claude/skills, so both claude
    # and opencode see it) and LLM_WIKI_PATH. Only where a wiki checkout
    # actually exists, which is also the only place llm-wiki-skill-src is
    # threaded in below. skillSrc is the wiki flake input's skills/ tree.
    wiki.enable = llm-wiki-path != null;
    wiki.path = llm-wiki-path;
    wiki.skillSrc = llm-wiki-skill-src;
  };

  # lavish is left at its module default (off) here and enabled per-host in
  # nixos-configurations/ns1010301, as is the Playwright MCP (enablePlaywrightMcp
  # above): a browser review tool and a chromium closure have no business on the
  # headless guests.
  #
  # The wiki integration needs no extra import any more: the llm-agents module
  # installs the querying-notes skill and LLM_WIKI_PATH itself from
  # wiki.skillSrc + wiki.path. It used to import the wiki flake's own HM module
  # (which declared programs.llmWiki and shipped a claude-only plugin) plus
  # wiki-bridge.nix; both are gone, and opencode now sees the skill.
  #
  # superpowers-plugin.nix is gone too: the superpowers plugin is now defined
  # inline on programs.claude-code.plugins above, gated on enableSuperpowers so
  # the key stays absent on the HM 25-11 hosts that lack the option.
  imports = [
    ../../home-manager-modules/dev-tools.nix
    ../../home-manager-modules/neovim.nix
    ../../home-manager-modules/git.nix
    ../../home-manager-modules/shell.nix
    ../../home-manager-modules/llm-agents
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
    # nixd on PATH so the local LSP marketplace plugin's bare `nixd` command
    # resolves (marketplace + settings wired onto programs.claude-code above).
    pkgs.nixd
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
