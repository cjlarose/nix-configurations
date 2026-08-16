# ai-memory (akitaonrails/ai-memory) -- local-first session memory for coding
# agents, wired declaratively for BOTH harnesses.
#
# On a two-week parallel trial against the llm-wiki. Nothing here touches the
# wiki; the two run side by side and the trial is judged on evidence.
#
# The trial began asking whether a TASK-shaped project is a useful unit of
# memory -- one ai-memory project per ~/workspaces/<task>/ directory, with
# default_global recall reading across them. That is NOT what this ships. The
# design does not survive contact with the MCP surface: cross-task recall is
# delivered only by the MCP tools, and those same tools resolve an omitted scope
# through a single process-wide "active project" pointer, which concurrent
# agents in different task dirs overwrite for each other. A single pinned
# project gets the same read reach with that whole class removed. The reasoning,
# and what it costs, is on the `marker.project` option.
#
# Split into its own file rather than folded into default.nix, like
# git-conventions.nix and github-conventions.nix: it owns a systemd user
# service, two harnesses' hook wiring and three generated config files, which is
# more than a `*.package` option's worth of surface. It is auto-imported from
# default.nix's `imports`, so a consumer needs only the enable.
#
# ============================================================================
# Why the hooks are rendered in a build sandbox rather than installed
# ============================================================================
#
# Upstream's documented install is imperative:
#
#     ai-memory install-hooks --agent claude-code --apply
#     ai-memory install-hooks --agent opencode    --apply
#
# Neither can run against this home. `--apply` for claude-code merges into
# ~/.claude/settings.json, which is a symlink into the read-only store
# (programs.claude-code.settings); the write fails with EROFS. The opencode half
# would succeed, and that is worse -- it would drop an unmanaged, unpinned file
# into a config tree home-manager otherwise owns, which the next generation
# would neither update nor remove.
#
# So the SAME renderer runs inside a build sandbox against a scratch HOME and
# this module takes its output. This is exactly the herdrIntegrations pattern in
# default.nix, and it is the reason a hook payload here can never document a
# protocol the installed binary does not speak: both come out of one derivation
# built from one pin.
#
# The claude half needs one extra step. Its payload has to reach
# programs.claude-code.settings.hooks as a Nix VALUE, and reading it back out of
# the derivation would mean readFile on a build output -- import-from-derivation
# in every home-manager eval. So the payload is hand-written below as
# `claudeHooks`, and the sandbox DIFFS the renderer's own output against it.
# Any drift -- a new lifecycle event, a changed flag, a different command shape
# -- fails the build with the diff on stderr. That is strictly stronger than the
# version-string grep herdrIntegrations uses: it compares the whole payload
# rather than trusting a constant to be bumped honestly.
{ lib, pkgs, config, ... }:

