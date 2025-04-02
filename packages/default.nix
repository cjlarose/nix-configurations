{
  pkgs,
  nixpkgs-24-11,
  nixpkgs-23-05,
  system,
  bundix,
  intranetHosts,
  nvr,
  trueColorTest,
  chicken-smoothie-automation,
  ...
}:

{
  atlas = nixpkgs-24-11.legacyPackages.${system}.atlas;
  chicken-smoothie-automation = chicken-smoothie-automation.packages.${system}.default;
  bundix = import "${bundix}/default.nix" { inherit pkgs; };
  intranetHosts = intranetHosts;
  git-make-apply-command = import ./git-make-apply-command { inherit pkgs; };
  nix-direnv = nixpkgs-24-11.legacyPackages.${system}.nix-direnv;
  nvr = import ./nvr { inherit pkgs nvr; };
  python39 = nixpkgs-23-05.legacyPackages.${system}.python39;
  teleport_16 = nixpkgs-24-11.legacyPackages.${system}.teleport_16;
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
