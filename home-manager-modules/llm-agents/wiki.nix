# LLM wiki delivery: the maintenance skills, the session-start context hook,
# and LLM_WIKI_PATH.
#
# This replaces what each wiki repo's own home-manager module used to do. Those
# modules had to go for two reasons, and both are structural rather than
# stylistic:
#
#  - They are all-or-nothing. The personal wiki ships a Claude Code PLUGIN whose
#    build copies its whole skills/ tree; the work wiki populates
#    programs.claude-code.skills from its whole skills/ directory. Neither can
#    hand over some skills and withhold others, so taking over the maintenance
#    skills meant not importing them at all.
#  - Both declare programs.llmWiki with the same enable/path pair, so importing
#    two of them into one home config is a duplicate-declaration error. That is
#    the hard ceiling on running a personal and a work wiki side by side.
#
# Skills land in ~/.claude/skills, flat. That is the one location BOTH harnesses
# read -- opencode scans it natively -- whereas a plugin is Claude-only, which is
# why the personal wiki's plugin-delivered skills never reached opencode. The
# names are the gerund forms the wiki repo already used, matching the convention
# every other skill in this module follows (starting-a-workspace,
# refreshing-a-repo, writing-commit-messages) and, per superpowers'
# writing-skills, the flat namespace is the intended shape rather than something
# to work around.
{ lib, pkgs, config, ... }:

let
  cfg = config.cjlarose.llmAgents;

  skillNames = [
    "capturing-sessions"
    "handing-off"
    "ingesting-sources"
    "querying-notes"
  ];

  # Every tool the script reaches for is resolved at build time rather than
  # trusted to be on PATH. A SessionStart hook runs with whatever environment
  # the harness hands it, which is not guaranteed to be a login shell's.
  #
  # patchShebangs matters as much as the PATH wrapping: the script's
  # `#!/usr/bin/env bash` needs bash ON PATH to start at all, so with a bare
  # environment it fails before the wrapper's PATH ever applies. Rewriting the
  # shebang to an absolute store bash removes that bootstrap dependency --
  # verified by running the result under `env -i`.
  injector = pkgs.runCommand "inject-wiki-context" {
    nativeBuildInputs = [ pkgs.makeWrapper ];
  } ''
    mkdir -p "$out/bin"
    cp ${./wiki/inject-wiki-context.sh} "$out/bin/inject-wiki-context"
    chmod +x "$out/bin/inject-wiki-context"
    patchShebangs "$out/bin/inject-wiki-context"
    wrapProgram "$out/bin/inject-wiki-context" \
      --prefix PATH : ${lib.makeBinPath [ pkgs.jq pkgs.coreutils pkgs.findutils pkgs.gawk ]}
  '';

  registryPath = "${config.xdg.configHome}/llm-wiki/wikis.json";

  # LLM_WIKI_PATH survives only for the single-wiki case, and only because the
  # skills still read it. It cannot express two wikis -- that is what the
  # registry is for -- so with several declared it is left unset rather than
  # silently naming one of them and inviting writes to the wrong wiki.
  soleWikiPath = cfg.wiki.solePath;
in
{
  config = lib.mkIf cfg.wiki.enable (lib.mkMerge [
    {
      # Flat, under ~/.claude/skills, so both harnesses see them. `source` on a
      # directory rather than the SKILL.md alone, so a skill that later grows
      # scripts/ or references/ needs no change here.
      home.file = lib.mkIf (cfg.claude.enable || cfg.opencode.enable) (
        builtins.listToAttrs (map (name: {
          name = ".claude/skills/${name}";
          value.source = ./wiki/skills + "/${name}";
        }) skillNames)
      );
    }

    (lib.mkIf (soleWikiPath != null) {
      home.sessionVariables.LLM_WIKI_PATH = soleWikiPath;
    })

    # The context hook. Registered through programs.claude-code.settings rather
    # than bundled into a plugin: a plugin would be invisible to opencode, and
    # the injector is useful to run by hand besides.
    (lib.mkIf cfg.claude.enable {
      programs.claude-code.settings.hooks.SessionStart = [
        {
          matcher = "startup|resume|clear|compact";
          hooks = [
            {
              type = "command";
              command = "${injector}/bin/inject-wiki-context ${lib.escapeShellArg registryPath}";
            }
          ];
        }
      ];
    })
  ]);
}
