#!/bin/bash
set -uo pipefail
# Run a claude command, treating "Limit reached" as success.
output=$("$@" 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && printf '%s\n' "$output" | grep -Eq "(Limit reached|hit your limit)"; then
  printf 'Usage limit detected: %s\n' "$output"
  exit 0
fi
printf '%s\n' "$output"
exit "$rc"
