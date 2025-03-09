{ pkgs, nvr }:

let
  manifest = (pkgs.lib.importTOML "${nvr.outPath}/Cargo.toml").package;
in
  pkgs.rustPlatform.buildRustPackage {
    pname = manifest.name;
    version = manifest.version;
    cargoLock.lockFile = "${nvr.outPath}/Cargo.lock";
    src = pkgs.lib.cleanSource nvr.outPath;
  }
