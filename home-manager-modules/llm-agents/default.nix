# Unified LLM-agent tooling module.
#
# One module owning everything agent-related for a user: Claude Code itself
# (package choice, MCP servers, settings, the nixd LSP marketplace), the
# superpowers skills plugin, lavish-axi, the personal LLM wiki integration, the
# standalone agent CLIs (opencode, herdr), and the gh-stack agent skill. Options
# ending in `Skill` install documentation only -- the tool they describe is
# installed elsewhere.
#
# It replaces the former separate claude / phx-workflow / lavish / opencode
# modules. Claude Code is unconditional -- importing this module is the decision
# to have claude; everything else is opt-in per host/user.
#
# The module takes no flake-specific arguments: every package it installs comes
# in through a `*.package` option that the consumer sets explicitly. It used to
# reach into an `additionalPackages` module arg for defaults, which coupled it to
# one particular shape of consuming flake and silently broke if that flake
# renamed or dropped an attr.
#
# The one thing this module cannot own is the `imports` of the wiki flake's own
# module (which declares programs.llmWiki): `imports` is resolved before config
# exists, so it can key off neither an option nor an optional module argument
# (an arg with a default forces _module.args evaluation => infinite recursion).
# The consumer therefore imports cjlarose-llm-wiki.homeManagerModules.default
# alongside this module -- see home/cjlarose -- and this module owns everything
# else about the wiki, including turning it on and pointing it at a worktree.
{ lib, pkgs, config, ... }:

let
  cfg = config.cjlarose.llmAgents;

  # The claude wrapper, shared by both consuming flakes. It used to be duplicated
  # as `mkTitleWrapper` in each repo's packages/default.nix, where it drifted
  # (cjlarose had it as a reusable function over both the Bun and node builds;
  # picktrace had the body inlined). Living here means one definition, and `pkgs`
  # is the host's own nixpkgs -- so bashInteractive is the one the system already
  # pulls in, with no nixpkgs-26-05 plumbing through packages/. The rationale for
  # each line lives in the script itself, so it survives into the store copy the
  # user actually reads.
  wrappedClaude = pkgs.writeShellScriptBin "claude" ''
    # Set the terminal title from the worktree layout: owner/repo [worktree].
    # Only fires under ~/worktrees/<owner>/<repo>/<worktree>; elsewhere the
    # title is left alone.
    if [[ "$PWD" =~ ^''${HOME}/worktrees/([^/]+)/([^/]+)/([^/]+) ]]; then
      printf '\033]2;%s\007' "Claude Code ✳ ''${BASH_REMATCH[1]}/''${BASH_REMATCH[2]} [''${BASH_REMATCH[3]}]"
    fi

    # We set the title above, so stop claude from fighting us over it.
    export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1

    # claude (via chalk) hard-caps its color level to 256 whenever $TMUX is set,
    # a cap even FORCE_COLOR=3 cannot defeat. Dropping the variable is the only
    # way to get 24-bit color inside tmux; we are already past the point where
    # anything else in this process needs it.
    unset TMUX

    # Pin the shell claude spawns for the Bash tool. Left unset it follows
    # $SHELL, which is zsh on these hosts, so tool invocations would run under a
    # different shell than the bash the agent's snippets assume. The :- default
    # means an explicit value in the environment still wins.
    export CLAUDE_CODE_SHELL="''${CLAUDE_CODE_SHELL:-${pkgs.bashInteractive}/bin/bash}"

    exec ${cfg.claude.package}/bin/claude "$@"
  '';

  claudeCodeStatusline = pkgs.writeShellApplication {
    name = "claude-code-statusline";
    runtimeInputs = [ pkgs.jq pkgs.gawk ];
    text = builtins.readFile ./claude-code-statusline.sh;
  };

  # playwright-mcp 0.0.69 ignores the PLAYWRIGHT_MCP_BROWSER env var that
  # nixpkgs sets, so it falls back to the "chrome" channel and tries to
  # provision a chrome-for-testing build by writing into its (read-only) Nix
  # store browsers path — which fails with ENOENT/mkdir. Point it explicitly at
  # the nix-provided chromium instead (the same playwright-driver.browsers
  # derivation the upstream wrapper already exports, so versions stay in sync).
  # The chromium revision is globbed at runtime to survive nixpkgs bumps.
  # Headless because this targets displayless hosts; isolated keeps the profile
  # in memory.
  playwrightMcp = pkgs.writeShellScriptBin "playwright-mcp-chromium" ''
    chrome=( ${pkgs.playwright-driver.browsers}/chromium-*/chrome-linux*/chrome )
    exec ${pkgs.playwright-mcp}/bin/playwright-mcp \
      --headless --isolated --executable-path "''${chrome[0]}" "$@"
  '';
