{
  pkgs,
  nixpkgs-24-11,
  nixpkgs-23-05,
  nixpkgs-25-05,
  nixpkgs-25-11,
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

{
  atlas = nixpkgs-24-11.legacyPackages.${system}.atlas;
  claude-code =
    let
      base = (import nixpkgs-unstable {
        inherit system;
        config.allowUnfreePredicate = allowUnfreePredicate;
      }).claude-code;
    in
    pkgs.writeShellScriptBin "claude" ''
      # Set terminal title based on worktree layout: owner/repo [worktree]
      if [[ "$PWD" =~ ^''${HOME}/worktrees/([^/]+)/([^/]+)/([^/]+) ]]; then
        printf '\033]2;%s\007' "Claude Code ✳ ''${BASH_REMATCH[1]}/''${BASH_REMATCH[2]} [''${BASH_REMATCH[3]}]"
      fi
      unset TMUX
      export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1
      exec ${base}/bin/claude "$@"
    '';
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
