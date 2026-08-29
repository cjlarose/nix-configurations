# akitaonrails/ai-memory -- a local-first session-memory MCP server for coding
# agents. Not in nixpkgs, so this is the packaging.
#
# Being evaluated on a two-week parallel trial against the hand-rolled llm-wiki;
# see home-manager-modules/llm-agents/ai-memory.nix for how it is wired, and the
# trial's open question (is a task-shaped project a useful unit of memory?).
#
# Built from nixpkgs-26-05 rather than the host's own pkgs because upstream's
# rust-toolchain.toml pins channel 1.95 and workspace.rust-version is 1.95 --
# 26-05 carries rustc 1.95.0 exactly. (unstable is at 1.97, which also works,
# but 26-05 is the closer match and is what gh-stack already builds from.)
#
# The output carries:
#   bin/ai-memory                 the CLI + daemon, one binary
#   share/ai-memory/hooks/        upstream's vendored per-agent hook scripts
#
# The hooks/ tree is needed even though nothing installed here runs those
# scripts. On a native platform the hooks Claude Code gets are direct
# `ai-memory hook --event ...` invocations of the binary; the shell scripts are
# the portable fallback. But `install-hooks` STAGES them as part of rendering,
# and looks for them at a compiled-in /usr/local/share/ai-memory/hooks that does
# not exist on NixOS -- so the module's renderer passes --hooks-dir at this
# package's own store path. Shipping them in the same derivation as the binary
# also keeps the scripts and the `ai-memory hook` protocol they speak from
# drifting apart across a version bump.
{ pkgs, src, version }:

pkgs.rustPlatform.buildRustPackage {
  pname = "ai-memory";
  inherit src version;

  # The lockfile rather than a cargoHash: upstream vendors nothing from git
  # (zero `source = "git+"` entries in Cargo.lock), so every dependency resolves
  # from crates.io and nix can build the vendor tree from the lock directly.
  # This is strictly better than a hash here -- a version bump needs no
  # recomputed sha, and a lockfile that stops being buildable fails loudly
  # instead of silently vendoring something else.
  cargoLock.lockFile = "${src}/Cargo.lock";

  # The workspace has ten crates plus an `evals` member that upstream's own
  # comment calls "not part of the shipped binary". Only the CLI crate produces
  # bin/ai-memory, and building just it keeps the A/B eval harness (and its
  # deps) out of the closure entirely.
  cargoBuildFlags = [ "--package" "ai-memory-cli" ];

  # rusqlite is `bundled` and git2 is `vendored-libgit2`, so both compile their
  # C libraries here -- which is the reason this package needs no libgit2 pin
  # and no sqlite from nixpkgs, but does need a working cc. reqwest is
  # rustls-tls with default-features off, so there is no openssl either.
  nativeBuildInputs = [ pkgs.cmake pkgs.pkg-config ];

  # crates/ai-memory-web/build.rs DOWNLOADS the standalone Tailwind CLI (a
  # pinned 3.4.17, sha-checked) and shells out to it to compile
  # static/input.css. That cannot work in a sandbox with no network, and must
  # not be allowed to try. TAILWIND_SKIP=1 is upstream's own documented escape
  # hatch and is what their AUR PKGBUILD sets: it copies the vendored
  # static/tailwind.css into OUT_DIR instead. The vendored file is the one
  # upstream ships in the release tarball, so the web UI still gets its real
  # stylesheet -- this drops the download, not the CSS.
  #
  # Note the build script PANICS if the vendored file is missing, so a future
  # release that stops shipping it fails the build rather than producing a
  # web UI with no styling.
  TAILWIND_SKIP = "1";

  # Upstream's own PKGBUILD runs `cargo test -p ai-memory-cli --bin ai-memory`
  # against a scratch $HOME. Left off here: the suite reaches for a real HOME
  # and a git identity (the wiki layer is git2-backed and several tests init
  # repos), neither of which the sandbox has -- the same reason gh-stack sets
  # doCheck = false. The versionCheckPhase below is the substitute smoke test.
  doCheck = false;

  nativeInstallCheckInputs = [ pkgs.versionCheckHook ];
  doInstallCheck = true;
  versionCheckProgramArg = "--version";

  postInstall = ''
    # Upstream's vendored hook scripts, one directory per supported agent CLI.
    # `install-hooks --hooks-dir` is pointed here; see the header comment.
    mkdir -p $out/share/ai-memory
    cp -r ${src}/hooks $out/share/ai-memory/hooks
    chmod -R u+w $out/share/ai-memory/hooks
    find $out/share/ai-memory/hooks -name '*.sh' -exec chmod +x {} +
  '';

  meta = {
    description = "Local-first long-term memory MCP server for AI coding agents";
    homepage = "https://github.com/akitaonrails/ai-memory";
    license = pkgs.lib.licenses.mit;
    mainProgram = "ai-memory";
  };
}
