# Unified LLM-agent tooling module.
#
# One module owning everything agent-related for a user: Claude Code itself
# (package choice, MCP servers, settings, the nixd LSP marketplace), the
# superpowers skills plugin, lavish-axi, the personal LLM wiki integration, the
# standalone agent CLIs (opencode, herdr, git-surgeon), tuicr, and the gh-stack
# agent skill. Options ending in `Skill` install documentation only -- the tool
# they describe is installed elsewhere; an option without the suffix that
# happens to ship a skill (lavish, gitSurgeon) installs the tool too. herdr is
# the third case: the tool is here but upstream keeps its skill out of the
# package, so the module lifts it out of upstream's source tree
# (herdr.skillSrc). tuicr is the fourth: no skill at all, and the only option
# here that carries configuration rather than just a package. superpowers is the
# fifth, and the same shape as herdr: a source comes in (superpowers.src) and
# the module builds the plugin from it, because its customizations
# (disableHooks, disableSpecCommits) are module options and a package built out
# in a consuming flake's packages/ cannot see them.
#
# It replaces the former separate claude / phx-workflow / lavish / opencode
# modules. Claude Code is unconditional -- importing this module is the decision
# to have claude; everything else is opt-in per host/user.
#
# Every skill an option here installs goes through cjlarose.llmAgents.skills
# (./skills.nix) rather than programs.claude-code.skills, because that module
# owns ~/.claude/skills as a single directory symlink so the same store path can
# also serve ~/.agents/skills. Nothing here may write a file underneath it.
#
# The module takes no flake-specific arguments: every package it installs comes
# in through a `*.package` option that the consumer sets explicitly. It used to
# reach into an `additionalPackages` module arg for defaults, which coupled it to
# one particular shape of consuming flake and silently broke if that flake
# renamed or dropped an attr.
#
# The one thing this module cannot own is the `imports` of the wiki flake's own
# module (which declares programs.llmWiki): `imports` is resolved before config
# exists, so it can key off neither an option nor an optional module argument
# (an arg with a default forces _module.args evaluation => infinite recursion).
# The consumer therefore imports cjlarose-llm-wiki.homeManagerModules.default
# alongside this module -- see home/cjlarose -- and this module owns everything
# else about the wiki, including turning it on and pointing it at a worktree.
{ lib, pkgs, config, ... }:

