# The ~/repos + ~/workspaces checkout layout, as it affects Claude Code.
#
# Split out of default.nix rather than added to it: this is a self-contained,
# opt-in concern (one option, one CLAUDE.md) and default.nix is already long.
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

  # Naming policy for hosts whose work is tracked in an issue tracker. Off by
  # default because it is false on a personal host -- ns1010301's repos have no
  # Jira project and no incident tracker, so requiring a key there would leave
  # every workspace unnameable.
  trackerNaming = ''

    ## Workspace names must carry the issue key

    Name a workspace `<KEY>-<short-kebab-description>`, where `<KEY>` is whichever
    of these the work has:

    - a **Jira issue key** — `PLAT-1518`, `LMG-1702`, `LMD-1138`
    - an **incident.io incident number** — `INC-128`

    So: `~/workspaces/PLAT-1518-coder-envbox`, `~/workspaces/INC-128-payroll-export-timeouts`.

    Keep the description short and kebab-cased. It is there to make the directory
    readable at a glance, not to restate the ticket title — the key is the durable
    identifier and the place to look up detail.

    ### When there is no key

    **Do not create the workspace directory.** Ask the user for the Jira issue or
    incident number first.

    Only create an unprefixed workspace if the user, having been asked, explicitly
    confirms they want to work without either. Their silence is not confirmation,
    and neither is the absence of a key in how they described the task — most work
    that arrives without a mentioned ticket still has one.
  '';
in
{
  options.cjlarose.llmAgents.claude.workspaceLayout = {
    enable = lib.mkEnableOption ''
      the ~/repos + ~/workspaces checkout layout: a user-level CLAUDE.md
      describing the convention. Off by default -- only hosts migrated to this
      layout should turn it on
    '';

    requireTrackerKey = lib.mkEnableOption ''
      the rule that a workspace directory is named <KEY>-<short-kebab-description>
      for a Jira issue key or incident.io incident number, and that an agent must
      ask rather than invent a name when the work has neither. Off by default:
      it is only true for hosts whose work is actually tracked that way, and a
      personal host has no such key to require
    '';
  };

  config = lib.mkIf cfg.enable {
    # programs.claude-code has no memory/CLAUDE.md option (it covers settings,
    # agents, commands, hooks, skills and mcpServers only), so this goes
    # through home.file. Consequence: ~/.claude/CLAUDE.md becomes a read-only
    # store symlink, and Claude's `#` memory-append shortcut cannot write to
    # it -- the same trade this module already makes for settings.json.
    home.file.".claude/CLAUDE.md".text =
      builtins.readFile ./workspace-layout/CLAUDE.md
      + lib.optionalString cfg.requireTrackerKey trackerNaming
      + lib.optionalString wikiUnderRepos wikiCarveOut;
  };
}
