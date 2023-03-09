#!/usr/bin/env bash

AGENT_ID="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 4 | head -n 1)"

# Configuration
export HOST="pipeline-agent-$AGENT_ID"

# Args
AZURE_AGENT_PATH="$HOME/agents/"
AZURE_AGENT_POOL="Default"
AZURE_AGENT_NAME="$HOST"
AZURE_AGENT_COUNT="1"
AZURE_ORG=""
AZURE_PAT=""
ENV_SETUP=""
FAST_DRIVE=""

# ------------------ #
# START SCRIPT LOGIC #
# ------------------ #

set -eu
source ./lib.sh

while [ "$1" != "" ]; do
    case $1 in
        --azure-agent-name)                   shift
                                        AZURE_AGENT_NAME=$1
                                        ;;
        --azure-agent-pool)                   shift
                                        AZURE_AGENT_POOL=$1
                                        ;;
        --azure-org)                          shift
                                        AZURE_ORG=$1
                                        ;;
        --azure-pat)                          shift
                                        AZURE_PAT=$1
                                        ;;
        --azure-agent-count)                  shift
                                        AZURE_AGENT_COUNT=$1
                                        ;;
        --env)                          shift
                                        ENV_SETUP=$1
                                        ;;
        --fast-drive)                   shift
                                        FAST_DRIVE=$1
                                        ;;
       * )                              error "Invalid argument: $1"
                                        exit 1
    esac
    shift
done

function validate_args {
    local valid=1

    if [[ "$AZURE_AGENT_POOL" == "" ]]; then
        error "No agent pool. Use --azure-agent-pool to specify agent pool"
        valid=0
    fi

    if [[ "$AZURE_AGENT_NAME" == "" ]]; then
        error "No agent name. Use --azure-agent-name to specify agent name"
        valid=0
    fi

    if [[ "$AZURE_ORG" == "" ]]; then
        error "No Azure DevOps organization. Use --org to specify an organization"
        valid=0
    fi

    if [[ "$AZURE_PAT" == "" ]]; then
        error "No Personal Access Token. Use --pat to specify a Personal Access Token"
        valid=0
    fi

    if [[ "$AZURE_AGENT_COUNT" == "" ]]; then
        error "No agent count specified."
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
./prepare.sh
check_pat_token
setup_azure_agent
setup_firewall

label "Cleaning up"
apt-get autoremove -y
apt-get clean

end_time=$(date +%s)
elapsed=$(( end_time - start_time ))
label "Done in $elapsed seconds"
