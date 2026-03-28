#!/bin/bash
#
# Called by Dagu handler_on.exit to register and ping healthchecks.io.
#
# Environment (set by Dagu and dagu-wrapper.sh):
#   DAG_NAME              - name of the DAG (e.g., "cleanup-nix")
#   DAG_RUN_STATUS        - "succeeded", "failed", etc.
#   DAGU_HEALTHCHECK_API_KEY   - management API key for creating checks
#   DAGU_HEALTHCHECK_PING_KEY  - ping key for pinging checks
#

set -eu -o pipefail

HC_HOST="https://hc.k.oneill.net"
CHECK_NAME="dagu-${DAG_NAME}"

# Create check if it doesn't exist (idempotent via unique constraint)
if [[ -z "${DAGU_HEALTHCHECK_API_KEY:-}" ]]; then
  echo "ERROR: DAGU_HEALTHCHECK_API_KEY is not set" >&2
  exit 1
fi

curl -sf -m 10 --retry 3 "${HC_HOST}/api/v1/checks/" \
  --data-binary @- >/dev/null 2>&1 <<EOF || true
{"api_key":"${DAGU_HEALTHCHECK_API_KEY}","name":"${CHECK_NAME}","timeout":604800,"grace":86400,"tags":"dagu","channels":"*","unique":["name"]}
EOF

# Ping based on DAG run status
if [[ -z "${DAGU_HEALTHCHECK_PING_KEY:-}" ]]; then
  echo "ERROR: DAGU_HEALTHCHECK_PING_KEY is not set" >&2
  exit 1
fi

case "${DAG_RUN_STATUS:-}" in
  succeeded)
    curl -fsS -m 10 --retry 5 -o /dev/null "${HC_HOST}/ping/${DAGU_HEALTHCHECK_PING_KEY}/${CHECK_NAME}"
    ;;
  *)
    curl -fsS -m 10 --retry 5 -o /dev/null "${HC_HOST}/ping/${DAGU_HEALTHCHECK_PING_KEY}/${CHECK_NAME}/fail"
    ;;
esac
