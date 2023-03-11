#!/usr/bin/env bash

AGENT_ID="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 4 | head -n 1)"

# Configuration
export HOST="worker-$AGENT_ID"

export ENV_SETUP=""
export FAST_DRIVE=""

# Azure DevOps configuration
export AZURE_AGENT_PATH="$HOME/agents/"
export AZURE_AGENT_POOL="Default"
export AZURE_AGENT_NAME="$HOST"
export AZURE_AGENT_COUNT="6"
export AZURE_ORG=""
export AZURE_PAT=""

# Set to "" to install latest release after .NET 6 and OpenSSL 3 support is released
# https://github.com/microsoft/azure-pipelines-agent/issues/3922
export AZURE_AGENT_VERSION="3.217.0"


# ------------------ #
# START SCRIPT LOGIC #
# ------------------ #

set -eu
source ./lib.sh

while [ "${1-}" != "" ]; do
    case $1 in
        --azure-agent-name)             shift
                                        export AZURE_AGENT_NAME=$1
                                        ;;
        --azure-agent-pool)             shift
                                        export AZURE_AGENT_POOL=$1
                                        ;;
        --azure-org)                    shift
                                        export AZURE_ORG=$1
                                        ;;
        --azure-pat)                    shift
                                        export AZURE_PAT=$1
                                        ;;
        --azure-agent-count)            shift
                                        export AZURE_AGENT_COUNT=$1
                                        ;;
        --env)                          shift
                                        export ENV_SETUP=$1
                                        ;;
        --fast-drive)                   shift
                                        export FAST_DRIVE=$1
                                        ;;
        * )                             error "Invalid argument: $1"
                                        exit 1
    esac
    shift
done

function validate_args {
    local valid=1
    local azure_settings=5

    if [[ "$AZURE_AGENT_POOL" == "" ]]; then
        error "No agent pool. Use --azure-agent-pool to specify agent pool"
        azure_settings=$(($azure_settings-1))
    fi

    if [[ "$AZURE_AGENT_NAME" == "" ]]; then
        error "No agent name. Use --azure-agent-name to specify agent name"
        azure_settings=$(($azure_settings-1))
    fi

    if [[ "$AZURE_ORG" == "" ]]; then
        error "No Azure DevOps organization. Use --org to specify an organization"
        azure_settings=$(($azure_settings-1))
    fi

    if [[ "$AZURE_PAT" == "" ]]; then
        error "No Personal Access Token. Use --pat to specify a Personal Access Token"
        azure_settings=$(($azure_settings-1))
    fi

    if [[ "$AZURE_AGENT_COUNT" == "" ]]; then
        error "No agent count specified."
        azure_settings=$(($azure_settings-1))
    fi

    if [[ "$azure_settings" != "0" && "$azure_settings" != "5" ]]; then
      echo "Azure configuration exists, but not all Azure settings are configured"
      valid=0
    fi

    if [[ "$FAST_DRIVE" != "" ]]; then
        if [[ ! -e "$FAST_DRIVE" ]]; then
          error "$FAST_DRIVE not found"
          valid=0
        fi
    fi

    if [[ "$FAST_DRIVE" == "" && -e /dev/sdb ]]; then
      echo "Found /dev/sdb but no --fast-drive configured, are you sure you didn't forget something?"
      sleep 3
    fi

    if [[ "$valid" == "0" ]]; then
        exit 1
    fi
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
    if [[ "$AZURE_AGENT_NAME" == "$HOST" ]]; then
      AZURE_AGENT_NAME="$old_host"
    fi
    return
  fi

  label "Setting hostname $HOST"

  hostnamectl set-hostname "$HOST"
  hostname "$HOST"
}

function setup_firewall {
  label "Configuring firewall"
  ufw allow 22
  ufw --force enable
}

echo -e "\x1b[1;31m"
echo "/---------------------\\"
echo "|                     |"
echo "| Build machine setup |"
echo "|                     |"
echo "\\---------------------/"
echo -en "\e[0m"
echo ""

check_root
validate_args

start_time="$(date +%s)"

set_hostname
#./prepare.sh
[[ "$AZURE_PAT" != "" ]] && check_pat_token
[[ "$AZURE_PAT" != "" ]] && setup_azure_agent
setup_firewall

label "Cleaning up"
apt-get autoremove -y
apt-get clean

end_time=$(date +%s)
elapsed=$(( end_time - start_time ))
label "Done in $elapsed seconds"
