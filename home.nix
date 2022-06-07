{ pkgs, ... }: {
  home.packages = [
    pkgs.neovim-remote
  ];

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
