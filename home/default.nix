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
      pkgs.csvtool
      pkgs.dig
      pkgs.docker
      pkgs.docker-compose
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
    initExtra = ''
      # Prompt
      __kube_ps1() {
        local context
        context=$(kubectl config current-context 2> /dev/null)
        [ -z "''${context}" ] && return
        if [[ "''${context}" = gke_* ]]; then
          context="%F{red}(k8s: ''$context)%f"
        else
          context="%F{blue}(k8s: ''$context)%f"
        fi
        echo "''$context "
      }

      setopt prompt_subst
      . ${pkgs.git}/share/git/contrib/completion/git-prompt.sh
      PROMPT='[%m] %~ %F{green}$(__git_ps1 "%s ")%f$(__kube_ps1)$ '

      # Allow command line editing in an external editor
      autoload -Uz edit-command-line
      zle -N edit-command-line
      bindkey '^x^e' edit-command-line

      # push directories to stack on cd
      setopt auto_pushd

      # Bulk renaming
      autoload -U zmv

      function set-kubeconfig {
        # Sets the KUBECONFIG environment variable to a dynamic concatentation of everything
        # under ~/.kube/*

        if [ -d ~/.kube ]; then
          export KUBECONFIG=$(find ~/.kube -maxdepth 1 -type f -name '*.yaml' 2>/dev/null | paste -sd ':' -)
        fi
      }

      add-zsh-hook precmd set-kubeconfig
    '';
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
    package = (additionalPackages system).go_1_18;
    goPrivate = [
      "bitbucket.org/picktrace"
      "github.com/picktrace"
    ];
  };
}
