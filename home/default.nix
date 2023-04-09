{ pkgs, system, pinpox, server, ... }: {
  imports = [
    ./personal-scripts.nix
    ./neovim.nix
  ];

  home.sessionPath = [
    "$HOME/go/bin"
    "$HOME/Library/Android/sdk/platform-tools"
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
    };
  in commonVariables // (if server then serverVariables else clientVariables);

  home.packages = [
    pinpox.packages.${system}.tfenv
    pkgs.csvtool
    pkgs.delta
    pkgs.dig
    pkgs.docker
    pkgs.docker-compose
    pkgs.fluxctl
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
    pkgs.moreutils
    pkgs.neovim-remote
    pkgs.nodePackages.bash-language-server
    pkgs.nodePackages.pyright
    pkgs.ruby
    pkgs.shellcheck
    pkgs.socat
    pkgs.speedtest-cli
    pkgs.stack
    pkgs.teleport
    pkgs.tmux
    pkgs.tree
    pkgs.wget
    pkgs.yarn
    pkgs.yq-go
  ];

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

      # syntax highlighting in diffs
      core.pager = "delta";
      diff.colorMoved = "default";
      interactive.diffFilter = "delta --color-only";
      merge.conflictstyle = "diff3";
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
    package = pkgs.go_1_18;
    goPrivate = [
      "bitbucket.org/picktrace"
      "github.com/picktrace"
    ];
  };
}
