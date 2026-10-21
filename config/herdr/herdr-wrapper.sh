#!/usr/bin/env bash
# Installed as `herdr` on macOS (see home.nix), which fills in the store
# paths of the real herdr and jq below.
#
# macOS Local Network privacy attributes a process to the app at the root of
# its launch chain. A server that herdr starts itself belongs to the terminal
# that ran it, and its panes lose LAN access once that terminal quits. This
# wrapper starts any missing server through Herdr.app instead, so the server
# and its panes always count as Herdr.app. See config/herdr/app/launcher.c.
#
# Only commands that attach the local client can start a server; everything
# else, including help and anything run inside a herdr pane, goes straight to
# herdr. HERDR_APP_BYPASS=1 skips the app entirely.
set -euo pipefail

herdr=@herdr@
jq=@jq@
app="$HOME/Library/Application Support/net.oneill.herdr/Herdr.app"

session=${HERDR_SESSION:-default}
explicit=0
attach=1
if [[ ${1-} == session && ${2-} == attach && $# -eq 3 ]]; then
  case $3 in
    help | --help | -h) attach=0 ;;
  esac
  session=$3
  explicit=1
else
  args=("$@")
  i=0
  while ((i < $#)); do
    case ${args[i]} in
      --session)
        session=${args[i + 1]-}
        explicit=1
        ((i += 2))
        ;;
      --session=*)
        session=${args[i]#--session=}
        explicit=1
        ((i += 1))
        ;;
      *)
        attach=0
        break
        ;;
    esac
  done
fi

# Inside a pane, herdr's socket variables point the client at the current
# server unless a session is named explicitly.
if [[ $explicit -eq 0 && -n ${HERDR_SOCKET_PATH-}${HERDR_CLIENT_SOCKET_PATH-} ]]; then
  attach=0
fi

# herdr refuses to attach from inside one of its own panes before starting
# anything; let it, rather than starting a server it will not use.
if [[ ${HERDR_ENV-} == 1 ]]; then
  attach=0
fi

if [[ $attach -eq 0 || -z $session || -n ${HERDR_APP_BYPASS-} || ! -d $app ]]; then
  exec "$herdr" "$@"
fi

# herdr's own client decides whether a server is running by connecting to
# its client socket, and starts one itself, outside Herdr.app, when that
# fails. Probe the same socket. `herdr session list` only checks the control
# socket, which a shutting-down server keeps open after it has closed the
# client socket.
session_field() {
  # $name and $field are jq variables, not shell expansions.
  # shellcheck disable=SC2016
  "$herdr" session list --json |
    "$jq" -r --arg name "$session" --arg field "$1" '.sessions[] | select(.name == $name) | .[$field]'
}
api_socket() {
  session_field socket_path
}
listening() {
  [[ -n $1 ]] && /usr/bin/nc -U -w 1 "$1" </dev/null >/dev/null 2>&1
}
api_up() {
  listening "$(api_socket)"
}
client_up() {
  local api
  api=$(api_socket)
  [[ -n $api ]] && listening "${api%/*}/herdr-client.sock"
}

# Before a server starts and restores its panes, check the .envrc of every
# directory those panes open in. Each must be allowed: the restore stops
# until it is, offering `direnv allow` after showing what changed. An .envrc
# can also declare how to tell whether loading it will prompt, for example
# for a 1Password secret, and how to get it ready:
#
#   # envrc-ready: <command that exits 0 when loading will not prompt>
#   # envrc-prepare: <command that gets it ready, such as direnv exec . true>
#
# Not-ready directories are prepared one at a time here, so each prompt
# appears once in this terminal instead of once per restored pane. Without an
# envrc-prepare line nothing is run; the wrapper asks whether to retry, start
# anyway or cancel. The lines are part of the .envrc, so `direnv allow`
# covers them.
envrc_copies="$HOME/Library/Caches/net.oneill.herdr/envrc-allowed"

ask() {
  local reply
  read -r -p "$1" reply </dev/tty || return 1
  printf '%s' "$reply"
}

# Print "<allowed>\t<path>" for the .envrc direnv would load in $1; allowed
# is 0 when direnv has approved its current contents.
envrc_status() {
  (cd "$1" && direnv status --json 2>/dev/null) |
    "$jq" -r '.state.foundRC // empty | "\(.allowed)\t\(.path)"'
}

# Keep a copy of each allowed .envrc, so a later change can be shown as a
# diff against what was approved.
save_envrc_copy() {
  local copy
  copy="$envrc_copies/$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
  mkdir -p "$envrc_copies"
  chmod 0700 "$envrc_copies"
  cmp -s "$1" "$copy" 2>/dev/null || cp "$1" "$copy"
}

show_envrc_changes() {
  local rc=$1 dir top main main_rc="" copy
  dir=${rc%/*}
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || top=""
  main=$(git -C "$dir" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p') || main=""
  if [[ -n $top && -n $main && $main != "$top" ]]; then
    # The same .envrc in the main checkout, for one in a subdirectory too.
    main_rc=$main/${rc#"$top"/}
  fi
  copy="$envrc_copies/$(printf '%s' "$rc" | cksum | cut -d' ' -f1)"
  if [[ -n $main_rc && -f $main_rc &&
    $(envrc_status "${main_rc%/*}") == "0"$'\t'"$main_rc" ]]; then
    if cmp -s "$main_rc" "$rc"; then
      echo "It is identical to the allowed $main_rc."
    else
      echo "Changes from the allowed $main_rc:"
      git --no-pager diff --no-index --color=auto -- "$main_rc" "$rc" || true
    fi
  elif [[ -f $copy ]]; then
    echo "Changes since herdr last saw it allowed:"
    git --no-pager diff --no-index --color=auto -- "$copy" "$rc" || true
  else
    echo "No earlier allowed copy to compare against; the whole file:"
    cat "$rc"
  fi
}

prepare_panes() {
  command -v direnv >/dev/null || return 0
  local session_dir
  if ! session_dir=$(session_field session_dir); then
    echo "herdr: could not list sessions to check the '$session' panes' .envrc files." >&2
    exit 1
  fi
  [[ -n $session_dir && -f $session_dir/session.json ]] || return 0

  local -A seen=()
  local allowed=() blocked=() still_blocked=() dir info rc
  while IFS= read -r dir; do
    [[ -d $dir ]] || continue
    info=$(envrc_status "$dir") || continue
    [[ -n $info ]] || continue
    rc=${info#*$'\t'}
    [[ -z ${seen[$rc]-} ]] || continue
    seen[$rc]=1
    if [[ ${info%%$'\t'*} == 0 ]]; then
      allowed+=("$rc")
      save_envrc_copy "$rc"
    else
      blocked+=("$rc")
    fi
  done < <("$jq" -r '[.. | objects | (.cwd // empty), (.identity_cwd // empty)] | unique[]' \
    "$session_dir/session.json")

  for rc in "${blocked[@]}"; do
    echo
    echo "herdr: direnv has not allowed $rc."
    show_envrc_changes "$rc"
    if [[ $(ask "Allow it? [y/N] " || true) == [yY]* ]] && direnv allow "$rc"; then
      allowed+=("$rc")
      save_envrc_copy "$rc"
    else
      still_blocked+=("$rc")
    fi
  done
  if ((${#still_blocked[@]} > 0)); then
    echo "herdr: not starting the '$session' server; these .envrc files are not allowed:" >&2
    printf '  %s\n' "${still_blocked[@]}" >&2
    exit 1
  fi

  local ready prepare tried choice
  for rc in "${allowed[@]}"; do
    ready=$(sed -n 's/^# envrc-ready: //p' "$rc" | head -n 1)
    [[ -n $ready ]] || continue
    prepare=$(sed -n 's/^# envrc-prepare: //p' "$rc" | head -n 1)
    tried=""
    until (cd "${rc%/*}" && bash -c "$ready") >/dev/null 2>&1; do
      # Without an envrc-prepare line there is nothing to run; ask straight
      # away, so it can be fixed by hand and retried.
      if [[ -n $tried || -z $prepare ]]; then
        choice=$(ask "herdr: ${rc%/*} is ${tried:+still }not ready. [r]etry, [s]tart anyway, [c]ancel? " || true)
        case $choice in
          [rR]*) ;;
          [sS]*) break ;;
          *) exit 1 ;;
        esac
      fi
      if [[ -n $prepare ]]; then
        echo "herdr: preparing ${rc%/*}"
        (cd "${rc%/*}" && bash -c "$prepare") || true
        tried=1
      fi
    done
  done
}

if ! client_up; then
  # A server that is shutting down closes its client socket first. Wait for
  # it to exit, so the replacement below starts through Herdr.app.
  for _ in {1..100}; do # 20 seconds
    api_up || break
    client_up && break
    sleep 0.2
  done
fi

if ! client_up; then
  if api_up; then
    echo "herdr: the '$session' server is starting or shutting down; try again shortly." >&2
    exit 1
  fi

  prepare_panes

  # Leave a launch request for Herdr.app (see launcher.c): the environment
  # herdr would give a server it started itself, including the directory for
  # its first pane. Write it under a temporary name so the launcher never
  # reads a partial file.
  launch_dir="$HOME/Library/Caches/net.oneill.herdr/launch"
  mkdir -p "$launch_dir"
  chmod 0700 "$launch_dir"
  request=$(mktemp "$launch_dir/.request.XXXXXX")
  ready=""
  # Remove the request however this exits, including Ctrl-C, unless the
  # launcher has already claimed it. exec below does not run the trap.
  trap 'rm -f "$request" ${ready:+"$ready"}' EXIT
  trap 'exit 130' INT TERM
  (
    if [[ $explicit -eq 1 ]]; then
      unset HERDR_SOCKET_PATH HERDR_CLIENT_SOCKET_PATH
    fi
    if [[ $session == default ]]; then
      unset HERDR_SESSION
    else
      export HERDR_SESSION=$session
    fi
    HERDR_STARTUP_CWD=$PWD env -0
  ) >"$request"
  ready="$launch_dir/request.${request##*/.request.}.env"
  mv "$request" "$ready"

  /usr/bin/open -n -g -a "$app"
  for _ in {1..75}; do # 15 seconds, as herdr itself allows
    client_up && break
    sleep 0.2
  done
  if ! client_up; then
    echo "herdr: Herdr.app did not start the '$session' server." >&2
    echo "herdr: See ~/Library/Logs/herdr-server.log; HERDR_APP_BYPASS=1 skips the app." >&2
    exit 1
  fi
fi

exec "$herdr" "$@"
