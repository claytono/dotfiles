#!/bin/bash

set -e -o pipefail

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SUPPORTED_OS="linux macos"

[ "$(uname -s)" = "Darwin" ] && export MACOS=1 && export UNIX=1 && export OS=macos
[ "$(uname -s)" = "Linux" ] && export LINUX=1 && export UNIX=1 && export OS=linux

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
  target=$HOME"/."$(basename "$linkable" | sed 's/\.symlink.*//')
  os_match="true"
  for os in $SUPPORTED_OS; do
    if [[ $target == *.${os} ]]; then
      if [[ $os == "$OS" ]]; then
        target=$(echo $target|sed "s/\.${OS}//")
      else
        os_match="false"
      fi
    fi
  done

  if [[ $os_match == "false" ]]; then
    continue
  fi

  if [ ! -e "$target" ]; then
    echo "🔗 Linking $target → $linkable"
  else
    echo "🔗 Replacing $target → $linkable"
  fi
  ln -Ff -s "$linkable" "$target"
done

for executable in "$BASEDIR"/**/install.sh; do
  echo "👟 Running $executable"
  bash "$executable"
done
