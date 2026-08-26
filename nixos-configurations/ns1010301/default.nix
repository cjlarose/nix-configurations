{ home-manager, stateVersion, additionalPackages, system, impermanence, disko, determinate, microvm, picktrace-nix-configurations, cjlarose-llm-wiki, self, ... }: {
  imports = [
    microvm.nixosModules.host
    ({ ... }: {
      microvm.vms."pt-docker-cjlarose" = {
        flake = picktrace-nix-configurations;
      };
      microvm.vms."minecraft-mellowcatfe" = {
        flake = self;
      };
      microvm.vms."media" = {
        flake = self;
      };
      microvm.vms."hermes" = {
        flake = self;
      };
      microvm.autostart = [ "pt-docker-cjlarose" "minecraft-mellowcatfe" "media" "hermes" ];
    })
    determinate.nixosModules.default
    (import ./disk-config.nix { inherit disko; })
    ./configuration.nix
    ({ pkgs, config, ... }: {
      imports = [
        impermanence.nixosModules.impermanence
      ];
      environment.persistence = {
        "/persistence" = {
          hideMounts = true;
          directories = [
            {
              directory = "/var/lib/tailscale";
              user = "root";
              group = "root";
              mode = "0700";
            }
            {
              directory = "/var/cache/restic-backups-minecraft-mellowcatfe";
              user = "root";
              group = "root";
              mode = "0755";
            }
            {
              directory = "/var/lib/acme";
              user = "acme";
              group = "acme";
              mode = "0755";
            }
          ];
        };
      };
    })
    home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      # dev-tools now manages ~/.config/gh/config.yml via programs.gh, and gh
      # has already written its own default one here; without a backup
      # extension activation hard-fails on "existing file is in the way". The
      # displaced file is pure gh defaults, so nothing is lost. Same setting
      # immich and the darwin host already use.
      home-manager.backupFileExtension = "hm-backup";
      home-manager.users.cjlarose = {
        imports = [
          ((import ../../home/cjlarose) {
            inherit system stateVersion additionalPackages;
            # Browser automation for cjlarose's sessions on this host: register
            # the Playwright MCP with Claude Code. The shared home/cjlarose
            # profile leaves this off so the chromium closure only lands where
            # it's wanted; scope the enable to ns1010301 here (it fans out to
            # every linux host otherwise).
            enablePlaywrightMcp = true;
            llm-wiki-path = "/home/cjlarose/repos/cjlarose/llm-wiki";
            # The wiki flake input's skills/ tree; llm-agents reads the
            # read-only querying-notes SKILL.md out of it and installs it into
            # ~/.claude/skills (both harnesses). Replaces the old
            # homeManagerModules.default import, which shipped it as a
            # claude-only plugin opencode could not see.
            llm-wiki-skill-src = "${cjlarose-llm-wiki}/skills";
          })
        ];
        # ns1010301 is the trial host for the ~/repos + ~/workspaces layout:
        # ~/repos/<owner>/<repo> holds a read-only checkout of each repo's
        # default branch, named for the canonical owner, and all writing
        # happens in per-task ~/workspaces/<task>/ directories holding one
        # linked worktree per repo. Both roots are two levels deep, unlike
        # ~/worktrees/<owner>/<repo>/<worktree>. Scoped here rather than in
        # home/cjlarose (which fans out to every linux host) so the other
        # cjlarose hosts keep the old layout while this is a trial.
        cjlarose.neovim.projectWorkspaces = [ "~/repos" "~/workspaces" ];
        cjlarose.neovim.projectMaxDepth = 2;
        cjlarose.llmAgents.claude.workspaceLayout.enable = true;
        # Commit-message conventions, and the GitHub ones separately -- this
        # host does both, but they are independent modules because a commit
        # message is git's artifact and a PR description is GitHub's.
        #
        # No extraInstructions on either: this host has no issue tracker to
        # link, and it wants the model disclosure the skills already default to.
        # It is picktrace that has to ban it, and only on PR descriptions.
        cjlarose.llmAgents.gitConventions.enable = true;
        cjlarose.llmAgents.githubConventions.enable = true;
        # Upstream lavish-axi CLI (built from source, telemetry off) + its Lavish
        # Editor Claude skill. Scoped to this interactive/browser host (not the
        # shared profile, which fans out to the headless cjlarose hosts that have
        # no use for a browser review tool).
        # Serve its review UI over tailscale with real TLS. lavish speaks only
        # plain HTTP, and the whole .dev TLD is HSTS-preloaded, so a browser
        # force-upgrades any lavish.ns1010301.cjlarose.dev request to https --
        # which a bare http lavish can't answer. So lavish binds loopback ONLY
        # (host = null) and a TLS-terminating nginx vhost on this host's tailscale
        # IP fronts it (see configuration.nix): browser -> nginx :443 (LE DNS-01
        # cert) -> http://127.0.0.1:4387. linkHost both names the printed link
        # and authorizes that name in lavish's DNS-rebinding guard (the Host
        # nginx forwards), so no separate allowedHosts is needed; linkScheme +
        # linkPort make the printed session links the clean https URL with no
        # port (nginx serves 443, the scheme default) -- these need the
        # reverse-proxy patch in packages/lavish-axi; port is pinned
        # so nginx's proxy_pass and the loopback bind stay in lockstep. The
        # firewall in configuration.nix now opens 443 on tailscale0 (not 4387) --
        # the public path stays closed.
        cjlarose.llmAgents.lavish = {
          enable = true;
          package = additionalPackages.${system}.lavish-axi;
          host = null; # loopback-only; nginx is the only reachable front
          linkHost = "lavish.ns1010301.cjlarose.dev";
          linkScheme = "https"; # nginx terminates TLS
          linkPort = ""; # omit the port; nginx serves the scheme default (443)
          port = 4387;
        };
        # The soliciting-pr-feedback skill and its mock-pr-html renderer, which
        # drive lavish above to review a change as a GitHub PR before it is
        # opened or pushed to. Paired with lavish here because it needs it.
        cjlarose.llmAgents.prFeedback.enable = true;
        # The rebuild-ns1010301 runbook, as a host-scoped Claude Code skill:
        # how to rebuild this host and bring its microvm guests forward without
        # rebooting them, including the cross-repo bump ceremony for a
        # pt-docker-cjlarose change that lands in picktrace/nix-configurations.
        # Installed straight into ~/.claude/skills (both harnesses read it there)
        # from the source tree beside this file. Host-scoped here rather than in
        # the shared llm-agents module because it hard-codes this host's guests,
        # bridge IPs and attribute paths -- it makes sense on no other host.
        home.file.".claude/skills/rebuild-ns1010301".source =
          ./skills/rebuild-ns1010301;
        # ai-memory, on a two-week parallel trial against the llm-wiki. Scoped
        # to this host and no further: it is the trial host for the
        # ~/repos + ~/workspaces layout above, and the marker below only makes
        # sense where that layout exists. The wiki is untouched -- the two run
        # side by side and the trial is judged on evidence, not on switching.
        #
        # Everything else stays at the module's defaults, which ARE the trial
        # configuration: loopback bind, no auth token, no LLM provider, and
        # upstream's own ~/.local/share/ai-memory data dir rather than a scratch
        # one, so a trial that goes well needs no migration to adopt.
        cjlarose.llmAgents.aiMemory = {
          enable = true;
          package = additionalPackages.${system}.ai-memory;
          workspace = "personal";
          # One marker at $HOME, pinning every session to a single project.
          #
          # This deliberately drops the per-task-project idea the trial started
          # with (each ~/workspaces/<task>/ its own project, plus default_global
          # recall to read across them). Two things decided it. The read half of
          # that design is delivered only by the MCP tools, and the write half
          # collides with them: the server keeps ONE process-wide "active
          # project" pointer in the default auto_scope mode, so concurrent
          # agents in different task dirs can have an unscoped write land in
          # each other's project (upstream's own docs/auto-scope.md). Pinning
          # one project removes that by construction -- there is no other
          # project to resolve to -- and gets the same cross-task read reach
          # that default_global was for, without the pointer machinery.
          #
          # Automatic session-resume survives the change: SessionEnd handoffs
          # are selected by cwd path boundary rather than by project, so
          # starting in ~/workspaces/<task>/ still gets that task's baton.
          #
          # At $HOME rather than ~/workspaces so it is the backstop for every
          # session, including ones started under ~/repos.
          marker = {
            enable = true;
            project = "cjlarose";
          };

          # The wiki lives on an orphan branch of the llm-wiki repo rather than
          # in a standalone repo of its own. Disjoint history, so ai-memory's
          # per-session commits never mix with the wiki's real history -- the
          # two share only an object store, one backup target, and one remote.
          #
          # Safe because ai-memory's git surface is append-only: it opens the
          # repo, commits to HEAD, and reads history. No set_head, reset,
          # checkout or remote anywhere in its wiki crate, so it cannot disturb
          # the main checkout.
          #
          # Only wiki/ is redirected; db/ (derived, rebuildable), raw/ and
          # logs/ stay local.
          wikiWorktree = {
            enable = true;
            repoPath = "/home/cjlarose/repos/cjlarose/llm-wiki";
          };

          # Nightly push, so the memory survives losing this machine.
          # ai-memory never pushes on its own -- git2::Remote is not constructed
          # anywhere in the tree -- so this is plain git on a timer.
          #
          # The key is named explicitly and must stay passphraseless: a timer
          # firing at 03:30 has no ssh-agent and no unlocked 1Password, and a
          # push that prompts would hang or fail with nothing watching.
          # cjlarose/llm-wiki is a PRIVATE repo, which is a precondition here
          # rather than a detail -- the branch carries captured session content.
          autoPush = {
            enable = true;
            sshKey = "/home/cjlarose/.ssh/id_ed25519";
            onCalendar = "*-*-* 03:30:00";
          };

          # Haiku for session summaries. Without a provider the summary is a
          # ledger -- tool counts by coarse class, and the opening prompt
          # restated under three headings -- which records that a session
          # happened rather than what came out of it.
          #
          # Haiku rather than a larger model because summarising one session is
          # small and bounded (upstream caps it around 6,500 in / 1,000 out),
          # so the cheapest current model is the right fit rather than a
          # compromise. Named explicitly so a provider-side default cannot move
          # the model, and the bill, without a change here.
          #
          # The key is NOT in this file, and must never be: everything nix
          # evaluates lands in the world-readable store. It is read at runtime
          # from the file below, which is created by hand, chmod 600, and not
          # in git -- the same shape as this fleet's other secrets.
          llm = {
            provider = "anthropic";
            model = "claude-haiku-4-5-20251001";
            environmentFile = "/home/cjlarose/.config/ai-memory/env";
          };
        };
      };
    }
  ];
}
