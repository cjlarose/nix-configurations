{ pkgs, ... }: {
  imports = [ ./personal-scripts.nix ];

  home.sessionVariables = {
    EDITOR = "nvr-edit-in-split-window";
  };

  home.packages = [
    pkgs.neovim-remote
  ];

  programs.zsh.enable = true;

  programs.git = {
    enable = true;
    userName = "Chris LaRose";
    userEmail = "cjlarose@gmail.com";
  };

  programs.ssh = {
    enable = true;
    extraOptionOverrides = {
      AddKeysToAgent = "yes";
    };
  };

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
  };
}
