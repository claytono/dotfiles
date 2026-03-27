# Dotfiles

Personal dotfiles managed with [YADM](https://yadm.io/) and [Nix](https://nixos.org/).

## Overview

- **Dotfiles**: Managed by YADM (symlinks files to home directory)
- **CLI packages**: Managed by home-manager via Nix flake (`home.nix`)
- **GUI apps**: Managed by Homebrew casks via `.Brewfile`

## Setup

### New Machine

1. Install Nix using the [Determinate Systems installer](https://determinate.systems/nix-installer/):
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   ```

2. Clone dotfiles with YADM:
   ```bash
   nix run nixpkgs#yadm -- clone https://github.com/claytono/dotfiles.git
   ```

   This will prompt to run bootstrap, which installs Homebrew and runs `brew bundle`.

3. Activate home-manager configuration:
   ```bash
   cd ~/src/dotfiles
   nix run home-manager/master -- switch --flake .
   ```

   This installs all CLI packages defined in `home.nix` and activates the
   home-manager configuration. The first run requires `--flake .` but
   home-manager creates a symlink at `~/.config/home-manager` so subsequent
   runs can use just `home-manager switch`.

## Nix

### Updating Packages

Update flake inputs and rebuild:
```bash
cd ~/src/dotfiles
nix flake update
home-manager switch
```

### Adding New Packages

Edit `home.nix` to add packages, then:
```bash
home-manager switch
```

## Homebrew

GUI apps and some CLI tools are managed via `.Brewfile`.

### Updating Packages

```bash
brew bundle --global
```

### Adding New Packages

Edit `.Brewfile` to add packages or casks, then run `brew bundle --global`.

## What's Included

### Shell Configuration
- `.bash_profile` - PATH setup, shell environment
- `.bashrc` - Interactive shell config, prompt, aliases

### Git Configuration
- `.gitconfig` - Machine-specific git config (includes common)
- `.gitconfig-common` - Shared git settings

### Other
- `.tmux.conf` - tmux configuration
- `.vimrc` - vim configuration
- `.Brewfile` - Homebrew packages and casks
- `home.nix` - Home-manager package configuration
- `flake.nix` - Nix flake definition
