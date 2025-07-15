#!/bin/sh
set -e

main() {
  check_required_env_vars
  create_target_dir
  if [ -f "${TARGET_FILE}" ]; then
    if cmp -s "${SOURCE_FILE}" "${TARGET_FILE}"; then
      echo "No changes detected in configuration"
      echo "Skipping file write - configuration is already up to date"
      return 0
    else
      diff_configs
    fi
  fi
  apply_config
  echo "Task completed successfully"
}

check_required_env_vars() {
  : "${SOURCE_FILE:?Missing SOURCE_FILE}"
  : "${TARGET_DIR:?Missing TARGET_DIR}"
  : "${TARGET_FILE:?Missing TARGET_FILE}"
  : "${REGISTRIES_FILENAME:?Missing REGISTRIES_FILENAME}"
}

create_target_dir() {
  echo "Creating directory if it doesn't exist..."
  mkdir -p "${TARGET_DIR}"
}

diff_configs() {
  echo "Comparing old and new configurations..."
  OLD_MASKED_FILE="/tmp/old_masked.yaml"
  NEW_MASKED_FILE="/tmp/new_masked.yaml"

  mask_secrets "${TARGET_FILE}" >"${OLD_MASKED_FILE}"
  mask_secrets "${SOURCE_FILE}" >"${NEW_MASKED_FILE}"

  echo "Configuration changes detected:"
  diff -u --label "OLD ${TARGET_FILE}" "${OLD_MASKED_FILE}" --label "NEW ${TARGET_FILE}" "${NEW_MASKED_FILE}" || true
  echo "(secrets redacted in diff above)"

  rm -f "${OLD_MASKED_FILE}" "${NEW_MASKED_FILE}"
}

mask_secrets() {
  yq eval '
    (.. | select(has("auth")) | select(.auth | has("username")) | .auth.username) = "<REDACTED>" |
    (.. | select(has("auth")) | select(.auth | has("password")) | .auth.password) = "<REDACTED>" |
    (.. | select(has("auth")) | select(.auth | has("token")) | .auth.token) = "<REDACTED>"
  ' "$1"
}

apply_config() {
  echo "Applying configuration..."
  install -m 600 "${SOURCE_FILE}" "${TARGET_FILE}"
  echo "Configuration applied successfully to ${TARGET_FILE}"
}

main
