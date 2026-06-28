{ additionalPackages, system, lib, pkgs, config, ... }:

let
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
  options.cjlarose.claude.mattpocock-skills = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "Path to the mattpocock/skills repository source.";
  };

  options.cjlarose.claude.enablePlaywrightMcp = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Register the Playwright MCP server with Claude Code, using the pinned
      pkgs.playwright-mcp build (chromium baked in via PLAYWRIGHT_BROWSERS_PATH,
      so no runtime npx/network). Default off because it pulls a chromium
      browser closure; enable only on hosts where browser automation is wanted.
    '';
  };

  options.cjlarose.claude.remoteControlAtStartup = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Enable Remote Control for every new session at startup (the
      remoteControlAtStartup setting). Default off; enabled on cjlarose's own
      hosts via home/cjlarose/default.nix. Left off on pt-docker-cjlarose,
      whose picktrace Claude subscription doesn't have Remote Control.
    '';
  };

  options.cjlarose.claude.useNodeRuntime = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Use the node-pinned claude-code build (frozen at npm 2.1.112) instead of
      the latest Bun standalone. Required on CPUs without AVX (the Goldmont-based
      pve guests), where the Bun binary segfaults at launch. Leave false on
      AVX-capable hosts so they keep receiving the latest claude-code.
    '';
  };

  config = {
    programs.claude-code = {
      enable = true;
      package =
        if config.cjlarose.claude.useNodeRuntime
        then additionalPackages.${system}.claude-code-node
        else additionalPackages.${system}.claude-code;

      # Pinned, self-contained Playwright MCP (chromium baked in via the
      # package's PLAYWRIGHT_BROWSERS_PATH wrapper, so no runtime npx/network).
      # Gated default-off so headless hosts don't pull the chromium closure.
      # The HM module surfaces this as a .mcp.json in a generated plugin-dir
      # wired onto claude-code via --plugin-dir. Uses the chromium-pinned
      # wrapper above so the browser actually launches (see its comment).
      mcpServers = lib.optionalAttrs config.cjlarose.claude.enablePlaywrightMcp {
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
        remoteControlAtStartup = config.cjlarose.claude.remoteControlAtStartup;
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
        # The llm-wiki SessionStart index hook, LLM_WIKI_PATH, and the
        # wiki-capture/query/ingest skills are now provided by the wiki flake's
        # own home-manager module (programs.llmWiki), not this shared module.
      };

      # Skills authored in this repo, deployed via the upstream
      # programs.claude-code.skills option (key = bare skill directory name,
      # value = its SKILL.md; never append /SKILL — that double-nests post
      # home-manager #8770). Output: ~/.claude/skills/<name>/SKILL.md.
      skills = {
        # launch-remote-session moved into the LLM wiki (skills/), deployed via
        # programs.llmWiki where the wiki is present (cjlarose@ns1010301).
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
    } // lib.optionalAttrs (config.cjlarose.claude.mattpocock-skills != null) (let
      src = config.cjlarose.claude.mattpocock-skills;
    in {
      ".claude/skills/handoff" = { source = "${src}/skills/productivity/handoff"; recursive = true; };
      ".claude/skills/grill-me" = { source = "${src}/skills/productivity/grill-me"; recursive = true; };
    });
  };
}
