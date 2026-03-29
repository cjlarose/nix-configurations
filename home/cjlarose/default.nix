{ system, additionalPackages, stateVersion, include1Password ? false, includeDockerClient ? false, includeGnuSed ? true, includeCoder ? false }:
{ pkgs, ... }: {
  imports = let
    baseImports = [
      ../../home-manager-modules/dev-tools.nix
      ../../home-manager-modules/neovim.nix
      ./karabiner-profile-switcher.nix
    ];
  in baseImports ++ (if include1Password then [./1password.nix] else []);

  home.file.".config/1Password/ssh/agent.toml".source = ../1Password/ssh/agent.toml;
  home.file.".config/karabiner/karabiner.json".source = ../karabiner/karabiner.json;

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

  home.sessionPath = [
    "$HOME/.yarn/bin"
    "$HOME/go/bin"
    "$HOME/Library/Android/sdk/platform-tools"
    "/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
    "/Applications/Inkscape.app/Contents/MacOS"
    "/Applications/WezTerm.app/Contents/MacOS"
    "node_modules/.bin"
  ];

  home.sessionVariables = {
    EDITOR = "${additionalPackages.${system}.nvr}/bin/nvr";
    LESS = "--quit-if-one-screen --RAW-CONTROL-CHARS --no-init";
    THOR_MERGE = "${pkgs.neovim-remote}/bin/nvr -s -d";
    CODER_SSH_CONFIG_FILE = "~/.ssh/config-coder";
  };

  home.packages = let
    commonPackages = [
      additionalPackages.${system}.atlas
      additionalPackages.${system}.bundix
      additionalPackages.${system}.git-make-apply-command
      (pkgs.google-cloud-sdk.withExtraComponents ([pkgs.google-cloud-sdk.components.pubsub-emulator]))
      pkgs.gradle
      pkgs.jdk11
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
      additionalPackages.${system}.teleport_16
      additionalPackages.${system}.trueColorTest
      additionalPackages.${system}.claude-code
    ];
    dockerClientPackages = (if includeDockerClient then [pkgs.docker-client] else []);
    gnuSedPackages = (if includeGnuSed then [pkgs.gnused] else []);
    coderPackages = (if includeCoder then [pkgs.coder] else []);
  in commonPackages ++ dockerClientPackages ++ gnuSedPackages ++ coderPackages;

  home.shellAliases = {
    gs = "git status";
    gd = "git diff";
    gds = "git diff --staged";
    gap = "git add --patch";
    gc = "git commit";
  };

  programs.zsh = {
    enable = true;
    envExtra = ''
      export GIT_PACKAGE_DIR=${pkgs.git}
    '';
    initExtra = builtins.readFile ./init.zsh;
  };

  programs.git = {
    enable = true;
    userName = "Chris LaRose";
    userEmail = "cjlarose@gmail.com";
    aliases = {
      switchoc = "!f() { git switch $1 2>/dev/null || git switch -c $1; }; f";
    };
    extraConfig = {
      color.ui = true;
      commit.verbose = true;
      diff.tool = "nvr";
      difftool.nvr.cmd = "${pkgs.neovim-remote}/bin/nvr -s -d $LOCAL $REMOTE";
      init.defaultBranch = "main";
      merge.tool = "nvr";
      mergetool.nvr.cmd = "${pkgs.neovim-remote}/bin/nvr -s -d $LOCAL $BASE $REMOTE $MERGED -c 'wincmd J | wincmd ='";
      pull.ff = "only";
      rebase.autosquash = true;
      rebase.autostash = true;
      rebase.updateRefs = true;
      "url \"git@bitbucket.org:\"".insteadOf = "https://bitbucket.org";
      "url \"ssh://git@github.com/\"".insteadOf = "https://github.com/";
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

  programs.ssh = {
    enable = true;
    addKeysToAgent = "yes";
    includes = [
      "config-coder"
    ];
    matchBlocks = {
      "*.toothyshouse.com" = {
        forwardAgent = true;
      };
    };
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
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
