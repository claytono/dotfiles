# -*- mode: ruby -*-
# vi: set ft=ruby :

require 'socket'

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

tap "caskroom/fonts"
tap "homebrew/services"
tap "homebrew/cask"
tap "homebrew/cask-drivers"
tap "hmarr/tap"
tap "claytono/extras"
tap "heroku/brew"

tap "github/bootstrap"
tap "github/packages"

brew "ansible"
brew "atool"
brew "autossh"
brew "awscli"
brew "azure-cli"
brew "bash"
brew "bash-completion"
brew "borgbackup"
brew "borgmatic"
brew "borgmatic-runner"
brew "terminal-notifier" # Needed by borgmatic-runner, but brew bundle doesn't detect it.
brew "calc"
brew "codeowners"
brew "coreutils"
brew "curl"
brew "dep"
brew "fd"
brew "findutils"
brew "fzf"
brew "ghi"
brew "git"
brew "git-crypt"
brew "go"
brew "gomplate"
brew "graphviz"
brew "hping"
brew "htop"
brew "jq"
brew "k9s"
brew "kubectx"
brew "kubernetes-cli"
brew "lftp"
brew "node"
brew "mpv"
brew "mtr"
brew "nmap"
brew "p7zip"
brew "prettyping"
brew "pstree"
brew "pyenv"
brew "pyenv-virtualenv"
brew "rbenv"
brew "rbenv-default-gems"
brew "rustup-init"
brew "rclone"
brew "reattach-to-user-namespace"
brew "ripgrep"
brew "sf-pwgen"
brew "shellcheck"
brew "socat"
brew "switchaudio-osx"
brew "telnet"
brew "terraform"
brew "tmux"
brew "unrar"
brew "vim"
brew "watch"
brew "wget"
brew "xz"

# GH
brew "awssume"
brew "gh"

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
cask "iina"
cask "iterm2"
cask "karabiner-elements"
cask "kindle"
cask "macdown"
cask "macmediakeyforwarder"
cask "platypus"
cask "rocket"
cask "spotify"
cask "vagrant"
cask "viscosity"
cask "visual-studio-code"
cask "vlc"
cask "wireshark"

# 3dprinting
cask "ultimaker-cura"
cask "openscad"

if hajnal?
  # Acrobat reader is horrible, but at some point Preview.app started sucking at
  # filling forms.
  cask "adobe-acrobat-reader"
  # For infinity thermostat control
  cask "anki"
  cask "bitbar"
  cask "brave-browser"
  cask "discord"
  cask "mailplane"
  cask "microsoft-teams"
  cask "mqttfx"
  cask "omnigraffle"
  cask "paw"
  cask "plantronics-hub"
  cask "sony-ps4-remote-play"
end

unless is_virtualized?
  cask "virtualbox"
  cask "virtualbox-extension-pack"
  cask "vmware-fusion" if hajnal?
end

cask "caskroom/fonts/font-hack-nerd-font"
cask "caskroom/fonts/font-inconsolata"
cask "caskroom/fonts/font-inconsolata-nerd-font"
cask "caskroom/fonts/font-inconsolata-nerd-font-mono"

brew "mas"
if mas_signed_in?
  mas "Deliveries", id: 924726344
  mas "Keynote", id: 409183694
  mas "Numbers", id: 409203825
  mas "Pages", id: 409201541
  mas "Pixelmator", id: 407963104
  mas "Reeder", id: 880001334
  mas "Tweetbot", id: 557168941
end
