# Get the IPv6 address of the node and use it in the traefik command
# to bind to this exact address, leaving ports available for other endpoints.

set -euo pipefail

function script_error_trap() {
  local last_exit_code=$?
  local line_number=$LINENO

  echo "--- Script Failed Unexpectedly ---" >&2
  echo "Error on line $line_number" >&2
  echo "Exit code: $last_exit_code" >&2

  # shellcheck disable=SC2128
  if [[ -n "$FUNCNAME" && "$FUNCNAME" != "script_error_trap" ]]; then
    echo "Failing function: $FUNCNAME" >&2
  else
    echo "Failing script: $0" >&2
  fi
  echo "-----------------------------------" >&2

  echo "Last known NODE_IPV6: $NODE_IPV6" >&2

  exit $last_exit_code
}

trap script_error_trap ERR

function get_ipv6() {
  nslookup -type=aaaa "${HOSTNAME:?}.${BASE_DOMAIN:?}" 1.1.1.1 \
    | grep '^Address:' \
    | tail -1 \
    | cut -d' ' -f2
}

NODE_IPV6="$(get_ipv6)"

echo "Selected IPv6: $NODE_IPV6"
ARGS=""
for arg in "$@"; do
  ARGS="${ARGS} ${arg/\$NODE_IPV6/$NODE_IPV6}"
done

exec $0 $ARGS &
PID=$!

trap 'kill -TERM $PID' TERM INT

while true; do
  if kill -0 $PID; then
    CURRENT_IPV6="$(get_ipv6)"
    if [[ $NODE_IPV6 != "$CURRENT_IPV6" ]]; then
      echo "IPv6 address changed, restarting traefik"
      echo "New IPv6: $CURRENT_IPV6"
      kill -TERM $PID
      exit 0
    fi
  else
    wait $PID
    exit $?
  fi
  sleep 5
done
