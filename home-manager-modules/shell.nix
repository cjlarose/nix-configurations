{ config, lib, pkgs, ... }:

let
  cfg = config.cjlarose.shell;

  dangerPatternChecks = builtins.concatStringsSep "\n" (map (pat: ''
        [[ "''${context}" = ${pat} ]] && danger=1
      '') cfg.kubePromptDangerPatterns);

  kubePromptFunction = ''
    __kube_ps1() {
      local context danger=0
      context=$(kubectl config current-context 2> /dev/null)
      [ -z "''${context}" ] && return
      ${dangerPatternChecks}
      if (( danger )); then
        context="%F{red}(k8s: $context)%f"
      else
        context="%F{blue}(k8s: $context)%f"
      fi
      echo "$context "
    }
  '';

  dockerPromptFunction = ''
    __docker_ps1() {
      local context
      context=$(docker context show 2> /dev/null)
      [ -z "''${context}" ] && return
      echo "%F{cyan}(docker: $context)%f "
    }
  '';

  kubePromptCall = if cfg.kubePrompt then "$(__kube_ps1)" else "";
  dockerPromptCall = if cfg.dockerPrompt then "$(__docker_ps1)" else "";

  initZsh = ''
    setopt prompt_subst
    . "''${GIT_PACKAGE_DIR}"/share/git/contrib/completion/git-prompt.sh
  '' + (if cfg.kubePrompt then kubePromptFunction else "")
     + (if cfg.dockerPrompt then dockerPromptFunction else "") + ''
    PROMPT='[%m] %~ %F{green}$(GIT_PS1_SHOWCOLORHINTS=1 GIT_PS1_SHOWUPSTREAM=git GIT_PS1_SHOWDIRTYSTATE=1 __git_ps1 "%s ")%f${kubePromptCall}${dockerPromptCall}
    $ '

    # Allow command line editing in an external editor
    autoload -Uz edit-command-line
    zle -N edit-command-line
    bindkey '^x^e' edit-command-line

    # push directories to stack on cd
    setopt auto_pushd

    # Bulk renaming
    autoload -U zmv

    _set_kubeconfig() {
      local files
      files=(~/.kube/*.yaml(N))
      export KUBECONFIG=''${(j.:.)files}
    }
    precmd_functions+=(_set_kubeconfig)

    # Create symlink for current SSH_AUTH_SOCK and set SSH_AUTH_SOCK to reference the link
    if [ -n "$SSH_AUTH_SOCK" ] && [ "$SSH_AUTH_SOCK" != "$HOME/.ssh/ssh_auth_sock" ]; then
      ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/ssh_auth_sock"
      export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"
    fi

    if [ -f ~/.zshlocalrc ]; then
      source ~/.zshlocalrc
    fi
  '';
in {
  options.cjlarose.shell = {
    nvrPackage = lib.mkOption {
      type = lib.types.package;
      description = "The cstyles/nvr (Rust) package for EDITOR";
    };

    kubePrompt = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Show kubectl context in shell prompt";
    };

    kubePromptDangerPatterns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Glob patterns for kube contexts that should appear in red (danger)";
    };

    dockerPrompt = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Show docker context in shell prompt";
    };
  };

  config = {
    home.sessionVariables = {
      EDITOR = "${cfg.nvrPackage}/bin/nvr";
      LESS = "--quit-if-one-screen --RAW-CONTROL-CHARS --no-init";
    };

    home.sessionPath = [
      "$HOME/.yarn/bin"
      "$HOME/go/bin"
      "node_modules/.bin"
    ];

    programs.zsh = {
      enable = true;
      envExtra = ''
        export GIT_PACKAGE_DIR=${pkgs.git}
      '';
      initExtra = initZsh;
    };

    programs.fzf = {
      enable = true;
      enableZshIntegration = true;
    };

    programs.ssh = {
      enable = true;
      addKeysToAgent = "yes";
    };
  };
}
