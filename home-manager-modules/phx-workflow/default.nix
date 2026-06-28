{ lib, config, ... }:

let
  cfg = config.cjlarose.claude.phxWorkflow;
in
{
  options.cjlarose.claude.phxWorkflow.enable =
    lib.mkEnableOption ''
      the language-agnostic phx workflow skills (/phx-brainstorm, /phx-plan,
      /phx-work, /phx-review, /phx-full). These are de-Elixir'd ports of the
      core workflow spine from oliver-kriska/claude-elixir-phoenix: same
      .claude/plans/{slug}/ artifact contract and decision-gate discipline,
      but with build/test/lint discovery left to the model (prose, not
      hardcoded mix commands) and research fan-out using the built-in
      general-purpose/Explore subagents instead of named Elixir agents.
      Requires the claude module (programs.claude-code) to also be imported
    '';

  config = lib.mkIf cfg.enable {
    # Deployed via the upstream programs.claude-code.skills option (key = bare
    # skill directory name, value = its SKILL.md; never append /SKILL — that
    # double-nests post home-manager #8770). skills is attrsOf, so these keys
    # merge with any set in the claude module. Output:
    # ~/.claude/skills/phx-<name>/SKILL.md.
    programs.claude-code.skills = {
      "phx-brainstorm" = ./skills/brainstorm/SKILL.md;
      "phx-plan" = ./skills/plan/SKILL.md;
      "phx-work" = ./skills/work/SKILL.md;
      "phx-review" = ./skills/review/SKILL.md;
      "phx-full" = ./skills/full/SKILL.md;
    };
  };
}
