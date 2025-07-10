#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <user@host> <local_project_dir>"
  exit 1
fi

HOST="$1"
LOCAL_DIR="$2"

# Resolve local dir to an absolute path (requires realpath)
if command -v realpath &>/dev/null; then
  LOCAL_DIR="$(realpath "$LOCAL_DIR")"
fi

# Ensure it ends without a trailing slash, for rsync syntax
LOCAL_DIR="${LOCAL_DIR%/}"

# Generate a UUID for this session (so temp dirs never collide)
if command -v uuidgen &>/dev/null; then
  UUID="$(uuidgen)"
else
  UUID="$(date +%s%N)-$RANDOM"
fi

REMOTE_DIR="/tmp/bausystem-${UUID}"

echo ">>> Deploying ${LOCAL_DIR} to ${HOST}:${REMOTE_DIR}"

# 1. Rsync local folder into the remote temp dir
rsync -az -LK --delete "${LOCAL_DIR}/" "${HOST}:${REMOTE_DIR}/"

# 2. SSH in and run the installer (either .sh or .php)
ssh "${HOST}" bash <<EOF
  set -euo pipefail
  echo ">>> Running installer on ${HOST}"
  
  # Check if both installers exist
  if [ -f "${REMOTE_DIR}/install.sh" ] && [ -f "${REMOTE_DIR}/install.php" ]; then
    echo ">>> WARNING: Both install.sh and install.php found in ${REMOTE_DIR}"
    echo ">>> This could indicate an error in project structure"
    echo ">>> Using install.sh by default"
    bash "${REMOTE_DIR}/install.sh"
  elif [ -f "${REMOTE_DIR}/install.sh" ]; then
    echo ">>> Found install.sh, executing with bash"
    bash "${REMOTE_DIR}/install.sh"
  elif [ -f "${REMOTE_DIR}/install.php" ]; then
    echo ">>> Found install.php, executing with php"
    php "${REMOTE_DIR}/install.php"
  else
    echo ">>> ERROR: Neither install.sh nor install.php was found in ${REMOTE_DIR}"
    exit 1
  fi
  
  echo ">>> Done on ${HOST}"
EOF

# Clean up remote directory
ssh "${HOST}" "rm -rf ${REMOTE_DIR}"
