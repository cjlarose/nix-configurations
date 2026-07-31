# obra/superpowers as a force-loadable Claude Code plugin.
#
# Upstream already ships the plugin layout (.claude-plugin/plugin.json, skills/,
# hooks/), so this is a copy with one substitution rather than a build.
#
# That substitution is the whole point. hooks/hooks.json invokes its own hook
# runner via "${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd", and CLAUDE_PLUGIN_ROOT
# is NOT set for SessionStart events -- the hook fails silently, which is exactly
# the failure mode that is hardest to notice, since a missing session preamble
# looks like a model that just didn't reach for a skill. Baking the real store
# path via builtins.placeholder "out" is the same fix the llm-wiki plugin uses.
#
# The hook script itself needs no patching: it derives the plugin root from its
# own $0, so once hooks.json points at the right run-hook.cmd everything below
# resolves relative to it.
{ pkgs, src, version }:

let
  # The literal text "${CLAUDE_PLUGIN_ROOT}" to search for. Built in a normal
  # double-quoted string where \${ is an unambiguous escape; writing it inline
  # in the '' block below collides with Nix's own '' and ''${ escapes.
  pluginRootVar = "\${CLAUDE_PLUGIN_ROOT}";
in
pkgs.runCommand "superpowers-plugin-${version}"
  {
    inherit src;
    meta = {
      description = "obra/superpowers skills library, packaged as a Claude Code plugin";
      homepage = "https://github.com/obra/superpowers";
      license = pkgs.lib.licenses.mit;
    };
  }
  ''
    cp -r "$src" "$out"
    chmod -R u+w "$out"

    # Fail loudly if upstream stops using the variable -- silently shipping an
    # unsubstituted hooks.json would reintroduce the bug this package exists for.
    grep -q 'CLAUDE_PLUGIN_ROOT' "$out/hooks/hooks.json" \
      || { echo "hooks.json no longer references CLAUDE_PLUGIN_ROOT; re-check this package" >&2; exit 1; }

    substituteInPlace "$out/hooks/hooks.json" \
      --replace '${pluginRootVar}' '${builtins.placeholder "out"}'

    # `if`, not `grep && exit` -- a correct run leaves no match, so grep exits 1
    # and the && form would fail the build precisely when it succeeded.
    if grep -q 'CLAUDE_PLUGIN_ROOT' "$out/hooks/hooks.json"; then
      echo "substitution left a CLAUDE_PLUGIN_ROOT reference behind" >&2
      exit 1
    fi

    # The hook runner and its scripts must stay executable through the copy.
    chmod +x "$out/hooks/run-hook.cmd" "$out/hooks/session-start"
  ''
