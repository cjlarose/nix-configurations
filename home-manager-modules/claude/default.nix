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

  config = {
    programs.claude-code = {
      enable = true;
      package = additionalPackages.${system}.claude-code;

      settings = {
        enabledPlugins = {
          "superpowers@claude-plugins-official" = true;
        };
        skipDangerousModePermissionPrompt = true;
        effortLevel = "medium";
        permissions = {
          defaultMode = "bypassPermissions";
        };
        statusLine = {
          type = "command";
          command = "${claudeCodeStatusline}/bin/claude-code-statusline";
        };
      };

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
