#!/usr/bin/env bash

# Generic global flags for predictability
export LC_ALL="C.UTF-8"
export LANG="C.UTF-8"
export DEBIAN_FRONTEND="noninteractive"
export TZ="UTC"
export PATH="/root/.local/bin:$PATH"

# Utility functions used in multiple scripts

function error {
  local msg="$*"

  line=$(echo "$msg" | sed 's/./-/g')
  echo ""
  echo -e "\x1b[1;31m"
  echo "    $line"
  echo "    $msg"
  echo "    $line"
  echo -en "\e[0m"
  echo ""
  echo ""
}

function label {
  local msg="$*"

  line=$(echo "$msg" | sed 's/./-/g')
  echo -e "\x1b[1;32m"
  echo "/-$line-\\"
  echo "| $msg |"
  echo "\\-$line-/"
  echo -en "\e[0m"
  echo ""
}

function dotify() {
  # shellcheck disable=SC2034
  while read -r f; do
    builtin echo -n .
  done
  echo
}


function check_pat_token {
  label "Checking AZURE_PAT token with Azure CLI"
  local result
  echo "$AZURE_PAT" | az devops login --organization "https://dev.azure.com/${AZURE_ORG}/"
  result="$?"
  if [[ "$result" != "0" ]]; then
    error "Failed to log in with the AZURE_PAT given. Please check token validity."
    exit
  fi
}

function setup_azure_agent {
  label "Setting up Azure DevOps Pipelines Agent"

  # A modified copy of
  # https://github.com/geekzter/azure-pipeline-agents/blob/master/scripts/agent/install_agent.sh

  mkdir -p "$AZURE_AGENT_PATH"
  pushd "$HOME" || exit 1

  # Find old agent directories, remove agents from DevOps, uninstall service and delete folder
  for old_agent_dir in "$HOME"/pipeline-agent-*; do
      if [ -f "$old_agent_dir/.agent" ]; then
          echo "Removing existing $(basename "$old_agent_dir")"
          pushd "$old_agent_dir" || exit 1
          ./svc.sh stop
          ./svc.sh uninstall
          ./config.sh remove --unattended --auth pat --token "$AZURE_PAT"
          popd || exit 1
          rm -rf "$old_agent_dir"
      fi
  done

  # Get latest released version from GitHub
  AGENT_VERSION=$(curl https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest | jq ".name" | sed -E 's/.*"v([^"]+)".*/\1/')
  AGENT_PACKAGE="vsts-agent-linux-x64-${AGENT_VERSION}.tar.gz"
  AGENT_URL="https://vstsagentpackage.azureedge.net/agent/${AGENT_VERSION}/${AGENT_PACKAGE}"
  PIPELINE_AGENT_TMPL="azure-pipelines-agent-${AGENT_VERSION}"

  # Remove any possibly existing client or template
  rm -rf "$AGENT_PACKAGE" "$PIPELINE_AGENT_TMPL"

  # Download the client
  echo "Dowloading from $AGENT_URL"
  wget "$AGENT_URL" -O "$AGENT_PACKAGE"

  echo "Creating pipeline agent template"
  mkdir "$PIPELINE_AGENT_TMPL"
  pushd "$PIPELINE_AGENT_TMPL" || exit 1
  echo "Extracting ${AGENT_PACKAGE} in $(pwd)..."
  tar zxf "$HOME/$AGENT_PACKAGE"
  echo "Installing dependencies..."
  ./bin/installdependencies.sh
  popd || exit 1

  # Create desired amount of new agents
  for i in $(seq 1 "$AZURE_AGENT_COUNT"); do
      PIPELINE_AGENT_DIR="$AZURE_AGENT_PATH/pipeline-agent-${i}"

      if [ -d "$PIPELINE_AGENT_DIR" ]; then
          echo "Deleting old $(basename "$PIPELINE_AGENT_DIR")"
          rm -rf "$PIPELINE_AGENT_DIR"
      fi

      echo "Creating $PIPELINE_AGENT_DIR"
      cp -r "$PIPELINE_AGENT_TMPL" "$PIPELINE_AGENT_DIR"
      pushd "$PIPELINE_AGENT_DIR" || exit 1

      # Unattended config
      # https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/v2-linux?view=azure-devops#unattended-config
      echo "Creating agent ${AZURE_AGENT_NAME}-${i} and adding it to pool ${AZURE_AGENT_POOL} in organization ${AZURE_ORG}..."
      ./config.sh --unattended \
                  --url "https://dev.azure.com/${AZURE_ORG}" \
                  --auth pat \
                  --token "${AZURE_PAT}" \
                  --pool "${AZURE_AGENT_POOL}" \
                  --agent "$AZURE_AGENT_NAME-${i}" \
                  --replace \
                  --acceptTeeEula

      # Run as systemd service
      echo "Setting up agent to run as systemd service..."
      ./svc.sh install root

      echo "Starting agent service..."
      ./svc.sh start

      ln -s bin/runsvc.sh .
      popd || exit 1
  done

  # Delete the template folder
  rm -rf "$PIPELINE_AGENT_TMPL"

  popd || exit 1
}
