# shellcheck shell=bash

# check if this is a login shell
# Use shopt instead of $0 check - works with both -bash and bash -l
shopt -q login_shell && export LOGIN_BASH="1"

# run bash_profile if this is not a login shell
[ -z "$LOGIN_BASH" ] && source ~/.bash_profile

if [ -n "${GHOSTTY_RESOURCES_DIR}" ] && [ -f "${GHOSTTY_RESOURCES_DIR}/shell-integration/bash/ghostty.bash" ]; then
  builtin source "${GHOSTTY_RESOURCES_DIR}/shell-integration/bash/ghostty.bash"
fi

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

# prompt colors
pc_lgreen="\[$(tput setaf 10)\]"
pc_lblue="\[$(tput setaf 12)\]"
pc_lred="\[$(tput setaf 9)\]"
pc_reset="\[$(tput sgr0)\]"

# inline flake name
flake_segment='${FLAKE_NAME:+${FLAKE_NAME}❄️}'

# inline conditional user (shown if not coneill, claytono, or codespace)
user_segment='$( [[ $USER != "coneill" && $USER != "claytono" && $USER != "codespace" ]] && echo "'$pc_lred'\u'$pc_reset'@" )'

# inline git branch
git_branch_segment='$(b=$(git rev-parse --abbrev-ref HEAD 2>/dev/null); [[ -n "$b" ]] && echo "'$pc_lred' ($b)'$pc_reset'")'

# final prompt string
PS1="$flake_segment$user_segment${pc_lgreen}\h${pc_reset}:${pc_lblue}\w${pc_reset}$git_branch_segment\$ "
PROMPT_DIRTRIM=3

alias k='kubecolor'

command -v direnv &>/dev/null && eval "$(direnv hook bash)"

[ -f ~/.fzf.bash ] && source ~/.fzf.bash

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

[[ -f ~/.bash-preexec.sh ]] && source ~/.bash-preexec.sh
command -v atuin &>/dev/null && eval "$(atuin init bash --disable-up-arrow)"
