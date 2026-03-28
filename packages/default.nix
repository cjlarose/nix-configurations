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
    pkgs.symlinkJoin {
      name = "claude-code";
      paths = [ base ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/claude --unset TMUX
      '';
    };
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
  teleport_16 = nixpkgs-25-05.legacyPackages.${system}.teleport_16;
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
      ${pkgs.ripgrep}/bin/rg --pretty --sort path "$@" | less
    else
      ${pkgs.ripgrep}/bin/rg --sort path "$@"
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
}
