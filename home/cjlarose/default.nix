{ system, pkgs, additionalPackages, stateVersion, include1Password, ... }: {
  imports = [
    ./personal-scripts.nix
    ./neovim.nix
  ];

  home.stateVersion = stateVersion;

  home.sessionPath = [
    "$HOME/.yarn/bin"
    "$HOME/go/bin"
    "$HOME/Library/Android/sdk/platform-tools"
    "/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
  ];

  home.sessionVariables = {
    EDITOR = "${(additionalPackages system).nvr}/bin/nvr";
    LESS = "--quit-if-one-screen --RAW-CONTROL-CHARS --no-init";
    THOR_MERGE = "nvr -s -d";
  };

  home.packages = let
    commonPackages = [
      pkgs.abduco
      (additionalPackages system).atlas
      (additionalPackages system).bundix
      pkgs.corepack
      pkgs.csvtool
      pkgs.dig
      pkgs.docker-client
      pkgs.fluxctl
      pkgs.git-absorb
      pkgs.git-filter-repo
      pkgs.gnused
      pkgs.google-cloud-sdk
      pkgs.gradle
      pkgs.htop
      pkgs.jdk11
      (additionalPackages system).wrappedJq
      pkgs.kotlin-language-server
      pkgs.kubectl
      pkgs.kubernetes-helm
      pkgs.kubeseal
      pkgs.kustomize
      pkgs.neovim-remote
      pkgs.nil
      pkgs.nodePackages.bash-language-server
      pkgs.nodePackages.pyright
      pkgs.nodePackages.typescript-language-server
      pkgs.nodePackages.vscode-langservers-extracted
      pkgs.nodejs_20
      pkgs.parallel
      pkgs.postgresql
      ((additionalPackages system).python39.withPackages (python-pkgs: with python-pkgs; [
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
      (additionalPackages system).wrappedRg
      pkgs.ruby
      pkgs.shellcheck
      pkgs.socat
      pkgs.speedtest-cli
      pkgs.stack
      pkgs.teleport_14
      pkgs.tfenv
      pkgs.tmux
      pkgs.tree
      (additionalPackages system).trueColorTest
      pkgs.unixtools.watch
      pkgs.wget
      pkgs.wrk
      pkgs.yq-go
    ];
  in commonPackages ++ (if include1Password then [pkgs._1password] else []);

  home.shellAliases = {
    gs = "git status";
  };

  programs.zsh = {
    enable = true;
    envExtra = ''
      export GIT_PACKAGE_DIR=${pkgs.git}
    '';
    initExtra = builtins.readFile ./.zshrc;
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
      "url \"git@bitbucket.org:\"".insteadOf = "https://bitbucket.org";
      "url \"ssh://git@github.com/\"".insteadOf = "https://github.com/";

      "remote.origin" = {
        tagopt = "--tags";
        prune = true;
        pruneTags = true;
      };
      "remote.upstream" = {
        tagopt = "--tags";
        prune = true;
        pruneTags = true;
      };
    };
    ignores = [
      "[._]*.s[a-w][a-z]"
      "[._]s[a-w][a-z]"
    ];
  };

  programs.ssh = {
    enable = true;
    extraOptionOverrides = {
      AddKeysToAgent = "yes";
    };
  };

  programs.direnv = {
    enable = true;
    config = {
      disable_stdin = true;
      strict_env = true;
      whitelist = {
        prefix = [
          "/home/cjlarose/workspace/picktrace"
        ];
      };
    };
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.go = {
    enable = true;
    package = pkgs.go_1_22;
    goPrivate = [
      "bitbucket.org/picktrace"
      "github.com/picktrace"
    ];
  };
}
