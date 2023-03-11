#!/usr/bin/env bash

export JAVA_VERSION="18"
export NODE_VERSION="18"
export PYTHON_VERSIONS="3.10 3.11"
export POETRY_VERSION="1.4.0"
export GOLANG_VERSION="1.20"

#
# Prepare the environment for use as an agent machine
# Configures the system, installs needed software, etc.
#
# Should be run from `setup.sh` or `setup_docker.sh`
#

export AGENT_ALLOW_RUNASROOT="1"
export AUTO_UPGRADES="/etc/apt/apt.conf.d/20auto-upgrades"
export UNATTENDED_UPGRADES="/etc/apt/apt.conf.d/50unattended-upgrades"
export UNATTENDED_UPGRADE_MARKER="# UNATTENDED UPGRADES"

set -eu

source ./lib.sh

export IN_DOCKER=0
if [[ "${ENV_LAST_LINE:-}" == "LEAVE-ME-HERE" ]]; then
  export IN_DOCKER=1
  echo "Running in Docker"
fi

function disable_ipv6 {
  label "Disabling IPv6"

  sysctl -a | grep disable_ipv6 | sed -E 's@ = 0@ = 1@g' > /etc/sysctl.d/01-disable-ipv6.conf
  sysctl -p /etc/sysctl.d/01-disable-ipv6.conf

  if [[ -f /etc/default/grub ]]; then
    sed -Ei 's@GRUB_CMDLINE_LINUX_DEFAULT=""@GRUB_CMDLINE_LINUX_DEFAULT="ipv6.disable=1"@g' /etc/default/grub
    update-grub
  fi
}

function prepare_dpkg {
  label "Preparing dpkg"

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

  apt-get remove -qy man-db --purge
}

function configure_updates {
  # Use local mirrors
  label "Configuring mirrors"

  # Why the fuck does every vendor customize these and then also fuck it up?
  cat << EOF > /etc/apt/sources.list
deb mirror://mirrors.ubuntu.com/mirrors.txt jammy main restricted
deb mirror://mirrors.ubuntu.com/mirrors.txt jammy multiverse
deb mirror://mirrors.ubuntu.com/mirrors.txt jammy universe
deb mirror://mirrors.ubuntu.com/mirrors.txt jammy-updates main restricted
deb mirror://mirrors.ubuntu.com/mirrors.txt jammy-updates multiverse
deb mirror://mirrors.ubuntu.com/mirrors.txt jammy-updates universe
deb mirror://mirrors.ubuntu.com/mirrors.txt jammy-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu jammy-security main restricted
deb http://security.ubuntu.com/ubuntu jammy-security multiverse
deb http://security.ubuntu.com/ubuntu jammy-security universe
EOF

  label "Updating APT"
  apt-get update | dotify
  apt-get dist-upgrade -y | dotify

  label "Setting up unattended upgrades"
  apt-get install -y unattended-upgrades update-notifier-common  --option=Dpkg::Options::=--force-confdef | dotify

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
  label "Setting up prerequisites"
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
    zip \
    unzip \
    wget \
    | dotify

  echo "Enabling repos"
  # Docker
  if [ ! -f /usr/share/keyrings/docker-archive-keyring.gpg ]; then
      curl -q -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg -q --dearmor > /etc/apt/trusted.gpg.d/download.docker.com.gpg
  fi

  echo "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

  # Node
  curl -q -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -  | dotify
  curl -q -sL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg -q --dearmor > /etc/apt/trusted.gpg.d/dl.yarnpkg.com.gpg
  echo "deb https://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list

  # Python
  add-apt-repository -y ppa:deadsnakes/ppa | dotify

  # Go
  add-apt-repository -y ppa:longsleep/golang-backports | dotify

  # Azure CLI
  curl -q -sL https://packages.microsoft.com/keys/microsoft.asc | gpg -q --dearmor > /etc/apt/trusted.gpg.d/packages.microsoft.com.gpg
  add-apt-repository "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" | dotify

  # Google Cloud SDK
  echo "deb https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list
  curl -q https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg -q --dearmor > /etc/apt/trusted.gpg.d/packages.cloud.google.com.gpg

  # .NET core
  wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
  dpkg -i packages-microsoft-prod.deb | dotify
  rm packages-microsoft-prod.deb

  echo "Reloading package indexes"
  apt-get update | dotify

  echo "Installing extra tools"
  apt-get install -y \
    azure-cli \
    build-essential \
    containerd.io \
    docker-ce \
    docker-ce-cli \
    g++ \
    gcc \
    golang-${GOLANG_VERSION} \
    google-cloud-sdk \
    google-cloud-sdk-firestore-emulator \
    libffi-dev \
    libssl-dev \
    make \
    nodejs \
    python3 \
    python3-venv \
    python3-dev \
    python3-pip \
    pipx \
    dotnet6 \
    aspnetcore-runtime-6.0 \
    yarn \
    | dotify

  echo "Installing Python versions $PYTHON_VERSIONS"
  for PYTHON_VERSION in $PYTHON_VERSIONS; do
    apt-get install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-dev | dotify
  done

  echo "Installing other deps"
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
    xvfb \
    | dotify
}

