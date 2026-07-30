# Bridge between the llm-agents module's cjlarose.llmAgents.wiki.* options and
# programs.llmWiki, the option the LLM wiki flake's own home-manager module
# declares.
#
# This is deliberately a SEPARATE module from ./default.nix. programs.llmWiki
# only exists where cjlarose-llm-wiki.homeManagerModules.default is imported,
# and a definition of an undeclared option is an error even under a false mkIf
# (the module system distributes mkIf down to the attribute path before the
# declaration check). So default.nix declares the interface on every host, and
# this file — imported only alongside the wiki module itself — supplies the
# definition. See home/cjlarose for the pairing.
{ config, lib, ... }:

{
  programs.llmWiki = lib.mkIf config.cjlarose.llmAgents.wiki.enable {
    enable = true;
    path = config.cjlarose.llmAgents.wiki.path;
  };
}
