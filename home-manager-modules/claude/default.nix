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

      skills = lib.mkIf (config.cjlarose.claude.mattpocock-skills != null) (let
        src = config.cjlarose.claude.mattpocock-skills;
      in {
        handoff = "${src}/skills/productivity/handoff/SKILL.md";
        grill-me = "${src}/skills/productivity/grill-me/SKILL.md";
      });

    };

    home.file."agent-docs/neovim-integration.md".source = ./agent-docs/neovim-integration.md;
  };
}
