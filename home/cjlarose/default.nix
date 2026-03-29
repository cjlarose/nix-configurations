{ system, additionalPackages, stateVersion, includeDockerClient ? false, includeCoder ? false }:
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
    CODER_SSH_CONFIG_FILE = "~/.ssh/config-coder";
  };

  home.packages = let
    commonPackages = [
      pkgs.abduco
      additionalPackages.${system}.atlas
      additionalPackages.${system}.bundix
      pkgs.corepack
      pkgs.csvtool
      pkgs.dig
      pkgs.gh
      pkgs.git-filter-repo
      additionalPackages.${system}.git-make-apply-command
      (pkgs.google-cloud-sdk.withExtraComponents ([pkgs.google-cloud-sdk.components.pubsub-emulator]))
      pkgs.gradle
      pkgs.jdk11
      pkgs.kotlin-language-server
      pkgs.kubernetes-helm
      pkgs.kubeseal
      pkgs.kustomize
      pkgs.pyright
      pkgs.nodePackages.typescript-language-server
      pkgs.nodePackages.vscode-langservers-extracted
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
      pkgs.shellcheck
      pkgs.socat
      pkgs.speedtest-cli
      pkgs.stack
      additionalPackages.${system}.teleport_16
      additionalPackages.${system}.trueColorTest
      pkgs.wget
      additionalPackages.${system}.claude-code
    ];
    dockerClientPackages = (if includeDockerClient then [pkgs.docker-client] else []);
    coderPackages = (if includeCoder then [pkgs.coder] else []);
  in commonPackages ++ dockerClientPackages ++ coderPackages;

  programs.git.userName = "Chris LaRose";
  programs.git.userEmail = "cjlarose@gmail.com";
  programs.git.extraConfig = {
    "url \"git@bitbucket.org:\"".insteadOf = "https://bitbucket.org";
    "url \"ssh://git@github.com/\"".insteadOf = "https://github.com/";
  };

  programs.ssh = {
    includes = [
      "config-coder"
    ];
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
