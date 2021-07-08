# shellcheck shell=bash

# check if this is a login shell
[ "$0" = "-bash" ] && export LOGIN_BASH="1"

# run bash_profile if this is not a login shell
[ -z "$LOGIN_BASH" ] && source ~/.bash_profile

# From: https://github.com/mrzool/bash-sensible/
# Update window size after every command
shopt -s checkwinsize

## SANE HISTORY DEFAULTS ##

# Append to the history file, don't overwrite it
shopt -s histappend

# Save multi-line commands as one command
shopt -s cmdhist

# Record each line as it gets issued
PROMPT_COMMAND='history -a'

# Huge history. Doesn't appear to slow things down, so why not?
HISTSIZE=500000
HISTFILESIZE=100000

# Avoid duplicate entries
HISTCONTROL="erasedups:ignoreboth"

# Don't record some commands
export HISTIGNORE="&:[ ]*:exit:ls:bg:fg:history:clear"

# Useful timestamp format
HISTTIMEFORMAT='%F %T '

# pc_ = promptcolor_
pc_lgreen="\[$(tput setaf 10)\]"
pc_lblue="\[$(tput setaf 12)\]"
pc_lred="\[$(tput setaf 9)\]"
pc_reset="\[$(tput sgr0)\]"

p_user() {
    if [[ $USER != "coneill" && $USER != "claytono " && $USER != "codespace" ]]; then
      echo "${pc_lred}\u${pc_reset}@"
    fi
}

p_git_branch() {
  git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}

prompt_command() {
  PS1="$(p_user)${pc_lgreen}\h${pc_reset}:${pc_lblue}\w${pc_lred}$(p_git_branch)${pc_reset}\$ "
}
PROMPT_DIRTRIM=3
PROMPT_COMMAND=prompt_command

[ -f ~/.fzf.bash ] && source ~/.fzf.bash

if [ -f ~/.ssh/github.id_rsa ]; then
  ssh-add -q ~/.ssh/github.id_rsa
fi
