{
  description = "NixOS-based development environment";

  inputs = {
    nixpkgs-23-05 = {
      url = "github:nixos/nixpkgs/nixos-23.05";
    };
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
      # of a nixpkgs-unstable bump), opencode, and herdr. Follows
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
    bundix = {
      url = "github:cjlarose/bundix";
      flake = false;
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
    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };
    superpowers = {
      url = "github:obra/superpowers";
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
      inputs.mattpocock-skills.follows = "mattpocock-skills";
      inputs.superpowers.follows = "superpowers";
    };
    cjlarose-llm-wiki = {
      url = "git+ssh://git@github.com/cjlarose/llm-wiki";
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
    lavish-axi = {
      # Upstream lavish-axi, pinned to a release tag and built from source in
      # packages/lavish-axi (flake = false: upstream ships no nix packaging).
      # v0.1.43 includes the DNS-rebinding Host-guard fix. The build disables
      # telemetry; see packages/lavish-axi/default.nix.
      url = "github:kunchenguid/lavish-axi/lavish-axi-v0.1.43";
      flake = false;
    };
  };

  outputs = {
    bundix,
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
    nixpkgs-23-05,
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
    mattpocock-skills,
    superpowers,
    microvm,
    hermes-agent,
    picktrace-nix-configurations,
    cjlarose-llm-wiki,
    tuicr,
    llm-agents,
    gh-stack,
    lavish-axi,
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
            inherit pkgs system nixpkgs-unstable nixpkgs-24-11 nixpkgs-23-05 nixpkgs-25-05 nixpkgs-25-11 nixpkgs-26-05 bundix intranetHosts nvr trueColorTest cs-automation nix-minecraft tuicr llm-agents gh-stack lavish-axi;
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
          inherit nixpkgs-25-05 nixpkgs-25-11 nixpkgs-26-05 sharedOverlays additionalPackages home-manager-25-05 home-manager-25-11 home-manager-26-05 pce impermanence disko determinate nix-minecraft microvm hermes-agent picktrace-nix-configurations cjlarose-llm-wiki cjlarose-home-manager-modules mattpocock-skills superpowers self;
        }
      );

      packages = additionalPackages;

      checks.x86_64-linux = lib.listToAttrs (map (name: {
        name = "home-cjlarose-${name}";
        value = mkNixosCheck nixpkgs-24-05.legacyPackages.x86_64-linux name;
      }) nixosConfigsWithCjlarose);

    };
}
