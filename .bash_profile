# OS variables
[ "$(uname -s)" = "Darwin" ] && export MACOS=1 && export UNIX=1
[ "$(uname -s)" = "Linux" ] && export LINUX=1 && export UNIX=1
uname -s | grep -q "_NT-" && export WINDOWS=1
grep -q "Microsoft" /proc/version 2>/dev/null && export UBUNTU_ON_WINDOWS=1

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

AIRPORTCMD="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/A/Resources/airport"
if [ -x $AIRPORTCMD ]; then
  alias airport=$AIRPORTCMD
fi

export GOPATH=$HOME/src/go
pathmunge $GOPATH/bin
pathmunge /usr/local/sbin
pathmunge $HOME/bin

VSCODE_BINDIR="/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
if [ -d "$VSCODE_BINDIR" ]; then
  pathmunge "$VSCODE_BINDIR" after
fi

if command_exists brew; then
  if [[ -f $(brew --prefix)/etc/bash_completion ]]; then
    source $(brew --prefix)/etc/bash_completion
  fi
fi

if [ $MACOS ]; then
  export CLICOLOR=1
  export LSCOLORS=ExFxCxDxBxegedabagacad
  if command_exists gls; then
    eval $(gdircolors)
    alias ls="gls --color=aut"
  fi
fi

if command_exists hub; then
    alias git=hub
fi

if command_exists vim; then
    export EDITOR=$(type -p vim)
    export GIT_EDITOR=$EDITOR
fi

if command_exists rbenv; then
    eval "$(rbenv init -)"
fi

alias "kt=watch kubectl get nodes,pods,cronjobs --all-namespaces -o wide"
alias "cfg=git --git-dir=$HOME/.dotfiles --work-tree=$HOME"

# check if this is a login and/or interactive shell
[ "$0" = "-bash" ] && export LOGIN_BASH="1"
echo "$-" | grep -q "i" && export INTERACTIVE_BASH="1"

# run bashrc if this is a login, interactive shell
if [ -n "$LOGIN_BASH" ] && [ -n "$INTERACTIVE_BASH" ]; then
  source ~/.bashrc
fi
