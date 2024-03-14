{ system, pkgs, additionalPackages, stateVersion, server, ... }: {
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

  home.sessionVariables = let
    commonVariables = {
      EDITOR = "nvr-edit-in-split-window";
      LESS = "--quit-if-one-screen --RAW-CONTROL-CHARS --no-init";
      THOR_MERGE = "nvr -s -d";
    };
    serverVariables = {
    };
    clientVariables = {
      DOCKER_HOST = "tcp://local.picktrace.dev:2376";
      DOCKER_BUILDKIT = "1";
    };
  in commonVariables // (if server then serverVariables else clientVariables);

  home.packages = let
    commonPackages = [
      pkgs.abduco
      pkgs.atlas
      (additionalPackages system).bundix
      pkgs.csvtool
      pkgs.dig
      pkgs.docker-client
      pkgs.fluxctl
      pkgs.git-absorb
      pkgs.git-filter-repo
      pkgs.gnused
      pkgs.google-cloud-sdk
      pkgs.gopls
      pkgs.gradle
      pkgs.htop
      pkgs.jdk11
      pkgs.jq
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
      pkgs.ripgrep
      pkgs.ruby
      pkgs.shellcheck
      pkgs.socat
      pkgs.speedtest-cli
      pkgs.stack
      pkgs.teleport
      pkgs.tfenv
      pkgs.tmux
      pkgs.tree
      pkgs.unixtools.watch
      pkgs.wget
      pkgs.wrk
      pkgs.yarn
      pkgs.yq-go
    ];
    serverPackages = [];
    clientPackages = [
      pkgs._1password
    ];
  in commonPackages ++ (if server then serverPackages else clientPackages);

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
    extraConfig = {
      color.ui = true;
      commit.verbose = true;
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
    package = (additionalPackages system).go_1_22;
    goPrivate = [
      "bitbucket.org/picktrace"
      "github.com/picktrace"
    ];
  };
}
