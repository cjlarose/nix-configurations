# Commit-message and PR-description conventions, as agent skills.
#
# Split from the workspace-layout module next door because the two are
# independent: a host may want the git conventions without the ~/repos layout or
# the other way round.
#
# The skills carry only what both consumers of this module actually agree on --
# Beams' seven rules, no prefixes of any kind, the model co-author trailer, the
# accuracy pass over PR prose. Everything the two houses do DIFFERENTLY arrives
# as text through the *ExtraInstructions options below, for the same reason
# workspaceLayout.extraInstructions exists: a boolean here would have this
# module carrying prose about someone else's issue tracker, and every new
# convention would need an option plus a release of this repo before the
# consumer that owns the convention could adopt it.
#
# The divergence is not hypothetical, and it is sharpest on PR descriptions:
# one consumer requires a tracker link on the first line and bans model
# attribution outright, while the other has no tracker and follows the harness
# default of a generated-with footer. A skill asserting either rule would be
# actively wrong on one of the two hosts, so it asserts neither -- it says the
# per-repo rules appended below are the authority.
{ lib, pkgs, config, ... }:

let
  cfg = config.cjlarose.llmAgents.gitConventions;

  # Appended rather than substituted, so the consumer's rules read as additions
  # to the shared ones and the shared text stays greppable. The extra block goes
  # after the body, never into the frontmatter, which must stay first.
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
      the writing-commit-messages and writing-pull-request-descriptions skills.
      Off by default: home-manager-modules/ is shared, and a host that does not
      want these particular house rules should not carry them
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

    pullRequestExtraInstructions = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = lib.literalExpression ''
        '''
          - The **first line** is the issue number, linked to the tracker.
          - **No model attribution of any kind** -- no trailer, no footer.
        '''
      '';
      description = ''
        Markdown appended to the writing-pull-request-descriptions skill.

        This is the option that matters most of the two: the shared skill
        deliberately takes no position on tracker links, prose mood, headings or
        model attribution, because the two consumers of this module require
        opposite things on the last of those. Whichever rules apply on this host
        have to be stated here, or the skill leaves the agent to the harness
        default.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    cjlarose.llmAgents.skills = {
      writing-commit-messages =
        mkSkill "writing-commit-messages" cfg.commitExtraInstructions;
      writing-pull-request-descriptions =
        mkSkill "writing-pull-request-descriptions" cfg.pullRequestExtraInstructions;
    };
  };
}
