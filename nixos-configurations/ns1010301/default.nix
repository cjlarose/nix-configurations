{ home-manager, stateVersion, additionalPackages, system, impermanence, disko, determinate, microvm, picktrace-nix-configurations, self, ... }: {
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
          # llm-wiki-path is deliberately unset: the wiki migrated to Basic
          # Memory, so the `wiki` Claude Code plugin, its SessionStart index
          # hook and LLM_WIKI_PATH all go away with it. Leaving it null also
          # drops the wiki flake's own module and the bridge that reads it.
          # Basic Memory replaces the whole arrangement, wired below.
          ((import ../../home/cjlarose) {
            inherit system stateVersion additionalPackages;
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
        # Basic Memory, replacing the hand-rolled LLM wiki. Registered once via
        # programs.mcp.servers, which reaches Claude Code and opencode alike.
        # Scoped to this host rather than home/cjlarose: it is the only one with
        # the knowledge base on disk, and the headless guests have no use for an
        # embedding model.
        #
        # ~/basic-memory rather than ~/repos: a daemon-written document store is
        # not a source checkout, and moving it out means the read-only rule for
        # ~/repos needs no exception carved out of it.
        cjlarose.llmAgents.basicMemory = {
          enable = true;
          package = additionalPackages.${system}.basic-memory;
          projects.personal.path = "/home/cjlarose/basic-memory/personal";
          defaultProject = "personal";
          # Replaces the wiki's `wiki:handing-off`. Basic Memory ships the
          # pieces but chains none of them, and the durable-knowledge versus
          # in-flight-state split is the judgement worth writing down.
          handoffSkill.enable = true;
        };
        # Upstream lavish-axi CLI (built from source, telemetry off) + its Lavish
        # Editor Claude skill. Scoped to this interactive/browser host (not the
        # shared profile, which fans out to the headless cjlarose hosts that have
        # no use for a browser review tool).
        cjlarose.llmAgents.lavish = {
          enable = true;
          package = additionalPackages.${system}.lavish-axi;
        };
      };
    }
  ];
}
