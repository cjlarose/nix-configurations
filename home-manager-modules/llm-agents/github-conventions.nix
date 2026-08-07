# PR-description and review-comment conventions, as agent skills.
#
# Split from ./git-conventions.nix: these are GitHub's artifacts and mean
# nothing on a host that never opens a pull request, where a commit message is
# git's and exists wherever git does.
#
# Two skills rather than one because the artifacts take deliberately different
# attribution rules, and collapsing them is the mistake they exist to prevent: a
# PR description and a comment posted on that same description are treated
# oppositely, and the instinct that a comment inherits its own PR's convention
# is exactly what goes wrong.
#
# The divergence between consumers is sharpest here: one requires a tracker link
# on the first line and bans model attribution outright, while the other has no
# tracker. On attribution the skills take a position rather than staying
# neutral -- disclosure is the DEFAULT, stated explicitly, because a skill that
# stayed silent would be read as permission to omit, and machine-written prose
# appearing under a human's name with nothing marking it is the failure worth
# defaulting against. A consumer that wants it gone says so in its own text.
{ lib, pkgs, config, ... }:

let
  cfg = config.cjlarose.llmAgents.githubConventions;
  agents = config.cjlarose.llmAgents;

  # Appended rather than substituted, so the consumer's rules read as additions
  # to the shared ones and the shared text stays greppable. The extra block goes
  # after the body, never into the frontmatter, which must stay first.
  #
  # Duplicated from git-conventions.nix rather than shared: it is a dozen lines,
  # and the two modules are meant to be readable and enableable alone.
  mkSkill = name: extra:
    let src = ./github-conventions + "/${name}"; in
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
  options.cjlarose.llmAgents.githubConventions = {
    enable = lib.mkEnableOption ''
      the writing-pull-request-descriptions and
      writing-pull-request-comments skills -- one per artifact, because the two
      take opposite attribution rules and collapsing them is the mistake they
      exist to prevent. Off by default: home-manager-modules/ is shared, and a
      host that does not want these particular house rules should not carry them
    '';

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

        This is the option that matters most of the two: the shared skill takes
        no position on tracker links, prose mood or headings, because the two
        consumers of this module want different things. It DOES take a position
        on model attribution -- disclosure is the documented default -- so a
        consumer that bans it has to say so here. Silence leaves it in place,
        deliberately.
      '';
    };

    commentExtraInstructions = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Markdown appended to the writing-pull-request-comments skill.

        Least likely of the two to be needed: the comment convention (a visible
        Generated-By signature, no email) is documented in one place and neither
        consumer contradicts it. The option exists for symmetry, and so that a
        house wanting a different signature form does not need a release of this
        repo to get one.
      '';
    };
  };

  # ~/.claude/skills only: opencode scans it natively, so a second copy under
  # opencode/skills would collide rather than help (see default.nix).
  config = lib.mkIf cfg.enable {
    home.file = lib.mkIf (agents.claude.enable || agents.opencode.enable) {
      ".claude/skills/writing-pull-request-descriptions".source =
        mkSkill "writing-pull-request-descriptions" cfg.pullRequestExtraInstructions;
      ".claude/skills/writing-pull-request-comments".source =
        mkSkill "writing-pull-request-comments" cfg.commentExtraInstructions;
    };
  };
}