let
  cfg = config.cjlarose.llmAgents;

  # Renders cjlarose.llmAgents.tuicr.settings to tuicr's config.toml. A freeform
  # format rather than a typed option per key: tuicr's config surface is its
  # own, and every key it grows would otherwise need a change here before a
  # consumer could set it.
  tomlFormat = pkgs.formats.toml { };

  # The claude wrapper, shared by both consuming flakes. It used to be duplicated
  # as `mkTitleWrapper` in each repo's packages/default.nix, where it drifted
  # (cjlarose had it as a reusable function over both the Bun and node builds;
  # picktrace had the body inlined). Living here means one definition, and `pkgs`
  # is the host's own nixpkgs -- so bashInteractive is the one the system already
  # pulls in, with no nixpkgs-26-05 plumbing through packages/. The rationale for
  # each line lives in the script itself, so it survives into the store copy the
  # user actually reads.
  wrappedClaude = pkgs.writeShellScriptBin "claude" ''
    # Set the terminal title from the checkout layout. Three schemes are
    # recognized so a host may use either the old or the new one:
    #   ~/worktrees/<owner>/<repo>/<worktree> -> owner/repo [worktree]
    #   ~/workspaces/<task>/<owner>-<repo>    -> owner-repo [task]
    #   ~/repos/<owner>/<repo>                -> owner/repo
    # Elsewhere the title is left alone. The ~/repos form has no bracket
    # because nothing should ever be edited there.
    if [[ "$PWD" =~ ^''${HOME}/worktrees/([^/]+)/([^/]+)/([^/]+) ]]; then
      printf '\033]2;%s\007' "Claude Code ✳ ''${BASH_REMATCH[1]}/''${BASH_REMATCH[2]} [''${BASH_REMATCH[3]}]"
    elif [[ "$PWD" =~ ^''${HOME}/workspaces/([^/]+)/([^/]+) ]]; then
      printf '\033]2;%s\007' "Claude Code ✳ ''${BASH_REMATCH[2]} [''${BASH_REMATCH[1]}]"
    elif [[ "$PWD" =~ ^''${HOME}/repos/([^/]+)/([^/]+) ]]; then
      printf '\033]2;%s\007' "Claude Code ✳ ''${BASH_REMATCH[1]}/''${BASH_REMATCH[2]}"
    fi

    # We set the title above, so stop claude from fighting us over it.
    export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1

    # claude (via chalk) hard-caps its color level to 256 whenever $TMUX is set,
    # a cap even FORCE_COLOR=3 cannot defeat. Dropping the variable is the only
    # way to get 24-bit color inside tmux; we are already past the point where
    # anything else in this process needs it.
    unset TMUX

    # Pin the shell claude spawns for the Bash tool. Left unset it follows
    # $SHELL, which is zsh on these hosts, so tool invocations would run under a
    # different shell than the bash the agent's snippets assume. The :- default
    # means an explicit value in the environment still wins.
    export CLAUDE_CODE_SHELL="''${CLAUDE_CODE_SHELL:-${pkgs.bashInteractive}/bin/bash}"

    # Always use the fullscreen (alt-screen, flicker-free) TUI renderer rather
    # than leaving it to a rollout gate. There is no CLI flag for this; the two
    # real mechanisms are the settings.json "tui": "fullscreen" key (what the
    # /tui slash command writes) and this variable, which the setting's own
    # description calls equivalent. The variable is the stronger of the two:
    # claude consults it *before* the settings key and before the automatic
    # opt-outs, so it also survives the tmux -CC and Windows-over-SSH
    # auto-disables, which the setting does not. It is parsed as a tri-state,
    # so the :- default leaves CLAUDE_CODE_NO_FLICKER=0 as a working escape
    # hatch for a session that needs the classic renderer. Screen-reader mode
    # still wins over both, by design.
    export CLAUDE_CODE_NO_FLICKER="''${CLAUDE_CODE_NO_FLICKER:-1}"

    exec ${cfg.claude.package}/bin/claude "$@"
  '';

  claudeCodeStatusline = pkgs.writeShellApplication {
    name = "claude-code-statusline";
    runtimeInputs = [ pkgs.jq pkgs.gawk ];
    text = builtins.readFile ./claude-code-statusline.sh;
  };

  # playwright-mcp 0.0.69 ignores the PLAYWRIGHT_MCP_BROWSER env var that
  # nixpkgs sets, so it falls back to the "chrome" channel and tries to
  # provision a chrome-for-testing build by writing into its (read-only) Nix
  # store browsers path — which fails with ENOENT/mkdir. Point it explicitly at
  # the nix-provided chromium instead (the same playwright-driver.browsers
  # derivation the upstream wrapper already exports, so versions stay in sync).
  # The chromium revision is globbed at runtime to survive nixpkgs bumps.
  # Headless because this targets displayless hosts; isolated keeps the profile
  # in memory.
  playwrightMcp = pkgs.writeShellScriptBin "playwright-mcp-chromium" ''
    chrome=( ${pkgs.playwright-driver.browsers}/chromium-*/chrome-linux*/chrome )
    exec ${pkgs.playwright-mcp}/bin/playwright-mcp \
      --headless --isolated --executable-path "''${chrome[0]}" "$@"
  '';

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

  # The literal text "${CLAUDE_PLUGIN_ROOT}" to search for. Built in a normal
  # double-quoted string where \${ is an unambiguous escape; writing it inline
  # in the '' block below collides with Nix's own '' and ''${ escapes.
  pluginRootVar = "\${CLAUDE_PLUGIN_ROOT}";

  # obra/superpowers as a force-loadable Claude Code plugin, built from
  # upstream's source with this fleet's customizations applied on top.
  #
  # Upstream already ships the plugin layout (.claude-plugin/plugin.json,
  # skills/, hooks/), so this is a copy with edits rather than a build. It used
  # to be packages/superpowers in each consuming flake -- hand-duplicated, and
  # therefore drifting -- but the customizations below are driven by module
  # options, which packages/ cannot see. Same reasoning as herdrSkill above:
  # a source comes in, the transformation happens once, here.
  #
  # Every edit is --replace-fail or an explicit guard, so an upstream rewording
  # breaks the BUILD rather than silently shipping unmodified text. The
  # line-count tripwires cover the opposite failure -- an upstream release that
  # ADDS commit language, which no search-and-replace can detect on its own.
  # When one fires, read the upstream diff and re-derive the strings; do not
  # just bump the expected count.
  #
  # Lazy, like the two herdr derivations: only forced from the block that
  # already guards src != null.
  superpowersPlugin = pkgs.runCommand "superpowers-plugin"
    {
      src = cfg.superpowers.src;
      meta = {
        description = "obra/superpowers skills library, packaged as a Claude Code plugin";
        homepage = "https://github.com/obra/superpowers";
        license = lib.licenses.mit;
      };
    }
    ''
      cp -r "$src" "$out"
      chmod -R u+w "$out"

      # Guard before either branch: both of them assume hook registration lives
      # in this file, so if upstream moves it, the disable branch would write a
      # stray no-op while the real hook keeps firing, and the substitute branch
      # would leave an unresolved path behind.
      [ -f "$out/hooks/hooks.json" ] \
        || { echo "hooks/hooks.json is gone; upstream moved hook registration -- re-check this module" >&2; exit 1; }

      ${
        if cfg.superpowers.disableHooks then ''
          grep -q '"SessionStart"' "$out/hooks/hooks.json" \
            || { echo "hooks.json no longer registers SessionStart; re-check superpowers.disableHooks" >&2; exit 1; }

          # Overwrite rather than delete: an empty hook set is unambiguous to
          # the plugin loader and keeps the file present so the guard above
          # stays meaningful. The hook scripts are left in place (unreferenced,
          # harmless) so flipping the option back needs no other change.
          echo '{"hooks":{}}' > "$out/hooks/hooks.json"
        '' else ''
          # hooks.json invokes its own hook runner via
          # "''${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd", and CLAUDE_PLUGIN_ROOT
          # is NOT set for SessionStart events -- the hook fails silently, which
          # is the failure mode hardest to notice, since a missing session
          # preamble looks like a model that just didn't reach for a skill.
          # Baking the real store path is the same fix the llm-wiki plugin uses.
          #
          # The hook script itself needs no patching: it derives the plugin root
          # from its own $0, so once hooks.json points at the right
          # run-hook.cmd everything below resolves relative to it.
          grep -q 'CLAUDE_PLUGIN_ROOT' "$out/hooks/hooks.json" \
            || { echo "hooks.json no longer references CLAUDE_PLUGIN_ROOT; re-check this module" >&2; exit 1; }

          substituteInPlace "$out/hooks/hooks.json" \
            --replace-fail '${pluginRootVar}' '${builtins.placeholder "out"}'

          # `if`, not `grep && exit` -- a correct run leaves no match, so grep
          # exits 1 and the && form would fail precisely when it succeeded.
          if grep -q 'CLAUDE_PLUGIN_ROOT' "$out/hooks/hooks.json"; then
            echo "substitution left a CLAUDE_PLUGIN_ROOT reference behind" >&2
            exit 1
          fi
        ''
      }

      # The hook runner and its scripts must stay executable through the copy,
      # whether or not anything currently invokes them.
      chmod +x "$out/hooks/run-hook.cmd" "$out/hooks/session-start"

      ${lib.optionalString cfg.superpowers.disableSpecCommits ''
        # The replacement wording deliberately says "add it to git" rather than
        # "do not commit it": the tripwire below counts lines matching 'commit',
        # so prose containing the word would inflate the count and blunt it.
        substituteInPlace "$out/skills/brainstorming/SKILL.md" \
          --replace-fail \
            '6. **Write design doc** — save to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` and commit' \
            '6. **Write design doc** — save to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`. Do NOT add it to git.' \
          --replace-fail \
            '- Commit the design document to git' \
            '- Do NOT add the design document to git. `docs/superpowers/` is gitignored globally; the spec is a working note, not repo history.' \
          --replace-fail \
            '> "Spec written and committed to `<path>`.' \
            '> "Spec written to `<path>`.'

        # The two survivors in brainstorming are both "check ... recent commits"
        # (reading history, not writing it); all four in writing-plans are about
        # committing the implementation, which this option deliberately keeps.
        for check in brainstorming:2 writing-plans:4; do
          skill="''${check%:*}"
          want="''${check#*:}"
          got=$(grep -ci 'commit' "$out/skills/$skill/SKILL.md" || true)
          [ "$got" = "$want" ] || {
            echo "$skill/SKILL.md: expected $want lines mentioning 'commit', found $got." >&2
            echo "Upstream changed its commit guidance -- re-read the diff before bumping this count." >&2
            exit 1
          }
        done
      ''}
    '';
