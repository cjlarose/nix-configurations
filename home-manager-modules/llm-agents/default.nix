# Unified LLM-agent tooling module.
#
# One module owning the agent-adjacent tooling for a user: lavish-axi, the
# personal LLM wiki integration, the standalone agent CLIs (opencode, herdr,
# git-surgeon), tuicr, and the gh-stack agent skill. Options ending in `Skill`
# install documentation only -- the tool they describe is installed elsewhere;
# an option without the suffix that happens to ship a skill (lavish, gitSurgeon)
# installs the tool too. herdr is the third case: the tool is here but upstream
# keeps its skill out of the package, so the module lifts it out of upstream's
# source tree (herdr.skillSrc). tuicr is the fourth: no skill at all, and the
# only option here that carries configuration rather than just a package.
#
# Claude Code itself is NOT owned here any more. The consumer configures stock
# programs.claude-code directly and applies harness-config's lib.wrapClaudeCode /
# lib.mkSuperpowersPlugin (see home/cjlarose). This module still installs skills
# into ~/.claude/skills and wires the herdr SessionStart hook onto
# programs.claude-code.settings, gated on config.programs.claude-code.enable
# (the stock option) rather than a claude.enable of its own.
#
# Every skill an option here installs lands in ~/.claude/skills and nowhere
# else, because that one location reaches BOTH harnesses: opencode scans
# ~/.claude/skills (and ~/.agents/skills) natively, alongside anything named in
# its own skills.paths. Installing a second copy under opencode/skills is not
# belt-and-braces, it is a collision -- opencode logs `duplicate skill name` and
# silently picks one by scan order.
#
# The reach of each location, which is what any change here has to respect:
#
#   ~/.claude/skills          claude + opencode
#   ~/.agents/skills          opencode only
#   opencode skills.paths     opencode only
#   a Claude Code plugin      claude only
#
# So an opencode-only skill goes through skills.paths, and a CLAUDE-only skill
# is not expressible except as a plugin: opencode's scan of ~/.claude is
# unconditional and has no exclude setting.
#
# The module takes no flake-specific arguments: every package it installs comes
# in through a `*.package` option that the consumer sets explicitly. It used to
# reach into an `additionalPackages` module arg for defaults, which coupled it to
# one particular shape of consuming flake and silently broke if that flake
# renamed or dropped an attr.
#
# The personal LLM wiki integration is owned entirely here: the read-only
# querying-notes skill (installed into ~/.claude/skills like every other skill,
# so it reaches both claude and opencode) and LLM_WIKI_PATH. The consumer hands
# in the wiki's skills/ tree via wiki.skillSrc and the checkout path via
# wiki.path. This module used to instead consume the llm-wiki flake's own
# home-manager module, which shipped the skill as a claude-only Claude Code
# plugin -- so opencode never saw it; delivering the skill through
# ~/.claude/skills is what fixed that.
{ lib, pkgs, config, ... }:

