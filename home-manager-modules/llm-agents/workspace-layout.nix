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
  agents = config.cjlarose.llmAgents;
  wiki = config.cjlarose.llmAgents.wiki;

  # Named once so the two harness blocks below cannot drift to different paths
  # while still looking symmetrical.
  skills = {
    refreshing-a-repo = ./workspace-layout/skills/refreshing-a-repo;
    starting-a-workspace = ./workspace-layout/skills/starting-a-workspace;
    adding-a-repo-to-a-workspace = ./workspace-layout/skills/adding-a-repo-to-a-workspace;
    tearing-down-a-workspace = ./workspace-layout/skills/tearing-down-a-workspace;
  };

  # The LLM wikis used to be carved out of the read-only rule: the skills wrote
  # pages and committed directly in ~/repos. They no longer do. Captures are
  # written in a linked worktree in a workspace like any other change, and
  # ingests run in a standing worktree of their own, so the wiki checkouts under
  # ~/repos are ordinary read-only checkouts and the blanket rule is simply true
  # of them.
  #
  # One sanctioned write remains, and it is worth stating rather than leaving to
  # be rediscovered: after an ingest lands, the standing agent fast-forwards the
  # wiki's ~/repos checkout. Without it that checkout -- which is what the
  # session-start hook reads index.md from, and what queries search -- silently
  # serves a wiki missing everything just filed. It is exactly the move
  # tearing-down-a-workspace already makes when work lands, and it is --ff-only,
  # so it refuses rather than inventing a merge.
  #
  # Emitted only where a wiki checkout really is under ~/repos; elsewhere there
  # is nothing to qualify.
  wikiPathsUnderRepos =
    lib.filter (p: lib.hasPrefix "${config.home.homeDirectory}/repos/" p)
      (lib.mapAttrsToList (_: w: w.repoPath)
        (lib.optionalAttrs wiki.enable wiki.wikis));

  wikiUnderRepos = wikiPathsUnderRepos != [ ];

  wikiCarveOut = ''

    ## The LLM wiki checkouts are read-only too

    ${lib.concatMapStringsSep "\n" (p: "- `${p}`") wikiPathsUnderRepos}

    These are ordinary `~/repos` checkouts and the rule above applies to them
    unchanged. Do not edit pages, commit, or create worktrees here.

    They were once an exception, and are not any more. Captures are written in a
    linked worktree in a workspace, like every other change; ingests run in a
    standing worktree of their own, which is also what serializes them.

    **The one sanctioned write** is the `--ff-only` fast-forward the ingest agent
    performs on these checkouts after pushing. It is not an edit — it advances a
    read-only checkout to what the remote already has, so that the session-start
    hook and `querying-notes`, both of which read from here, do not serve a wiki
    missing what was just filed. Do not "clean it up".
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
    home.file = {
      ".claude/CLAUDE.md".text =
        builtins.readFile ./workspace-layout/CLAUDE.md
        + lib.optionalString (cfg.extraInstructions != "") "\n${cfg.extraInstructions}"
        + lib.optionalString wikiUnderRepos wikiCarveOut;
    }
    # The mechanics the CLAUDE.md above deliberately does not carry. It states
    # the rules and names the skill at each gate; the commands, the decision
    # trees and the scripts live here, where they cost nothing until invoked.
    #
    # ~/.claude/skills only: opencode scans it natively, so a second copy under
    # opencode/skills would collide rather than help (see default.nix). None is
    # gated beyond that -- the read-side gate applies on every host with
    # ~/repos, which is exactly the hosts enabling this module.
    // lib.optionalAttrs (agents.claude.enable || agents.opencode.enable) {
      ".claude/skills/refreshing-a-repo".source = skills.refreshing-a-repo;
      ".claude/skills/starting-a-workspace".source = skills.starting-a-workspace;
      ".claude/skills/adding-a-repo-to-a-workspace".source = skills.adding-a-repo-to-a-workspace;
      ".claude/skills/tearing-down-a-workspace".source = skills.tearing-down-a-workspace;
    };
  };
}
