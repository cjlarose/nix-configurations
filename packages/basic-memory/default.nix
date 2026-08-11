# basicmachines-co/basic-memory -- local-first knowledge graph over plain
# markdown, exposed to Claude Code and opencode as an MCP server. Backs
# ~/basic-memory/personal (see home-manager-modules/llm-agents).
#
# Why uv2nix rather than buildPythonApplication
# ---------------------------------------------
# nixpkgs does not carry basic-memory, and hand-listing its dependencies against
# python3Packages does not survive contact with this project: v0.22.1 pins
# `fastmcp==3.3.1` exactly, `psycopg==3.3.1` exactly, and pulls fastembed +
# sqlite-vec + litellm + logfire for semantic search. nixpkgs has none of those
# at the pinned versions.
#
# Every third-party derivation found for this package took the hand-listing
# route, and every one of them is stuck on an old release (0.16.3, 0.20.2) with
# the entire semantic-search stack silently omitted -- an install that starts
# fine and then answers queries with keyword matching only. uv2nix instead reads
# upstream's own uv.lock, so the resolution is exactly what upstream tested.
#
# sourcePreference = "wheel" matters for the same reason: of the 192 packages in
# that lock, only pybars3 and pymeta3 lack wheels. Everything heavy --
# onnxruntime, tokenizers, numpy -- arrives prebuilt rather than as a source
# build of an ML toolchain.
{
  pkgs,
  src,
  version,
  pyproject-nix,
  uv2nix,
  pyproject-build-systems,
}:

let
  inherit (pkgs) lib;

  python = pkgs.python313;

  workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = src; };

  overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

  pythonSet =
    (pkgs.callPackage pyproject-nix.build.packages { inherit python; }).overrideScope
      (lib.composeManyExtensions [
        pyproject-build-systems.overlays.wheel
        overlay
        (final: prev: {
          # The only two sdists in the lock. Neither declares setuptools as a
          # build dependency, so both fail to build without it added by hand.
          pymeta3 = prev.pymeta3.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
          });
          pybars3 = prev.pybars3.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.setuptools ];
          });

          # basic-memory takes its version from `git describe` via
          # uv-dynamic-versioning, with fallback-version = "0.0.0". fetchFromGitHub
          # gives no .git, so an otherwise perfect build would report 0.0.0 and
          # `basic-memory --version` would contradict the pin. Stamp the real tag
          # at BUILD time -- a runtime wrapper cannot fix this, since the version
          # is baked into the installed package metadata.
          basic-memory = prev.basic-memory.overrideAttrs (old: {
            env = (old.env or { }) // { UV_DYNAMIC_VERSIONING_BYPASS = version; };
          });
        })
      ]);

  venv = pythonSet.mkVirtualEnv "basic-memory-env" workspace.deps.default;
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "basic-memory";
  inherit version;

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    # Both console scripts are declared upstream and share one entry point.
    for exe in basic-memory bm; do
      makeWrapper ${venv}/bin/$exe $out/bin/$exe \
        --set BASIC_MEMORY_AUTO_UPDATE false
    done

    runHook postInstall
  '';

  passthru = {
    inherit venv python;
  };

  meta = {
    description = "Local-first knowledge management combining Zettelkasten with knowledge graphs";
    homepage = "https://github.com/basicmachines-co/basic-memory";
    license = lib.licenses.agpl3Plus;
    mainProgram = "basic-memory";
    platforms = lib.platforms.unix;
  };
}
