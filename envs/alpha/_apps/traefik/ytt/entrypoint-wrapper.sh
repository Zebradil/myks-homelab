# Get the IPv6 address of the node and use it in the traefik command
# to bind to this exact address, leaving ports available for other endpoints.

set -euo pipefail

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
  if ps -p $PID >/dev/null; then
    CURRENT_IPV6=$(get_ipv6)
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