let
  cfg = config.cjlarose.llmAgents.aiMemory;

  # Only meaningful when there is a harness to hook. Both blocks below guard on
  # the relevant harness individually as well; this is the "is any of this worth
  # rendering" test.
  enabled = cfg.enable && cfg.package != null;

  # Upstream's vendored hook scripts, shipped in the package's own share/ --
  # see packages/ai-memory. install-hooks defaults to a compiled-in
  # /usr/local/share/ai-memory/hooks that does not exist on NixOS, so the
  # renderer below names this explicitly.
  #
  # Note these scripts are NOT what the installed hooks run. On a native
  # platform Claude Code gets a direct `ai-memory hook --event ...` command (see
  # hookCommand); the scripts are the portable fallback, and install-hooks
  # stages a copy into the data dir as a side effect. Pointing --hooks-dir at
  # the store is what stops it reaching for /usr/local during the render.
  hooksDir = "${cfg.package}/share/ai-memory/hooks";

  # The nine Claude Code lifecycle events ai-memory captures, mapped to the
  # kebab-case name each is passed to `hook --event` as -- upstream's own
  # CLAUDE_CODE_EVENTS table (render_shared.rs), in its order. Transcribed
  # rather than derived from a naming rule: this table is one side of the diff
  # guard below, and a rule that happened to reproduce a renamed event would
  # defeat the check it exists for. If upstream adds a tenth event, the build
  # fails here rather than the fleet silently capturing less.
  claudeEvents = {
    SessionStart = "session-start";
    UserPromptSubmit = "user-prompt-submit";
    PreToolUse = "pre-tool-use";
    PostToolUse = "post-tool-use";
    PreCompact = "pre-compact";
    Stop = "stop";
    SessionEnd = "session-end";
    # Subagent boundaries, so the server can drop a whole nested session's
    # captures when a subagent ends rather than leaving them attributed to the
    # parent.
    SubagentStart = "subagent-start";
    SubagentStop = "subagent-stop";
  };

  # The hook command install-hooks renders for a native POSIX install: the
  # binary itself, not a shell script and not an env-var preamble. Claude Code
  # does not honour an `env` field on a hook entry, so everything the hook needs
  # arrives as argv.
  #
  # --data-dir is baked in, and that is the whole reason cfg.dataDir is an
  # explicit absolute path rather than something resolved from XDG at runtime:
  # the daemon resolves its data dir under systemd's environment and each hook
  # would resolve it again under an interactive shell's. Naming one path here
  # makes them agree by construction.
  #
  # No --auth-token: the server is loopback-bound and tokenless for the trial
  # (see the service below). Adding auth means adding it on both sides at once,
  # and the diff guard catches a payload that has it on only one.
  hookCommand = event:
    "${cfg.package}/bin/ai-memory"
    + " --data-dir ${cfg.dataDir}"
    + " hook --event ${event}"
    + " --agent claude-code"
    + " --server-url ${cfg.serverUrl}";

  # The value that goes into programs.claude-code.settings.hooks. An empty
  # matcher means "every event of this kind", which is right for capture hooks:
  # every prompt, every tool call, every session boundary.
  claudeHooks = lib.mapAttrs
    (_name: event: [{
      matcher = "";
      hooks = [{
        type = "command";
        command = hookCommand event;
      }];
    }])
    claudeEvents;

  # home.file target for the marker. Kept out of the config block because the
  # empty-relativeDir case ($HOME itself) must not produce "/.ai-memory.toml",
  # which home-manager would install at the filesystem root's name under $HOME.
  markerTarget =
    if cfg.marker.relativeDir == ""
    then ".ai-memory.toml"
    else "${cfg.marker.relativeDir}/.ai-memory.toml";

  # The MCP endpoint. install-mcp appends /mcp to a base URL; done here so the
  # hand-written entries below and the sandbox render agree by construction.
  mcpUrl = "${cfg.serverUrl}/mcp";

  # Claude Code's entry: `type = "http"`, the native remote-MCP shape. No
  # command, no args -- nothing is spawned.
  claudeMcp = { type = "http"; url = mcpUrl; };

  # opencode spells the same thing `remote`, and carries an explicit enabled
  # flag. Upstream emits all three keys; the diff guard holds us to that.
  opencodeMcp = { type = "remote"; url = mcpUrl; enabled = true; };

  # What the renderer must agree with, in the shape each installer emits it.
  claudeExpected = pkgs.writeText "ai-memory-claude-hooks-expected.json"
    (builtins.toJSON { hooks = claudeHooks; });

  claudeMcpExpected = pkgs.writeText "ai-memory-claude-mcp-expected.json"
    (builtins.toJSON { mcpServers.ai-memory = claudeMcp; });

  opencodeMcpExpected = pkgs.writeText "ai-memory-opencode-mcp-expected.json"
    (builtins.toJSON { mcp.ai-memory = opencodeMcp; });

  # Run upstream's own renderer in a sandbox and take what it produces.
  #
  # `--config-file` points each agent at a scratch path, so nothing is merged
  # into (or read from) a real config: the claude output is ai-memory's hooks
  # ALONE, which is what makes the diff below a clean comparison rather than a
  # search through unrelated keys.
  #
  # Everything is rendered in the BUILD DIRECTORY and only the wanted files are
  # copied into $out. `--apply` writes a `.bak-<unix-timestamp>` next to any
  # file it mutates, and a timestamped filename in a derivation output is not
  # reproducible -- two builds of the same input would differ. Rendering aside
  # and copying deliberately is what keeps $out a function of its inputs.
  #
  # Lazy, like the herdr derivations in default.nix: only forced from a config
  # block that has already checked package != null.
  renderedHooks = pkgs.runCommand "ai-memory-hooks"
    {
      nativeBuildInputs = [ pkgs.jq ];
      meta.description = "ai-memory lifecycle hook payloads, rendered from the pinned binary";
    }
    ''
      export HOME=$PWD/home
      mkdir -p $HOME work $out

      # --- Claude Code -----------------------------------------------------
      # Rendered only to be CHECKED. The value home-manager actually installs is
      # the Nix-authored claudeHooks above, because reaching into a derivation
      # output for it would be import-from-derivation on every eval.
      echo '{}' > work/claude-settings.json
      ${cfg.package}/bin/ai-memory --data-dir ${cfg.dataDir} install-hooks \
        --agent claude-code \
        --apply \
        --hooks-dir ${hooksDir} \
        --server-url ${cfg.serverUrl} \
        --config-file work/claude-settings.json \
        >/dev/null

      # Sorted keys on both sides: the renderer preserves insertion order
      # (serde_json is built with preserve_order) while builtins.toJSON sorts,
      # so an unsorted diff would fire on ordering alone.
      jq -S '{hooks}' work/claude-settings.json > actual.json
      jq -S '.'       ${claudeExpected}         > expected.json

      if ! diff -u expected.json actual.json > payload.diff; then
        echo "" >&2
        echo "ai-memory's Claude Code hook payload has changed." >&2
        echo "" >&2
        echo "The hand-written claudeHooks in llm-agents/ai-memory.nix no longer" >&2
        echo "matches what this ai-memory renders. It is hand-written to avoid" >&2
        echo "import-from-derivation; re-derive it from the diff below rather" >&2
        echo "than deleting this check." >&2
        echo "" >&2
        echo "  - expected (what this module installs)" >&2
        echo "  + actual   (what ai-memory ${cfg.package.version} renders)" >&2
        echo "" >&2
        cat payload.diff >&2
        exit 1
      fi

      # --- OpenCode ---------------------------------------------------------
      # No hand-written half and no diff: this one is a whole generated
      # TypeScript file, installed verbatim as a store symlink, so there is
      # nothing for it to drift from. It is a self-contained plugin -- its only
      # import is `type { Plugin }`, erased at load -- so no node_modules and no
      # runtime fetch.
      ${cfg.package}/bin/ai-memory --data-dir ${cfg.dataDir} install-hooks \
        --agent opencode \
        --apply \
        --server-url ${cfg.serverUrl} \
        --config-file $out/opencode-plugin.ts \
        >/dev/null

      # An empty or missing plugin would install silently and capture nothing,
      # which is the failure mode hardest to notice on a memory tool: sessions
      # look normal and the wiki just stays empty.
      test -s $out/opencode-plugin.ts || {
        echo "ai-memory rendered no opencode plugin" >&2
        exit 1
      }
      grep -q '${cfg.serverUrl}' $out/opencode-plugin.ts || {
        echo "the opencode plugin does not point at ${cfg.serverUrl}" >&2
        exit 1
      }

      # --- MCP entries, both harnesses -------------------------------------
      # Same treatment as the claude hook payload: rendered here only to be
      # CHECKED against the hand-written Nix values, which are what
      # home-manager actually installs.
      checkMcp() {
        client="$1"; scratch="$2"; expected="$3"; filter="$4"

        echo '{}' > "$scratch"
        ${cfg.package}/bin/ai-memory --data-dir ${cfg.dataDir} install-mcp \
          --client "$client" \
          --apply \
          --server-url ${cfg.serverUrl} \
          --config-file "$scratch" \
          >/dev/null

        jq -S "$filter" "$scratch"  > "actual-$client.json"
        jq -S '.'       "$expected" > "expected-$client.json"

        if ! diff -u "expected-$client.json" "actual-$client.json" > "$client.diff"; then
          echo "" >&2
          echo "ai-memory's $client MCP entry has changed." >&2
          echo "" >&2
          echo "The hand-written value in llm-agents/ai-memory.nix no longer" >&2
          echo "matches what this ai-memory renders. Re-derive it from the" >&2
          echo "diff below rather than deleting this check." >&2
          echo "" >&2
          echo "  - expected (what this module installs)" >&2
          echo "  + actual   (what ai-memory ${cfg.package.version} renders)" >&2
          echo "" >&2
          cat "$client.diff" >&2
          exit 1
        fi
        cp "$scratch" "$out/$client-mcp.json"
      }

      checkMcp claude-code work/claude-mcp.json   ${claudeMcpExpected}   '{mcpServers}'
      checkMcp opencode    work/opencode-mcp.json ${opencodeMcpExpected} '{mcp}'
    '';

  tomlFormat = pkgs.formats.toml { };
