#!/bin/bash
set -u

# Dagu can dispatch jobs during macOS DarkWake, before normal LAN connectivity
# is available. Promote the system to a full wake, then give networking a short
# opportunity to recover without blocking the DAG if it remains unavailable.
wake_host="${DAGU_WAKE_HOST:-hc.k.oneill.net}"
wake_port="${DAGU_WAKE_PORT:-443}"
wake_attempts="${DAGU_WAKE_ATTEMPTS:-10}"

/usr/bin/caffeinate -u -t 5

for ((attempt = 1; attempt <= wake_attempts; attempt++)); do
  if /usr/bin/nc -z -G 1 "${wake_host}" "${wake_port}" 2>/dev/null; then
    exit 0
  fi
  sleep 1
done

echo "WARNING: ${wake_host}:${wake_port} is still unreachable after wake; running DAG anyway" >&2
exit 0
