# Bridge between cjlarose.llmAgents.superpowers.finalPackage and
# programs.claude-code.plugins.
#
# Separate from ./default.nix for the same reason ./wiki-bridge.nix is: the
# definition has to be absent, not merely disabled, on hosts where the option
# does not exist. home-manager 25-11's programs.claude-code module has no
# `plugins` option at all, and a definition of an undeclared option is an error
# even under a false mkIf -- the module system distributes mkIf down to the
# attribute path before the declaration check. So default.nix declares the
# interface everywhere, and this file -- imported only where home-manager is new
# enough -- supplies the definition. See home/cjlarose's enableSuperpowers.
{ config, lib, ... }:

{
  # finalPackage, not a package the consumer named: ./default.nix builds the
  # plugin from superpowers.src with the disableHooks / disableSpecCommits
  # options applied, and surfaces the result through that internal option
  # because a sibling module cannot reach its `let` bindings. It is null exactly
  # when superpowers is off, so this stays correct on a host that imports this
  # file but leaves the feature disabled.
  programs.claude-code.plugins =
    lib.optional (config.cjlarose.llmAgents.superpowers.finalPackage != null)
      config.cjlarose.llmAgents.superpowers.finalPackage;
}
