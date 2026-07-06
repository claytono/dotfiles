# Renovate Eval Context

## Role of This File

This file provides repository context, discovery hints, validation commands, and
action-menu behavior for Renovate PR evaluation. It does not redefine the shared
`renovate:safe`, `renovate:caution`, `renovate:breaking`, or `renovate:risk`
label semantics.

## Repo Layout

- Nix flake: `flake.nix` and `flake.lock`
- Home Manager configuration: `home.nix`
- Homebrew bundle: `.Brewfile`
- Shell configuration: `.bash_profile`, `.bashrc`, and related root dotfiles
- Dagu scheduler configuration: `config/dagu/`
- Local scripts: `scripts/`
- Renovate configuration: `.renovaterc`

## Normal Validation Actions

- CI lint workflow runs
  `nix develop --command ./scripts/lint --from-ref origin/<base> --to-ref HEAD`.
- Flake builds validate Home Manager activation packages and the Codex package
  across macOS arm64, Linux arm64, and Linux amd64.
- Renovate PRs may trigger `.github/workflows/renovate-lint-fix.yaml`, which
  refreshes flake artifacts and applies pre-commit fixes to lintable files.
- For local evaluation of shell config changes, inspect whether the changed file
  is intended to be safe when sourced repeatedly.

## Config Discovery

- Nix package and Home Manager changes usually live in `flake.nix`,
  `flake.lock`, and `home.nix`.
- Homebrew cask and formula changes live in `.Brewfile`.
- Pre-commit and lint behavior is controlled by `.pre-commit-config.yaml` and
  `scripts/lint`.
- Dagu jobs live under `config/dagu/dags/` and inherit defaults from
  `config/dagu/base.yaml`.

## Notes

- The repository is managed by YADM; many files in the repo root are intended to
  become user-home dotfiles.
- Nix should be used for CLI tools when available. Homebrew is primarily for GUI
  apps, casks, or tools not available in nixpkgs.
- Shell config changes should remain compatible with macOS and Linux and should
  be idempotent when sourced more than once.

## Actions Menu

Include the default shared actions menu. Add a "Review CI artifacts" action when
Renovate changes `flake.nix`, `flake.lock`, `home.nix`, or workflow files,
because those changes often need the matrix build logs to understand impact.
