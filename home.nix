{ pkgs, system, pinpox, ... }: {
  imports = [
    ./personal-scripts.nix
    ./neovim.nix
  ];

  home.sessionVariables = {
    EDITOR = "nvr-edit-in-split-window";
    LESS = "--quit-if-one-screen --RAW-CONTROL-CHARS --no-init";
    KUBECONFIG = "$HOME/.kube/gke-dev.yaml:$HOME/.kube/gke-test.yaml:$HOME/.kube/gke-prod.yaml:$HOME/.kube/lab.yaml:$HOME/.kube/local-k3s.yaml";
  };

  home.packages = [
    pinpox.packages.${system}.tfenv
    pkgs.csvtool
    pkgs.dig
    pkgs.docker-compose
    pkgs.fluxctl
    pkgs.go_1_18
    pkgs.google-cloud-sdk
    pkgs.gopls
    pkgs.htop
    pkgs.jq
    pkgs.kotlin-language-server
    pkgs.kubectl
    pkgs.kubernetes-helm
    pkgs.kubeseal
    pkgs.kustomize
    pkgs.moreutils
    pkgs.neovim-remote
    pkgs.nodePackages.bash-language-server
    pkgs.ruby
    pkgs.shellcheck
    pkgs.tree
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
        context=$(kubectl config current-context)
        if [ -n "''${context}" ]; then
          echo "(k8s: ''${context}) "
        fi
      }

      setopt prompt_subst
      . ${pkgs.git}/share/git/contrib/completion/git-prompt.sh
      PROMPT='%~ %F{green}$(__git_ps1 "%s ")%f%F{blue}$(__kube_ps1)%f$ '

      # Allow command line editing in an external editor
      autoload -Uz edit-command-line
      zle -N edit-command-line
      bindkey '^x^e' edit-command-line
    '';
  };

  programs.git = {
    enable = true;
    userName = "Chris LaRose";
    userEmail = "cjlarose@gmail.com";
    extraConfig = {
      color.ui = true;
      rebase.autosquash = true;
      commit.verbose = true;
      pull.ff = "only";
      "url \"git@bitbucket.org:\"".insteadOf = "https://bitbucket.org";
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
}
