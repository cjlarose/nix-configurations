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
    the worktree rule holds here too: ${
      if aiMemoryWorktreeInWiki
      then "see the ai-memory exception below, and create no others."
      else "do not create worktrees in the wiki either."
    }
  '';

  # ai-memory parks its wiki on an orphan branch of a repo under ~/repos, which
  # the blanket "do not create worktrees here" rule would otherwise forbid. It
  # is a real exception rather than a loophole, so CLAUDE.md has to state it --
  # an agent that reads the rule and finds a worktree contradicting it learns
  # the rules are approximate, which is worse than the worktree.
  #
  # Derived from the same options that create the thing, like the wiki path
  # above: the carve-out cannot name a repo ai-memory is not actually using, and
  # it disappears on a host where ai-memory is off.
  aiMemory = config.cjlarose.llmAgents.aiMemory;

  aiMemoryWorktreeUnderRepos =
    aiMemory.enable
    && aiMemory.wikiWorktree.enable
    && aiMemory.wikiWorktree.repoPath != null
    && lib.hasPrefix "${config.home.homeDirectory}/repos/" aiMemory.wikiWorktree.repoPath;

  # Whether ai-memory's worktree is in the WIKI specifically, as opposed to some
  # other repo under ~/repos. Only then does the wiki carve-out's own "create no
  # worktrees here" sentence contradict the section below, and only then does it
  # have to defer. Two sections flatly disagreeing is worse than either rule on
  # its own: an agent that catches CLAUDE.md contradicting itself has learned to
  # weigh all of it more loosely.
  aiMemoryWorktreeInWiki =
    aiMemoryWorktreeUnderRepos
    && wikiUnderRepos
    && aiMemory.wikiWorktree.repoPath == wiki.path;

  # Stated as a property of the machine rather than an instruction, because
  # there is nothing here for an agent to do: systemd creates and maintains it.
  # The point is that finding it should not read as a violation to be tidied up
  # -- an agent that meets a worktree contradicting the rule it just read learns
  # the rules are approximate, which costs more than the worktree.
  #
  # A section of its own rather than a clause inside the wiki carve-out above:
  # the two are independent. ai-memory's repo need not be the wiki, and on a
  # host where the wiki is not under ~/repos this exception can still apply.
  aiMemoryCarveOut = ''

    ## ai-memory keeps a worktree under `~/repos`

    `${aiMemory.wikiWorktree.repoPath}` has a second worktree, checked out at
    `${aiMemory.dataDir}/wiki` on the `${aiMemory.wikiWorktree.branch}` branch.
    It is created and maintained by the `ai-memory-wiki-worktree` systemd user
    service, and it holds ai-memory's session memory rather than source.

    The branch is an **orphan**: its history is disjoint from `main`, so the two
    share an object store and nothing else.

    So `git worktree list` there shows an entry outside `~/workspaces`, and
    `git branch` shows a branch sharing no commits with `main`. Both are
    correct, and neither is yours to clean up. Do not remove the worktree,
    delete the branch, or merge it anywhere — `tearing-down-a-workspace` does
    not apply to it.

    This is the **only** exception. Create no other worktrees under `~/repos`.
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
        + lib.optionalString wikiUnderRepos wikiCarveOut
        + lib.optionalString aiMemoryWorktreeUnderRepos aiMemoryCarveOut;
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
