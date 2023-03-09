#!/usr/bin/env bash

# ------------------ #
# START SCRIPT LOGIC #
# ------------------ #

set -eu
source ./lib.sh

function prepare_docker_env {
  label "Preparing Docker environment"

  echo "Configuring precendence for networking"
  echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf

  echo "Installing ca-certificates and cron"
  apt-get update | dotify
  apt-get install -y ca-certificates cron | dotify
  mkdir -p /etc/cron.hourly/
}

echo -e "\x1b[1;31m"
echo "/-------------------\\"
echo "|                   |"
echo "| Build image setup |"
echo "|                   |"
echo "\\-------------------/"
echo -en "\e[0m"
echo ""

start_time="$(date +%s)"

prepare_docker_env
./prepare.sh

label "Cleaning up"
apt-get autoremove -y
apt-get clean

end_time=$(date +%s)
elapsed=$(( end_time - start_time ))
label "Done in $elapsed seconds"
