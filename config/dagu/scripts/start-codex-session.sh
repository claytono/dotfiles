#!/bin/bash
set -uo pipefail

cleanup() {
  if [ -n "${tmpdir:-}" ] && [ -d "$tmpdir" ]; then
    rm -rf "$tmpdir"
  fi
}

if [ "$#" -lt 2 ] || [ "$1" != "codex" ] || [ "$2" != "exec" ]; then
  printf 'Usage: %s codex exec [args...]\n' "$0" >&2
  exit 2
fi

tmpdir="$(mktemp -d)" || exit 1
trap cleanup EXIT HUP INT TERM

# Run Codex in an isolated temp dir, bypassing the repo check because mktemp
# does not create a Git repo or a trusted project path.
output="$(cd "$tmpdir" && "$1" "$2" --skip-git-repo-check -C "$tmpdir" "${@:3}" </dev/null 2>&1)"
rc=$?
cleanup
if [ "$rc" -ne 0 ] && printf '%s\n' "$output" | grep -Eq "(You've hit your (usage )?limit|Limit reached|hit your limit|rate_limit)"; then
  printf 'Usage limit detected: %s\n' "$output"
  exit 0
fi
printf '%s\n' "$output"
exit "$rc"
