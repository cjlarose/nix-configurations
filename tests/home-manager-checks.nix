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

    true;

in {
  inherit assertCoreInvariants;
}
