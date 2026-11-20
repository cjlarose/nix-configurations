# The LLM-agent half of cjlarose's home: Claude Code and opencode (stock
# home-manager modules, wrapped by harness-config's lib), the superpowers plugin,
# the nixd LSP marketplace, the Playwright MCP, and the cjlarose.llmAgents
# tooling (herdr, tuicr, git-surgeon, skills, the wiki integration).
#
# Opt-in: hosts get this only by importing it alongside the base profile in
# ./default.nix. Today that is ns1010301 alone.
{ system, additionalPackages, llm-wiki-path ? null, llm-wiki-skill-src ? null, enablePlaywrightMcp ? false }:
{ pkgs, lib, config, ... }:
let
  # harness-config's lib, re-exported through additionalPackages (see
  # packages/default.nix). Provides wrapClaudeCode (the terminal-env claude
  # wrapper) and mkSuperpowersPlugin (builds obra/superpowers into a plugin from
  # harness-config's own pinned source). Claude Code itself is now stock
  # programs.claude-code, configured here rather than by the llm-agents module.
  harnessConfig = additionalPackages.${system}.harnessConfig;

  # obra/superpowers as a namespaced Claude Code plugin, built by harness-config
  # from its own pinned source. Two customizations: drop
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
  # Stock Claude Code, wrapped by harness-config's
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
      package = additionalPackages.${system}.claude-code;
      trueColorInTmux = true;
      fullscreenTui = true;
      toolShell = "${pkgs.bashInteractive}/bin/bash";
      agentTeams = true;
      disableAutoMemory = true;
      disableAgentView = true;
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
      # Keep session transcripts effectively forever (default is 30 days). They
      # are the source for llm-wiki backfill/capture, so retention matters.
      cleanupPeriodDays = 3650;
      permissions.defaultMode = "bypassPermissions";
      statusLine = {
        type = "command";
        command = "${statusline}/bin/claude-code-statusline";
      };
    };

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

  # Stock opencode, wrapped by harness-config's lib to disable
  # Claude Code compatibility: without this opencode falls back to reading Claude's
  # ~/.claude/CLAUDE.md and ~/.claude/skills, which on a host running both agents
  # deliberately is a leak. With compat off it reads only its own AGENTS.md (stock
  # programs.opencode.rules, see workspace-layout.nix) and its own skill dirs (stock
  # programs.opencode.skills, written by the llm-agents siblings) plus skills.paths.
  programs.opencode = {
    enable = true;
    package = harnessConfig.wrapOpencode {
      inherit pkgs;
      package = additionalPackages.${system}.opencode;
      disableClaudeCompat = true;
    };

    # superpowers' skills for opencode, through its native skills.paths key (the
    # plugin's /skills subdir).
    settings.skills.paths = [ "${superpowersPlugin}/skills" ];
  };

  # The rest of the LLM-agent tooling lives behind the single llm-agents module,
  # which defaults every feature off. Everything wanted wherever this file is
  # imported is opted into here, and the rest per-host where the closure cost
  # warrants it. The module
  # takes no additionalPackages arg -- every package is named explicitly here.
  cjlarose.llmAgents = {
    # herdr manages claude/opencode sessions.
    # (opencode itself is stock programs.opencode above, no longer a module option.)
    herdr = {
      enable = true;
      package = additionalPackages.${system}.herdr;
      # Upstream's own agent skill, which the module lifts out of the source
      # tree -- the same pin the binary above is built from, so the skill cannot
      # describe subcommands this herdr does not have.
      skillSrc = additionalPackages.${system}.herdr-src;
    };

    # Code review at the keyboard. `reverse` comes from the
    # commit-order-display-option branch of cjlarose/tuicr, which is what the
    # package below is built from -- render the inline commit selector
    # parent -> child for GitHub-PR-style branch review.
    tuicr = {
      enable = true;
      package = additionalPackages.${system}.tuicr;
      settings.reverse = true;
    };

    # Hunk-level git surgery for agents, plus upstream's skill describing it.
    # Not split across dev-tools like gh-stack -- `git-surgeon` is
    # agent tooling, and the interactive equivalents (git add -p, rebase -i) are
    # what a human at the keyboard reaches for.
    gitSurgeon = { enable = true; package = additionalPackages.${system}.git-surgeon; };

    # Skill only, as the name says; the gh extension itself is a human CLI tool
    # enabled via cjlarose.devTools.ghStack in ./default.nix. Same package for both, so the
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
  imports = [
    ../../home-manager-modules/llm-agents
  ];

  home.packages = [
    # nixd on PATH so the local LSP marketplace plugin's bare `nixd` command
    # resolves (marketplace + settings wired onto programs.claude-code above).
    pkgs.nixd
    # opencode2 (the OpenCode 2.0 beta) alongside v1, same wrapper (Claude-compat
    # off) under its own binary name. It shares v1's ~/.config/opencode config --
    # AGENTS.md, the skill dirs, the herdr plugin, opencode.json -- so it needs
    # nothing but the binary on PATH. Its background service binds 0xC0DE (49374),
    # which is why ns1010301 moves ai-memory off that port (see aiMemory there).
    (harnessConfig.wrapOpencode {
      inherit pkgs;
      package = additionalPackages.${system}.opencode2;
      binName = "opencode2";
      disableClaudeCompat = true;
    })
  ];
}
