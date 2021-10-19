#!/usr/bin/env bash

# Configuration
id="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 4 | head -n 1)"
export HOST="pipeline-agent-$id"
export AUTO_UPGRADES="/etc/apt/apt.conf.d/20auto-upgrades"
export UNATTENDED_UPGRADES="/etc/apt/apt.conf.d/50unattended-upgrades"
export UNATTENDED_UPGRADE_MARKER="# UNATTENDED UPGRADES"
export JAVA_VERSION="16"
export JAVA_HASH="7863447f0ab643c585b9bdebf67c69db"
export POETRY_VERSION="1.1.11"
export PATH="/root/.local/bin:$PATH"
export AGENT_ALLOW_RUNASROOT="1"

# Args
AGENT_PATH="$HOME/agents/"
AGENT_POOL="Default"
AGENT_NAME="$HOST"
AGENT_COUNT="1"
ORG=""
PAT=""
ENV_SETUP=""
FAST_DRIVE=""

# Generic global flags for predictability
export LC_ALL="C.UTF-8"
export LANG="C.UTF-8"
export DEBIAN_FRONTEND="noninteractive"
export TZ="UTC"
export PATH="/root/.local/bin:$PATH"

# ------------------ #
# START SCRIPT LOGIC #
# ------------------ #

start_time="$(date +%s)"

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

    if [[ "$FAST_DRIVE" != "" ]]; then
        if [[ ! -e "$FAST_DRIVE" ]]; then
          error "$FAST_DRIVE not found"
          valid=0
        fi
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

function configure_dpkg {
  label "Configuring dpkg"

  cat << EOF > /etc/apt/apt.conf.d/01autoremove
APT
{
  NeverAutoRemove
  {
        "^firmware-linux.*";
        "^linux-firmware$";
        "^linux-image-[a-z0-9]*$";
        "^linux-image-[a-z0-9]*-[a-z0-9]*$";
  };

  VersionedKernelPackages
  {
        # kernels
        "linux-.*";
        "kfreebsd-.*";
        "gnumach-.*";
        # (out-of-tree) modules
        ".*-modules";
        ".*-kernel";
  };

  Never-MarkAuto-Sections
  {
        "metapackages";
        "contrib/metapackages";
        "non-free/metapackages";
        "restricted/metapackages";
        "universe/metapackages";
        "multiverse/metapackages";
        "man-db";
        "gnome-shell";
        "ubuntu-docs";
        "gdm3";
        "ubuntu-session";
        "xserver-xorg-video-*";
        "libdrm-*";
        "*-doc";
        "pulseaudio";
        "*-demo";
        "cups-*";
        "mesa-vulkan-drivers";
  };

  Move-Autobit-Sections
  {
        "oldlibs";
        "contrib/oldlibs";
        "non-free/oldlibs";
        "restricted/oldlibs";
        "universe/oldlibs";
        "multiverse/oldlibs";
  };
};
EOF

  apt-get remove -y man-db --purge
}

function configure_updates {
  # Use local mirrors
  label "Configuring mirrors"
  
  # Why the fuck does every vendor customize these and then also fuck it up?
  cat << EOF > /etc/apt/sources.list
deb mirror://mirrors.ubuntu.com/mirrors.txt focal main restricted
deb mirror://mirrors.ubuntu.com/mirrors.txt focal multiverse
deb mirror://mirrors.ubuntu.com/mirrors.txt focal universe
deb mirror://mirrors.ubuntu.com/mirrors.txt focal-updates main restricted
deb mirror://mirrors.ubuntu.com/mirrors.txt focal-updates multiverse
deb mirror://mirrors.ubuntu.com/mirrors.txt focal-updates universe
deb mirror://mirrors.ubuntu.com/mirrors.txt focal-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu focal-security main restricted
deb http://security.ubuntu.com/ubuntu focal-security multiverse
deb http://security.ubuntu.com/ubuntu focal-security universe
deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ focal main
EOF

  label "Updating APT"
  apt-get update
  apt-get dist-upgrade -y

  label "Setting up unattended upgrades"
  apt-get install -y unattended-upgrades update-notifier-common  --option=Dpkg::Options::=--force-confdef

  if ! grep -q "$UNATTENDED_UPGRADE_MARKER" "$UNATTENDED_UPGRADES"; then
    cat << EOF >> "$UNATTENDED_UPGRADES"
$UNATTENDED_UPGRADE_MARKER
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:12";
EOF
  fi

  echo "APT::Periodic::Update-Package-Lists \"1\";" > "$AUTO_UPGRADES"
  echo "APT::Periodic::Unattended-Upgrade \"1\";" >> "$AUTO_UPGRADES"

  unattended-upgrades
}

function setup_prerequisites {
  label "Configuring prerequisites"
  apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    git \
    gnupg \
    gnupg-agent \
    jq \
    lsb-release \
    openssh-client \
    software-properties-common \
    ufw \
    wget

  label "Enabling repos"
  # Docker
  if [ ! -f /usr/share/keyrings/docker-archive-keyring.gpg ]; then
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  fi

  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

  # Node
  curl -fsSL https://deb.nodesource.com/setup_14.x | bash -
  curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
  echo "deb https://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list

  # Python
  add-apt-repository -y ppa:deadsnakes/ppa

  # Azure CLI
  curl -sL https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
  add-apt-repository "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main"

  # Google Cloud SDK
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -

  # .NET core
  wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
  dpkg -i packages-microsoft-prod.deb
  rm packages-microsoft-prod.deb

  label "Installing extra tools"
  apt-get update
  apt-get install -y \
    azure-cli \
    build-essential \
    containerd.io \
    docker-ce \
    docker-ce-cli \
    g++ \
    gcc \
    google-cloud-sdk \
    google-cloud-sdk-firestore-emulator \
    libffi-dev \
    libssl-dev \
    make \
    nodejs \
    python3.9 \
    python3.9-dev \
    python3.9-venv \
    aspnetcore-runtime-5.0 \
    yarn

  apt-get install -y --no-install-recommends \
    libgtk2.0-0 \
    libgtk-3-0 \
    libgbm-dev \
    libnotify-dev \
    libgconf-2-4 \
    libnss3 \
    libxss1 \
    libasound2 \
    libxtst6 \
    xauth \
    xvfb
}

