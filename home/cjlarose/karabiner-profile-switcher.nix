{ pkgs, ... }:
let
  switcherScript = pkgs.writeScriptBin "karabiner-profile-switcher" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./karabiner-profile-switcher.py}
  '';
in
{
  home.packages = [ switcherScript ];

  home.file.".config/karabiner-profile-switcher/config.json".source = ./karabiner-profile-switcher-config.json;

  launchd.agents.karabiner-profile-switcher = {
    enable = true;
    config = {
      ProgramArguments = [ "${switcherScript}/bin/karabiner-profile-switcher" ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/karabiner-profile-switcher.log";
      StandardErrorPath = "/tmp/karabiner-profile-switcher.log";
    };
  };
}
