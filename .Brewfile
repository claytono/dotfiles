# -*- mode: ruby -*-
# vi: set ft=ruby :

require 'socket'

def macos?
  RUBY_PLATFORM =~ /darwin/
end

def linux?
  RUBY_PLATFORM =~ /linux/
end

def is_virtualized?
  `ioreg -l|grep -i board-id` =~ /Virtualbox/i
end

def mas_signed_in?
  %x(mas account) !~ /Not signed in/
  rescue
end

def hostname
  Socket.gethostname
end

def hajnal?
  hostname == 'hajnal'
end

if macos?
  tap "caskroom/fonts"
  tap "claytono/extras"
  tap "homebrew/services"
  tap "homebrew/cask"
  tap "homebrew/cask-drivers"
  tap "hmarr/tap"
  tap "heroku/brew"
  tap "yqrashawn/goku"

  tap "github/bootstrap" if hajnal?
  tap "github/packages" if hajnal?
end

brew "atool"
brew "calc"
brew "dust"
brew "fd"
brew "fzf"
brew "gh"
brew "git"
brew "git-crypt"
brew "htop"
brew "jq"
brew "k9s"
brew "kubectx"
brew "kubernetes-cli"
brew "lftp"
brew "lsd"
brew "nmap"
brew "p7zip"
brew "prettyping"
brew "rclone"
brew "ripgrep"
brew "socat"
brew "tmux"
brew "vim"
brew "wget"
brew "xz"
brew "yadm"

if macos?
  brew "ansible"
  brew "autossh"
  brew "awscli"
  brew "azure-cli"
  brew "bash"
  brew "bash-completion"
  brew "borgbackup"
  brew "borgmatic"
  brew "borgmatic-runner"
  brew "codeowners"
  brew "coreutils"
  brew "curl"
  brew "findutils"
  brew "go"
  brew "goku"
  brew "gomplate"
  brew "graphviz"
  brew "hping"
  brew "httpie"
  brew "node"
  brew "mpv"
  brew "mtr"
  brew "pstree"
  brew "pyenv"
  brew "pyenv-virtualenv"
  brew "rbenv"
  brew "rbenv-default-gems"
  brew "rustup-init"
  brew "reattach-to-user-namespace"
  brew "sf-pwgen"
  brew "shellcheck"
  brew "switchaudio-osx"
  brew "telnet"
  brew "terminal-notifier" # Needed by borgmatic-runner, but brew bundle doesn't detect it.
  brew "watch"

  # GH
  brew "awssume" if hajnal?

  cask "alfred"
  cask "balenaetcher"
  cask "bartender"
  cask "borgbackup"
  cask "carbon-copy-cloner"
  cask "disk-inventory-x"
  cask "docker"
  cask "dropbox"
  cask "evernote"
  cask "franz"
  cask "hammerspoon"
  cask "iina"
  cask "iterm2"
  cask "karabiner-elements"
  cask "kindle"
  cask "macdown"
  cask "macmediakeyforwarder"
  cask "platypus"
  cask "rocket"
  cask "spotify"
  cask "synology-drive"
  cask "vagrant"
  cask "viscosity"
  cask "visual-studio-code"
  cask "vlc"
  cask "wireshark"

  # 3dprinting
  cask "ultimaker-cura"
  cask "openscad"

  cask "caskroom/fonts/font-hack-nerd-font"
  cask "caskroom/fonts/font-inconsolata"
  cask "caskroom/fonts/font-inconsolata-nerd-font"

  unless is_virtualized?
    cask "virtualbox"
    cask "virtualbox-extension-pack"
    cask "vmware-fusion" if hajnal?
  end

  if hajnal?
    # Acrobat reader is horrible, but at some point Preview.app started sucking at
    # filling forms.
    cask "adobe-acrobat-reader"
    # For infinity thermostat control
    cask "anki"
    cask "brave-browser"
    cask "discord"
    cask "mailplane"
    cask "microsoft-teams"
    cask "mqttfx"
    cask "omnigraffle"
    cask "paw"
    cask "plantronics-hub"
    cask "sony-ps4-remote-play"
    cask "swiftbar"
  end

  brew "mas"
  if mas_signed_in?
    mas "Deliveries", id: 924726344
    mas "Pixelmator", id: 407963104
    mas "Reeder", id: 880001334
    mas "Tweetbot", id: 557168941
  end
end

