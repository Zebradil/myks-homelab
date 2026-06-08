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
  local logged_in
  logged_in="$(l:argocd account get-user-info --output yaml 2>/dev/null | yq .loggedIn || true)"
  if [[ "$logged_in" != "true" ]]; then
    echo "Logging in to Argo CD..."
    l:argocd login "${ARGOCD_SERVER:?}"
  fi
}
