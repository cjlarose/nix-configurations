# Agent skills for the Basic Memory knowledge base.
#
# Separate from the basicMemory.* options in ./default.nix, which wire the MCP
# server: a host can have the server without these skills (the stock
# memory-notes / memory-capture / memory-continue set is enough for most), and
# the skills are worth nothing without the server. Same split as
# git-conventions.nix versus the claude options it rides alongside.
#
# Only handing-off lives here. Basic Memory's own skills cover capture, note
# format, resumption and task tracking; what upstream has no equivalent for is
# the END of a session -- deciding what was durable knowledge versus in-flight
# state, and landing each in the right kind of note. None of its skills
# orchestrates another, so that shape has to come from somewhere.
{ lib, pkgs, config, ... }:

let
  cfg = config.cjlarose.llmAgents.basicMemory;
  agents = config.cjlarose.llmAgents;

  # Appended rather than substituted, so a consumer's rules read as additions
  # and the shared text stays greppable. Same shape as
  # gitConventions.commitExtraInstructions, and for the same reason: a boolean
  # would put someone else's conventions in this repo.
  handingOff =
    if cfg.handoffExtraInstructions == "" then
      ./basic-memory/handing-off
    else
      pkgs.runCommand "skill-handing-off" { extra = cfg.handoffExtraInstructions; } ''
        cp -r ${./basic-memory/handing-off} $out
        chmod -R u+w $out
        {
          printf '\n## Rules for this knowledge base\n\n'
          printf 'These come from the configuration that installed this skill.\n'
          printf 'Where they conflict with anything above, they win.\n\n'
          printf '%s\n' "$extra"
        } >> $out/SKILL.md
      '';
in
{
  options.cjlarose.llmAgents.basicMemory = {
    handoffSkill.enable = lib.mkEnableOption ''
      the handing-off skill: promote a long session's durable knowledge and its
      in-flight work into Basic Memory, one task note per thread, so the next
      session resumes from the knowledge graph instead of a summary that dies
      with the conversation.

      Replaces the wiki's `wiki:handing-off`, which orchestrated a
      capture->ingest cycle. Basic Memory covers the pieces -- memory-capture,
      memory-tasks, memory-continue -- but no skill of its own chains them, and
      the durable-versus-in-flight split is the judgement worth writing down
    '';

    handoffExtraInstructions = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = lib.literalExpression ''
        '''
          - Task notes for work tracked in Jira carry the issue key in `tags`.
        '''
      '';
      description = ''
        Markdown appended to the handing-off skill, for rules real on one
        knowledge base and meaningless on another.

        Text rather than flags, deliberately -- see the header comment and
        cjlarose.llmAgents.gitConventions.commitExtraInstructions.
      '';
    };
  };

  # ~/.claude/skills only: opencode scans it natively, so a second copy under
  # opencode/skills would collide rather than help (see default.nix).
  config = lib.mkIf cfg.handoffSkill.enable {
    assertions = [
      {
        assertion = cfg.enable;
        message =
          "cjlarose.llmAgents.basicMemory.handoffSkill.enable is true but basicMemory.enable is not: "
          + "the skill drives MCP tools that are not registered without it.";
      }
    ];

    home.file = lib.mkIf (agents.claude.enable || agents.opencode.enable) {
      ".claude/skills/handing-off".source = handingOff;
    };
  };
}