let
  cfg = config.cjlarose.llmAgents;

  # Whether to install skills at all. ~/.claude/skills is written whenever
  # EITHER harness is enabled, not just claude: it is the location both of them
  # read, so on a host running opencode alone it is still where opencode looks.
  # Writing under ~/.claude with claude off reads oddly for a moment, and is
  # cheaper than a second copy that opencode would only warn about.
  skillsWanted = config.programs.claude-code.enable || cfg.opencode.enable;

  # Renders cjlarose.llmAgents.tuicr.settings to tuicr's config.toml. A freeform
  # format rather than a typed option per key: tuicr's config surface is its
  # own, and every key it grows would otherwise need a change here before a
  # consumer could set it.
  tomlFormat = pkgs.formats.toml { };

  # herdr's agent integrations -- the hook/plugin that report pane agent state
  # (working/blocked/idle) back to the herdr server, so panes show live status.
  #
  # Upstream installs these imperatively with `herdr integration install <target>`,
  # which cannot work here: the claude half wants to merge its hook registration
  # into ~/.claude/settings.json, and that is a symlink into the read-only store
  # (programs.claude-code.settings, below). The install fails with EROFS and
  # writes nothing.
  #
  # So we run the same installer inside a build sandbox and take the files it
  # produces. Both payloads are fully static -- no paths, ids, or versions baked
  # in; everything dynamic arrives at runtime via HERDR_ENV / HERDR_SOCKET_PATH /
  # HERDR_PANE_ID -- so extracting rather than vendoring a copy means they track
  # cfg.herdr.package automatically and never drift from the installed binary.
  #
  # Lazy: only forced from the herdr branch of config, which already guards
  # package != null.
  herdrIntegrations = pkgs.runCommand "herdr-integrations" { } ''
    export HOME=$PWD/home
    export XDG_CONFIG_HOME=$HOME/.config
    # The installer refuses a target whose config dir does not already exist.
    mkdir -p $HOME/.claude $HOME/.config/opencode
    ${cfg.herdr.package}/bin/herdr integration install claude   >/dev/null
    ${cfg.herdr.package}/bin/herdr integration install opencode >/dev/null

    mkdir -p $out

    # The one thing we cannot extract is the settings.json hook registration --
    # reading it back would mean readFile on a derivation output, i.e. IFD in
    # every home-manager eval. It is hand-written below instead, so pin the
    # payload version it was written against: a herdr bump that changes the
    # contract fails the build here rather than silently half-wiring the hook.
    grep -q '^# HERDR_INTEGRATION_VERSION=7$' $HOME/.claude/hooks/herdr-agent-state.sh || {
      echo "herdr claude integration version changed; re-check the SessionStart" >&2
      echo "registration in programs.claude-code.settings.hooks against:" >&2
      cat $HOME/.claude/settings.json >&2
      exit 1
    }
    grep -q '^// HERDR_INTEGRATION_VERSION=9$' $HOME/.config/opencode/plugins/herdr-agent-state.js || {
      echo "herdr opencode integration version changed; re-check the plugin wiring" >&2
      exit 1
    }

    # The hook shells out to python3 and exits 0 -- silently, reporting itself
    # as installed and current -- when it is not on PATH. It is not on PATH in
    # this login environment, so pin it to the store. Free in practice: python3
    # is already in the home closure on every host in this profile, so the whole
    # extraction adds ~11 KiB.
    substitute $HOME/.claude/hooks/herdr-agent-state.sh $out/claude-hook.sh \
      --replace-fail 'command -v python3' 'command -v ${pkgs.python3}/bin/python3' \
      --replace-fail ' python3 - <<' ' ${pkgs.python3}/bin/python3 - <<'
    chmod +x $out/claude-hook.sh

    cp $HOME/.config/opencode/plugins/herdr-agent-state.js $out/opencode-plugin.js
  '';

  # Upstream's official agent skill (herdr.dev/docs/agent-skill), lifted out of
  # the herdr source tree. Upstream ships it in the repo but keeps it out of the
  # package, distributing it through `npx skills add` -- which would write into
  # ~/.claude/skills, a home-manager-managed tree here.
  #
  # Lazy, like herdrIntegrations: only forced from the block that already guards
  # skillSrc != null.
  herdrSkill = pkgs.runCommand "herdr-skill" { } ''
    # v0.7.5 keeps SKILL.md at the repo root; upstream has since moved it to
    # skills/herdr/. Take whichever the pinned revision has, so a version bump
    # is a one-line change in the consuming flake, and fail loudly rather than
    # installing an empty skill if it ever moves somewhere else again.
    for candidate in ${cfg.herdr.skillSrc}/skills/herdr/SKILL.md \
                     ${cfg.herdr.skillSrc}/SKILL.md; do
      if [ -f "$candidate" ]; then
        install -D "$candidate" "$out/SKILL.md"
        break
      fi
    done
    if [ ! -f "$out/SKILL.md" ]; then
      echo "no SKILL.md in the herdr source at ${cfg.herdr.skillSrc}" >&2
      exit 1
    fi
  '';

