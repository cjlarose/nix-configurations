{
  pkgs,
  nixpkgs-24-11,
  nixpkgs-23-05,
  nixpkgs-25-05,
  nixpkgs-25-11,
  nixpkgs-26-05,
  nixpkgs-unstable,
  system,
  bundix,
  intranetHosts,
  nvr,
  trueColorTest,
  cs-automation,
  nix-minecraft,
  tuicr,
  llm-agents,
  lavish-axi,
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
  claude-code = claude-code-bun;
  claude-code-node = claude-code-node-pkg;
  cs-automation = cs-automation.packages.${system}.default;
  bundix = import "${bundix}/default.nix" { inherit pkgs; };
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
  # Terminal workspace manager for AI coding agents (herdr.dev). Only in
  # llm-agents.nix, not nixpkgs.
  herdr = llm-agents-pkgs.herdr;
  # From llm-agents.nix rather than nixpkgs-unstable so it tracks the same
  # daily-updated source as claude-code and herdr.
  opencode = llm-agents-pkgs.opencode;
  tuicr = tuicr.packages.${system}.default;
  # Built from source (flake = false input `lavish-axi` is the upstream src).
  # callPackage supplies lib/stdenv/nodejs_22/pnpm/makeWrapper from nixpkgs-26-05.
  lavish-axi = nixpkgs-26-05.legacyPackages.${system}.callPackage ./lavish-axi {
    src = lavish-axi;
    version = "0.1.43";
  };
  nvr = import ./nvr { inherit pkgs nvr; };
  go_1_22 = nixpkgs-24-11.legacyPackages.${system}.go_1_22;
  python39 = nixpkgs-23-05.legacyPackages.${system}.python39;
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
  wrappedJq = pkgs.writeShellScriptBin "jqp" ''
    if [ -t 1 ]; then
      ${pkgs.jq}/bin/jq --color-output "$@" | less
    else
      ${pkgs.jq}/bin/jq "$@"
    fi
  '';
  wrappedRg = pkgs.writeShellScriptBin "rg" ''
    if [ -t 1 ]; then
      ${pkgs.ripgrep}/bin/rg --hidden --glob '!.git' --sort path --pretty "$@" | less
    else
      ${pkgs.ripgrep}/bin/rg --hidden --glob '!.git' --sort path "$@"
    fi
  '';
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
