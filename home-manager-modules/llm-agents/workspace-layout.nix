# The ~/repos + ~/workspaces checkout layout, as it affects Claude Code.
#
# Split out of default.nix rather than added to it: this is a self-contained,
# opt-in concern (one option, one CLAUDE.md, four skills) and default.nix is
# already long.
#
# The division between the two halves: the CLAUDE.md carries the rules and the
# reasons, because it is loaded into every session whether or not it is wanted,
# and it names the skill to reach for at each gate. The skills carry the
# commands, the decision trees and the scripts, because those cost nothing until
# something actually invokes them. Anything stated in both places will drift, so
# it is stated once.
# Off by default: home-manager-modules/ is shared across the fleet and only
# hosts actually migrated to this layout should carry the CLAUDE.md.
{ lib, config, ... }:

let
  cfg = config.cjlarose.llmAgents.claude.workspaceLayout;
  wiki = config.cjlarose.llmAgents.wiki;

  # The wiki is the one writable path under ~/repos. Rather than restate the
  # path in prose (two hosts, two different paths, guaranteed to drift), derive
  # it from the option that already decides it -- so the carve-out cannot name
  # a directory the wiki isn't actually in.
  #
  # Only emitted when the wiki really does live under ~/repos: on a host where
  # it doesn't, the blanket "never write here" rule is simply true and needs no
  # exception.
  wikiUnderRepos =
    wiki.enable
    && wiki.path != null
    && lib.hasPrefix "${config.home.homeDirectory}/repos/" wiki.path;

  wikiCarveOut = ''

    ## The LLM wiki is the one exception

    `${wiki.path}` is under `~/repos` but is **writable**, and the wiki skills
    are expected to write to it: `wiki:capturing-sessions` writes `raw/sessions/`,
    `wiki:ingesting-sources` writes `pages/`, `index.md` and `log.md`, and commits.

    This is deliberate. The wiki is a live document store, not a source checkout —
    the whole point is that pages are live rather than store copies, which is why
    only the skills are pinned to a flake rev and the pages are not.

    The read-only rule still holds for every other directory under `~/repos`, and
    the worktree rule holds here too: do not create worktrees in the wiki either.
  '';

in
{
  options.cjlarose.llmAgents.claude.workspaceLayout = {
    enable = lib.mkEnableOption ''
      the ~/repos + ~/workspaces checkout layout: a user-level CLAUDE.md
      describing the convention. Off by default -- only hosts migrated to this
      layout should turn it on
    '';

    extraInstructions = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = lib.literalExpression ''
        '''
          ## Workspace names must carry the issue key

          Name a workspace `<KEY>-<short-kebab-description>` ...
        '''
      '';
      description = ''
        Markdown appended to the layout CLAUDE.md, for conventions that are
        real on one consumer but meaningless on another.

        This is text rather than a set of booleans on purpose. A flag here
        would mean this module carries prose about someone else's issue
        tracker, and every new convention would need a new option plus a
        release of this repo before the consumer could adopt it. Passing the
        text lets the consumer that actually holds the convention own the
        wording and change it on its own schedule.

        Appended after the layout body and before the wiki carve-out.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # programs.claude-code has no memory/CLAUDE.md option (it covers settings,
    # agents, commands, hooks, skills and mcpServers only), so this goes
    # through home.file. Consequence: ~/.claude/CLAUDE.md becomes a read-only
    # store symlink, and Claude's `#` memory-append shortcut cannot write to
    # it -- the same trade this module already makes for settings.json.
    home.file.".claude/CLAUDE.md".text =
      builtins.readFile ./workspace-layout/CLAUDE.md
      + lib.optionalString (cfg.extraInstructions != "") "\n${cfg.extraInstructions}"
      + lib.optionalString wikiUnderRepos wikiCarveOut;

    # The mechanics the CLAUDE.md above deliberately does not carry. It states
    # the rules and names the skill at each gate; the commands, the decision
    # trees and the scripts live here, where they cost nothing until invoked.
    #
    # Installed through cjlarose.llmAgents.skills rather than
    # programs.claude-code.skills so they also land in ~/.agents/skills for the
    # other agents -- see ./skills.nix.
    cjlarose.llmAgents.skills = {
      # Deliberately not gated on anything: the read-side gate applies on every
      # host that has ~/repos at all, which is exactly the hosts that enable
      # this module.
      refreshing-a-repo = ./workspace-layout/skills/refreshing-a-repo;
      starting-a-workspace = ./workspace-layout/skills/starting-a-workspace;
      adding-a-repo-to-a-workspace = ./workspace-layout/skills/adding-a-repo-to-a-workspace;
      tearing-down-a-workspace = ./workspace-layout/skills/tearing-down-a-workspace;
    };
  };
}
