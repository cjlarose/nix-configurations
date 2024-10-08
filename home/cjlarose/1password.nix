{ pkgs, ... }: {

  home.packages = [
    pkgs._1password
  ];

  programs.ssh = {
    extraConfig = ''
      IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    '';
  };
}
