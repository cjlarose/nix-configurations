{ config, lib, pkgs, ... }:

let
  cfg = config.cjlarose._1password;
in {
  options.cjlarose._1password = {
    signingKey = lib.mkOption {
      type = lib.types.str;
      description = "SSH public key for git commit signing via 1Password";
    };
  };

  config = {
    home.packages = [
      (pkgs._1password-cli or pkgs._1password)
    ];

    home.file.".config/1Password/ssh/agent.toml".source = ./_1password/agent.toml;

    programs.ssh.extraConfig = ''
      IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    '';

    programs.git = {
      signing = {
        key = cfg.signingKey;
        signByDefault = false;
      };
      extraConfig = {
        gpg.format = "ssh";
        "gpg \"ssh\"" = {
          program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
        };
      };
    };
  };
}
