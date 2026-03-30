# shellcheck shell=bash

# OS variables
[ "$(uname -s)" = "Darwin" ] && export MACOS=1 && export UNIX=1
[ "$(uname -s)" = "Linux" ] && export LINUX=1 && export UNIX=1

command_exists () {
    type "$1" &> /dev/null ;
}

pathmunge () {
        if ! echo "$PATH" | grep -Eq "(^|:)$1($|:)" ; then
           if [ "$2" = "after" ] ; then
              PATH="$PATH:$1"
           else
              PATH="$1:$PATH"
           fi
        fi
}

move_to_front() {
    local dir="$1"
    # Remove the directory from the PATH if it exists
    PATH=$(echo "$PATH" | awk -v RS=: -v ORS=: '$0 != "'"$dir"'"' | sed 's/:$//')
    # Add the directory to the front of the PATH
    export PATH="$dir:$PATH"
}

pathmunge /usr/local/sbin
pathmunge "$HOME/.local/bin"
pathmunge "$HOME/bin"

if [ -d /opt/homebrew/bin ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  pathmunge "$HOMEBREW_PREFIX/opt/findutils/libexec/gnubin"
fi

if [ -d /home/linuxbrew/.linuxbrew/bin ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

VSCODE_BINDIR="/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
if [ -d "$VSCODE_BINDIR" ]; then
  pathmunge "$VSCODE_BINDIR" after
fi

OBSIDIAN_BINDIR="/Applications/Obsidian.app/Contents/MacOS"
if [ -d "$OBSIDIAN_BINDIR" ]; then
  pathmunge "$OBSIDIAN_BINDIR" after
fi

if [ -d "${HOME}/.krew/bin" ]; then
  pathmunge "${HOME}/.krew/bin" after
fi

# Check if bash completion is available before sourcing
if command_exists brew; then
  if [[ -f $(brew --prefix)/etc/bash_completion ]]; then
    if command_exists complete; then
      source $(brew --prefix)/etc/bash_completion
    else
      echo "Warning: bash completion not available - 'complete' command not found" >&2
    fi
  fi
fi

if command_exists lsd; then
    alias ls=lsd
else
  if [ $MACOS ]; then
    export CLICOLOR=1
    export LSCOLORS=ExFxCxDxBxegedabagacad
    if command_exists gls; then
      eval $(gdircolors)
      alias ls="gls --color=aut"
    fi
  fi
fi

if command_exists vim; then
    export EDITOR=$(type -p vim)
    export GIT_EDITOR=$EDITOR
fi

# OrbStack: command-line tools and integration
if [ -f ~/.orbstack/shell/init.bash ]; then
  source ~/.orbstack/shell/init.bash
fi
# Nix PATH priority - ensure nix binaries come first
if [ -d ~/.nix-profile/bin ]; then
  move_to_front ~/.nix-profile/bin
fi
if [ -d /nix/var/nix/profiles/default/bin ]; then
  move_to_front /nix/var/nix/profiles/default/bin
fi

# check if this is a login and/or interactive shell
# Use shopt instead of $0 check - works with both -bash and bash -l
shopt -q login_shell && export LOGIN_BASH="1"
[[ "$-" == *i* ]] && export INTERACTIVE_BASH="1"

# run bashrc if this is a login, interactive shell
if [ -n "$LOGIN_BASH" ] && [ -n "$INTERACTIVE_BASH" ]; then
  source ~/.bashrc
fi


# LM Studio CLI
if [ -d ~/.lmstudio/bin ]; then
  pathmunge ~/.lmstudio/bin after
fi
