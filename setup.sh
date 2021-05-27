#!/bin/bash

set -e -o pipefail

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

[ "$(uname -s)" = "Darwin" ] && export MACOS=1 && export UNIX=1
[ "$(uname -s)" = "Linux" ] && export LINUX=1 && export UNIX=1

command_exists () {
    type "$1" &> /dev/null ;
}

if [[ -n "$UNIX" ]]; then
  if ! command_exists curl; then
    NEED="curl $NEED"
  fi

  # Used to have more cases here, so this is more complex than needed.

  if [[ "$NEED" != "" ]]; then
    echo "Need the following binaries available: $NEED"
    exit 1
  fi
fi

if [[ -n "$MACOS" ]]; then
  if ! command_exists brew; then
    # Install Homebrew
    curl -vL https://raw.githubusercontent.com/Homebrew/install/master/install >/tmp/homebrew-install
    ruby /tmp/homebrew-install
    rm -f /tmp/homebrew-install
  fi

  brew bundle install --no-lock --file "$BASEDIR/homebrew/Brewfile.symlink"
fi

# Based on: https://github.com/skalnik/dotfiles/blob/6f1d812ce8d68a541173c1f6f81f640ad9d8840a/install.sh
# Link all linkable files
for linkable in "$BASEDIR"/**/*.symlink*; do
  target=$HOME"/."$(basename "$linkable" | sed 's/\.symlink\..*//')
  if [ ! -e "$target" ]; then
    echo "🔗 Linking $target → $linkable."
  else
    echo "🔗 Replacing $target → $linkable."
  fi
  ln -Ff -s "$linkable" "$target"
done

for executable in "$BASEDIR"/**/install.sh; do
  echo "👟 Running $executable."
  bash "$executable"
done
