{ pkgs, ... }:

let
  nvrEditInSplitWindow = pkgs.writeShellScriptBin "nvr-edit-in-split-window" ''
    if [ -z "$NVIM" ]; then
      nvim "$@"
    else
      nvr -cc split --remote-wait +'set bufhidden=wipe' "$@"
    fi
  '';

  wrappedRg = pkgs.writeShellScriptBin "rgp" ''
    if [ -t 1 ]; then
      ${pkgs.ripgrep}/bin/rg --pretty --sort path "$@" | less
    else
      ${pkgs.ripgrep}/bin/rg --sort path "$@"
    fi
  '';

  runUntilFailure = pkgs.writeShellScriptBin "run-until-failure" ''
    while "$@"; do :; done
  '';

  runUntilSuccess = pkgs.writeShellScriptBin "run-until-success" ''
    while ! "$@"; do :; done
  '';

  trueColorTest = pkgs.stdenv.mkDerivation {
    name = "true-color-test";
    src = fetchGit {
      url = "https://gist.github.com/09a44b8cf0f9397465614e622979107f.git";
      rev = "d89f28711c037e53f03e312f6fef11bcc75006f8";
    };
    buildPhase = ''
      chmod +x 24-bit-color.sh
    '';
    installPhase = ''
      mkdir -p $out/bin
      cp 24-bit-color.sh $out/bin
    '';
  };
in {
  home.packages = [
    nvrEditInSplitWindow
    wrappedRg
    runUntilFailure
    runUntilSuccess
    trueColorTest
  ];
}
