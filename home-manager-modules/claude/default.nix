{ additionalPackages, system, lib, ... }:
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
    };

    memory.text = lib.mkBefore (builtins.readFile ./CLAUDE.md);

    skills = {
      "nix-configurations/SKILL" = ./skills/nix-configurations/SKILL.md;
      "nix-configurations/home-manager-switch/SKILL" = ./skills/nix-configurations/home-manager-switch/SKILL.md;
      "nix-configurations/nixos-rebuild/SKILL" = ./skills/nix-configurations/nixos-rebuild/SKILL.md;
      "transcode-media/SKILL" = ./skills/transcode-media/SKILL.md;
    };
  };

  home.file."agent-docs/neovim-integration.md".source = ./agent-docs/neovim-integration.md;
}
