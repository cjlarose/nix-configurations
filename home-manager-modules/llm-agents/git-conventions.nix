# Commit-message conventions, as an agent skill.
#
# Split from ./github-conventions.nix because the two are independent: a commit
# message is a git artifact and exists wherever git does, while PR descriptions
# and review comments are GitHub's and mean nothing on a host that never opens
# one. A consumer can want either without the other.
#
# The skill carries only what both consumers of this module agree on -- Beams'
# seven rules, no prefixes of any kind, the model disclosure trailer, no
# plan-document references. What the two houses do DIFFERENTLY arrives as text
# through commitExtraInstructions, for the same reason
# workspaceLayout.extraInstructions exists: a boolean here would have this
# module carrying prose about someone else's issue tracker, and every new
# convention would need an option plus a release of this repo before the
# consumer that owns the convention could adopt it.
{ lib, pkgs, config, ... }:

let
  cfg = config.cjlarose.llmAgents.gitConventions;
  agents = config.cjlarose.llmAgents;

  # Appended rather than substituted, so the consumer's rules read as additions
  # to the shared ones and the shared text stays greppable. The extra block goes
  # after the body, never into the frontmatter, which must stay first.
  #
  # Duplicated in github-conventions.nix rather than shared: it is a dozen
  # lines, and the two modules are meant to be readable and enableable alone.
  mkSkill = name: extra:
    let src = ./git-conventions + "/${name}"; in
    if extra == "" then src
    else pkgs.runCommand "skill-${name}" { inherit extra; } ''
      cp -r ${src} $out
      chmod -R u+w $out
      {
        printf '\n## Rules for this repo\n\n'
        printf 'These come from the configuration that installed this skill.\n'
        printf 'Where they conflict with anything above, they win.\n\n'
        printf '%s\n' "$extra"
      } >> $out/SKILL.md
    '';
in
{
  options.cjlarose.llmAgents.gitConventions = {
    enable = lib.mkEnableOption ''
      the writing-commit-messages skill: Beams' seven rules, no prefixes of any
      kind, the model disclosure trailer, and the check-before-you-write gate
      that exists because agents take their cue from recent history on the
      branch. Off by default: home-manager-modules/ is shared, and a host that
      does not want these particular house rules should not carry them
    '';

    commitExtraInstructions = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = lib.literalExpression ''
        '''
          - **Issue keys are banned everywhere in a commit message** -- subject
            and body both.
        '''
      '';
      description = ''
        Markdown appended to the writing-commit-messages skill, for rules that
        are real on one consumer and meaningless on another.

        Text rather than flags, deliberately. See the header comment, and
        cjlarose.llmAgents.claude.workspaceLayout.extraInstructions, which
        exists for the same reason.
      '';
    };
  };

  # ~/.claude/skills only: opencode scans it natively, so a second copy under
  # opencode/skills would collide rather than help (see default.nix).
  config = lib.mkIf cfg.enable {
    home.file = lib.mkIf (agents.claude.enable || agents.opencode.enable) {
      ".claude/skills/writing-commit-messages".source =
        mkSkill "writing-commit-messages" cfg.commitExtraInstructions;
    };
  };
}
