#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
TARGET_FILE="${SCRIPT_DIR}/lib/cloudflare.lib.yaml"

log() { printf '%s [INFO]  %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$*" >&2; }
warn() { printf '%s [WARN]  %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$*" >&2; }
err() { printf '%s [ERROR] %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')" "$*" >&2; }
die() {
  err "$*"
  exit 1
}

command -v curl &>/dev/null || die "curl not found in PATH."
command -v yq &>/dev/null || die "yq not found in PATH."

# Ensure this is mikefarah/yq
if ! yq --version 2>&1 | grep -qi 'mikefarah'; then
  die "Wrong yq detected. This script requires mikefarah/yq (yq-go). Found: $(yq --version 2>&1)"
fi

[[ -f "$TARGET_FILE" ]] || die "Target file not found: $TARGET_FILE"
[[ -w "$TARGET_FILE" ]] || die "Target file not writable: $TARGET_FILE"

function work() {
  local URL="${1:?}"
  local YAML_PATH="${2:?}"

  log "Fetching content from: $URL"
  content="$(curl -fsSL -- "$URL")" || die "curl failed to fetch: $URL"

  [[ -n "$content" ]] || warn "Fetched content is empty; array will be set to an empty/single-element value."

  line_count="$(printf '%s' "$content" | grep -c '' || true)"
  log "Fetched $line_count line(s)."

  log "Writing lines to '$YAML_PATH' in $TARGET_FILE"
  printf '%s' "$content" | yq -i "${YAML_PATH} = (load_str(\"/dev/stdin\") | split(\"\n\"))" "$TARGET_FILE" \
    || die "yq failed to update $TARGET_FILE"

  log "Done. Updated $TARGET_FILE successfully."
}

work "https://www.cloudflare.com/ips-v4" .ipv4
work "https://www.cloudflare.com/ips-v6" .ipv6
