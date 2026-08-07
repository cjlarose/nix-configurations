# Skills that used to ship from the personal LLM wiki repo's own skills/ tree.
#
# They moved here because the wiki flake's home-manager module is
# all-or-nothing: its plugin copies the whole skills/ directory, so there is no
# way to take some of its skills and not others. The wiki MAINTENANCE skills
# (capturing-sessions, ingesting-sources, querying-notes, handing-off) are being
# taken over by the llm-agents module, and suppressing the wiki's copies of
# those means not importing that module at all -- which would have taken these
# six down with it.
#
# Why home/cjlarose and not home-manager-modules/llm-agents: that module is a
# published subflake picktrace consumes, and none of this is theirs. bumping-cc
# and rebuilding-nixos are about this fleet's own hosts, and hermes-* pair with
# the hermes-agent input of this flake alone.
#
# Gated on a wiki being declared, which reproduces the previous deployment set
# exactly -- these only ever installed where the wiki plugin did, i.e. on
# ns1010301. Four of them genuinely need that: bumping-cc, rebuilding-nixos,
# transcoding-media and launching-remote-sessions are thin shims that defer to
# wiki pages for the real procedure, so on a host with no wiki they would name
# pages nothing can read.
#
# hermes-ask and hermes-soul do NOT reference the wiki at all. They are gated
# here only because that is where they were, and this move is meant to be a
# relocation rather than a change in what is installed where. Ungating them is
# a separate decision, and a separate commit.
{ llm-wikis }:
{ lib, ... }:
let
  skills = [
    "bumping-cc"
    "hermes-ask"
    "hermes-soul"
    "launching-remote-sessions"
    "rebuilding-nixos"
    "transcoding-media"
  ];
in
{
  # Flat names under ~/.claude/skills, matching where the wiki plugin put them
  # and, more importantly, the one directory both harnesses read -- opencode
  # scans ~/.claude/skills natively, so a nested or plugin-scoped layout would
  # quietly make these Claude-only.
  programs.claude-code.skills = lib.mkIf (llm-wikis != { }) (
    builtins.listToAttrs (map (name: {
      inherit name;
      value = ./claude-skills + "/${name}/SKILL.md";
    }) skills)
  );
}
