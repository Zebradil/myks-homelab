# Common library functions for plugins

# l:argocd sets default flags to argocd command
function l:argocd() {
  argocd \
    --grpc-web \
    "$@"
}
