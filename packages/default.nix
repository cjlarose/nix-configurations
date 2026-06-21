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
  allowUnfreePredicate,
  nix-minecraft,
  ...
}:

let
  # Wrap any package that exposes bin/claude with worktree-aware terminal-title
  # behavior. Shared by the Bun (claude-code) and node (claude-code-node)
  # variants so both behave identically.
  mkTitleWrapper = underlying: pkgs.writeShellScriptBin "claude" ''
    # Set terminal title based on worktree layout: owner/repo [worktree]
    if [[ "$PWD" =~ ^''${HOME}/worktrees/([^/]+)/([^/]+)/([^/]+) ]]; then
      printf '\033]2;%s\007' "Claude Code ✳ ''${BASH_REMATCH[1]}/''${BASH_REMATCH[2]} [''${BASH_REMATCH[3]}]"
    fi
    unset TMUX
    export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1
    exec ${underlying}/bin/claude "$@"
  '';

  # Latest Bun standalone claude-code. doInstallCheck is disabled because the
  # upstream versionCheckPhase runs `claude --version` at build time, and the
  # Bun binary segfaults on no-AVX CPUs (e.g. the pve guests), failing the
  # build. Skipping the check does not affect the produced binary. NOTE: the
  # binary still cannot RUN on a no-AVX CPU — those hosts use claude-code-node.
  claude-code-bun = ((import nixpkgs-unstable {
    inherit system;
    config.allowUnfreePredicate = allowUnfreePredicate;
  }).claude-code).overrideAttrs (_: {
    doInstallCheck = false;
  });

  # Node-runnable claude-code, pinned to 2.1.112 (the last npm release whose
  # bin is a node-runnable cli.js; 2.1.113+ ship the Bun native binary). Runs
  # on no-AVX CPUs because V8/node has no AVX requirement. Frozen on purpose.
  claude-code-node-unwrapped =
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
  claude-code = mkTitleWrapper claude-code-bun;
  claude-code-node = mkTitleWrapper claude-code-node-unwrapped;
  cs-automation = cs-automation.packages.${system}.default;
  bundix = import "${bundix}/default.nix" { inherit pkgs; };
  immich = nixpkgs-25-11.legacyPackages.${system}.immich;
  intranetHosts = intranetHosts;
  git-make-apply-command = import ./git-make-apply-command { inherit pkgs; };
  ghostty-terminfo = pkgs.runCommand "ghostty-terminfo" {} ''
    mkdir -p $out/share/terminfo
    cp -r ${nixpkgs-unstable.legacyPackages.${system}.ghostty}/share/terminfo/. \
      $out/share/terminfo/
  '';
  nix-direnv = nixpkgs-unstable.legacyPackages.${system}.nix-direnv;
  opencode = nixpkgs-unstable.legacyPackages.${system}.opencode;
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
