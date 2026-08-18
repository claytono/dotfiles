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

# Only load bash completion in interactive shells
if [[ $- == *i* ]] && command_exists brew; then
  if [[ -f "$(brew --prefix)/etc/profile.d/bash_completion.sh" ]]; then
    if command_exists complete; then
      source "$(brew --prefix)/etc/profile.d/bash_completion.sh"
    else
      echo "Warning: bash completion not available - 'complete' command not found" >&2
    fi
  fi
fi

if command_exists lsd; then
    alias ls=lsd
else
  if [ "$MACOS" ]; then
    export CLICOLOR=1
    export LSCOLORS=ExFxCxDxBxegedabagacad
    if command_exists gls; then
      eval "$(gdircolors)"
      alias ls="gls --color=auto"
    fi
  fi
fi

if command_exists vim; then
    EDITOR=$(type -p vim)
    export EDITOR
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

# run bashrc if this is a login, interactive shell
if shopt -q login_shell && [[ "$-" == *i* ]]; then
  source ~/.bashrc
fi


# LM Studio CLI
if [ -d ~/.lmstudio/bin ]; then
  pathmunge ~/.lmstudio/bin after
fi
