def is_virtualized?
  `ioreg -l|grep -i board-id` =~ /Virtualbox/i
end

def mas_signed_in?
  %x(mas account) !~ /Not signed in/
  rescue
end

tap "caskroom/fonts"
tap "caskroom/versions"
tap "caskroom/cask"
tap "homebrew/services"
tap "claytono/extras"

brew "ansible"
brew "asdf"
brew "awscli"
brew "bash"
brew "bash-completion"
brew "borgmatic"
brew "borgmatic-runner"
brew "terminal-notifier" # Needed by borgmatic-runner, but brew bundle doesn't detect it.
brew "calc"
brew "coreutils"
brew "fd"
brew "findutils", args: ["with-default-names"]
brew "git"
brew "git-crypt"
brew "go"
brew "gomplate"
brew "hub"
brew "jq"
brew "kubectx"
brew "kubernetes-cli"
brew "legit"
brew "mpv"
brew "mtr"
brew "nmap"
brew "pstree"
brew "rbenv"
brew "rbenv-default-gems"
brew "rclone"
brew "reattach-to-user-namespace"
brew "ripgrep"
brew "shellcheck"
brew "socat"
brew "terraform"
brew "the_silver_searcher"
brew "tmux"
brew "vim"
brew "watch"
brew "wget"
brew "xz"
brew "zstd"

# Acrobat reader is horrible, but at some point Preview.app started sucking at
# filling forms.
cask "adobe-acrobat-reader"
cask "alfred"
cask "bartender"
cask "caskroom/versions/docker-edge"
cask "borgbackup"
cask "dropbox"
cask "evernote"
cask "iterm2"
cask "java"
cask "kindle"
cask "mailplane"
cask "omnigraffle"
cask "rocket"
cask "spotify"
cask "textexpander"
cask "vagrant"
cask "viscosity"

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
  mas "Alternote", id: 974971992
  mas "Deliveries", id: 924726344
  mas "Keynote", id: 409183694
  mas "Numbers", id: 409203825
  mas "Pages", id: 409201541
  mas "Pixelmator", id: 407963104
  mas "Reeder", id: 880001334
  mas "SnoozeMaster", id: 614955483
  mas "Tweetbot", id: 557168941
  mas "YubiKey Personalization Tool", id: 638161122
end
