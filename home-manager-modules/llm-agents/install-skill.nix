# Where a skill has to land so the enabled harnesses find it.
#
# This fleet runs opencode with Claude Code compatibility DISABLED: the package
# is wrapped by harness-config lib.wrapOpencode in the consumer (see
# home/cjlarose), which sets OPENCODE_DISABLE_CLAUDE_CODE, so opencode no longer
# reads anything under ~/.claude. Skills therefore reach each harness through its
# OWN native channel rather than the single shared ~/.claude/skills this module
# used to rely on:
#
#   claude    ~/.claude/skills/<name>                  via home.file
#   opencode  stock programs.opencode.skills.<name>    -> ~/.config/opencode/skills/<name>/
#
# A skill wanted by both is delivered through both, and there is NO duplicate-name
# collision -- the thing the old "~/.claude/skills only" rule guarded against --
# because with compat off opencode never sees the ~/.claude copy. superpowers is
# separate again: it reaches opencode through programs.opencode.settings.skills.paths
# in the consumer, another native path unaffected by compat.
#
# Gating is on the STOCK options (config.programs.{claude-code,opencode}.enable),
# the same way claude's own skills are gated now that this module no longer owns
# either agent.
#
# Arguments:
#   name  the skill directory name, used verbatim on both harnesses' native
#         channels.
#   src   a skill directory or a single SKILL.md file; the stock skills option
#         accepts either and writes skills/<name>/ or skills/<name>/SKILL.md.
#
# The claude-side subpath is derived from src, not passed in: claude nests a
# single-file SKILL.md source under the skill directory itself (so the path needs
# the /SKILL.md suffix), whereas a directory source lands whole at <name>. The
# stock opencode option does that nesting either way, so it only ever needs <name>.
{ lib, config }:
name: src:
let
  claudePath =
    if baseNameOf (toString src) == "SKILL.md" then "${name}/SKILL.md" else name;
in
{
  home.file = lib.optionalAttrs config.programs.claude-code.enable {
    ".claude/skills/${claudePath}".source = src;
  };
  programs.opencode.skills = lib.optionalAttrs config.programs.opencode.enable {
    ${name} = src;
  };
}
