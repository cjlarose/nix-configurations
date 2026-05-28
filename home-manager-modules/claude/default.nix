{ additionalPackages, system, lib, pkgs, ... }:

let
  claudeCodeStatusline = pkgs.writeShellApplication {
    name = "claude-code-statusline";
    runtimeInputs = [ pkgs.jq pkgs.gawk ];
    text = builtins.readFile ./claude-code-statusline.sh;
  };
in
{
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

  home.file."agent-docs/neovim-integration.md".source = ./agent-docs/neovim-integration.md;
}
