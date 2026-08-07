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

let
  wiki = config.cjlarose.llmAgents.wiki;
in
{
  # wiki.solePath, not wiki.path: a consumer may declare its wiki either the new
  # way (wiki.wikis.<id>) or the deprecated way (wiki.path), and solePath is the
  # normalization of both. Guarding on it being non-null also keeps the zero-
  # and multi-wiki cases from crashing here -- default.nix asserts on them and
  # says something useful, which a `head []` in this file would pre-empt.
  programs.llmWiki = lib.mkIf (wiki.enable && wiki.solePath != null) {
    enable = true;
    path = wiki.solePath;
  };
}
