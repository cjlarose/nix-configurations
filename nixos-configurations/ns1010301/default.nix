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
            llm-wiki-path = "/home/cjlarose/repos/cjlarose/llm-wiki";
            llm-wiki-module = cjlarose-llm-wiki.homeManagerModules.default;
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
        # Browser automation for cjlarose's sessions on this host. The shared
        # home/cjlarose profile leaves enablePlaywrightMcp off so the chromium
        # closure only lands where it's wanted; scope the enable to ns1010301
        # here rather than in home/cjlarose (which fans out to every linux host).
        cjlarose.llmAgents.claude.enablePlaywrightMcp = true;
        # Upstream lavish-axi CLI (built from source, telemetry off) + its Lavish
        # Editor Claude skill. Scoped to this interactive/browser host (not the
        # shared profile, which fans out to the headless cjlarose hosts that have
        # no use for a browser review tool).
        cjlarose.llmAgents.lavish = {
          enable = true;
          package = additionalPackages.${system}.lavish-axi;
        };
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
          # The experiment itself: one marker at the root of ~/workspaces makes
          # each per-task directory its own project (writes stay task-scoped)
          # while default_global recall spans all of them (reads do not). The
          # question the trial answers is whether that task-shaped project is a
          # useful unit of memory or a pile of dead workspaces -- see the
          # option's description.
          workspacesMarker.enable = true;
        };
      };
    }
  ];
}
