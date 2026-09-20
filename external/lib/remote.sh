# shellcheck shell=bash
# Shared by the suite wrappers whose suites live on the eval server. Sourced.
#
# The wrapper runs on the workstation; the suite runs on the eval server. A run
# is: copy a payload into a run directory there, start it over ssh, copy the
# results back.
#
# API keys travel on the ssh session's stdin, one per line, and the far side
# exports them for that one process. A key is never part of a command line, a
# file on the eval server, or run-config.txt. No pty is requested: a pty would
# echo the key lines into the captured output.

# xtrace prints every expansion, including the keys.
case $- in *x*) echo "refusing to run under 'set -x': the trace would print the API keys" >&2; exit 2 ;; esac

EVAL_SERVER="${EVAL_SERVER:-ubuntu@192.168.2.175}"
EVAL_ROOT="${EVAL_ROOT:-/opt/evals}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=30
          -o ServerAliveCountMax=10 -o LogLevel=ERROR)

# die <reason> — the reason also lands in $OUT/FAILED, which eval-tier quotes in
# its STATUS file.
die() {
  printf '%s: %s\n' "${SUITE:-wrapper}" "$1" >&2
  if [[ -n "${OUT:-}" ]]; then
    mkdir -p "$OUT"
    printf '%s\n' "$1" > "$OUT/FAILED"
  fi
  exit 1
}

# normalize_url <url> — the repo's other runners take a base URL without /v1,
# the router is usually written with it. Accept both, return it with.
normalize_url() {
  local u="${1%/}"
  u="${u%/v1}"
  printf '%s/v1' "$u"
}

# key_from <ENV-NAME> <default-name> — the value of the named variable. The
# default name may be unset, which means an endpoint without authentication; a
# name the caller chose must be set. The argument is never echoed: a caller who
# passes the key itself by habit must not see it land in a log.
key_from() {
  local name="$1" default_name="$2"
  [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
    || die "the API key argument must be the NAME of an environment variable holding the key"
  if [[ -z "${!name:-}" ]]; then
    [[ "$name" == "$default_name" ]] \
      || die "the environment variable named as the API key argument is not set"
    printf 'none'
    return
  fi
  printf '%s' "${!name}"
}

# Callers build the command with remote_quote, so expanding here is intended.
# shellcheck disable=SC2029
remote() { ssh "${SSH_OPTS[@]}" "$EVAL_SERVER" "$@"; }

# remote_quote <arg>... — one shell-quoted string for the far side.
remote_quote() { printf '%q ' "$@"; }

# remote_preflight <suite> — fail with the reason a reader can act on.
remote_preflight() {
  local suite="$1"
  remote true 2>/dev/null \
    || die "cannot reach the eval server ($EVAL_SERVER) over ssh"
  remote "test -x $(remote_quote "$EVAL_ROOT/$suite/.venv/bin/$suite")" \
    || die "$suite is not installed on $EVAL_SERVER — run external/provision/setup-eval-server.sh"
}

# remote_put <remote-dir> <file>... — payload only; never anything secret.
remote_put() {
  local dir="$1"; shift
  remote "mkdir -p $(remote_quote "$dir")" || die "cannot create $dir on $EVAL_SERVER"
  scp -q "${SSH_OPTS[@]}" "$@" "$EVAL_SERVER:$dir/" || die "cannot copy the payload to $EVAL_SERVER"
}

# remote_stop <run-dir> — end the suite on the eval server. remote.sh records
# its pid in the run directory; its children are the suite's processes. Their
# pids are collected before anything is signalled, because they are reparented
# the moment remote.sh dies and cannot be found through it afterwards. A Python
# process waiting on a request in flight sits on SIGTERM until the request
# returns, so what is still alive after three seconds is killed.
remote_stop() {
  remote "p=\$(cat $(remote_quote "$1/pid") 2>/dev/null) || exit 0
          kids=\$(pgrep -P \"\$p\")
          kill -TERM \$kids \"\$p\" 2>/dev/null
          sleep 3
          kill -KILL \$kids 2>/dev/null
          true" 2>/dev/null
}

# remote_run_with_keys <run-dir> <remote-command> <key>... — each key is one
# stdin line. ssh runs in the background and is waited for, because bash defers
# a trap until a foreground child exits: a wrapper that is told to stop has to
# stop the far side at once, or the suite outlives it and goes on sending
# requests to the endpoint with nobody reading the answers.
remote_run_with_keys() {
  _REMOTE_RUN="$1"; local cmd="$2"; shift 2
  # shellcheck disable=SC2029
  printf '%s\n' "$@" | ssh "${SSH_OPTS[@]}" "$EVAL_SERVER" "$cmd" &
  _REMOTE_SSH_PID=$!
  trap 'remote_stop "$_REMOTE_RUN"; kill "$_REMOTE_SSH_PID" 2>/dev/null; die "interrupted — the run on $EVAL_SERVER was stopped, its directory is kept at $_REMOTE_RUN"' INT TERM HUP
  local rc=0
  wait "$_REMOTE_SSH_PID" || rc=$?
  trap - INT TERM HUP
  return "$rc"
}

# remote_fetch <remote-dir> <local-dir> — returns non-zero when nothing usable
# came back; the caller knows whether the run itself had already failed.
remote_fetch() {
  mkdir -p "$2"
  remote "tar -C $(remote_quote "$1") -cf - ." | tar -C "$2" -xf -
}

# last_log_line <run.log> — what the far side said last; for a Python traceback
# that is the exception.
last_log_line() {
  [[ -f "$1" ]] || return 0
  tr '\r' '\n' < "$1" | grep -v '^[[:space:]]*$' | tail -1 | cut -c1-240
}

# assert_no_key <dir> <key>... — a key that reached the results is a leak, and
# the results are what gets committed and shared.
assert_no_key() {
  local dir="$1" key; shift
  for key in "$@"; do
    [[ "$key" == "none" || ${#key} -lt 8 ]] && continue
    # The pattern comes from a pipe so the key is never in grep's argv.
    if grep -rqF -f <(printf '%s\n' "$key") "$dir"; then
      die "an API key appears in the results under $dir — do not commit them; find the file with grep -rlF"
    fi
  done
}
