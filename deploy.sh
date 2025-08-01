#!/usr/bin/env bash

set -euo pipefail

# Default values
SSH_PORT=""
SSH_PORT_OPT=""

# Parse options
while getopts "P:h" opt; do
  case ${opt} in
    P )
      SSH_PORT=$OPTARG
      SSH_PORT_OPT="-p $SSH_PORT"
      ;;
    h )
      echo "Usage: $0 [-P port] <user@host> <local_project_dir>"
      echo ""
      echo "Options:"
      echo "  -P port    Specify SSH port for connection"
      echo "  -h         Display this help message"
      exit 0
      ;;
    \? )
      echo "Invalid option: $OPTARG" 1>&2
      echo "Usage: $0 [-P port] <user@host> <local_project_dir>"
      exit 1
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      echo "Usage: $0 [-P port] <user@host> <local_project_dir>"
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# Check required positional arguments
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 [-P port] <user@host> <local_project_dir>"
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
if [ -n "$SSH_PORT" ]; then
  echo ">>> Using SSH port: ${SSH_PORT}"
fi

# 1. Rsync local folder into the remote temp dir
rsync -az -LK --delete ${SSH_PORT:+"-e ssh $SSH_PORT_OPT"} "${LOCAL_DIR}/" "${HOST}:${REMOTE_DIR}/"

# 2. SSH in and run the installer (either .sh or .php)
ssh ${SSH_PORT_OPT} "${HOST}" bash <<EOF
  set -euo pipefail
  echo ">>> Running installer on ${HOST}"
  
  # Set a trap to ensure cleanup on any exit
  trap 'echo ">>> Cleaning up remote directory"; rm -rf "${REMOTE_DIR}"' EXIT
  
  # Change to the remote directory first to make relative paths work
  cd "${REMOTE_DIR}"
  
  # Check if both installers exist
  if [ -f "install.sh" ] && [ -f "install.php" ]; then
    echo ">>> WARNING: Both install.sh and install.php found in ${REMOTE_DIR}"
    echo ">>> This could indicate an error in project structure"
    echo ">>> Using install.sh by default"
    bash install.sh
  elif [ -f "install.sh" ]; then
    echo ">>> Found install.sh, executing with bash"
    bash install.sh
  elif [ -f "install.php" ]; then
    echo ">>> Found install.php, executing with php"
    php install.php
  else
    echo ">>> ERROR: Neither install.sh nor install.php was found in ${REMOTE_DIR}"
    exit 1
  fi
  
  echo ">>> Done on ${HOST}"
  
  # Cleanup is handled by the EXIT trap
EOF
