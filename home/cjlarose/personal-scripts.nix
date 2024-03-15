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
      url = "https://gist.github.com/db6c5654fa976be33808b8b33a6eb861.git";
      rev = "1875ff9b84a014214d0ce9d922654bb34001198e";
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