function setup_python {
  label "Configuring Python"
  update-alternatives --install /usr/bin/python python /usr/bin/python3.9 1
  curl https://bootstrap.pypa.io/get-pip.py | python

  label "Installing Poetry"
  curl -sSL https://raw.githubusercontent.com/python-poetry/poetry/${POETRY_VERSION}/get-poetry.py | python
  ln -sf "${HOME}"/.poetry/bin/poetry /usr/bin/poetry

  label "Installing pre-commit"
  pip install pre-commit

  label "Installing pipx"
  python3.9 -m pip install --user -U pipx
  /root/.local/bin/pipx ensurepath
}

function setup_gcloud {
  label "Configuring gcloud SDK"
  gcloud config set --installation component_manager/disable_update_check true
}

function setup_node {
  label "Configuring Node"
  npm install -g pnpm
  pnpm install -g firebase-tools
}

function install_java {
  label "Installing Java 😷"
  mkdir -p /usr/share/man/man1/
  if [ ! -d /opt/jdk-${JAVA_VERSION} ]; then
      pushd /opt || exit 1
      tarball=openjdk-${JAVA_VERSION}_linux-x64_bin.tar.gz
      # The site http://openjdk.java.net/ provides downloads for OpenJDK releases.
      curl -O \
          https://download.java.net/java/GA/jdk${JAVA_VERSION}/${JAVA_HASH}/36/GPL/${tarball}
      tar xfz ${tarball}
      rm -f ${tarball}

      update-alternatives --install /usr/bin/java java /opt/jdk-${JAVA_VERSION}/bin/java 1
      popd || exit 1
  fi
  rm -rf /usr/share/man/man1/
}

function setup_git {
  label "Setting up Git"
  git config --global user.name "Azure Pipelines"
  git config --global user.email "<noreply@devops.azure.com>"
}

function install_custom_tools {
  label "Installing custom tools"
  # Install gcrc
  pipx install gcrc --force
}

function setup_firewall {
  label "Configuring firewall"
  ufw allow 22
  ufw --force enable
}

function setup_firestore_emulator {
  label "Installing Firestore emulator"

  # Create a service for the firestore emulator
  if [ ! "$(getent passwd firebase)" ]; then
    useradd --system firebase
  fi

  mkdir -p /firebase /home/firebase
  cat << EOF > /firebase/firebase.json
{
  "emulators": {
    "firestore": {
      "port": "8686"
    },
    "ui": {
      "enabled": true,
      "port": 4000
    }
  }
}
EOF

  chown -R firebase:firebase /firebase /home/firebase

  cat << EOF > /etc/systemd/system/firebase.service
[Unit]
Description=Firebase
After=network.target

[Service]
User=firebase
Group=firebase
ExecStart=firebase -P havu-staging emulators:start --only firestore
WorkingDirectory=/firebase
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable firebase
  systemctl start firebase
}

function setup_az {
  label "Setting up Azure CLI"
  az extension add --upgrade --name azure-devops
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

function setup_fast_drive {
  local PART
  local OPTS

  if [[ "$FAST_DRIVE" == "" ]]; then
    return
  fi

  if grep -q "$FAST_DRIVE" "/etc/fstab"; then
    # Already configured
    return
  fi

  label "Configuring $FAST_DRIVE for $AGENT_PATH"
  echo 'start=2048, type=83' | sudo sfdisk "$FAST_DRIVE"
  PART="${FAST_DRIVE}1"
  mkfs.ext4 "$PART" -m 0

  OPTS="barrier=0,data=writeback,relatime"
  mkdir -p "$AGENT_PATH"
  mount -o "$OPTS" "$PART" "$AGENT_PATH"
  echo "$PART $AGENT_PATH ext4 $OPTS 0 0" >> /etc/fstab
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
      popd || exit 1
  done

  # Delete the template folder
  rm -rf "$PIPELINE_AGENT_TMPL"

  popd || exit 1
}

function setup_env {
  label "Setting up global environment"

    cat << EOF > /etc/profile.d/99-build-machine.sh
# GLOBAL ENV
export LC_ALL="C.UTF-8"
export LANG="C.UTF-8"
export DEBIAN_FRONTEND="noninteractive"
export TZ="UTC"
export PATH="/root/.local/bin:$PATH"

$ENV_SETUP
EOF

  timedatectl set-timezone UTC
  timedatectl set-ntp on
}


echo -e "\x1b[1;31m"
echo "/---------------------------\\"
echo "|                           |"
echo "| Azure build machine setup |"
echo "|                           |"
echo "\\---------------------------/"
echo -en "\e[0m"
echo ""

check_root
validate_args
set_hostname
configure_dpkg
configure_updates
setup_prerequisites
setup_python
setup_gcloud
setup_node
install_java
setup_git
setup_firewall
setup_firestore_emulator
setup_az
check_pat_token
setup_fast_drive
setup_agent
setup_env

label "Cleaning up"
apt-get autoremove -y
apt-get clean

end_time=$(date +%s)
elapsed=$(( end_time - start_time ))
label "Done in $elapsed seconds"
