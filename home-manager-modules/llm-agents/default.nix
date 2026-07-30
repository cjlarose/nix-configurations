# Unified LLM-agent tooling module.
#
# One module owning everything agent-related for a user: Claude Code itself
# (package choice, MCP servers, settings, the nixd LSP marketplace, vendored
# skills), the phx workflow skills, lavish-axi, the personal LLM wiki
# integration, and the standalone agent CLIs (opencode, herdr).
#
# It replaces the former separate claude / phx-workflow / lavish / opencode
# modules. Claude Code is unconditional -- importing this module is the decision
# to have claude; everything else is opt-in per host/user.
#
# Module arguments (both consumers supply these):
#   additionalPackages, system  -- the consuming flake's package set, used for
#                                  the package option defaults.
#
# The one thing this module cannot own is the `imports` of the wiki flake's own
# module (which declares programs.llmWiki): `imports` is resolved before config
# exists, so it can key off neither an option nor an optional module argument
# (an arg with a default forces _module.args evaluation => infinite recursion).
# The consumer therefore imports cjlarose-llm-wiki.homeManagerModules.default
# alongside this module -- see home/cjlarose -- and this module owns everything
# else about the wiki, including turning it on and pointing it at a worktree.
{ additionalPackages, system, lib, pkgs, config, ... }:

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

    # claude (via chalk) hard-caps its color level to 256 whenever $TMUX is set,
    # a cap even FORCE_COLOR=3 cannot defeat. Dropping the variable is the only
    # way to get 24-bit color inside tmux; we are already past the point where
    # anything else in this process needs it.
    unset TMUX

    # We set the title above, so stop claude from fighting us over it.
    export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1

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

    claude.mattpocock-skills = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to the mattpocock/skills repository source.";
    };

    claude.superpowers-skills = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to the obra/superpowers repository source. When set, the
        systematic-debugging skill (SKILL.md + its supporting technique files) is
        copied into ~/.claude/skills/. Only that one skill is pulled, not the rest
        of the superpowers plugin.
      '';
    };

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

    claude.useNodeRuntime = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Use the node-pinned claude-code build (frozen at npm 2.1.112) instead of
        the latest Bun standalone. Required on CPUs without AVX (the Goldmont-based
        pve guests), where the Bun binary segfaults at launch. Leave false on
        AVX-capable hosts so they keep receiving the latest claude-code.
      '';
    };

    claude.package = lib.mkOption {
      type = lib.types.package;
      default =
        if cfg.claude.useNodeRuntime
        then additionalPackages.${system}.claude-code-node
        else additionalPackages.${system}.claude-code;
      defaultText = lib.literalExpression
        "additionalPackages.\${system}.claude-code{,-node}, per useNodeRuntime";
      description = ''
        The UNWRAPPED claude-code package. This module applies its own wrapper
        (terminal title, TMUX/colour and CLAUDE_CODE_SHELL handling) on top, so
        the consuming flake should hand over a plain claude-code build --
        llm-agents.nix's for the Bun default, or the frozen node build for
        no-AVX hosts.
      '';
    };

    # --- phx workflow skills ------------------------------------------------

    phxWorkflow.enable = lib.mkEnableOption ''
      the language-agnostic phx workflow skills (/phx-brainstorm, /phx-plan,
      /phx-work, /phx-review, /phx-full). These are de-Elixir'd ports of the
      core workflow spine from oliver-kriska/claude-elixir-phoenix: same
      .claude/plans/{slug}/ artifact contract and decision-gate discipline,
      but with build/test/lint discovery left to the model (prose, not
      hardcoded mix commands) and research fan-out using the built-in
      general-purpose/Explore subagents instead of named Elixir agents
    '';

    # --- lavish-axi ---------------------------------------------------------

    lavish.enable = lib.mkEnableOption ''
      the lavish-axi CLI (upstream kunchenguid/lavish-axi, built from source with
      telemetry disabled) and its Lavish Editor Claude Code skill. lavish-axi opens
      an agent-generated HTML artifact in a sandboxed browser for human annotation
      and ships the feedback back to the driving agent over a loopback server with
      a Host-header DNS-rebinding guard. Disabled by default; opt in per host/user
    '';

    lavish.package = lib.mkOption {
      type = lib.types.package;
      default = additionalPackages.${system}.lavish-axi;
      defaultText = lib.literalExpression "additionalPackages.\${system}.lavish-axi";
      description = ''
        The lavish-axi package to install. Carries the CLI at bin/lavish-axi and
        the generated Claude Code skill at share/lavish-axi/skill/SKILL.md.
      '';
    };

    # --- standalone agent CLIs ---------------------------------------------

    opencode.enable = lib.mkEnableOption
      "opencode, the standalone terminal coding agent (programs.opencode)";

    opencode.package = lib.mkOption {
      type = lib.types.package;
      default = additionalPackages.${system}.opencode;
      defaultText = lib.literalExpression "additionalPackages.\${system}.opencode";
      description = "The opencode package to install.";
    };

    herdr.enable = lib.mkEnableOption ''
      herdr, a terminal workspace manager for AI coding agents (herdr.dev).
      Packaged only in llm-agents.nix, not nixpkgs
    '';

    herdr.package = lib.mkOption {
      type = lib.types.package;
      default = additionalPackages.${system}.herdr;
      defaultText = lib.literalExpression "additionalPackages.\${system}.herdr";
      description = "The herdr package to install.";
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

    # --- vendored third-party skills ---------------------------------------
    (lib.mkIf (cfg.claude.mattpocock-skills != null) {
      # handoff is provided by the LLM wiki (skills/handoff), deployed via the
      # wiki plugin where a wiki is present. grill-me stays vendored here.
      home.file.".claude/skills/grill-me" = {
        source = "${cfg.claude.mattpocock-skills}/skills/productivity/grill-me";
        recursive = true;
      };
    })

    (lib.mkIf (cfg.claude.superpowers-skills != null) {
      # systematic-debugging pulled from obra/superpowers (flake input). Recursive
      # so the SKILL.md plus its supporting technique files (root-cause-tracing.md,
      # defense-in-depth.md, condition-based-waiting.md, ...) all land and the
      # in-directory references resolve. Only this one skill is pulled, not the
      # rest of the superpowers plugin; its superpowers:* cross-refs are inert.
      home.file.".claude/skills/systematic-debugging" = {
        source = "${cfg.claude.superpowers-skills}/skills/systematic-debugging";
        recursive = true;
      };
    })

    # --- phx workflow skills ------------------------------------------------
    (lib.mkIf cfg.phxWorkflow.enable {
      # Deployed via the upstream programs.claude-code.skills option (key = bare
      # skill directory name, value = its SKILL.md; never append /SKILL — that
      # double-nests post home-manager #8770). skills is attrsOf, so these keys
      # merge with any set elsewhere. Output: ~/.claude/skills/phx-<name>/SKILL.md.
      programs.claude-code.skills = {
        "phx-brainstorm" = ./skills/phx/brainstorm/SKILL.md;
        "phx-plan" = ./skills/phx/plan/SKILL.md;
        "phx-work" = ./skills/phx/work/SKILL.md;
        "phx-review" = ./skills/phx/review/SKILL.md;
        "phx-full" = ./skills/phx/full/SKILL.md;
      };
    })

    # --- lavish-axi ---------------------------------------------------------
    (lib.mkIf cfg.lavish.enable {
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

    # --- standalone agent CLIs ---------------------------------------------
    (lib.mkIf cfg.opencode.enable {
      programs.opencode = {
        enable = true;
        package = cfg.opencode.package;
      };
    })

    (lib.mkIf cfg.herdr.enable {
      home.packages = [ cfg.herdr.package ];
    })

    # --- personal LLM wiki --------------------------------------------------
    # The programs.llmWiki definition itself lives in ./wiki-bridge.nix, which
    # the consumer imports next to the wiki flake's module. It cannot live here:
    # mkIf distributes down to the attribute path, so a `programs.llmWiki`
    # definition under a false mkIf is still checked against the declarations
    # and errors with "option does not exist" on every wiki-less host.
    {
      assertions = [
        {
          assertion = !cfg.wiki.enable || cfg.wiki.path != null;
          message = "cjlarose.llmAgents.wiki.enable is true but cjlarose.llmAgents.wiki.path is unset.";
        }
      ];
    }
  ];
}
