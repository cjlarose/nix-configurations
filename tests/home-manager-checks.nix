{ lib }:

let
  hasPackage = packages: target:
    builtins.any (p: (p.pname or "") == target) packages;

  check = configName: invariant: cond:
    if cond then true
    else builtins.throw "${configName}: invariant failed: ${invariant}";

  assertCoreInvariants = configName: hm:
    let c = check configName; in

    assert c "programs.neovim.enable" hm.programs.neovim.enable;
    assert c "programs.git.enable" hm.programs.git.enable;
    assert c "programs.git.delta.enable" hm.programs.git.delta.enable;
    assert c "programs.zsh.enable" hm.programs.zsh.enable;
    assert c "programs.fzf.enable" hm.programs.fzf.enable;
    assert c "programs.ssh.enable" hm.programs.ssh.enable;

    assert c "htop in packages" (hasPackage hm.home.packages "htop");
    assert c "kubectl in packages" (hasPackage hm.home.packages "kubectl");
    assert c "tmux in packages" (hasPackage hm.home.packages "tmux");
    assert c "tree in packages" (hasPackage hm.home.packages "tree");
    assert c "jq in packages" (hasPackage hm.home.packages "jq");
    assert c "nil in packages" (hasPackage hm.home.packages "nil");
    assert c "git-absorb in packages" (hasPackage hm.home.packages "git-absorb");
    assert c "yq-go in packages" (hasPackage hm.home.packages "yq-go");

    assert c "EDITOR is set" (hm.home.sessionVariables ? EDITOR);
    assert c "LESS is set" (hm.home.sessionVariables ? LESS);

    assert c "alias gs = git status" (hm.home.shellAliases.gs or "" == "git status");
    assert c "alias gd = git diff" (hm.home.shellAliases.gd or "" == "git diff");
    assert c "alias gds = git diff --staged" (hm.home.shellAliases.gds or "" == "git diff --staged");
    assert c "alias gap = git add --patch" (hm.home.shellAliases.gap or "" == "git add --patch");
    assert c "alias gc = git commit" (hm.home.shellAliases.gc or "" == "git commit");

    assert c "git pull.ff = only" (hm.programs.git.extraConfig.pull.ff or "" == "only");
    assert c "git rebase.autosquash" (hm.programs.git.extraConfig.rebase.autosquash or false);
    assert c "git rebase.autostash" (hm.programs.git.extraConfig.rebase.autostash or false);

    # The wiki registry, on the hosts that have a wiki. Conditional rather than
    # core: most of the fleet has none, and asserting the file exists everywhere
    # would just be asserting mkIf works.
    #
    # Worth a check at all because the registry is the ONLY thing that tells a
    # skill or the session-start hook which wikis exist and how to reach them.
    # A wiki whose repoPath is relative, or whose routingHint is blank, breaks
    # at capture time in an unrelated session rather than here -- so the shape
    # is pinned where it is cheap to catch.
    assert c "wiki registry is written when a wiki is enabled"
      (!hm.cjlarose.llmAgents.wiki.enable
       || hm.xdg.configFile ? "llm-wiki/wikis.json");

    assert c "every wiki has an absolute repoPath"
      (builtins.all (w: lib.hasPrefix "/" w.repoPath)
        (builtins.attrValues hm.cjlarose.llmAgents.wiki.wikis));

    assert c "every wiki has a non-empty routingHint"
      (builtins.all (w: w.routingHint != "")
        (builtins.attrValues hm.cjlarose.llmAgents.wiki.wikis));

    true;

in {
  inherit assertCoreInvariants;
}