in
{
  options.cjlarose.llmAgents = {

    # --- Claude Code -------------------------------------------------------

    claude.enablePlaywrightMcp = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Register the Playwright MCP server with Claude Code, using the pinned
        pkgs.playwright-mcp build (chromium baked in via PLAYWRIGHT_BROWSERS_PATH,
        so no runtime npx/network). Default off because it pulls a chromium
        browser closure; enable only on hosts where browser automation is wanted.
      '';
    };

    claude.remoteControlAtStartup = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable Remote Control for every new session at startup (the
        remoteControlAtStartup setting). Default off; enabled on cjlarose's own
        hosts via home/cjlarose/default.nix. Left off on pt-docker-cjlarose,
        whose picktrace Claude subscription doesn't have Remote Control.
      '';
    };

    claude.package = lib.mkOption {
      type = lib.types.package;
      description = ''
        The UNWRAPPED claude-code package. Required -- claude is the one piece of
        this module that is unconditional. The module applies its own wrapper
        (terminal title, TMUX/colour and CLAUDE_CODE_SHELL handling) on top, so
        hand over a plain build.

        Which build is a property of the HOST, not of this module: AVX-capable
        machines take the latest Bun standalone, while the Goldmont-based pve
        guests need the node-pinned build (frozen at npm 2.1.112) because the Bun
        binary segfaults at launch there. The consumer picks; this used to be a
        `useNodeRuntime` boolean here, which forced the module to know both
        package names.
      '';
    };

    # --- superpowers ---------------------------------------------------------

    superpowers.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        obra/superpowers packaged as a force-loaded Claude Code plugin: 14 skills
        covering brainstorming, planning, TDD, code review, git worktrees and
        debugging, invocable as superpowers:<name>, plus upstream's SessionStart
        hook which prepends the using-superpowers skill to every session.

        Replaces two things that used to live here: the vendored
        systematic-debugging copy (now one skill of the set, with its
        superpowers:* cross-references finally resolving) and the phx workflow
        skills, whose brainstorm/plan/work/review spine upstream covers natively
        with brainstorming + writing-plans + executing-plans + *-code-review.

        Setting this is NOT enough on its own -- ./superpowers-plugin.nix must
        also be imported, which is what actually defines
        programs.claude-code.plugins. That option does not exist on
        home-manager 25-11, so the definition has to be absent rather than
        disabled there; see that file.
      '';
    };

    # --- lavish-axi ---------------------------------------------------------

    lavish.enable = lib.mkEnableOption ''
      the lavish-axi CLI (upstream kunchenguid/lavish-axi, built from source with
      telemetry disabled) and its Lavish Editor Claude Code skill. lavish-axi opens
      an agent-generated HTML artifact in a sandboxed browser for human annotation
      and ships the feedback back to the driving agent over a loopback server with
      a Host-header DNS-rebinding guard. Disabled by default; opt in per host/user
    '';

    lavish.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        The lavish-axi package to install. Carries the CLI at bin/lavish-axi and
        the generated Claude Code skill at share/lavish-axi/skill/SKILL.md.
        Required when lavish.enable is set; asserted below rather than defaulted,
        so hosts with lavish off need not name a package at all.
      '';
    };

    # --- gh stacked PRs (skill only) ----------------------------------------

    ghStackSkill.enable = lib.mkEnableOption ''
      the agent skill that github/gh-stack ships at share/gh-stack/skill/.

      The name is literal: this installs the SKILL.md and nothing else. `gh
      stack` is a human CLI tool and is not this module's business -- registering
      the extension with gh and putting the binary on PATH is
      cjlarose.devTools.ghStack, in the dev-tools module. Enable both, from the
      same package, or the skill documents a command that is not installed
    '';

    ghStackSkill.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        The gh-stack package to read share/gh-stack/skill/SKILL.md from. Should
        be the same package given to cjlarose.devTools.ghStack.package -- the
        skill documents specific subcommands and flags, so a skill from a
        different build than the installed extension is actively misleading.
        Required when ghStackSkill.enable is set.
      '';
    };

    # --- standalone agent CLIs ---------------------------------------------

    opencode.enable = lib.mkEnableOption
      "opencode, the standalone terminal coding agent (programs.opencode)";

    opencode.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "The opencode package to install. Required when opencode.enable is set.";
    };

    herdr.enable = lib.mkEnableOption ''
      herdr, a terminal workspace manager for AI coding agents (herdr.dev).
      Packaged only in llm-agents.nix, not nixpkgs
    '';

    herdr.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "The herdr package to install. Required when herdr.enable is set.";
    };

    # --- personal LLM wiki --------------------------------------------------

    wiki.enable = lib.mkEnableOption ''
      the personal LLM wiki integration: the `wiki` Claude Code plugin (skills +
      SessionStart index hook) and LLM_WIKI_PATH. Only valid where the consumer
      also imports cjlarose-llm-wiki.homeManagerModules.default, which is what
      declares programs.llmWiki (see the header comment)
    '';

    wiki.path = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/you/worktrees/owner/llm-wiki/default";
      description = ''
        Absolute path to the writable llm-wiki git worktree on the target
        machine. Exported as LLM_WIKI_PATH and baked into the plugin's
        session-start hook, which cats the live index.md there.
      '';
    };
  };

  config = lib.mkMerge [

    # --- Claude Code (unconditional) ---------------------------------------
    {
      programs.claude-code = {
        enable = true;
        # The module's own wrapper, not cfg.claude.package directly -- see
        # wrappedClaude above. home-manager wraps this again with its
        # --plugin-dir flags, so the final chain is
        # HM plugin wrapper -> title/env wrapper -> claude-code.
        package = wrappedClaude;

        # Pinned, self-contained Playwright MCP (chromium baked in via the
        # package's PLAYWRIGHT_BROWSERS_PATH wrapper, so no runtime npx/network).
        # Gated default-off so headless hosts don't pull the chromium closure.
        # The HM module surfaces this as a .mcp.json in a generated plugin-dir
        # wired onto claude-code via --plugin-dir. Uses the chromium-pinned
        # wrapper above so the browser actually launches (see its comment).
        mcpServers = lib.optionalAttrs cfg.claude.enablePlaywrightMcp {
          playwright = {
            type = "stdio";
            command = "${playwrightMcp}/bin/playwright-mcp-chromium";
          };
        };

        settings = {
          enabledPlugins = {
            # nixd Nix language server, provided by the local marketplace below.
            "nixd@cjlarose-lsps" = true;
          };
          # Local plugin marketplace (files materialized via home.file below) that
          # ships a single LSP plugin wiring nixd as the Nix language server, so
          # Claude Code gets real diagnostics on .nix edits (unused bindings,
          # undefined vars, flake/option-aware analysis). nixd binary comes from
          # home.packages so the bare "nixd" command resolves on PATH.
          extraKnownMarketplaces."cjlarose-lsps".source = {
            source = "directory";
            path = "${config.home.homeDirectory}/.claude/lsp-marketplace";
          };
          skipDangerousModePermissionPrompt = true;
          remoteControlAtStartup = cfg.claude.remoteControlAtStartup;
          effortLevel = "medium";
          autoMemoryEnabled = false;
          # Keep session transcripts effectively forever (default is 30 days, which
          # silently garbage-collects ~/.claude/projects history). These transcripts
          # are the source for llm-wiki backfill/capture, so retention matters.
          cleanupPeriodDays = 3650;
          env = {
            CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
          };
          permissions = {
            defaultMode = "bypassPermissions";
          };
          statusLine = {
            type = "command";
            command = "${claudeCodeStatusline}/bin/claude-code-statusline";
          };
        };
      };

      home.packages = [ pkgs.nixd ];

      home.file = {
        # Local LSP plugin marketplace consumed via settings.extraKnownMarketplaces
        # + enabledPlugins above. Ships nixd as the Nix language server.
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
    }

    # --- lavish-axi ---------------------------------------------------------
    # The `package != null` half of each guard is not redundant with the
    # assertions below: without it a null reaches home.packages and fails the
    # `package` type check FIRST, burying the assertion's readable message.
    (lib.mkIf (cfg.lavish.enable && cfg.lavish.package != null) {
      # CLI on PATH. Under home-manager useUserPackages this rides the system
      # profile, so the picktrace VM needs a system switch-to-configuration to pick
      # it up (an HM-only activate won't), same as tuicr / the playwright closure.
      home.packages = [ cfg.lavish.package ];

      # The skill drives the on-PATH lavish-axi binary directly (never npx), so
      # nothing is fetched from npm at runtime. Single-file SKILL.md shipped in the
      # package's share/ output; raw home.file (like the upstream lavish-axi HM
      # module) rather than programs.claude-code.skills.
      home.file.".claude/skills/lavish/SKILL.md".source =
        "${cfg.lavish.package}/share/lavish-axi/skill/SKILL.md";
    })

    # --- gh stacked PRs (skill only) ----------------------------------------
    (lib.mkIf (cfg.ghStackSkill.enable && cfg.ghStackSkill.package != null) {
      # Upstream's own skill, read out of the package so it always matches the
      # extension binary built from the same source.
      programs.claude-code.skills."gh-stack" =
        "${cfg.ghStackSkill.package}/share/gh-stack/skill/SKILL.md";
    })

    # --- standalone agent CLIs ---------------------------------------------
    (lib.mkIf (cfg.opencode.enable && cfg.opencode.package != null) {
      programs.opencode = {
        enable = true;
        package = cfg.opencode.package;
      };
    })

    (lib.mkIf (cfg.herdr.enable && cfg.herdr.package != null) {
      home.packages = [ cfg.herdr.package ];
    })

    # --- personal LLM wiki --------------------------------------------------
    # The programs.llmWiki definition itself lives in ./wiki-bridge.nix, which
    # the consumer imports next to the wiki flake's module. It cannot live here:
    # mkIf distributes down to the attribute path, so a `programs.llmWiki`
    # definition under a false mkIf is still checked against the declarations
    # and errors with "option does not exist" on every wiki-less host.
    # Every enable that needs a package asserts it rather than defaulting one, so
    # a host that leaves the feature off never has to name a package at all.
    {
      assertions = [
        {
          assertion = !cfg.wiki.enable || cfg.wiki.path != null;
          message = "cjlarose.llmAgents.wiki.enable is true but cjlarose.llmAgents.wiki.path is unset.";
        }
        {
          assertion = !cfg.lavish.enable || cfg.lavish.package != null;
          message = "cjlarose.llmAgents.lavish.enable is true but cjlarose.llmAgents.lavish.package is unset.";
        }
        {
          assertion = !cfg.opencode.enable || cfg.opencode.package != null;
          message = "cjlarose.llmAgents.opencode.enable is true but cjlarose.llmAgents.opencode.package is unset.";
        }
        {
          assertion = !cfg.herdr.enable || cfg.herdr.package != null;
          message = "cjlarose.llmAgents.herdr.enable is true but cjlarose.llmAgents.herdr.package is unset.";
        }
        {
          assertion = !cfg.ghStackSkill.enable || cfg.ghStackSkill.package != null;
          message = "cjlarose.llmAgents.ghStackSkill.enable is true but cjlarose.llmAgents.ghStackSkill.package is unset.";
        }
      ];
    }
  ];
}
