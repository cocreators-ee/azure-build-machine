#!/usr/bin/env bash

# Configuration
id="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 4 | head -n 1)"
export HOST="pipeline-agent-$id"
export AGENT_ALLOW_RUNASROOT="1"

# Args
AGENT_PATH="$HOME/agents/"
AGENT_POOL="Default"
AGENT_NAME="$HOST"
AGENT_COUNT="1"
ORG=""
PAT=""


# ------------------ #
# START SCRIPT LOGIC #
# ------------------ #

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

while [ "$1" != "" ]; do
    case $1 in
        --agent-name)                   shift
                                        AGENT_NAME=$1
                                        ;;
        --agent-pool)                   shift
                                        AGENT_POOL=$1
                                        ;;
        --org)                          shift
                                        ORG=$1
                                        ;;
        --pat)                          shift
                                        PAT=$1
                                        ;;
        --agent-count)                  shift
                                        AGENT_COUNT=$1
                                        ;;
       * )                              error "Invalid argument: $1"
                                        exit 1
    esac
    shift
done

function validate_args {
    local valid=1

    if [[ "$AGENT_POOL" == "" ]]; then
        error "No agent pool. Use --agent-pool to specify agent pool"
        valid=0
    fi

    if [[ "$AGENT_NAME" == "" ]]; then
        error "No agent name. Use --agent-name to specify agent name"
        valid=0
    fi

    if [[ "$ORG" == "" ]]; then
        error "No Azure DevOps organization. Use --org to specify an organization"
        valid=0
    fi

    if [[ "$PAT" == "" ]]; then
        error "No Personal Access Token. Use --pat to specify a Personal Access Token"
        valid=0
    fi

    if [[ "$AGENT_COUNT" == "" ]]; then
        error "No agent count specified."
        valid=0
    fi

    if [[ "$valid" == "0" ]]; then
        exit 1
    fi
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

function check_root {
  if [[ "$EUID" != "0" ]]; then
    echo "Please run as root."
    exit
  fi
}

function set_hostname {
  # Check for previous executions
  local old_host
  old_host=$(hostname)
  if echo "$old_host" | grep -q "pipeline-agent-"; then
    if [[ "$AGENT_NAME" == "$HOST" ]]; then
      AGENT_NAME="$old_host"
    fi
    return
  fi

  label "Setting hostname $HOST"

  hostnamectl set-hostname "$HOST"
  hostname "$HOST"
}

function check_pat_token {
  label "Checking PAT token with Azure CLI"
  local result
  echo "$PAT" | az devops login --organization "https://dev.azure.com/${ORG}/"
  result="$?"
  if [[ "$result" != "0" ]]; then
    error "Failed to log in with the PAT given. Please check token validity."
    exit
  fi
}

function setup_agent {
  label "Setting up Azure DevOps Pipelines Agent"

  # A modified copy of
  # https://github.com/geekzter/azure-pipeline-agents/blob/master/scripts/agent/install_agent.sh

  mkdir -p "$AGENT_PATH"
  pushd "$HOME" || exit 1

  # Find old agent directories, remove agents from DevOps, uninstall service and delete folder
  for old_agent_dir in "$HOME"/pipeline-agent-*; do
      if [ -f "$old_agent_dir/.agent" ]; then
          echo "Removing existing $(basename "$old_agent_dir")"
          pushd "$old_agent_dir" || exit 1
          ./svc.sh stop
          ./svc.sh uninstall
          ./config.sh remove --unattended --auth pat --token "$PAT"
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
  for i in $(seq 1 "$AGENT_COUNT"); do
      PIPELINE_AGENT_DIR="$AGENT_PATH/pipeline-agent-${i}"

      if [ -d "$PIPELINE_AGENT_DIR" ]; then
          echo "Deleting old $(basename "$PIPELINE_AGENT_DIR")"
          rm -rf "$PIPELINE_AGENT_DIR"
      fi

      echo "Creating $PIPELINE_AGENT_DIR"
      cp -r "$PIPELINE_AGENT_TMPL" "$PIPELINE_AGENT_DIR"
      pushd "$PIPELINE_AGENT_DIR" || exit 1

      # Unattended config
      # https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/v2-linux?view=azure-devops#unattended-config
      echo "Creating agent ${AGENT_NAME}-${i} and adding it to pool ${AGENT_POOL} in organization ${ORG}..."
      ./config.sh --unattended \
                  --url "https://dev.azure.com/${ORG}" \
                  --auth pat \
                  --token "${PAT}" \
                  --pool "${AGENT_POOL}" \
                  --agent "$AGENT_NAME-${i}" \
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


echo -e "\x1b[1;31m"
echo "/---------------------\\"
echo "|                     |"
echo "| Azure build machine |"
echo "|                     |"
echo "\\---------------------/"
echo -en "\e[0m"
echo ""

check_root
validate_args

start_time="$(date +%s)"

set_hostname
check_pat_token
setup_agent

label "Cleaning up"
apt-get autoremove -y
apt-get clean

end_time=$(date +%s)
elapsed=$(( end_time - start_time ))
label "Prepared in $elapsed seconds"
echo "Starting up"

exec /sbin/init
