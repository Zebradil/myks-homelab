# Common library functions for plugins

# l:argocd sets default flags to argocd command
function l:argocd() {
  argocd \
    --grpc-web \
    --server "${ARGOCD_SERVER:?}" \
    "$@"
}

# l:ensure_login ensures that the user is logged in to Argo CD
function l:ensure_login() {
  status="$(l:argocd account get-user-info --output yaml | yq .loggedIn)"
  if [[ "$status" != "true" ]]; then
    echo "Logging in to Argo CD..."
    l:argocd login "${ARGOCD_SERVER:?}"
  fi
}
