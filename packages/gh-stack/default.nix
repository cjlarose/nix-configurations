# github/gh-stack -- GitHub's official stacked-PR gh CLI extension.
#
# nixpkgs does carry gh-stack, but it lags -- 0.0.4 at the time of writing,
# against v0.1.0 here -- so build from the pinned tag instead.
#
# gh discovers extensions by directory layout, not PATH, so the dev-tools module
# links bin/ into ~/.local/share/gh/extensions/gh-stack rather than putting the
# package into home.packages.
{ pkgs, src, version }:

pkgs.buildGoModule {
  pname = "gh-stack";
  inherit src version;

  # Recomputed whenever the pinned tag moves; `nix build` prints the correct
  # value on mismatch.
  vendorHash = "sha256-0Xtr/MOpX4u5GnbRdNxKPA0GpSzi8PIbVc9MmP05De4=";

  # Upstream reports `gh stack version` from cmd.Version, which defaults to
  # "dev"; stamp the real tag so the binary and the pinned input agree.
  ldflags = [ "-s" "-w" "-X github.com/github/gh-stack/cmd.Version=${version}" ];

  # The test suite shells out to git and expects a configured identity; the
  # build sandbox has neither.
  doCheck = false;

  meta = {
    description = "GitHub CLI extension for managing stacked pull requests";
    homepage = "https://github.github.com/gh-stack/";
    license = pkgs.lib.licenses.mit;
    mainProgram = "gh-stack";
  };
}