in
{
  options.cjlarose.llmAgents.aiMemory = {
    enable = lib.mkEnableOption ''
      ai-memory: a local-first, git-backed session-memory server for coding
      agents, with lifecycle hooks for Claude Code and opencode, a ~13-tool MCP
      surface, and a read-only web browser over the wiki it builds.

      Runs as a loopback-only systemd user service in zero-LLM mode -- no
      provider, no API key, no outbound traffic, no billing. FTS5, entity and
      graph search, rule-based session summaries and auto-handoffs all work
      without one; see llmProvider below for why that is a floor rather than a
      default to relax casually.

      On a two-week trial. Enabling this changes nothing about the llm-wiki,
      which keeps running exactly as before
    '';

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        The ai-memory package: bin/ai-memory (CLI and daemon in one binary) plus
        upstream's vendored hook scripts at share/ai-memory/hooks. Required when
        enable is set.

        Both the daemon and the rendered hook payloads come from this one
        package, so the scripts can never speak a protocol the running server
        does not.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/ai-memory";
      description = ''
        Where ai-memory keeps everything: wiki/ (the git repo it commits into),
        db/memory.sqlite (derived and rebuildable from the wiki), raw/, logs/,
        models/, config.toml and auth.json.

        This is upstream's own default location -- dirs::data_local_dir() plus
        "ai-memory" -- named explicitly rather than left implicit ON PURPOSE.
        The daemon resolves it under systemd's environment and every hook
        resolves it again under an interactive shell's; if that resolution is
        left to XDG_DATA_HOME the two can silently disagree and the hooks spool
        to a directory the server never reads. Naming one absolute path makes
        the divergence unrepresentable.

        Deliberately NOT a scratch directory. The prior Basic Memory evaluation
        never created ~/.basic-memory and threw its index away; this trial is
        run at the real location so that a trial that goes well needs no
        migration to adopt.
      '';
    };

    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:49374";
      description = ''
        Base URL the hooks POST to and the MCP clients connect to; also what the
        service binds. Upstream's own default, restated here because it is baked
        into three generated artifacts and one systemd unit, and all four have
        to agree.

        Loopback only. The daemon has no auth token in this configuration, so
        the bind address IS the access control -- anything that can reach the
        port can read every captured session and, with --enable-web, browse the
        whole wiki. Changing this to a non-loopback address without also setting
        AI_MEMORY_AUTH_TOKEN publishes the user's session history to the
        network.
      '';
    };

    bind = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:49374";
      description = ''
        The address:port the daemon listens on. Upstream's default, restated
        because it is the only access control this configuration has -- see
        serverUrl, which must address the same socket.

        A separate option rather than something derived from serverUrl by
        string-munging the scheme off: the two are genuinely different values
        (one is a URL a client dials, one is a socket a server binds), and a
        regex between them would be a silent way to get a bind wrong.
      '';
    };

    enableWeb = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Mount the read-only wiki browser at /web, plus the read-only /api/v1
        frontend API.

        On by default here because it is the only legible view of what the tool
        has actually captured, and that is precisely what the trial has to
        judge: pages land at wiki/<workspace-uuid>/<project-uuid>/<page>.md, so
        UUID directories are what a plain `ls` shows. Safe only while the bind
        stays loopback -- see serverUrl.
      '';
    };

    workspace = lib.mkOption {
      type = lib.types.str;
      default = "default";
      example = "personal";
      description = ''
        ai-memory's outermost scope -- a "life context", above projects. The
        server takes this as the fallback for hook events that arrive with no
        usable cwd; the marker file below is what sets it for real work.
      '';
    };

    marker = {
      enable = lib.mkEnableOption ''
        the `.ai-memory.toml` marker that decides how sessions are scoped into
        projects.

        ai-memory scopes memory BY CWD, one project per session, resolved by
        walking up from the cwd to $HOME and taking the NEAREST marker. There is
        no per-file-path routing: with an agent started at ~/workspaces/<task>/,
        an edit under web-api/ and one under internal-operations/ land in the
        same project no matter which repo each file is in. That is not a setting
        -- it is the whole scoping model, and `project_strategy = "repo-root"`
        does not change it (it derives a project from the checkout the cwd is
        INSIDE, and a task dir is ABOVE several checkouts)

      '';

      relativeDir = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "workspaces";
        description = ''
          Directory the marker is written into, RELATIVE TO $HOME. The empty
          string (the default) means $HOME itself, which is the widest possible
          placement: resolution stops at $HOME, so a marker there is the
          backstop every session falls through to, whether it starts under
          ~/workspaces, ~/repos, or anywhere else.

          Relative because this is a home.file target, which is always
          home-relative -- an absolute path would install at
          $HOME/<the absolute path>.

          Narrow it (e.g. "workspaces") only to scope the marker to one subtree
          and let sessions outside it resolve differently.
        '';
      };

      project = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "cjlarose";
        description = ''
          Pin every session under this marker to ONE named project, instead of
          letting basename(cwd) make a project per directory.

          Null keeps upstream's default: project = basename(cwd), so each
          ~/workspaces/<task>/ becomes its own project. Setting a name collapses
          everything into a single bucket.

          The pin is what makes the MCP surface safe to enable here. The server
          keeps a "currently active project" pointer that MCP tools consult when
          a call omits workspace/project, and in the default `single` auto_scope
          mode that pointer is ONE process-wide slot. Upstream documents the
          consequence plainly: it "collapses parallel sessions ... a hook firing
          from ~/repo-A overwrites the slot that a concurrent memory_query (with
          no explicit project) in ~/repo-B was about to read" (docs/auto-scope.md).
          Running several agents at once across different task dirs -- the normal
          case here -- would therefore let one agent's unscoped write land in
          another's project. With one project there is no other project to
          resolve to, so the whole class is gone by construction, and neither
          `[auto_scope] mode = "per_session"` nor an `install-mcp --session-aware`
          stdio bridge is needed.

          What the pin does NOT cost: automatic session-resume. SessionEnd
          handoffs are selected by cwd PATH BOUNDARY, not by project
          (`auto_handoff_matches_cwd` -> `cwd_within`), so a session starting in
          ~/workspaces/task-B still receives task-B's baton and not the most
          recent one from anywhere. Only MANUAL handoffs (memory_handoff_begin,
          which sets from_session_id = None) are project-wide "whatever cwd they
          carry" and would cross tasks.

          What it does cost: the ability to scope a query to one task, and
          per-project consolidation/decay. Retrieval leans on FTS5, tags and the
          entity index instead of on scope.
        '';
      };

      defaultGlobalRecall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Set [recall] default_global, which upstream documents for "meta-repos
          that constantly need sibling-project context": an unscoped
          memory_query behaves as global=true, and memory_recent returns recent
          pages across every project, each hit annotated with its workspace and
          project.

          Only meaningful WITHOUT a pinned `project` -- it is what would make a
          per-task layout survivable, by letting reads span every task while
          writes stay task-scoped. With a single pinned project there are no
          sibling projects to reach, so it is dead config; the assertion below
          rejects the combination rather than letting it read as if it did
          something.

          Note it is consumed ONLY by the MCP tools (memory_query,
          memory_recent). The hook router publishes the flag and never reads it,
          so on a hooks-only install this setting has no effect at all.
        '';
      };
    };

    enableMcp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Register ai-memory's MCP server with each enabled harness, giving the
        agent the ~13 memory_* tools: memory_query, memory_recent,
        memory_write_page, memory_briefing, memory_handoff_*, memory_lint and
        the rest.

        This is the difference between a memory the agent can USE and one it
        merely feeds. Hooks alone capture everything and inject a handoff at
        session start, but the agent cannot ask a question mid-task or record
        something deliberately -- and `[recall] default_global` is read only by
        the MCP tools, so on a hooks-only install that marker key does nothing.

        A plain HTTP entry, not the `install-mcp --session-aware` stdio bridge.
        The bridge exists to forward a lifecycle session id so
        `[auto_scope] mode = "per_session"` can key the active-project pointer
        per session; that is only needed when concurrent sessions can resolve to
        DIFFERENT projects. With marker.project pinned it is redundant -- see
        that option.
      '';
    };

    requireScopedMcp = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Refuse to build when MCP is enabled on a per-task project layout
        (marker.project = null), which is the combination that exposes the
        active-project collision documented in upstream's docs/auto-scope.md.

        On by default because that combination is safe in a single session and
        silently wrong with concurrent agents -- the failure is a page filed
        under the wrong task, which looks like nothing at all until you go
        looking for it. Set false to take the risk knowingly (e.g. after moving
        the server to `[auto_scope] mode = "per_session"` and installing the
        session-aware stdio bridge, which this module does not wire).
      '';
    };

    llmProvider = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "anthropic";
      description = ''
        AI_MEMORY_LLM_PROVIDER, or null for zero-LLM mode.

        Null on purpose, and the trial starts here: rule-based session summaries
        and auto-handoffs, FTS5, entity and graph search all work with no
        provider, no key, no outbound traffic and no bill. Reach for a provider
        only if the trial specifically shows rule-based summaries are the
        limiting factor -- that is a finding to record, not a default to relax.

        Never set this to `anthropic-oauth`. That mode borrows a Claude
        subscription's OAuth credentials for API calls, which ai-memory's OWN
        documentation calls against Anthropic's usage policies. An API key is
        the supported path, at roughly $0.01-0.05 per session against a bounded
        6,500-in / 1,000-out budget.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf enabled {
      # The CLI on PATH: `ai-memory curator`, `ai-memory show`, and the status
      # and backup subcommands are all things a human runs at the keyboard
      # during the trial, not just things the hooks call.
      home.packages = [ cfg.package ];

      # The daemon. One process owns the data dir -- the Wiki holds a
      # mutation_lock and bootstrap is mutex-serialised -- so Claude Code and
      # opencode can both write through it concurrently and safely. A user
      # service rather than a system one because the wiki it commits into is
      # this user's, and so is every session it captures.
      systemd.user.services.ai-memory = {
        Unit = {
          Description = "ai-memory session-memory server (loopback, zero-LLM)";
          Documentation = "https://github.com/akitaonrails/ai-memory";
        };
        Service = {
          Type = "simple";
          # --bind restated rather than left to the config default: loopback is
          # the ONLY access control here (no auth token), so it should not be
          # possible for a changed default to widen it silently.
          ExecStart = lib.concatStringsSep " " ([
            "${cfg.package}/bin/ai-memory"
            "--data-dir ${cfg.dataDir}"
            "serve"
            "--transport http"
            "--bind ${cfg.bind}"
            "--workspace ${cfg.workspace}"
          ] ++ lib.optional cfg.enableWeb "--enable-web");
          Restart = "on-failure";
          RestartSec = "5s";
          # Upstream's own unit sets both. Cheap, and this process reads a git
          # repo full of the user's work.
          NoNewPrivileges = true;
          PrivateTmp = true;
        };
        Install.WantedBy = [ "default.target" ];
      };
    })

    # --- the marker that decides project scoping -----------------------------
    # Written through home.file so it is a store symlink like everything else:
    # the point of the trial is to judge the tool, and a hand-edited marker
    # drifting from what this module says would make the result unattributable.
    (lib.mkIf (enabled && cfg.marker.enable) {
      home.file.${markerTarget}.source =
        tomlFormat.generate "ai-memory-marker.toml" ({
          workspace = cfg.workspace;
        } // lib.optionalAttrs (cfg.marker.project != null) {
          project = cfg.marker.project;
        } // lib.optionalAttrs cfg.marker.defaultGlobalRecall {
          # A real TOML boolean. Upstream's docs show the quoted `"true"`
          # spelling, but its marker reader (marker.rs, parse_toml_flag) strips
          # surrounding quotes and then applies shell-parity truthiness over
          # 1/true/yes/on -- so both spellings resolve identically, and this is
          # the one pkgs.formats.toml emits naturally.
          recall.default_global = true;
        });
    })

    # --- MCP: the agent-facing surface ---------------------------------------
    # Both harnesses get a plain HTTP entry pointed at the same loopback server
    # the hooks POST to. Nothing is stdio-bridged and nothing is spawned per
    # session -- see enableMcp and marker.project for why the session-aware
    # bridge is unnecessary once the project is pinned.
    #
    # Hand-written on both sides and diffed against upstream's own renderer in
    # the sandbox, exactly like the claude hook payload: these are Nix values
    # that have to reach home-manager options, and reading them out of a
    # derivation would be import-from-derivation on every eval.
    (lib.mkIf (enabled && cfg.enableMcp && config.cjlarose.llmAgents.claude.enable) {
      # Merges with the playwright entry default.nix defines under
      # claude.enablePlaywrightMcp; home-manager surfaces the union as a
      # generated .mcp.json wired on via --plugin-dir.
      programs.claude-code.mcpServers.ai-memory = claudeMcp;
    })

    (lib.mkIf (enabled && cfg.enableMcp && config.cjlarose.llmAgents.opencode.enable) {
      # opencode's own native config key, same shape as the superpowers
      # skills.paths entry already set in default.nix -- not a plugin.
      # `type = "remote"` is opencode's spelling for an HTTP MCP server, and it
      # works against ai-memory's stateless transport with no mcp-remote shim.
      programs.opencode.settings.mcp.ai-memory = opencodeMcp;
    })

    # --- Claude Code ---------------------------------------------------------
    # Merges into the settings attrset default.nix defines under claude.enable,
    # exactly as the herdr SessionStart registration does. Note both this and
    # herdr define settings.hooks.SessionStart; home-manager merges the two
    # lists, and Claude Code runs every registered SessionStart hook, so they
    # coexist rather than one winning.
    (lib.mkIf (enabled && config.cjlarose.llmAgents.claude.enable) {
      programs.claude-code.settings.hooks = claudeHooks;

      # This is what makes the diff guard actually RUN on a claude-only host.
      #
      # The payload above is a plain Nix value and mentions renderedHooks
      # nowhere, so nothing else here would put that derivation in the
      # generation's closure -- and a derivation that is never realised never
      # checks anything. (`builtins.seq` does not help: it forces the
      # derivation to weak head normal form, i.e. evaluates it, which is not
      # the same as building it.) Referencing an output file as a home.file
      # source is what pulls it into the closure and forces the build.
      #
      # It is worth installing on its own account too: it is the renderer's
      # verbatim output, so it is the thing to read when asking what ai-memory
      # believes it registered, without re-running anything.
      home.file.".claude/hooks/ai-memory-rendered-payload.json".source =
        "${renderedHooks}/claude-settings.json";
    })

    # --- opencode ------------------------------------------------------------
    # A generated plugin file, installed verbatim. opencode scans
    # ~/.config/opencode/plugins/ at startup and home-manager's programs.opencode
    # does not manage that directory, so there is nothing to collide with -- and
    # nothing to register either.
    #
    # opencode must be RESTARTED to pick up a changed plugin; a home-manager
    # switch alone will not do it.
    (lib.mkIf (enabled && config.cjlarose.llmAgents.opencode.enable) {
      xdg.configFile."opencode/plugins/ai-memory.ts".source =
        "${renderedHooks}/opencode-plugin.ts";
    })

    {
      assertions = [
        {
          assertion = !cfg.enable || cfg.package != null;
          message = "cjlarose.llmAgents.aiMemory.enable is true but cjlarose.llmAgents.aiMemory.package is unset.";
        }
        {
          # The whole point of the trial configuration. A provider is a
          # deliberate, recorded decision; anthropic-oauth is never one.
          assertion = cfg.llmProvider != "anthropic-oauth";
          message = ''
            cjlarose.llmAgents.aiMemory.llmProvider is set to "anthropic-oauth",
            which borrows a Claude subscription's OAuth credentials for API
            calls. ai-memory's own documentation calls that against Anthropic's
            usage policies. Use an API key provider, or leave it null for
            zero-LLM mode.
          '';
        }
        {
          # Two settings that cancel each other out. default_global broadens an
          # unscoped read to every SIBLING project; a pinned project means there
          # are none, so the combination reads as if recall were configured when
          # nothing is. Reject it rather than let it sit in the marker looking
          # load-bearing.
          assertion = !(cfg.marker.project != null && cfg.marker.defaultGlobalRecall);
          message = ''
            cjlarose.llmAgents.aiMemory.marker sets both `project` (pinning every
            session to one project) and `defaultGlobalRecall` (broadening
            unscoped reads across projects). With a single project there are no
            other projects to reach, so default_global is dead config. Drop one:
            keep the pin for a single bucket, or drop it for per-task projects
            with global recall.
          '';
        }
        {
          # Enabling MCP on a per-task layout is the one combination that walks
          # into the active-project collision upstream documents. It is not
          # wrong in a single-agent session, so this is a WARNING's job, not an
          # assertion's -- but the module has no warnings channel, and silently
          # shipping it would defeat the reasoning in marker.project.
          assertion = !(cfg.enableMcp && cfg.marker.enable && cfg.marker.project == null
            && config.cjlarose.llmAgents.aiMemory.requireScopedMcp);
          message = ''
            cjlarose.llmAgents.aiMemory enables MCP with per-task projects
            (marker.project = null). The server's active-project pointer is one
            process-wide slot in the default `single` auto_scope mode, so with
            concurrent agents in different task dirs an unscoped memory_query or
            memory_write_page can resolve to another session's project --
            upstream documents this in docs/auto-scope.md.

            Pick one: set marker.project to pin a single project (simplest), or
            set requireScopedMcp = false to accept the risk deliberately, or
            turn enableMcp off.
          '';
        }
        {
          # Loopback is the only access control here. Catch the combination that
          # publishes session history rather than trusting a reviewer to notice.
          assertion = !cfg.enable
            || lib.hasPrefix "http://127.0.0.1:" cfg.serverUrl
            || lib.hasPrefix "http://localhost:" cfg.serverUrl
            || lib.hasPrefix "http://[::1]:" cfg.serverUrl;
          message = ''
            cjlarose.llmAgents.aiMemory.serverUrl is not a loopback address.
            This configuration runs the daemon with no auth token, so the bind
            address is the only thing keeping captured sessions and the whole
            wiki off the network. Set AI_MEMORY_AUTH_TOKEN and front it with TLS
            before relaxing this.
          '';
        }
      ];
    }
  ];
}
