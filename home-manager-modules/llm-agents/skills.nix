# User-level agent skills, installed once and shared between agents.
#
# One attrset option (cjlarose.llmAgents.skills) collects every skill the user
# should have, builds them into a single directory in the store, and points both
# ~/.agents/skills and ~/.claude/skills at that one path.
#
# Why a directory symlink rather than home-manager's own
# programs.claude-code.skills: that option materializes one home.file entry per
# skill under ~/.claude/skills/, which makes ~/.claude/skills a real directory
# and forecloses ever symlinking it. ~/.agents/skills would then have to be a
# second, independently-materialized copy of the same content -- two trees that
# agree only as long as nobody edits one of them. Building the tree ourselves
# means the two paths are the same store path by construction, not by
# convention.
#
# Why ~/.agents/skills at all: Claude Code does not read it. Its user-level
# skill discovery is ~/.claude/skills and nothing else (verified against the
# 2.1.104 bundle -- there is no .agents path in it). ~/.agents/skills is the
# cross-agent location, for the other agents on these hosts; the Claude symlink
# is what makes one authored skill serve both.
#
# Consequence, and the reason this module has to be the only way skills are
# installed: nothing else may define a file *underneath* ~/.claude/skills. A
# nested home.file entry and a directory symlink cannot coexist -- the home-files
# derivation would have to mkdir inside a read-only store symlink -- so the
# per-tool skills in default.nix all come through here.
#
# Not covered: skills delivered as Claude Code *plugins* (the wiki plugin,
# superpowers). Those are a separate mechanism with their own namespacing, they
# never touch ~/.claude/skills, and they are therefore invisible to the other
# agents. That is a real limit of this, not an oversight.
{ lib, pkgs, config, ... }:

let
  cfg = config.cjlarose.llmAgents;

  # Each value is a path to either a skill directory (containing SKILL.md and
  # whatever else it references) or a bare SKILL.md file.
  #
  # Which one it is gets decided in bash, at build time, rather than with
  # lib.pathIsDirectory at eval time: most of these values are strings pointing
  # into a package's output (`${cfg.lavish.package}/share/...`), and inspecting
  # such a path during evaluation forces the package to be realised mid-eval --
  # import-from-derivation, on every home-manager eval, for every host.
  skillsTree = pkgs.runCommand "agent-skills" { } ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: src: ''
      if [ -d "${src}" ]; then
        cp -r "${src}" "$out/${name}"
        chmod -R u+w "$out/${name}"
      else
        install -D -m 0444 "${src}" "$out/${name}/SKILL.md"
      fi

      # A skill directory whose entry point is missing or misnamed is not
      # ignored by the agent so much as silently absent: it never matches, and
      # the failure looks exactly like a model that just didn't reach for it.
      # Fail the build instead.
      [ -f "$out/${name}/SKILL.md" ] || {
        echo "skill '${name}': no SKILL.md in ${src}" >&2
        exit 1
      }
    '') cfg.skills)}
  '';

in
{
  options.cjlarose.llmAgents.skills = lib.mkOption {
    type = lib.types.attrsOf lib.types.path;
    default = { };
    example = lib.literalExpression ''
      {
        starting-a-workspace = ./skills/starting-a-workspace;
        gh-stack = "''${pkgs.gh-stack}/share/gh-stack/skill/SKILL.md";
      }
    '';
    description = ''
      User-level agent skills, keyed by skill name. Each value is either a
      directory containing SKILL.md, or a bare SKILL.md file that gets installed
      as <name>/SKILL.md.

      Both forms take the skill name from the attribute name rather than from
      the path, so a package whose skill lives at share/<tool>/skill/SKILL.md
      needs no particular directory naming upstream -- and there is no way to
      repeat the /SKILL.md suffix in the key and end up with a skill nested one
      level too deep to be discovered.

      Set this rather than programs.claude-code.skills: the two cannot both be
      used, since this module owns ~/.claude/skills as a whole (see the header
      comment). For a skill authored inline, pass pkgs.writeText "SKILL.md"
      "..." -- the value is a path, not markdown.
    '';
  };

  # Left empty, this writes nothing at all: an empty ~/.agents/skills directory
  # and a hijacked ~/.claude/skills are both worse than absence on a host that
  # installs no skills.
  config = lib.mkIf (cfg.skills != { }) {
    # Without this, adding a skill through home-manager's own option fails at
    # home-files build time with a message about being unable to create a
    # directory -- true, but no help at all in finding the line that caused it.
    # The two mechanisms are mutually exclusive by construction, so say so.
    assertions = [{
      assertion = config.programs.claude-code.skills == { };
      message = ''
        programs.claude-code.skills is set alongside cjlarose.llmAgents.skills
        (${lib.concatStringsSep ", " (lib.attrNames config.programs.claude-code.skills)}).

        They cannot coexist: this module installs ~/.claude/skills as a single
        symlink into the store, and home-manager's option needs to create files
        underneath that path. Move those skills to cjlarose.llmAgents.skills,
        which installs them for the other agents as well.
      '';
    }];

    home.file = {
      # The cross-agent location, and the one real copy.
      ".agents/skills".source = skillsTree;

      # The same store path, not a copy of it and not a symlink to the path
      # above: chaining through ~/.agents would make Claude's skills depend on
      # a second home-manager-managed symlink that has no reason to outlive its
      # own consumers.
      #
      # Consequence, the same trade this module already makes for settings.json
      # and CLAUDE.md: ~/.claude/skills is a read-only store symlink, so
      # Claude's own skill-authoring flow cannot write into it. Skills come from
      # here, or they do not exist.
      ".claude/skills".source = skillsTree;
    };
  };
}