in
{
  imports = [ ./workspace-layout.nix ./git-conventions.nix ./github-conventions.nix ./ai-memory.nix ./pr-feedback.nix ];

  options.cjlarose.llmAgents = {

    # --- lavish-axi ---------------------------------------------------------

    lavish.enable = lib.mkEnableOption ''
      the lavish-axi CLI (upstream kunchenguid/lavish-axi, built from source with
      telemetry disabled) and its Lavish Editor agent skill. lavish-axi opens
      an agent-generated HTML artifact in a sandboxed browser for human annotation
      and ships the feedback back to the driving agent over a loopback server with
      a Host-header DNS-rebinding guard. Disabled by default; opt in per host/user
    '';

    lavish.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        The lavish-axi package to install. Carries the CLI at bin/lavish-axi and
        the generated agent skill at share/lavish-axi/skill/SKILL.md, which this
        module installs into every enabled harness.
        Required when lavish.enable is set; asserted below rather than defaulted,
        so hosts with lavish off need not name a package at all.
      '';
    };

    lavish.host = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "myhost.example.ts.net";
      description = ''
        Bind address for the lavish-axi review server (LAVISH_AXI_HOST). Null
        leaves lavish on its 127.0.0.1 default -- reachable only from this host.
        A hostname or IP binds that interface instead; a hostname that resolves
        to a tailscale IP serves the review UI over the tailnet with no literal
        IP in config. Binding beyond loopback exposes the files lavish serves to
        anything that can reach the socket, so pair it with a firewall that only
        opens the port on the intended interface.
      '';
    };

    lavish.linkHost = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Hostname written into the session URLs lavish prints
        (LAVISH_AXI_LINK_HOST). Null uses the bind address. Set it to the name a
        reviewer actually reaches the server by, so the printed links are
        clickable from their machine.
      '';
    };

    lavish.linkScheme = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "http" "https" ]);
      default = null;
      example = "https";
      description = ''
        Scheme lavish prints its session links with (LAVISH_AXI_LINK_SCHEME).
        Null leaves upstream's http. Set https when a TLS-terminating reverse
        proxy fronts the loopback server. Composes with linkHost/linkPort and
        requires the reverse-proxy build patch in packages/lavish-axi.
      '';
    };

    lavish.linkPort = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "";
      description = ''
        Port segment lavish prints its session links with (LAVISH_AXI_LINK_PORT).
        Null keeps the actual bind port. The empty string omits the port entirely
        -- use it when a reverse proxy serves the link on the scheme's default
        port (443/80), so the printed URL has no `:port`. A number forces that
        port. Composes with linkScheme; requires the packages/lavish-axi patch.
      '';
    };

    lavish.allowedHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "myhost.example.ts.net" ];
      description = ''
        Extra Host-header values lavish's DNS-rebinding guard accepts
        (LAVISH_AXI_ALLOWED_HOSTS, space-joined). Loopback, localhost and the
        bind/link hosts are always allowed; add any other name a reviewer reaches
        the server by. Empty leaves only that built-in set.
      '';
    };

    lavish.port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = ''
        Fixed port for the lavish-axi server (LAVISH_AXI_PORT). Null uses
        lavish's own default (4387). Pin it when a firewall rule has to name the
        same port.
      '';
    };

    # --- gh stacked PRs (skill only) ----------------------------------------

    ghStackSkill.enable = lib.mkEnableOption ''
      the agent skill that github/gh-stack ships at share/gh-stack/skill/.

      The name is literal: this installs the SKILL.md and nothing else. `gh
      stack` is a human CLI tool and is not this module's business -- registering
      the extension with gh and putting the binary on PATH is
      cjlarose.devTools.ghStack, in the dev-tools module. Enable both, from the
      same package, or the skill documents a command that is not installed
    '';

    ghStackSkill.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        The gh-stack package to read share/gh-stack/skill/SKILL.md from. Should
        be the same package given to cjlarose.devTools.ghStack.package -- the
        skill documents specific subcommands and flags, so a skill from a
        different build than the installed extension is actively misleading.
        Required when ghStackSkill.enable is set.
      '';
    };

    # --- git-surgeon --------------------------------------------------------

    gitSurgeon.enable = lib.mkEnableOption ''
      git-surgeon: hunk-level git staging, unstaging, discarding, undoing,
      folding, amending, squashing, commit splitting and commit reordering, all
      non-interactive and addressed by content-derived hunk ID. Installs BOTH the
      CLI and upstream's own agent skill, which is why this is not named
      `gitSurgeonSkill` -- the skill drives the bare `git-surgeon` command, so
      shipping the two apart would give the agent instructions for a binary that
      is not there. Contrast ghStackSkill above, whose tool is a human CLI owned
      by cjlarose.devTools.

      The CLI is agent tooling first (upstream's stated audience is agents that
      need precise control over which hunks to stage), so unlike gh-stack it
      lives entirely here rather than being split across dev-tools
    '';

    gitSurgeon.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        The git-surgeon package to install. Carries the CLI at bin/git-surgeon
        and upstream's skill at share/git-surgeon/skills/git-surgeon/SKILL.md
        (note the plural `skills/` -- gh-stack and lavish-axi both use a singular
        `skill/`). Required when gitSurgeon.enable is set.
      '';
    };

    # --- tuicr ---------------------------------------------------------------

    tuicr.enable = lib.mkEnableOption ''
      tuicr, a code-review TUI with vim keybindings that reviews a commit range
      or working tree and exports the annotations to a GitHub PR or the
      clipboard. Ships no agent skill -- it is a tool for a human at the
      keyboard, and lives here rather than in dev-tools because reviewing what
      an agent just wrote is what it gets used for
    '';

    tuicr.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "The tuicr package to install. Required when tuicr.enable is set.";
    };

    tuicr.settings = lib.mkOption {
      type = tomlFormat.type;
      default = { };
      example = { reverse = true; };
      description = ''
        Freeform tuicr configuration, rendered to ~/.config/tuicr/config.toml.
        Left empty, no file is written at all, so tuicr keeps its own built-in
        defaults rather than being handed an empty config.

        The only key this fleet sets is `reverse` (tuicr's own default is off),
        which renders the inline commit selector parent -> child for
        GitHub-PR-style branch review. It comes from the
        commit-order-display-option branch of cjlarose/tuicr, so it is only
        meaningful when tuicr.package is built from that fork.
      '';
    };

    # --- standalone agent CLIs ---------------------------------------------

    opencode.enable = lib.mkEnableOption ''
      opencode, the standalone terminal coding agent: its integrations here --
      the shared ~/.claude/skills, the herdr plugin, superpowers' skills.paths
      -- and, when `package` is set, the binary itself through
      programs.opencode
    '';

    opencode.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        The opencode package, installed through programs.opencode.

        Null means opencode reaches this host from somewhere else -- another
        module owning programs.opencode -- and this module contributes only the
        integrations above. That is what lets a host take the binary from
        whichever module installs it, including one that has to place it
        outside the nix store, while keeping the personal wiring here. Nothing
        is installed and nothing collides.

        The integrations that write files -- the skills and the herdr plugin --
        land either way. The one that does not is superpowers' skills.paths,
        which is a programs.opencode SETTING and so needs whichever module owns
        that option to have enabled it.
      '';
    };

    herdr.enable = lib.mkEnableOption ''
      herdr, a terminal workspace manager for AI coding agents (herdr.dev).
      Packaged only in llm-agents.nix, not nixpkgs
    '';

    herdr.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "The herdr package to install. Required when herdr.enable is set.";
    };

    herdr.skillSrc = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Upstream's herdr source tree (the herdrdev/herdr flake input itself),
        from which the module lifts the official agent skill and installs it as
        the `herdr` agent skill, into every enabled harness. Optional -- herdr works fine without it;
        leave null to install the terminal multiplexer but not the instructions
        for driving it.

        A source rather than a package because upstream's derivation
        deliberately excludes the skill from its src fileset, distributing it
        through `npx skills add` instead -- so there is nothing to read out of
        herdr.package, and the extraction has to happen somewhere. Here, so
        both consuming flakes get it from one definition rather than a copy
        each.

        Set this from the SAME input that produced herdr.package, so the skill
        cannot document subcommands the installed binary does not have.

        Ignored unless herdr.enable is also set: a skill telling the agent to
        run `herdr` is worse than useless without the binary.
      '';
    };

    # --- personal LLM wiki --------------------------------------------------

    wiki.enable = lib.mkEnableOption ''
      the personal LLM wiki integration: the read-only querying-notes skill
      (installed into ~/.claude/skills, so it reaches both claude and opencode)
      and LLM_WIKI_PATH. The skill body comes from wiki.skillSrc; the wiki is
      read-only, so there is no SessionStart hook and no maintenance skills
    '';

    wiki.path = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/you/repos/cjlarose/llm-wiki";
      description = ''
        Absolute path to the llm-wiki checkout on the target machine. Exported
        as LLM_WIKI_PATH, which the querying-notes skill reads to locate the
        wiki. Required when wiki.enable is set.
      '';
    };

    wiki.skillSrc = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        The wiki's skills/ directory (the cjlarose-llm-wiki flake input's
        skills tree), from which the module installs the read-only
        querying-notes skill into ~/.claude/skills. Same shape as
        herdr.skillSrc: a source tree comes in, the module reads one SKILL.md
        out of it.

        Delivered through ~/.claude/skills rather than a Claude Code plugin
        because that one location reaches BOTH harnesses -- the wiki used to
        ship this as a claude-only plugin, which opencode never saw.

        Optional: left null, wiki.enable still exports LLM_WIKI_PATH but installs
        no skill. Set it from the SAME flake input wiki.path points at, so the
        skill matches the wiki it queries.
      '';
    };
  };

  config = lib.mkMerge [

    # --- lavish-axi ---------------------------------------------------------
    # The `package != null` half of each guard is not redundant with the
    # assertions below: without it a null reaches home.packages and fails the
    # `package` type check FIRST, burying the assertion's readable message.
    (lib.mkIf (cfg.lavish.enable && cfg.lavish.package != null) {
      # CLI on PATH. Under home-manager useUserPackages this rides the system
      # profile, so the picktrace VM needs a system switch-to-configuration to pick
      # it up (an HM-only activate won't), same as tuicr / the playwright closure.
      home.packages = [ cfg.lavish.package ];

      # The skill drives the on-PATH lavish-axi binary directly (never npx), so
      # nothing is fetched from npm at runtime. Single-file SKILL.md shipped in
      # the package's share/ output, installed into each enabled harness.
      home.file = lib.mkIf skillsWanted {
        ".claude/skills/lavish/SKILL.md".source =
          "${cfg.lavish.package}/share/lavish-axi/skill/SKILL.md";
      };

      # The LAVISH_AXI_* env vars the CLI reads, rendered only from the options a
      # host actually sets -- an unconfigured host keeps lavish's loopback
      # default. The firewall that exposes the port is a system-level concern and
      # lives in the host's nixos config, not here.
      home.sessionVariables =
        lib.optionalAttrs (cfg.lavish.host != null) { LAVISH_AXI_HOST = cfg.lavish.host; }
        // lib.optionalAttrs (cfg.lavish.linkHost != null) { LAVISH_AXI_LINK_HOST = cfg.lavish.linkHost; }
        // lib.optionalAttrs (cfg.lavish.linkScheme != null) { LAVISH_AXI_LINK_SCHEME = cfg.lavish.linkScheme; }
        // lib.optionalAttrs (cfg.lavish.linkPort != null) { LAVISH_AXI_LINK_PORT = cfg.lavish.linkPort; }
        // lib.optionalAttrs (cfg.lavish.allowedHosts != [ ]) { LAVISH_AXI_ALLOWED_HOSTS = lib.concatStringsSep " " cfg.lavish.allowedHosts; }
        // lib.optionalAttrs (cfg.lavish.port != null) { LAVISH_AXI_PORT = toString cfg.lavish.port; };
    })

    # --- gh stacked PRs (skill only) ----------------------------------------
    (lib.mkIf (cfg.ghStackSkill.enable && cfg.ghStackSkill.package != null) {
      # Upstream's own skill, read out of the package so it always matches the
      # extension binary built from the same source.
      home.file = lib.mkIf skillsWanted {
        ".claude/skills/gh-stack/SKILL.md".source =
          "${cfg.ghStackSkill.package}/share/gh-stack/skill/SKILL.md";
      };
    })

    # --- git-surgeon --------------------------------------------------------
    (lib.mkIf (cfg.gitSurgeon.enable && cfg.gitSurgeon.package != null) {
      # Binary and skill together, out of one package, so the documented
      # subcommands and flags always match the build that is installed.
      home.packages = [ cfg.gitSurgeon.package ];

      # Upstream nests its skill one level deeper than the other two tools we
      # read a SKILL.md out of: share/git-surgeon/skills/<name>/SKILL.md, not
      # share/<tool>/skill/SKILL.md. Irrelevant to where it lands, which is
      # spelled out on the left of each assignment below.
      home.file = lib.mkIf skillsWanted {
        ".claude/skills/git-surgeon/SKILL.md".source =
          "${cfg.gitSurgeon.package}/share/git-surgeon/skills/git-surgeon/SKILL.md";
      };
    })

    # --- tuicr ---------------------------------------------------------------
    (lib.mkIf (cfg.tuicr.enable && cfg.tuicr.package != null) {
      home.packages = [ cfg.tuicr.package ];

      # Only written when the consumer actually sets something: an empty
      # settings attrset means no config.toml, not a config.toml saying nothing.
      # mkIf wraps the whole attrset rather than the entry's value -- under
      # attrsOf, a filtered-out value can still leave the key behind with an
      # all-defaults submodule, which would write an empty file.
      xdg.configFile = lib.mkIf (cfg.tuicr.settings != { }) {
        "tuicr/config.toml".source =
          tomlFormat.generate "tuicr-config.toml" cfg.tuicr.settings;
      };
    })

    # --- standalone agent CLIs ---------------------------------------------
    (lib.mkIf (cfg.opencode.enable && cfg.opencode.package != null) {
      programs.opencode = {
        enable = true;
        package = cfg.opencode.package;
      };
    })

    (lib.mkIf (cfg.herdr.enable && cfg.herdr.package != null) {
      home.packages = [ cfg.herdr.package ];

      # Claude Code integration, in the two halves `herdr integration install
      # claude` would have written (see herdrIntegrations above for why it
      # cannot run against this home).
      #
      # The script goes to the exact path herdr probes so `herdr integration
      # status` reports `current (v7)` instead of `not installed`. `.source`
      # rather than programs.claude-code.hooks (which takes script *content*,
      # so would need readFile on the derivation -> IFD).
      home.file.".claude/hooks/herdr-agent-state.sh".source =
        "${herdrIntegrations}/claude-hook.sh";

      # The registration half. Merges into the consumer's
      # programs.claude-code.settings (see home/cjlarose) -- so on a host with
      # herdr but no claude this defines settings for a claude that is not
      # installed, which home-manager simply does not write. Kept in sync with
      # the script by the VERSION=7 assertion in herdrIntegrations.
      programs.claude-code.settings.hooks.SessionStart = [{
        matcher = "*";
        hooks = [{
          type = "command";
          timeout = 10;
          command = "${pkgs.bash}/bin/bash '${config.home.homeDirectory}/.claude/hooks/herdr-agent-state.sh' session";
        }];
      }];
    })

    # Upstream's agent skill for driving herdr from inside a herdr-managed pane.
    # Split from the block above because it is optional and separately sourced
    # (see herdr.skillSrc), but gated on herdr.enable all the same. Harmless on
    # hosts where herdr is installed but unused: the skill's first instruction
    # is to check HERDR_ENV=1 and stop if it is unset.
    (lib.mkIf (cfg.herdr.enable && cfg.herdr.package != null && cfg.herdr.skillSrc != null) {
      home.file = lib.mkIf skillsWanted {
        ".claude/skills/herdr/SKILL.md".source = "${herdrSkill}/SKILL.md";
      };
    })

    # opencode integration. Split from the block above because it needs both
    # tools; the plugin is inert (and harmless) without opencode installed, but
    # there is no reason to write it. No registration half -- opencode scans the
    # plugins directory, and home-manager's programs.opencode does not manage
    # it, so there is nothing to collide with.
    (lib.mkIf (cfg.herdr.enable && cfg.herdr.package != null && cfg.opencode.enable) {
      xdg.configFile."opencode/plugins/herdr-agent-state.js".source =
        "${herdrIntegrations}/opencode-plugin.js";
    })

    # --- personal LLM wiki --------------------------------------------------
    # Owned entirely here now: LLM_WIKI_PATH plus the read-only querying-notes
    # skill in ~/.claude/skills (both harnesses). This used to be a claude-only
    # plugin defined in the llm-wiki flake's own HM module, reached through a
    # programs.llmWiki bridge -- opencode never saw it. Both the env var and the
    # skill go through always-declared options (home.sessionVariables,
    # home.file), so unlike programs.llmWiki they need no separately-imported
    # declaration and live under a plain mkIf here.
    (lib.mkIf cfg.wiki.enable {
      home.sessionVariables.LLM_WIKI_PATH = cfg.wiki.path;

      # skillsWanted gates it to hosts running at least one harness; skillSrc is
      # the wiki's own skills/ tree, handed in by the consumer. Left null (or on
      # a host with neither harness), only LLM_WIKI_PATH is set.
      home.file = lib.mkIf (skillsWanted && cfg.wiki.skillSrc != null) {
        ".claude/skills/querying-notes/SKILL.md".source =
          "${cfg.wiki.skillSrc}/querying-notes/SKILL.md";
      };
    })

    # Every enable that needs a package asserts it rather than defaulting one, so
    # a host that leaves the feature off never has to name a package at all.
    {
      assertions = [
        {
          assertion = !cfg.wiki.enable || cfg.wiki.path != null;
          message = "cjlarose.llmAgents.wiki.enable is true but cjlarose.llmAgents.wiki.path is unset.";
        }
        {
          assertion = !cfg.lavish.enable || cfg.lavish.package != null;
          message = "cjlarose.llmAgents.lavish.enable is true but cjlarose.llmAgents.lavish.package is unset.";
        }
        {
          assertion = !cfg.herdr.enable || cfg.herdr.package != null;
          message = "cjlarose.llmAgents.herdr.enable is true but cjlarose.llmAgents.herdr.package is unset.";
        }
        {
          assertion = !cfg.ghStackSkill.enable || cfg.ghStackSkill.package != null;
          message = "cjlarose.llmAgents.ghStackSkill.enable is true but cjlarose.llmAgents.ghStackSkill.package is unset.";
        }
        {
          assertion = !cfg.gitSurgeon.enable || cfg.gitSurgeon.package != null;
          message = "cjlarose.llmAgents.gitSurgeon.enable is true but cjlarose.llmAgents.gitSurgeon.package is unset.";
        }
        {
          assertion = !cfg.tuicr.enable || cfg.tuicr.package != null;
          message = "cjlarose.llmAgents.tuicr.enable is true but cjlarose.llmAgents.tuicr.package is unset.";
        }
      ];
    }
  ];
}
