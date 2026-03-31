#!/bin/bash
# shellcheck source=../../.bash_profile
source "$HOME/.bash_profile"
export DAGU_HEALTHCHECK_API_KEY="$(/usr/bin/security find-generic-password -a "$(id -un)" -s "healthchecks-api-key" -w 2>/dev/null || true)"
export DAGU_HEALTHCHECK_PING_KEY="$(/usr/bin/security find-generic-password -a "$(id -un)" -s "healthchecks-ping-key" -w 2>/dev/null || true)"
exec dagu start-all \
  --config "$HOME/src/dotfiles/config/dagu/config.yaml" \
  --host 127.0.0.1 \
  --port 6767 \
  "$@"
