{
  description = "NixOS-based development environment";

  inputs = {
    nixpkgs-24-05 = {
      url = "github:nixos/nixpkgs/nixos-24.05";
    };
    nixpkgs-24-11 = {
      url = "github:nixos/nixpkgs/nixos-24.11";
    };
    nixpkgs-25-05 = {
      url = "github:nixos/nixpkgs/nixos-25.05";
    };
    nixpkgs-25-11 = {
      url = "github:nixos/nixpkgs/nixos-25.11";
    };
    nixpkgs-26-05 = {
      url = "github:nixos/nixpkgs/nixos-26.05";
    };
    nixpkgs-unstable = {
      url = "github:nixos/nixpkgs/nixpkgs-unstable";
    };
    determinate = {
      url = "github:DeterminateSystems/determinate";
    };
    nix-minecraft = {
      url = "github:Infinidoge/nix-minecraft";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    tuicr = {
      # Dogfooding the `reverse` commit-list option (parent->child branch
      # review) from the commit-order-display-option branch before it's merged
      # to the fork's main / sent upstream. Revert to plain
      # "github:cjlarose/tuicr" once it lands.
      url = "github:cjlarose/tuicr/commit-order-display-option";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    llm-agents = {
      # numtide/llm-agents.nix -- AI-coding-agent tools packaged for nix and
      # auto-updated daily. Source of claude-code (rolls forward independently
      # of a nixpkgs-unstable bump), opencode, and git-surgeon; herdr used to
      # come from here too and now comes from its own upstream flake. Follows
      # nixpkgs-unstable, which is also what the flake pins upstream, so no
      # second nixpkgs subtree lands in the lock.
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    home-manager-25-05 = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs-25-05";
    };
    home-manager-25-11 = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs-25-11";
    };
    home-manager-26-05 = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-26-05";
    };
    fzfVim = {
      url = "github:cjlarose/fzf.vim";
      inputs.nixpkgs.follows = "nixpkgs-24-05";
    };
    fzfProject = {
      url = "github:cjlarose/fzf-project";
      inputs.nixpkgs.follows = "nixpkgs-24-05";
    };
    tfenv = {
      url = "github:cjlarose/tfenv-nix";
    };
    pce = {
      url = "git+ssh://git@github.com/cjlarose/pixel-cats-end-automation";
    };
    cs-automation = {
      url = "git+ssh://git@github.com/cjlarose/cs-automation";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs-24-05";
    };
    intranetHosts = {
      url = "git+ssh://git@github.com/cjlarose/intranet-hosts";
      flake = false;
    };
    omnisharpVim = {
      url = "github:OmniSharp/omnisharp-vim";
      flake = false;
    };
    trueColorTest = {
      url = "git+https://gist.github.com/db6c5654fa976be33808b8b33a6eb861.git";
      flake = false;
    };
    nvr = {
      url = "github:cstyles/nvr";
      flake = false;
    };
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs-25-11";
    };
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
    };
    picktrace-nix-configurations = {
      url = "git+ssh://git@github.com/picktrace/nix-configurations";
    };
    cjlarose-llm-wiki = {
      url = "git+ssh://git@github.com/cjlarose/llm-wiki";
      inputs.nixpkgs.follows = "nixpkgs-26-05";
    };
    harness-config = {
      # cjlarose/harness-config.nix -- reusable Claude Code / agent tooling for
      # home-manager. Exposes lib.wrapClaudeCode (the terminal-env claude wrapper)
      # and lib.mkSuperpowersPlugin (builds obra/superpowers into a plugin, from
      # its own pinned source). Replaces the vendored wrapper and the superpowers
      # input, both of which used to live here.
      url = "github:cjlarose/harness-config.nix";
      inputs.nixpkgs.follows = "nixpkgs-26-05";
    };
    gh-stack = {
      # github/gh-stack -- GitHub's official stacked-PR gh CLI extension
      # (https://github.github.com/gh-stack/). flake = false: upstream ships no
      # nix packaging. One input serves two purposes -- it is the src for the
      # buildGoModule package in packages/gh-stack AND the source of the agent
      # skill at skills/gh-stack/SKILL.md, so the binary and the skill that
      # documents it can never drift apart.
      url = "github:github/gh-stack/v0.1.0";
      flake = false;
    };
    herdr = {
      # herdrdev/herdr -- upstream's own flake, and the definitive source for
      # BOTH the herdr binary and the official agent SKILL.md
      # (herdr.dev/docs/agent-skill). One pin for both, like the gh-stack input
      # above, so a skill documenting subcommands the installed binary does not
      # have is structurally impossible.
      #
      # This replaces llm-agents.nix as the source of herdr specifically (that
      # input still provides claude-code, opencode and git-surgeon). The trade
      # is llm-agents.nix's daily auto-bump for one deliberate tag: herdr now
      # moves when this line moves. Upstream's package covers all four supported
      # platforms and its build.rs passes an explicit -Dtarget, so the vendored
      # zig builds for the arch baseline -- no AVX on the Goldmont pve guests.
      #
      # NOTE when bumping the tag: upstream moved SKILL.md from the repo root to
      # skills/herdr/ after v0.7.5, and v0.8.0 has only the new path. The
      # llm-agents module tries both in order, so either layout resolves.
      url = "github:herdrdev/herdr/v0.8.0";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    ai-memory = {
      # akitaonrails/ai-memory -- local-first session memory for coding agents,
      # running alongside the llm-wiki rather than replacing it. flake = false,
      # so packages/ai-memory builds it from source with our own derivation.
      #
      # Upstream added its own flake.nix in v1.29.0, and we deliberately do not
      # consume it: it makes the same core choices ours does (cargoLock.lockFile,
      # TAILWIND_SKIP=1, doCheck=false, hooks -> share/ai-memory), but building
      # its packages.default would pull rust-overlay + flake-utils into our lock,
      # build the whole workspace including the evals crate, and drop the lean
      # single-crate build and versionCheckHook smoke test packages/ai-memory
      # keeps. flake = false plus our derivation stays leaner and insulated from
      # upstream restructuring its flake outputs.
      #
      # Pinned to a tag, not a branch, and deliberately so: this is a
      # three-month-old project with a 3,000-line changelog whose hook payloads
      # are baked into ~/.claude/settings.json and an opencode plugin. An
      # unpinned bump would silently rewrite both.
      #
      # NOTE when bumping: home-manager-modules/llm-agents/ai-memory.nix diffs
      # the hook payloads this version generates against the ones checked in
      # there, so a contract change fails the BUILD rather than half-wiring the
      # hooks. Expect to re-render those files on a bump.
      url = "github:akitaonrails/ai-memory/v1.30.0";
      flake = false;
    };
  };

  outputs = {
    determinate,
    disko,
    fzfProject,
    fzfVim,
    home-manager-25-05,
    home-manager-25-11,
    home-manager-26-05,
    impermanence,
    intranetHosts,
    nix-minecraft,
    nixpkgs-24-05,
    nixpkgs-24-11,
    nixpkgs-25-05,
    nixpkgs-25-11,
    nixpkgs-26-05,
    nixpkgs-unstable,
    omnisharpVim,
    pce,
    self,
    tfenv,
    trueColorTest,
    nvr,
    cs-automation,
    microvm,
    hermes-agent,
    picktrace-nix-configurations,
    cjlarose-llm-wiki,
    tuicr,
    llm-agents,
    gh-stack,
    herdr,
    ai-memory,
    harness-config,
  }:
    let
      supportedPlatforms = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      additionalPackages = nixpkgs-24-05.lib.genAttrs supportedPlatforms (system:
        let
          pkgs = nixpkgs-24-05.legacyPackages.${system};
          packageArgs = {
            inherit pkgs system nixpkgs-unstable nixpkgs-24-11 nixpkgs-25-05 nixpkgs-25-11 nixpkgs-26-05 intranetHosts nvr trueColorTest cs-automation nix-minecraft tuicr llm-agents gh-stack harness-config herdr ai-memory;
          };
        in
          import ./packages packageArgs
      );

      # Evaluate the sub-flake to get { homeManagerModules = { default, coder, claude, ... }; }.
      # The outputs function takes { self } but never references it, so {} is safe.
      # If a self reference is ever added to the sub-flake, this will need updating.
      cjlarose-home-manager-modules = (import ./home-manager-modules/flake.nix).outputs { self = {}; };

      sharedOverlays = [
        fzfProject.overlay
        fzfVim.overlay
        tfenv.overlays.default
        (final: prev: {
          vimPlugins = prev.vimPlugins // {
            omnisharpVim = with final; vimUtils.buildVimPlugin {
              name = "omnisharp-vim";
              src = omnisharpVim;
            };
          };
        })
      ];
      lib = nixpkgs-24-05.lib;

      hmChecks = import ./tests/home-manager-checks.nix { inherit lib; };

      nixosHmConfig = name:
        self.nixosConfigurations.${name}.config.home-manager.users.cjlarose;

      nixosConfigsWithCjlarose = [
        "bots" "cache" "dns" "immich" "media"
        "splitpro" "ns1010301"
      ];

      mkNixosCheck = pkgs: name:
        assert hmChecks.assertCoreInvariants name (nixosHmConfig name);
        pkgs.runCommand "home-cjlarose-${name}-ok" {} "echo ok > $out";

    in {
      nixosConfigurations = (
        import ./nixos-configurations {
          inherit nixpkgs-25-05 nixpkgs-25-11 nixpkgs-26-05 sharedOverlays additionalPackages home-manager-25-05 home-manager-25-11 home-manager-26-05 pce impermanence disko determinate nix-minecraft microvm hermes-agent picktrace-nix-configurations cjlarose-llm-wiki cjlarose-home-manager-modules harness-config self;
        }
      );

      packages = additionalPackages;

      checks.x86_64-linux = lib.listToAttrs (map (name: {
        name = "home-cjlarose-${name}";
        value = mkNixosCheck nixpkgs-24-05.legacyPackages.x86_64-linux name;
      }) nixosConfigsWithCjlarose);

    };
}
