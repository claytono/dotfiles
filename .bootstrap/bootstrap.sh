#!/bin/bash

set -exv -o pipefail

[ "$(uname -s)" = "Darwin" ] && export MACOS=1 && export UNIX=1
[ "$(uname -s)" = "Linux" ] && export LINUX=1 && export UNIX=1

command_exists () {
    type "$1" &> /dev/null ;
}

if [[ -n "$UNIX" ]]; then
  NEED=""
  if ! command_exists git; then
    NEED="git $NEED"
  fi
  if ! command_exists curl; then
    NEED="curl $NEED"
  fi

  if [[ "$NEED" != "" ]]; then
    echo "Need the following binaries available: $NEED"
    exit 1
  fi
fi


if [[ ! -d ~/.dotfiles/.git ]]; then
    rm -rf ~/.dotfiles
    git clone --bare https://github.com/claytono/dotfiles.git ~/.dotfiles
fi

# Setup alias and checkout
shopt -s expand_aliases
alias cfg="git --git-dir=$HOME/.dotfiles --work-tree=$HOME/"
cfg checkout -f
cfg config --local status.showUntrackedFiles no

if [[ -n "$MACOS" ]]; then
  # Install Homebrew
  curl -vL https://raw.githubusercontent.com/Homebrew/install/master/install >/tmp/homebrew-install
  ruby /tmp/homebrew-install
  brew bundle --global
fi
