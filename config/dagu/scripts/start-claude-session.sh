#!/bin/bash
set -uo pipefail

cleanup() {
  if [ -n "${tmpdir:-}" ] && [ -d "$tmpdir" ]; then
    rm -rf "$tmpdir"
  fi
}

if [ "$#" -lt 1 ]; then
  printf 'Usage: %s <command> [args...]\n' "$0" >&2
  exit 2
fi

tmpdir="$(mktemp -d)" || exit 1
trap cleanup EXIT HUP INT TERM

# Run Claude in an isolated temp dir, treating usage-limit output as success.
output="$(cd "$tmpdir" && "$@" </dev/null 2>&1)"
rc=$?
cleanup
if [ "$rc" -ne 0 ] && printf '%s\n' "$output" | grep -Eq "(Limit reached|hit your limit)"; then
  printf 'Usage limit detected: %s\n' "$output"
  exit 0
fi
printf '%s\n' "$output"
exit "$rc"
