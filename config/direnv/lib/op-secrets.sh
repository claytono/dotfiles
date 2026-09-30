# shellcheck shell=bash
# direnv library: load 1Password secrets through a per-repo cache in /tmp.
#
# Agent shells (Claude Code, Codex) have no TTY, so every `op` call there asks
# for Touch ID again. Resolving all of a repo's secrets in one `op inject` and
# caching the result in a user-only directory under /tmp (cleared at boot)
# gives one prompt per repo per boot for terminals and agents alike.
#
# Usage in .envrc:
#
#   use op_secrets
#   op_set NOTION_TOKEN "op://Private/Notion/API Token"
#   op_set HOMEBOX_PASSWORD "op://infra/homebox/admin_password"
#   op_load
#
# Changing the op_set lines refetches into the same cache file. After rotating a
# secret in 1Password, run `op-secrets-refresh` in the repo.

use_op_secrets() {
	_op_secrets_names=()
	_op_secrets_refs=()
	_op_secrets_active=1
}

op_set() {
	if [[ -z ${_op_secrets_active:-} ]]; then
		log_error "op_set: call 'use op_secrets' first"
		return 1
	fi
	if [[ $# -ne 2 || ! $1 =~ ^[A-Za-z_][A-Za-z0-9_]*$ || $2 != op://* ]]; then
		log_error "op_set: usage: op_set NAME op://vault/item/field"
		return 1
	fi
	_op_secrets_names+=("$1")
	_op_secrets_refs+=("$2")
}

op_load() {
	if [[ -z ${_op_secrets_active:-} || ${#_op_secrets_names[@]} -eq 0 ]]; then
		log_error "op_load: no secrets declared with op_set"
		return 1
	fi

	local dir cache lock rc=0
	dir=$(_op_secrets_cache_dir) || return 1
	cache="$dir/$(_op_secrets_cache_name "$PWD")"
	lock="$dir/.lock.${cache##*/}"

	if [[ -L $cache || (-e $cache && ! -O $cache) ]]; then
		log_error "op_secrets: refusing to use unsafe cache file $cache"
		return 1
	fi

	if ! _op_secrets_cache_current "$cache"; then
		# Parallel agent commands would otherwise each run op inject and each
		# raise a Touch ID prompt. Recheck after locking because another shell
		# may have filled the cache while this one waited.
		_op_secrets_lock "$lock" || return 1
		if ! _op_secrets_cache_current "$cache"; then
			_op_secrets_fetch "$cache" || rc=1
		fi
		_op_secrets_unlock "$lock"
		((rc == 0)) || return 1
	fi

	# shellcheck disable=SC1090 # cache path is computed at runtime
	if ! source "$cache"; then
		log_error "op_secrets: failed to load $cache"
		return 1
	fi
	log_status "op_secrets: loaded ${#_op_secrets_names[@]} secret(s)"
	unset _op_secrets_names _op_secrets_refs _op_secrets_active
}

# Print the cache directory, creating it if needed. Refuses a directory that
# another user could have pre-created in the shared /tmp.
_op_secrets_cache_dir() {
	local dir="/tmp/op-secrets-${USER:-$(id -un)}" perm
	mkdir -m 700 "$dir" 2>/dev/null
	perm=$(stat -c %a "$dir" 2>/dev/null || stat -f %Lp "$dir" 2>/dev/null)
	if [[ ! -d $dir || -L $dir || ! -O $dir || $perm != 700 ]]; then
		log_error "op_secrets: unsafe cache dir $dir (must be a directory owned by you with mode 700)"
		return 1
	fi
	printf '%s\n' "$dir"
}

# One cache file per repo: a readable, bounded form of the directory name plus
# a checksum of the full path, so the name is short and stable for a directory.
_op_secrets_cache_name() {
	local base=${1##*/} sum
	base=${base//[^A-Za-z0-9._-]/_}
	read -r sum _ < <(printf '%s' "$1" | cksum)
	printf '%s-%s\n' "${base:0:64}" "$sum"
}

# Header recording the repo and its declarations. A cache whose header differs
# from the current op_set lines is refetched in place.
_op_secrets_header() {
	local i
	printf '# op_secrets dir=%s\n' "$PWD"
	for i in "${!_op_secrets_names[@]}"; do
		printf '# op_set %s=%s\n' "${_op_secrets_names[i]}" "${_op_secrets_refs[i]}"
	done
}

_op_secrets_cache_current() {
	[[ -f $1 && $(_op_secrets_header) == "$(grep '^# ' "$1")" ]]
}

# Take a mkdir-based lock (flock is not available on macOS by default). Waits
# up to two minutes because the holder may be waiting on a Touch ID prompt.
# Breaks locks whose recorded process has exited, and locks that never got a
# PID written (holder died right after mkdir) once they are 10 seconds old.
_op_secrets_lock() {
	local lock=$1 pid mtime tries=0
	until mkdir "$lock" 2>/dev/null; do
		pid=$(cat "$lock/pid" 2>/dev/null) || pid=
		if [[ -n $pid ]]; then
			if ! kill -0 "$pid" 2>/dev/null; then
				_op_secrets_unlock "$lock"
				continue
			fi
		else
			mtime=$(stat -c %Y "$lock" 2>/dev/null || stat -f %m "$lock" 2>/dev/null) || mtime=
			if [[ -n $mtime ]] && (($(date +%s) - mtime > 10)); then
				_op_secrets_unlock "$lock"
				continue
			fi
		fi
		if ((tries++ >= 600)); then
			log_error "op_secrets: timed out waiting for $lock"
			return 1
		fi
		sleep 0.2
	done
	if ! printf '%s\n' "$$" >"$lock/pid"; then
		_op_secrets_unlock "$lock"
		log_error "op_secrets: could not write $lock/pid"
		return 1
	fi
}

_op_secrets_unlock() {
	rm -f "$1/pid"
	rmdir "$1" 2>/dev/null
}

# Resolve every declared reference in a single `op inject` and write the
# quoted exports to the cache atomically.
_op_secrets_fetch() {
	local cache=$1 n=${#_op_secrets_names[@]} template="" out tmp i line count=0
	# The end marker must follow the last value directly. Command substitution
	# strips trailing newlines, so without it a trailing newline in the final
	# secret would be silently dropped instead of rejected.
	local end=__OP_SECRETS_END__

	if ! command -v op >/dev/null; then
		log_error "op_secrets: 1Password CLI (op) not found"
		return 1
	fi

	for i in "${!_op_secrets_names[@]}"; do
		template+="${_op_secrets_names[i]}={{ ${_op_secrets_refs[i]} }}"$'\n'
	done
	template+="$end"$'\n'

	log_status "op_secrets: fetching $n secret(s) from 1Password"
	if ! out=$(printf '%s' "$template" | op inject); then
		log_error "op_secrets: op inject failed; secrets not loaded"
		return 1
	fi

	tmp=$(mktemp "${cache%/*}/.tmp.XXXXXX") || return 1
	{
		_op_secrets_header
		while IFS= read -r line; do
			if ((count == n)); then
				if [[ $line == "$end" ]]; then
					count=-2
				else
					count=-1
				fi
				break
			fi
			if [[ ${line%%=*} != "${_op_secrets_names[count]}" ]]; then
				count=-1
				break
			fi
			if [[ $line == *'{{'*'op://'* ]]; then
				log_error "op_secrets: ${line%%=*} was not resolved by op inject"
				count=-1
				break
			fi
			printf 'export %s=%q\n' "${line%%=*}" "${line#*=}"
			((count += 1))
		done <<<"$out"
	} >"$tmp"

	if ((count != -2)); then
		rm -f "$tmp"
		log_error "op_secrets: unexpected op inject output (multi-line secret values are not supported)"
		return 1
	fi
	mv -f "$tmp" "$cache"
}
