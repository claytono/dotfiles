#!/bin/bash

set -eixv -o pipefail

# Install Homebrew
curl -vL https://raw.githubusercontent.com/Homebrew/install/master/install >/tmp/homebrew-install
ruby /tmp/homebrew-install

if [[ ! -d ~/.dotfiles/.git ]]; then
    rm -rf ~/.dotfiles
    git clone --bare https://github.com/claytono/dotfiles.git ~/.dotfiles
fi

# Setup alias and checkout
shopt -s expand_aliases
alias cfg="git --git-dir=$HOME/.dotfiles --work-tree=$HOME/"
cfg checkout -f
cfg config --local status.showUntrackedFiles no

brew bundle --global
