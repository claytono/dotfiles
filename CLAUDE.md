# Claude Code Instructions

## Repository Structure

This is a dotfiles repository managed by YADM. Files in the root are symlinked to the home directory.

## Nix Flake

CLI packages are managed by home-manager via `home.nix`.

To apply changes after editing `home.nix`:
```bash
home-manager switch
```

To update inputs:
```bash
nix flake update
```

## Testing Changes

Shell config changes can be tested by sourcing:
```bash
source ~/.bash_profile
```

## Conventions

- Nix must be used for CLI tools when available in nixpkgs. Homebrew is only for GUI apps (casks) and tools not in nixpkgs.
- Shell configs (`.bash_profile`, `.bashrc`) must be idempotent - sourcing multiple times should have no side effects.
- Keep shell configs compatible with both macOS and Linux.
- Use defensive checks (e.g., `[ -f file ] && source file`) for optional integrations.
