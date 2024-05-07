setopt prompt_subst
. "${GIT_PACKAGE_DIR}"/share/git/contrib/completion/git-prompt.sh
PROMPT='[%m] %~ %F{green}$(__git_ps1 "%s ")%f$ '

# Allow command line editing in an external editor
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^x^e' edit-command-line

# push directories to stack on cd
setopt auto_pushd

# Bulk renaming
autoload -U zmv

if [ -f ~/.zshlocalrc ]; then
  source ~/.zshlocalrc
fi
