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

## Dagu Job Scheduler

Dagu runs as a launchd agent on macOS, configured in `home.nix`. Configuration lives in `config/dagu/`:
- `config.yaml` — server config (paths, queues). Loaded via `--config` flag in the wrapper script.
- `base.yaml` — shared DAG defaults (retry policy, healthcheck handler). All DAGs inherit these.
- `dags/` — DAG definitions
- `dagu-wrapper.sh` — launchd entrypoint. Reads healthcheck secrets from macOS Keychain, then exec's dagu with `--config`.
- `scripts/healthcheck-ping.sh` — called by the exit handler in base.yaml. Creates healthchecks.io checks on demand and pings success/fail.

Dagu logs (useful for debugging):
- `~/.local/share/dagu/dagu.stdout.log`
- `~/.local/share/dagu/dagu.stderr.log`

Healthcheck secrets are stored in macOS Keychain (bootstrapped via `scripts/bootstrap-secrets --apply`).

Web UI: http://localhost:6767