function setup_python {
  label "Configuring Python"

  # Set first version from $PYTHON_VERSIONS as default
  for PYTHON_VERSION in $PYTHON_VERSIONS; do
    echo "Setting Python $PYTHON_VERSION as default"
    update-alternatives --install /usr/bin/python python /usr/bin/python${PYTHON_VERSION} 1
    break
  done

  # Upgrade pip
  echo "Updating pip"
  curl -q https://bootstrap.pypa.io/get-pip.py | python | dotify

  echo "Installing Poetry"
  curl -q -sSL https://install.python-poetry.org | python | dotify
  ln -sf "${HOME}/.poetry/bin/poetry" /usr/bin/poetry

  echo "Installing pre-commit"
  pip install pre-commit | dotify
}

function setup_gcloud {
  label "Configuring gcloud SDK"
  gcloud config set --installation component_manager/disable_update_check true
}

function setup_node {
  label "Configuring Node"

  echo "Installing pnpm"
  npm install -g pnpm | dotify

  echo "Installing firebase-tools"
  pnpm install -g firebase-tools | dotify
}

function install_java {
  label "Installing Java 😷"
  apt-get install -y "openjdk-${JAVA_VERSION}-jre" | dotify
}

function setup_git {
  label "Setting up Git"
  git config --global user.name "Pipelines"
  git config --global user.email "<noreply@pipelines.local>"
}

function install_custom_tools {
  label "Installing custom tools"
  # Install gcrc
  pipx install gcrc --force | dotify
}

function setup_firestore_emulator {
  label "Installing Firestore emulator"
  set -x

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

  if [[ "$IN_DOCKER" == "0" ]]; then
    systemctl daemon-reload
    systemctl enable firebase
    systemctl start firebase
  fi
  set +x
}

function setup_az {
  label "Setting up Azure CLI"
  az extension add --upgrade --name azure-devops
}

function setup_fast_drive {
  local PART
  local OPTS

  if [[ "${FAST_DRIVE-}" == "" ]]; then
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

function setup_docuum {
  label "Setting up Docuum"

  echo "Installing Docuum"
  curl -q -LSfs https://raw.githubusercontent.com/stepchowfun/docuum/main/install.sh | sh

  cat << EOF > /etc/systemd/system/docuum.service
[Unit]
Description=Docuum
After=docker.service
Wants=docker.service

[Service]
Environment='THRESHOLD=100 GB'
ExecStart=/usr/local/bin/docuum --threshold \${THRESHOLD}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  if [[ "$IN_DOCKER" == "0" ]]; then
    systemctl daemon-reload
    systemctl enable docuum
    systemctl start docuum
  fi
}

function setup_chrome {
  label "Setting up Google Chrome"

  wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  dpkg -i google-chrome-stable_current_amd64.db > /dev/null 2>/dev/null || true
  apt --fix-broken install -y | dotify

}

function setup_builder_prune_cron {
  label "Setting up cronjob to prune BuildKit cache"

  cat << EOF > /etc/cron.hourly/docker_builder_prune
docker builder prune --all --force --keep-storage '60 GB'
EOF

  chmod +x /etc/cron.hourly/docker_builder_prune
}

function setup_env {
  label "Setting up global environment"

  ENV_SETUP="${ENV_SETUP:-}"

  cat << EOF > /etc/profile.d/99-build-machine.sh
# GLOBAL ENV
export LC_ALL="C.UTF-8"
export LANG="C.UTF-8"
export DEBIAN_FRONTEND="noninteractive"
export TZ="UTC"
export GOPATH="$HOME/go"
export PATH="/root/.local/bin:/usr/lib/go-${GOLANG_VERSION}/bin:\$GOPATH/bin:\$PATH"

$ENV_SETUP
EOF

  if [[ "$IN_DOCKER" == "0" ]]; then
    timedatectl set-timezone UTC
    timedatectl set-ntp on
  fi
}

disable_ipv6
prepare_dpkg
configure_updates
setup_prerequisites
setup_python
setup_gcloud
setup_node
install_java
setup_git
setup_firestore_emulator
setup_az
setup_fast_drive
setup_docuum
setup_chrome
setup_builder_prune_cron
setup_env

}