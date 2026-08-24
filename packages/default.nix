{
  pkgs,
  nixpkgs-24-11,
  nixpkgs-25-05,
  nixpkgs-25-11,
  nixpkgs-26-05,
  nixpkgs-unstable,
  system,
  intranetHosts,
  nvr,
  trueColorTest,
  cs-automation,
  nix-minecraft,
  tuicr,
  llm-agents,
  gh-stack,
  superpowers,
  harness-config,
  lavish-axi,
  herdr,
  ai-memory,
  ...
}:

let
  # numtide/llm-agents.nix. Its own lib marks the unfree licenses free, so
  # claude-code needs no allowUnfreePredicate here (it is still unfree, and
  # nixos-modules/allow-unfree.nix keeps listing it for the system-level sets).
  llm-agents-pkgs = llm-agents.packages.${system};

  # Both claude-code attrs below are UNWRAPPED. The worktree terminal-title /
  # TMUX / CLAUDE_CODE_SHELL wrapper used to live here as mkTitleWrapper, but it
  # was duplicated (and drifting) in picktrace/nix-configurations too; it now
  # lives once in home-manager-modules/llm-agents, which wraps whichever build
  # cjlarose.llmAgents.claude.package selects.

  # Latest Bun standalone claude-code, used by AVX-capable hosts. The no-AVX pve
  # guests use claude-code-node instead — the Bun binary's JIT requires AVX, so
  # it segfaults at launch (and its build-time versionCheckPhase segfaults too)
  # on those CPUs. Since no no-AVX host builds this anymore, the upstream
  # versionCheckPhase is left enabled (it passes on the AVX hosts that build it).
  #
  # Sourced from llm-agents.nix rather than nixpkgs-unstable so claude rolls
  # forward on its own (that flake auto-updates daily) instead of only when
  # nixpkgs-unstable is bumped. Its wrapper differs slightly from the nixpkgs
  # one: same DISABLE_AUTOUPDATER / DISABLE_INSTALLATION_CHECKS and
  # bubblewrap+socat on PATH, plus --argv0 claude (so it shows as "claude" in
  # ps/htop) and DISABLE_NON_ESSENTIAL_MODEL_CALLS; it does not set
  # USE_BUILTIN_RIPGREP=0, so claude uses its bundled ripgrep.
  claude-code-bun = llm-agents-pkgs.claude-code;

  # Node-runnable claude-code, pinned to 2.1.112 (the last npm release whose
  # bin is a node-runnable cli.js; 2.1.113+ ship the Bun native binary). Runs
  # on no-AVX CPUs because V8/node has no AVX requirement. Frozen on purpose.
  claude-code-node-pkg =
    let
      up = nixpkgs-26-05.legacyPackages.${system};
    in
    pkgs.stdenvNoCC.mkDerivation {
      pname = "claude-code-node";
      version = "2.1.112";
      src = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-2.1.112.tgz";
        hash = "sha256-hDeZaepToOX9IxqPd96+THyxfdlx9ICdENM/muyl3gk=";
      };
      # The npm tarball's single top-level dir (package/) is auto-detected as
      # sourceRoot and cd'd into, so installPhase's "." is the package contents
      # (cli.js, vendor/, ...). No build step.
      dontBuild = true;
      dontConfigure = true;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      installPhase = ''
        runHook preInstall

        mkdir -p $out/libexec/claude-code $out/bin
        cp -R . $out/libexec/claude-code/

        # Mirror the runtime environment the upstream nixpkgs claude-code
        # package wires in via wrapProgram.
        makeWrapper ${up.nodejs}/bin/node $out/bin/claude \
          --add-flags $out/libexec/claude-code/cli.js \
          --set DISABLE_AUTOUPDATER 1 \
          --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
          --set DISABLE_INSTALLATION_CHECKS 1 \
          --set USE_BUILTIN_RIPGREP 0 \
          --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath [ up.alsa-lib ]} \
          --prefix PATH : ${pkgs.lib.makeBinPath [ up.procps up.ripgrep up.bubblewrap up.socat ]}

        runHook postInstall
      '';
    };
