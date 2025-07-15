#!/bin/sh
set -e

# Check required environment variables
: "${SOURCE_FILE:?Missing SOURCE_FILE}"
: "${TARGET_DIR:?Missing TARGET_DIR}"
: "${TARGET_FILE:?Missing TARGET_FILE}"
: "${REGISTRIES_FILENAME:?Missing REGISTRIES_FILENAME}"

echo "Creating directory if it doesn't exist..."
mkdir -p "${TARGET_DIR}"

# Function to mask secrets in YAML files using yq
mask_secrets() {
  yq eval '
    (.. | select(has("auth")) | select(.auth | has("username")) | .auth.username) = "<REDACTED>" |
    (.. | select(has("auth")) | select(.auth | has("password")) | .auth.password) = "<REDACTED>" |
    (.. | select(has("auth")) | select(.auth | has("token")) | .auth.token) = "<REDACTED>"
  ' "$1"
}

# Show diff if old file exists
if [ -f "${TARGET_FILE}" ]; then
  echo "Comparing old and new configurations..."

  # Check if files are actually different (not just formatting)
  if cmp -s "${SOURCE_FILE}" "${TARGET_FILE}"; then
    echo "No changes detected in configuration"
    echo "Skipping file write - configuration is already up to date"
  else
    # Create masked versions for diff display
    OLD_MASKED_FILE="/tmp/old_masked.yaml"
    NEW_MASKED_FILE="/tmp/new_masked.yaml"

    mask_secrets "${TARGET_FILE}" > "${OLD_MASKED_FILE}"
    mask_secrets "${SOURCE_FILE}" > "${NEW_MASKED_FILE}"

    echo "Configuration changes detected:"
    diff -u --label "OLD ${TARGET_FILE}" "${OLD_MASKED_FILE}" --label "NEW ${TARGET_FILE}" "${NEW_MASKED_FILE}" || true
    echo "(secrets redacted in diff above)"

    # Cleanup temp files
    rm -f "${OLD_MASKED_FILE}" "${NEW_MASKED_FILE}"

    # Copy new file to final location
    echo "Writing registries configuration..."
    cp "${SOURCE_FILE}" "${TARGET_FILE}"
    echo "Configuration written successfully to ${TARGET_FILE}"
  fi
else
  echo "Creating new registries configuration file"
  echo "New configuration preview (secrets redacted):"
  mask_secrets "${SOURCE_FILE}" | sed 's/^/  /'

  # Copy new file to final location
  echo "Writing registries configuration..."
  cp "${SOURCE_FILE}" "${TARGET_FILE}"
  echo "Configuration written successfully to ${TARGET_FILE}"
fi

echo "File permissions:"
ls -la "${TARGET_FILE}"
echo "Task completed successfully"
