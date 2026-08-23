# The soliciting-pr-feedback skill and its deterministic renderer.
#
# The skill drives lavish to review a change as a GitHub-styled pull request
# before it is opened or pushed to. The heavy lifting -- turning a commit range
# plus a title and body into the review page -- is the `mock-pr-html` command
# rather than prose, so the result is deterministic and cannot drift or
# reintroduce the diff-loading and file-list bugs a hand-written page keeps
# hitting. It is all Node: cli.mjs does the git work and HTML assembly and calls
# render-body.mjs for the body, which is rendered exactly as GitHub renders it --
# GFM plus remark-github's autolinking (#123, owner/repo#123, @user, commit SHAs
# shortened to 7 chars, ranges) plus alert blocks. Built from a pinned lockfile,
# so the closure is fixed and nothing is fetched at runtime.
#
# A separate module like git-conventions / workspace-layout: the skill pairs with
# lavish but is independent of it as a package, and a host wanting the reviewer
# turns it on explicitly. See home/cjlarose for where it is enabled.
{ lib, pkgs, config, ... }:

let
  cfg = config.cjlarose.llmAgents.prFeedback;
  agents = config.cjlarose.llmAgents;

  # `mock-pr-html`, all Node. buildNpmPackage from the pinned lockfile. doCheck
  # runs the renderer's TDD (test.mjs) on every build, so a GFM/autolink
  # regression fails the build rather than shipping. patchShebangs bakes the nix
  # node into the bin; git is wrapped onto PATH for cli.mjs's child_process git
  # calls. dontNpmBuild: these are runtime scripts, there is no build step.
  mockPr = pkgs.buildNpmPackage {
    pname = "mock-pr-html";
    version = "1.0.0";
    src = ./pr-feedback/mock-pr;
    npmDepsHash = "sha256-mfOCGSbO83Sc6yj1/IiXJ4R0TX7TCd7YgVokjz7bTx0=";
    dontNpmBuild = true;
    doCheck = true;
    # git for the cli git-parsing tests; HOME so git has somewhere to look.
    nativeCheckInputs = [ pkgs.git ];
    checkPhase = ''
      runHook preCheck
      export HOME=$(mktemp -d)
      node --test
      runHook postCheck
    '';
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postInstall = ''
      wrapProgram $out/bin/mock-pr-html \
        --prefix PATH : ${lib.makeBinPath [ pkgs.git ]}
    '';
  };
in
{
  options.cjlarose.llmAgents.prFeedback = {
    enable = lib.mkEnableOption ''
      the soliciting-pr-feedback skill and its `mock-pr-html` renderer: build a
      GitHub-styled mock pull request from a commit range and open it in lavish
      for review before the PR is opened or pushed to. Needs lavish to drive the
      review loop, so enable it on hosts that also set cjlarose.llmAgents.lavish
    '';
  };

  config = lib.mkIf cfg.enable {
    # The renderer on PATH. Useful on its own (it just writes HTML), so it is not
    # gated on a harness -- only the skill doc below is.
    home.packages = [ mockPr ];

    # ~/.claude/skills only: opencode scans it natively, so a second copy under
    # opencode/skills would collide rather than help (see default.nix).
    home.file = lib.mkIf (agents.claude.enable || agents.opencode.enable) {
      ".claude/skills/soliciting-pr-feedback".source =
        ./pr-feedback/soliciting-pr-feedback;
    };
  };
}