in
{
  atlas = nixpkgs-24-11.legacyPackages.${system}.atlas;
  # Local-first session memory for coding agents (akitaonrails/ai-memory), on a
  # two-week parallel trial. Built from nixpkgs-26-05, whose rustc is 1.95.0 --
  # exactly what upstream's rust-toolchain.toml pins. Not in nixpkgs.
  ai-memory = import ./ai-memory {
    pkgs = nixpkgs-26-05.legacyPackages.${system};
    src = ai-memory;
    version = "1.30.0";
  };
  claude-code = claude-code-bun;
  claude-code-node = claude-code-node-pkg;
  cs-automation = cs-automation.packages.${system}.default;
  immich = nixpkgs-25-11.legacyPackages.${system}.immich;
  intranetHosts = intranetHosts;
  # mosh patched so mosh-server advertises COLORTERM=truecolor to the session.
  # mosh renders 24-bit color but otherwise strips the signal, leaving nothing
  # able to detect truecolor over mosh; see ./mosh/colorterm.patch. Built from
  # nixpkgs-26-05 to match ns1010301, the only host wiring programs.mosh.package
  # to this.
  mosh = nixpkgs-26-05.legacyPackages.${system}.mosh.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./mosh/colorterm.patch ];
  });
  git-make-apply-command = import ./git-make-apply-command { inherit pkgs; };
  ghostty-terminfo = pkgs.runCommand "ghostty-terminfo" {} ''
    mkdir -p $out/share/terminfo
    cp -r ${nixpkgs-unstable.legacyPackages.${system}.ghostty}/share/terminfo/. \
      $out/share/terminfo/
  '';
  nix-direnv = nixpkgs-unstable.legacyPackages.${system}.nix-direnv;
  # From unstable rather than the host's 26-05, which lags at 2.93.0. unstable
  # is already locked here and carries 2.96.0, the current upstream release, so
  # this needs no channel bump.
  gh = nixpkgs-unstable.legacyPackages.${system}.gh;
  # Built from the flake input (flake = false), which is also where the
  # llm-agents module reads skills/gh-stack/SKILL.md -- one pin for both.
  gh-stack = import ./gh-stack {
    pkgs = nixpkgs-26-05.legacyPackages.${system};
    src = gh-stack;
    version = "0.1.0";
  };
  # Non-interactive hunk-level git surgery (stage/unstage/discard/undo/fold/
  # amend/squash/split/move by hunk ID). Only in llm-agents.nix, not nixpkgs.
  # The package carries upstream's own agent skill in share/, so the SKILL.md
  # the llm-agents module installs cannot drift from the binary.
  git-surgeon = llm-agents-pkgs.git-surgeon;
  # Terminal workspace manager for AI coding agents (herdr.dev). Not in nixpkgs.
  # From upstream's own flake rather than llm-agents.nix, so this pin serves the
  # binary and the agent skill below at once and the two cannot drift.
  herdr = herdr.packages.${system}.default;
  # The same input as a bare source tree, for cjlarose.llmAgents.herdr.skillSrc:
  # upstream's official agent skill (herdr.dev/docs/agent-skill) is in the repo
  # but deliberately NOT in the package -- its src fileset is code only, and the
  # skill is distributed through `npx skills add`. The llm-agents module lifts
  # the SKILL.md out; passing the source rather than a package built here keeps
  # that extraction in the one place both repos share. Same passthrough shape as
  # intranetHosts above.
  herdr-src = herdr;
  # From llm-agents.nix rather than nixpkgs-unstable so it tracks the same
  # daily-updated source as claude-code.
  opencode = llm-agents-pkgs.opencode;
  # Upstream obra/superpowers source, re-exported unbuilt for
  # cjlarose.llmAgents.superpowers.src -- the llm-agents module builds the
  # plugin itself, since the customizations it applies (disabling the
  # SessionStart hook, stripping the spec-commit instructions) are driven by
  # module options that packages/ cannot see. Same shape as herdr-src above.
  superpowers-src = superpowers;
  # cjlarose/harness-config.nix's lib, re-exported to every consumer through
  # additionalPackages.${system}.harnessConfig. Exposes wrapClaudeCode (the
  # terminal-env claude wrapper) and mkSuperpowersPlugin (builds obra/superpowers
  # into a plugin from harness-config's own pinned source).
  harnessConfig = harness-config.lib;
  tuicr = tuicr.packages.${system}.default;
  # Built from source (flake = false input `lavish-axi` is the upstream src).
  # callPackage supplies lib/stdenv/nodejs_22/pnpm/makeWrapper from nixpkgs-26-05.
  lavish-axi = nixpkgs-26-05.legacyPackages.${system}.callPackage ./lavish-axi {
    src = lavish-axi;
    version = "0.1.43";
  };
  nvr = import ./nvr { inherit pkgs nvr; };
  trueColorTest = pkgs.stdenv.mkDerivation {
    name = "true-color-test";
    src = trueColorTest;
    buildPhase = ''
      chmod +x 24-bit-color.sh
    '';
    installPhase = ''
      mkdir -p $out/bin
      cp 24-bit-color.sh $out/bin
    '';
  };
  # Shared with home-manager-modules/dev-tools.nix, which installs the same two
  # wrappers directly. They live over there because that directory is its own
  # flake and cannot import from here, while this one can import from there.
  inherit (import ../home-manager-modules/shell-wrappers.nix { inherit pkgs; })
    wrappedJq wrappedRg;
  wrappedTailscale = pkgs.writeShellScriptBin "tailscale" ''
    exec /Applications/Tailscale.app/Contents/MacOS/Tailscale "$@"
  '';
  wrappedWireshark = pkgs.writeShellScriptBin "wireshark" ''
    exec /Applications/Wireshark.app/Contents/MacOS/Wireshark "$@"
  '';
  openCommitInGitlab = pkgs.writeShellScriptBin "open-gitlab" ''
    commit=$(git rev-parse ''${1:-HEAD})
    open "$GITLAB_HOST/$(basename $(git rev-parse --show-toplevel))/-/commit/$commit"
  '';
  minecraft-modpack = import ./minecraft { inherit pkgs nix-minecraft; };
  minecraft-mods-zip = let modpack = import ./minecraft { inherit pkgs nix-minecraft; }; in
    pkgs.runCommand "mellowcatfe-mods-zip" { nativeBuildInputs = [ pkgs.zip ]; } ''
      mkdir -p $out
      cd ${modpack}
      zip -r $out/mods.zip mods/
    '';
}
