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
# attribution outright, while the other has no tracker.
#
# On attribution the skills take a position rather than staying neutral:
# disclosure is the DEFAULT, stated explicitly, in all three artifacts. A skill
# that merely stayed silent and deferred would be read as permission to omit,
# and the failure mode -- machine-written prose appearing under a human's name
# with nothing marking it -- is the one worth defaulting against. A consumer
# that wants it gone says so in its own text, which is what picktrace does for
# PR descriptions and only for PR descriptions: it requires the trailer on
# commits and a Generated-By signature on comments.
{ lib, pkgs, config, ... }:

let
  cfg = config.cjlarose.llmAgents.gitConventions;
  agents = config.cjlarose.llmAgents;

  # Built once and referenced by both harness blocks below: mkSkill may run a
  # derivation, and calling it twice per skill would build the same thing twice
  # under two names.
  skills = {
    writing-commit-messages =
      mkSkill "writing-commit-messages" cfg.commitExtraInstructions;
    writing-pull-request-descriptions =
      mkSkill "writing-pull-request-descriptions" cfg.pullRequestExtraInstructions;
    writing-pull-request-comments =
      mkSkill "writing-pull-request-comments" cfg.commentExtraInstructions;
  };

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
      the writing-commit-messages, writing-pull-request-descriptions and
      writing-pull-request-comments skills -- one per artifact, because the
      three take deliberately different attribution rules and collapsing them is
      the mistake they exist to prevent. Off by default: home-manager-modules/
      is shared, and a host that does not want these particular house rules
      should not carry them
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

        This is the option that matters most of the three: the shared skill
        takes no position on tracker links, prose mood or headings, because the
        two consumers of this module want different things. It DOES take a
        position on model attribution -- the disclosure footer is the documented
        default -- so a consumer that bans it has to say so here. Silence leaves
        the footer in place, deliberately.
      '';
    };

    commentExtraInstructions = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Markdown appended to the writing-pull-request-comments skill.

        Least likely of the three to be needed: the comment convention (a
        visible Generated-By signature, no email) is documented in one place and
        neither consumer contradicts it. The option exists for symmetry, and so
        that a house wanting a different signature form does not need a release
        of this repo to get one.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # ~/.claude/skills only: opencode scans it natively, so a second copy under
    # opencode/skills would collide rather than help (see default.nix).
    home.file = lib.mkIf (agents.claude.enable || agents.opencode.enable) {
      ".claude/skills/writing-commit-messages".source =
        skills.writing-commit-messages;
      ".claude/skills/writing-pull-request-descriptions".source =
        skills.writing-pull-request-descriptions;
      ".claude/skills/writing-pull-request-comments".source =
        skills.writing-pull-request-comments;
    };

  };
}