in
{
  imports = [ ./skills.nix ./workspace-layout.nix ./git-conventions.nix ];

  options.cjlarose.llmAgents = {

    # --- Claude Code -------------------------------------------------------

    claude.enablePlaywrightMcp = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Register the Playwright MCP server with Claude Code, using the pinned
        pkgs.playwright-mcp build (chromium baked in via PLAYWRIGHT_BROWSERS_PATH,
        so no runtime npx/network). Default off because it pulls a chromium
        browser closure; enable only on hosts where browser automation is wanted.
      '';
    };

    claude.remoteControlAtStartup = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable Remote Control for every new session at startup (the
        remoteControlAtStartup setting). Default off; enabled on cjlarose's own
        hosts via home/cjlarose/default.nix. Left off on pt-docker-cjlarose,
        whose picktrace Claude subscription doesn't have Remote Control.
      '';
    };

    claude.package = lib.mkOption {
      type = lib.types.package;
      description = ''
        The UNWRAPPED claude-code package. Required -- claude is the one piece of
        this module that is unconditional. The module applies its own wrapper
        (terminal title, TMUX/colour and CLAUDE_CODE_SHELL handling) on top, so
        hand over a plain build.

        Which build is a property of the HOST, not of this module: AVX-capable
        machines take the latest Bun standalone, while the Goldmont-based pve
        guests need the node-pinned build (frozen at npm 2.1.112) because the Bun
        binary segfaults at launch there. The consumer picks; this used to be a
        `useNodeRuntime` boolean here, which forced the module to know both
        package names.
      '';
    };

    # --- superpowers ---------------------------------------------------------

    superpowers.enable = lib.mkEnableOption ''
      obra/superpowers as a Claude Code plugin: 14 skills covering
      brainstorming, planning, TDD, code review, git worktrees and debugging,
      invocable as superpowers:<name>.

      Replaces two things that used to live here: the vendored
      systematic-debugging copy (now one skill of the set, with its
      superpowers:* cross-references finally resolving) and the phx workflow
      skills, whose brainstorm/plan/work/review spine upstream covers natively
      with brainstorming + writing-plans + executing-plans + *-code-review.

      Enabling this is NOT enough on its own -- ./superpowers-plugin.nix must
      also be imported, which is what actually defines
      programs.claude-code.plugins. That option does not exist on
      home-manager 25-11, so the definition has to be absent rather than
      disabled there; see that file. Gate the import and this option off the
      same flag in the consumer so the two cannot drift
    '';

    superpowers.src = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Upstream's obra/superpowers source tree (the flake input itself, pinned
        to a release tag). The module builds the plugin from it.

        A source rather than a package because the customizations below are
        driven by the options in this module, and a package built out in
        packages/ cannot see them. This used to be packages/superpowers in each
        consuming flake -- a file hand-copied between two repos, with the
        customizations frozen into it. Same shape as herdr.skillSrc: the source
        comes in, the transformation happens once, here.

        Pin to a tag rather than a branch. Upstream ships a SessionStart hook
        that injects context into every session, so an unpinned bump would
        change every host's prompt with no lock diff to show for it.

        Required when superpowers.enable is set.
      '';
    };

    superpowers.disableHooks = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Ship the plugin with an empty hook set, replacing upstream's
        hooks/hooks.json.

        Upstream registers a SessionStart hook that cats
        skills/using-superpowers/SKILL.md into every session wrapped in
        <EXTREMELY_IMPORTANT>, whose text orders the agent to invoke a skill
        "BEFORE any response or action" and to brainstorm before entering plan
        mode. That is too eager -- it front-loads a brainstorm onto questions
        that only wanted an answer.

        Turning this on leaves every skill invocable through the Skill tool,
        including superpowers:using-superpowers; it just stops one being
        force-fed. Note it is a reduction, not an elimination: the skill
        descriptions still nudge (brainstorming's own description says "You MUST
        use this before any creative work"). The hook is what made it
        unconditional.

        Left off (the default), the module instead bakes the plugin's real store
        path into hooks.json, because CLAUDE_PLUGIN_ROOT is not set for
        SessionStart events and the hook would otherwise fail silently.
      '';
    };

    superpowers.disableSpecCommits = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Remove the brainstorming skill's instructions to COMMIT its design
        document. Upstream writes the spec to docs/superpowers/specs/ and
        commits it; where specs are working notes rather than repo history, that
        dirties every repo the agent touches.

        Only the doc-committing language is touched. The implementation-commit
        guidance in writing-plans and subagent-driven-development is left alone
        deliberately -- the implementation step is expected to commit.
        writing-plans needs no edit at all: it never says to commit the plan
        document, only the code.

        Pairs with gitignoring docs/superpowers (see home-manager-modules/git.nix),
        so the specs land untracked rather than as a dirty worktree.
      '';
    };

    superpowers.finalPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      internal = true;
      description = ''
        The built plugin, or null when superpowers is off. Read by
        ./superpowers-plugin.nix, which is the file that actually defines
        programs.claude-code.plugins -- it cannot be defined from here, and that
        sibling module has no way to reach a `let` binding in this one. Internal:
        set by this module, never by a consumer.
      '';
    };

    # --- lavish-axi ---------------------------------------------------------

    lavish.enable = lib.mkEnableOption ''
      the lavish-axi CLI (upstream kunchenguid/lavish-axi, built from source with
      telemetry disabled) and its Lavish Editor Claude Code skill. lavish-axi opens
      an agent-generated HTML artifact in a sandboxed browser for human annotation
      and ships the feedback back to the driving agent over a loopback server with
      a Host-header DNS-rebinding guard. Disabled by default; opt in per host/user
    '';

    lavish.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        The lavish-axi package to install. Carries the CLI at bin/lavish-axi and
        the generated Claude Code skill at share/lavish-axi/skill/SKILL.md.
        Required when lavish.enable is set; asserted below rather than defaulted,
        so hosts with lavish off need not name a package at all.
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

    opencode.enable = lib.mkEnableOption
      "opencode, the standalone terminal coding agent (programs.opencode)";

    opencode.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "The opencode package to install. Required when opencode.enable is set.";
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
        the `herdr` Claude Code skill. Optional -- herdr works fine without it;
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
      the personal LLM wiki integration: the `wiki` Claude Code plugin (skills +
      SessionStart index hook) and LLM_WIKI_PATH. Only valid where the consumer
      also imports cjlarose-llm-wiki.homeManagerModules.default, which is what
      declares programs.llmWiki (see the header comment)
    '';

    wiki.path = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/you/worktrees/owner/llm-wiki/default";
      description = ''
        Absolute path to the writable llm-wiki git worktree on the target
        machine. Exported as LLM_WIKI_PATH and baked into the plugin's
        session-start hook, which cats the live index.md there.
      '';
    };
  };

  config = lib.mkMerge [

    # --- Claude Code (unconditional) ---------------------------------------
    {
      programs.claude-code = {
        enable = true;
        # The module's own wrapper, not cfg.claude.package directly -- see
        # wrappedClaude above. home-manager wraps this again with its
        # --plugin-dir flags, so the final chain is
        # HM plugin wrapper -> title/env wrapper -> claude-code.
        package = wrappedClaude;

        # Pinned, self-contained Playwright MCP (chromium baked in via the
        # package's PLAYWRIGHT_BROWSERS_PATH wrapper, so no runtime npx/network).
        # Gated default-off so headless hosts don't pull the chromium closure.
        # The HM module surfaces this as a .mcp.json in a generated plugin-dir
        # wired onto claude-code via --plugin-dir. Uses the chromium-pinned
        # wrapper above so the browser actually launches (see its comment).
        mcpServers = lib.optionalAttrs cfg.claude.enablePlaywrightMcp {
          playwright = {
            type = "stdio";
            command = "${playwrightMcp}/bin/playwright-mcp-chromium";
          };
        };

        settings = {
          enabledPlugins = {
            # nixd Nix language server, provided by the local marketplace below.
            "nixd@cjlarose-lsps" = true;
          };
          # Local plugin marketplace (files materialized via home.file below) that
          # ships a single LSP plugin wiring nixd as the Nix language server, so
          # Claude Code gets real diagnostics on .nix edits (unused bindings,
          # undefined vars, flake/option-aware analysis). nixd binary comes from
          # home.packages so the bare "nixd" command resolves on PATH.
          extraKnownMarketplaces."cjlarose-lsps".source = {
            source = "directory";
            path = "${config.home.homeDirectory}/.claude/lsp-marketplace";
          };
          skipDangerousModePermissionPrompt = true;
          remoteControlAtStartup = cfg.claude.remoteControlAtStartup;
          effortLevel = "medium";
          autoMemoryEnabled = false;
          # Keep session transcripts effectively forever (default is 30 days, which
          # silently garbage-collects ~/.claude/projects history). These transcripts
          # are the source for llm-wiki backfill/capture, so retention matters.
          cleanupPeriodDays = 3650;
          env = {
            CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
          };
          permissions = {
            defaultMode = "bypassPermissions";
          };
          statusLine = {
            type = "command";
            command = "${claudeCodeStatusline}/bin/claude-code-statusline";
          };
        };
      };

      home.packages = [ pkgs.nixd ];

      home.file = {
        # Local LSP plugin marketplace consumed via settings.extraKnownMarketplaces
        # + enabledPlugins above. Ships nixd as the Nix language server.
        ".claude/lsp-marketplace/.claude-plugin/marketplace.json".text = builtins.toJSON {
          name = "cjlarose-lsps";
          owner.name = "cjlarose";
          description = "cjlarose local LSP plugins";
          plugins = [{
            name = "nixd";
            source = "./nixd";
            description = "Nix language server (nixd)";
          }];
        };
        ".claude/lsp-marketplace/nixd/.claude-plugin/plugin.json".text = builtins.toJSON {
          name = "nixd";
          description = "Nix language server (nixd)";
          version = "1.0.0";
          author.name = "cjlarose";
        };
        ".claude/lsp-marketplace/nixd/.lsp.json".text = builtins.toJSON {
          nix = {
            command = "nixd";
            extensionToLanguage.".nix" = "nix";
          };
        };
      };
    }

    # --- superpowers ---------------------------------------------------------
    # Only builds the plugin; the programs.claude-code.plugins definition that
    # consumes it lives in ./superpowers-plugin.nix, for the same reason the
    # wiki's does not live here (see the llmWiki note below).
    (lib.mkIf (cfg.superpowers.enable && cfg.superpowers.src != null) {
      cjlarose.llmAgents.superpowers.finalPackage = superpowersPlugin;
    })

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
      # the package's share/ output.
      cjlarose.llmAgents.skills.lavish =
        "${cfg.lavish.package}/share/lavish-axi/skill/SKILL.md";
    })

    # --- gh stacked PRs (skill only) ----------------------------------------
    (lib.mkIf (cfg.ghStackSkill.enable && cfg.ghStackSkill.package != null) {
      # Upstream's own skill, read out of the package so it always matches the
      # extension binary built from the same source.
      cjlarose.llmAgents.skills."gh-stack" =
        "${cfg.ghStackSkill.package}/share/gh-stack/skill/SKILL.md";
    })

    # --- git-surgeon --------------------------------------------------------
    (lib.mkIf (cfg.gitSurgeon.enable && cfg.gitSurgeon.package != null) {
      # Binary and skill together, out of one package, so the documented
      # subcommands and flags always match the build that is installed.
      home.packages = [ cfg.gitSurgeon.package ];

      # Upstream nests its skill one level deeper than the other two tools we
      # read a SKILL.md out of: share/git-surgeon/skills/<name>/SKILL.md, not
      # share/<tool>/skill/SKILL.md. Irrelevant to the installed name, which
      # comes from the attribute key -- see cjlarose.llmAgents.skills.
      cjlarose.llmAgents.skills."git-surgeon" =
        "${cfg.gitSurgeon.package}/share/git-surgeon/skills/git-surgeon/SKILL.md";
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

      # The registration half. Merges into the settings attrset defined in the
      # unconditional Claude block above. Kept in sync with the script by the
      # VERSION=7 assertion in herdrIntegrations.
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
      cjlarose.llmAgents.skills."herdr" = "${herdrSkill}/SKILL.md";
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
    # The programs.llmWiki definition itself lives in ./wiki-bridge.nix, which
    # the consumer imports next to the wiki flake's module. It cannot live here:
    # mkIf distributes down to the attribute path, so a `programs.llmWiki`
    # definition under a false mkIf is still checked against the declarations
    # and errors with "option does not exist" on every wiki-less host.
    # Every enable that needs a package asserts it rather than defaulting one, so
    # a host that leaves the feature off never has to name a package at all.
    {
      assertions = [
        {
          assertion = !cfg.wiki.enable || cfg.wiki.path != null;
          message = "cjlarose.llmAgents.wiki.enable is true but cjlarose.llmAgents.wiki.path is unset.";
        }
        {
          assertion = !cfg.superpowers.enable || cfg.superpowers.src != null;
          message = "cjlarose.llmAgents.superpowers.enable is true but cjlarose.llmAgents.superpowers.src is unset.";
        }
        {
          assertion = !cfg.lavish.enable || cfg.lavish.package != null;
          message = "cjlarose.llmAgents.lavish.enable is true but cjlarose.llmAgents.lavish.package is unset.";
        }
        {
          assertion = !cfg.opencode.enable || cfg.opencode.package != null;
          message = "cjlarose.llmAgents.opencode.enable is true but cjlarose.llmAgents.opencode.package is unset.";
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
