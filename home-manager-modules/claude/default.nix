{ additionalPackages, system, lib, pkgs, config, ... }:

let
  claudeCodeStatusline = pkgs.writeShellApplication {
    name = "claude-code-statusline";
    runtimeInputs = [ pkgs.jq pkgs.gawk ];
    text = builtins.readFile ./claude-code-statusline.sh;
  };
in
{
  options.cjlarose.claude.mattpocock-skills = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    description = "Path to the mattpocock/skills repository source.";
  };

  options.cjlarose.claude.llm-wiki-path = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = ''
      Absolute path to a local llm-wiki working tree. When set, exports
      LLM_WIKI_PATH and out-of-store-symlinks the repo's wiki-capture and
      wiki-query skills under ~/.claude/skills/ so edits in the working
      tree are visible without a home-manager rebuild.
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

      settings = {
        enabledPlugins = {
          "superpowers@claude-plugins-official" = true;
        };
        skipDangerousModePermissionPrompt = true;
        effortLevel = "medium";
        autoMemoryEnabled = false;
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
      } // lib.optionalAttrs (config.cjlarose.claude.llm-wiki-path != null) (let
        injector = "${config.cjlarose.claude.llm-wiki-path}/.claude/hooks/inject-wiki-index.sh";
      in {
        # Surface the llm-wiki index at the start of every session so the model
        # knows what the wiki covers and can use wiki-query proactively. The
        # script self-guards on a missing index.md; the command additionally
        # tolerates the script file itself being absent (e.g. an older wiki
        # checkout at this path, or a stale llm-wiki-path), staying a silent
        # no-op instead of erroring on every session start. Gated on the same
        # option as the LLM_WIKI_PATH export and the wiki skill symlinks.
        hooks = {
          SessionStart = [
            {
              matcher = "startup|resume|clear|compact";
              hooks = [
                {
                  type = "command";
                  command = ''if [ -x "${injector}" ]; then exec "${injector}"; fi'';
                }
              ];
            }
          ];
        };
      });

      memory.text = lib.mkBefore (builtins.readFile ./CLAUDE.md);

    };

    home.sessionVariables = lib.optionalAttrs (config.cjlarose.claude.llm-wiki-path != null) {
      LLM_WIKI_PATH = config.cjlarose.claude.llm-wiki-path;
    };

    home.file = {
      "agent-docs/neovim-integration.md".source = ./agent-docs/neovim-integration.md;
    } // lib.optionalAttrs (config.cjlarose.claude.mattpocock-skills != null) (let
      src = config.cjlarose.claude.mattpocock-skills;
    in {
      ".claude/skills/handoff" = { source = "${src}/skills/productivity/handoff"; recursive = true; };
      ".claude/skills/grill-me" = { source = "${src}/skills/productivity/grill-me"; recursive = true; };
    }) // lib.optionalAttrs (config.cjlarose.claude.llm-wiki-path != null) (let
      src = config.cjlarose.claude.llm-wiki-path;
    in {
      ".claude/skills/wiki-capture".source =
        config.lib.file.mkOutOfStoreSymlink "${src}/skills/wiki-capture";
      ".claude/skills/wiki-query".source =
        config.lib.file.mkOutOfStoreSymlink "${src}/skills/wiki-query";
    });
  };
}
