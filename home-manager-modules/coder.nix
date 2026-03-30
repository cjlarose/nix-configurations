{ pkgs, ... }:
{
  home.packages = [
    pkgs.coder
  ];

  home.sessionVariables = {
    CODER_SSH_CONFIG_FILE = "~/.ssh/config-coder";
  };

  programs.ssh = {
    includes = [
      "config-coder"
    ];
  };
}
