{ pkgs, ... }: {

  home.packages = [
    pkgs._1password
  ];

  programs.git = {
    signing = {
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPVpeUiVCUdL3/2xAORyus00XAOrvXukwpOiaZhdHoKs";
      signByDefault = true;
    };
    extraConfig = {
      gpg.format = "ssh";
      "gpg \"ssh\"" = {
        program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
      };
    };
  };

  programs.ssh = {
    extraConfig = ''
      IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    '';
  };
}
