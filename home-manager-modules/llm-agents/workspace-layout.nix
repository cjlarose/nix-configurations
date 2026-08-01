# The ~/repos + ~/workspaces checkout layout, as it affects Claude Code.
#
# Split out of default.nix rather than added to it: this is a self-contained,
# opt-in concern (one option, one CLAUDE.md) and default.nix is already long.
# Off by default, because home-manager-modules/ is shared with the picktrace
# user on pt-docker-cjlarose, which still uses ~/worktrees.
{ lib, config, ... }:

let
  cfg = config.cjlarose.llmAgents.claude.workspaceLayout;
in
{
  options.cjlarose.llmAgents.claude.workspaceLayout = {
    enable = lib.mkEnableOption ''
      the ~/repos + ~/workspaces checkout layout: a user-level CLAUDE.md
      describing the convention. Off by default -- only hosts migrated to this
      layout should turn it on
    '';
  };

  config = lib.mkIf cfg.enable {
    # programs.claude-code has no memory/CLAUDE.md option (it covers settings,
    # agents, commands, hooks, skills and mcpServers only), so this goes
    # through home.file. Consequence: ~/.claude/CLAUDE.md becomes a read-only
    # store symlink, and Claude's `#` memory-append shortcut cannot write to
    # it -- the same trade this module already makes for settings.json.
    home.file.".claude/CLAUDE.md".source = ./workspace-layout/CLAUDE.md;
  };
}
