{ pkgs }:

pkgs.stdenv.mkDerivation {
  name = "git-make-apply-command";
  src = ./.;
  
  dontBuild = true;
  
  installPhase = ''
    mkdir -p $out/bin
    cp ${./script.sh} $out/bin/git-make-apply-command
    chmod +x $out/bin/git-make-apply-command
    
    # Fix the interpreter path by patching the shebang
    patchShebangs $out/bin/git-make-apply-command
  '';
}
