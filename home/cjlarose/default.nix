{ system, additionalPackages, stateVersion }:
{ pkgs, ... }: {
  imports = [
    ../../home-manager-modules/dev-tools.nix
    ../../home-manager-modules/neovim.nix
    ../../home-manager-modules/git.nix
    ../../home-manager-modules/shell.nix
  ];

  cjlarose.shell.nvrPackage = additionalPackages.${system}.nvr;
  cjlarose.shell.kubePrompt = true;
  cjlarose.shell.dockerPrompt = true;

  home.file.".claude/settings.json".text = builtins.toJSON {
    enabledPlugins = {
      "superpowers@claude-plugins-official" = true;
    };
    skipDangerousModePermissionPrompt = true;
    effortLevel = "medium";
    permissions = {
      defaultMode = "bypassPermissions";
    };
  };

  home.stateVersion = stateVersion;

  home.sessionVariables = {
    THOR_MERGE = "${pkgs.neovim-remote}/bin/nvr -s -d";
  };

  home.packages = [
    additionalPackages.${system}.bundix
    additionalPackages.${system}.git-make-apply-command
    pkgs.nodejs_22
    pkgs.oha
    pkgs.parallel
    pkgs.postgresql
    (additionalPackages.${system}.python39.withPackages (python-pkgs: with python-pkgs; [
      faker
      google-cloud-firestore
      google-cloud-pubsub
      ipython
      psycopg2
      pytz
      requests
      setuptools
      shortuuid
    ]))
    pkgs.ruby
    pkgs.socat
    pkgs.speedtest-cli
    pkgs.stack
    additionalPackages.${system}.trueColorTest
    additionalPackages.${system}.claude-code
  ];

  programs.git.userName = "Christopher La Rose";
  programs.git.userEmail = "cjlarose@gmail.com";
  programs.git.extraConfig = {
    "url \"git@bitbucket.org:\"".insteadOf = "https://bitbucket.org";
    "url \"ssh://git@github.com/\"".insteadOf = "https://github.com/";
  };

  programs.ssh = {
    matchBlocks = {
      "*.toothyshouse.com" = {
        forwardAgent = true;
      };
    };
  };

  programs.go = {
    enable = true;
    package = additionalPackages.${system}.go_1_22;
    goPrivate = [
      "bitbucket.org/picktrace"
      "github.com/picktrace"
    ];
  };
}
