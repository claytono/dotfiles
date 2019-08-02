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
tap "homebrew/cask-drivers"
tap "claytono/extras"
tap "heroku/brew"

brew "ansible"
brew "awscli"
brew "bash"
brew "bash-completion"
brew "borgmatic"
brew "borgmatic-runner"
brew "terminal-notifier" # Needed by borgmatic-runner, but brew bundle doesn't detect it.
brew "calc"
brew "coreutils"
brew "dep"
brew "docker"
brew "fd"
brew "findutils"
brew "fzf"
brew "ghi"
brew "git"
brew "git-crypt"
brew "go"
brew "gomplate"
brew "heroku"
brew "heroku-node"
brew "htop"
brew "httpie"
brew "hub"
brew "jq"
brew "kubectx"
brew "kubernetes-cli"
brew "legit"
brew "lftp"
brew "node"
brew "mpv"
brew "mtr"
brew "nmap"
brew "pstree"
brew "rbenv"
brew "rbenv-default-gems"
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
brew "vim"
brew "watch"
brew "wget"
brew "xz"
brew "zstd"

# Acrobat reader is horrible, but at some point Preview.app started sucking at
# filling forms.
cask "alfred"
cask "bartender"
cask "borgbackup"
cask "dropbox"
cask "evernote"
cask "franz"
cask "google-backup-and-sync"
cask "iina"
cask "iterm2"
cask "karabiner-elements"
cask "kindle"
cask "macmediakeyforwarder"
cask "rocket"
cask "spotify"
cask "vagrant"
cask "viscosity"
cask "visual-studio-code"
cask "wireshark"

if hajnal?
  cask "adobe-acrobat-reader"
  # For infinity thermostat control
  cask "adobe-air" if hajnal?
  cask "anki"
  cask "bitbar"
  cask "logitech-myharmony"
  cask "mailplane"
  cask "mqttfx"
  cask "omnigraffle"
end

unless is_virtualized?
  cask "virtualbox"
  cask "virtualbox-extension-pack"
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
