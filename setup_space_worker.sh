#!/usr/bin/env bash

# JetBrains Space configuration
export SPACE_SERVER_URL=""
export SPACE_TOKEN=""
export SPACE_WORKER_NAME=""

# ------------------ #
# START SCRIPT LOGIC #
# ------------------ #

set -eu
source ./lib.sh

while [ "${1-}" != "" ]; do
    case $1 in
        --serverUrl)    shift
                        export SPACE_SERVER_URL=$1
                        ;;
        --token)        shift
                        export SPACE_TOKEN=$1
                        ;;
        --name)         shift
                        export SPACE_WORKER_NAME=$1
                        ;;
        * )             error "Invalid argument: $1"
                        exit 1
    esac
    shift
done

function validate_args {
    local valid=1

    if [[ "$SPACE_SERVER_URL" == "" ]]; then
        error "No Space server URL. Use --serverUrl to specify"
        valid=0
    fi

    if [[ "$SPACE_TOKEN" == "" ]]; then
        error "No Space token. Use --token to specify"
        valid=0
    fi

    if [[ "$SPACE_WORKER_NAME" == "" ]]; then
        error "No Space worker name. Use --name to specify"
        valid=0
    fi

    if [[ "$valid" == "0" ]]; then
        exit 1
    fi
}

function setup_space_worker {
  label "Setting up JetBrains Space worker"

  curl -q -fsSL --output space-automation-worker-linux.zip https://cocreators.jetbrains.space/pipelines/system/worker/linux-x64/zip

  SPACE_ZIP="$(pwd)/space-automation-worker-linux.zip"

  # Create unique path for the worker
  WORKER_PATH="$HOME/space/worker-${SPACE_WORKER_NAME}"
  mkdir -p "$WORKER_PATH"
  cd "$WORKER_PATH" || exit 1
  unzip -q -o "$SPACE_ZIP"
  chmod +x worker.sh
  cd - > /dev/null || exit 1

  cat << EOF > "$WORKER_PATH/start-worker.sh"
#/usr/bin/env bash
./worker.sh start --serverUrl \${SPACE_SERVER_URL} --token \${SPACE_TOKEN}
EOF

  chmod +x "$WORKER_PATH/start-worker.sh"

  cat << EOF > "/etc/systemd/system/space-worker-${SPACE_WORKER_NAME}.service"
[Unit]
Description=Space Worker ${SPACE_WORKER_NAME}
After=network.target

[Service]
User=root
Group=root
Environment='SPACE_SERVER_URL=${SPACE_SERVER_URL}'
Environment='SPACE_TOKEN=${SPACE_TOKEN}'
ExecStart=/usr/bin/env bash ${WORKER_PATH}/start-worker.sh
WorkingDirectory=$WORKER_PATH
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "space-worker-${SPACE_WORKER_NAME}" > /dev/null
  systemctl restart "space-worker-${SPACE_WORKER_NAME}" > /dev/null

  echo "Set up JetBrains Space worker ${SPACE_WORKER_NAME}"
}
validate_args
setup_space_worker
