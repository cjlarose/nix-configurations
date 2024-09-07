# Prompt
__kube_ps1() {
  local context
  context=$(kubectl config current-context 2> /dev/null)
  [ -z "${context}" ] && return
  if [[ "${context}" = gke_* ]]; then
    context="%F{red}(k8s: $context)%f"
  else
    context="%F{blue}(k8s: $context)%f"
  fi
  echo "$context "
}

setopt prompt_subst
. "${GIT_PACKAGE_DIR}"/share/git/contrib/completion/git-prompt.sh
PROMPT='[%m] %~ %F{green}$(GIT_PS1_SHOWCOLORHINTS=1 GIT_PS1_SHOWUPSTREAM=git GIT_PS1_SHOWDIRTYSTATE=1 __git_ps1 "%s ")%f$(__kube_ps1)$ '

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

autoload -U add-zsh-hook
add-zsh-hook precmd set-kubeconfig

if [ -f ~/.zshlocalrc ]; then
  source ~/.zshlocalrc
fi
