# github/gh-stack -- GitHub's official stacked-PR gh CLI extension.
#
# Built from the same pinned source as the agent skill the llm-agents module
# installs, so the binary and the SKILL.md documenting it can never drift.
# nixpkgs does carry gh-stack, but it lags (0.0.4 at the time of writing, versus
# v0.1.0 here and a skill that documents 0.0.9 behaviour) -- a mismatch between
# the skill's instructions and the binary's actual flags is worse than a build.
#
# The output carries bin/gh-stack plus upstream's agent skill at
# share/gh-stack/skill/SKILL.md -- the same shape lavish-axi uses. Shipping the
# skill in the package rather than reading it from the flake input means the
# consuming home config only has to thread ONE thing (the package), and the
# binary and its documentation are guaranteed to come from the same tag.
#
# gh discovers extensions by directory layout, not PATH, so the llm-agents
# module links bin/ into ~/.local/share/gh/extensions/gh-stack rather than
# putting the package into home.packages.
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

  postInstall = ''
    install -Dm644 skills/gh-stack/SKILL.md \
      $out/share/gh-stack/skill/SKILL.md
  '';

  meta = {
    description = "GitHub CLI extension for managing stacked pull requests";
    homepage = "https://github.github.com/gh-stack/";
    license = pkgs.lib.licenses.mit;
    mainProgram = "gh-stack";
  };
}
