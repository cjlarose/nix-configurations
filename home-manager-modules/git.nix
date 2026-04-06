{ config, lib, pkgs, ... }:

let
  cfg = config.cjlarose.git;
in {
  options.cjlarose.git = {
    neovimRemotePackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.neovim-remote;
      description = "The Python neovim-remote package for difftool/mergetool";
    };
  };

  config = {
    home.shellAliases = {
      gap = "git add --patch";
      gc = "git commit";
      gd = "git diff";
      gds = "git diff --staged";
      gpoh = "git push origin HEAD";
      gs = "git status";
    };

    programs.git = {
      enable = true;
      aliases = {
        switchoc = "!f() { git switch $1 2>/dev/null || git switch -c $1; }; f";
      };
      extraConfig = {
        color.ui = true;
        commit.verbose = true;
        diff.tool = "nvr";
        difftool.nvr.cmd = "${cfg.neovimRemotePackage}/bin/nvr -s -d $LOCAL $REMOTE";
        init.defaultBranch = "main";
        merge.tool = "nvr";
        mergetool.nvr.cmd = "${cfg.neovimRemotePackage}/bin/nvr -s -d $LOCAL $BASE $REMOTE $MERGED -c 'wincmd J | wincmd ='";
        pull.ff = "only";
        rebase.autosquash = true;
        rebase.autostash = true;
        rebase.updateRefs = true;
      };
      ignores = [
        "[._]*.s[a-w][a-z]"
        "[._]s[a-w][a-z]"
        ".claude"
      ];
      delta = {
        enable = true;
      };
    };
  };
}
