# -*- mode: ruby -*-
# vi: set ft=ruby :

require 'socket'

def macos?
  RUBY_PLATFORM =~ /darwin/
end

def linux?
  RUBY_PLATFORM =~ /linux/
end

def apple_silicon?
  macos? and RUBY_PLATFORM =~ /arm64/
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
  hostname.start_with? 'hajnal'
end

def xtal?
  hostname.start_with? 'xtal'
end

if macos?
  tap "claytono/extras"
  tap "homebrew/services"
  tap "homebrew/cask"
  tap "homebrew/cask-drivers"
  tap "homebrew/cask-fonts"
  tap "hmarr/tap"
  tap "heroku/brew"
  tap "yqrashawn/goku"
  tap "candid82/brew" # Needed for goku

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
  brew "codeowners"
  brew "coreutils"
  brew "curl"
  brew "findutils"
  brew "go"
  brew "goku"
    brew "joker" # Needed for goku
    brew "watchexec" # Needed for goku
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
  brew "watch"

  # GH
  brew "awssume" if hajnal?

  cask "1password"
  cask "alfred"
  cask "balenaetcher"
  cask "bartender"
  cask "carbon-copy-cloner"
  cask "disk-inventory-x"
  cask "docker"
  cask "evernote"
  cask "franz"
  cask "google-chrome"
  cask "hammerspoon"
  cask "iina"
  cask "iterm2"
  cask "karabiner-elements"
  cask "kindle"
  cask "macdown"
  cask "mailplane"
  cask "macmediakeyforwarder"
  cask "microsoft-edge"
  cask "notion"
  cask "platypus"
  cask "rocket"
  cask "setapp"
  cask "slack"
  cask "spotify"
  cask "synology-drive"
  cask "viscosity"
  cask "visual-studio-code"
  cask "vlc"
  cask "wireshark"

  # 3dprinting
  cask "ultimaker-cura"
  cask "openscad"

  cask "homebrew/cask-fonts/font-hack-nerd-font"

  unless is_virtualized? or apple_silicon?
    cask "virtualbox"
    cask "virtualbox-extension-pack"
    cask "vmware-fusion" if hajnal?
  end

  if hajnal?
    cask "microsoft-teams"
    cask "plantronics-hub"
    cask "paw"
  end

  if xtal?
    cask "mqttfx"
    cask "fujitsu-scansnap-home"
  end

  if hajnal? or xtal?
    # Acrobat reader is horrible, but at some point Preview.app started sucking at
    # filling forms.
    cask "adobe-acrobat-reader"
    cask "anki"
    cask "arq"
    cask "brave-browser"
    cask "discord"
    cask "mailplane"
    cask "omnigraffle"
    cask "swiftbar"
  end

end

