#!/usr/bin/env bash

# Configuration
export AUTO_UPGRADES="/etc/apt/apt.conf.d/20auto-upgrades"
export UNATTENDED_UPGRADES="/etc/apt/apt.conf.d/50unattended-upgrades"
export UNATTENDED_UPGRADE_MARKER="# UNATTENDED UPGRADES"
export JAVA_VERSION="16"
export JAVA_HASH="7863447f0ab643c585b9bdebf67c69db"
export POETRY_VERSION="1.1.11"
export PATH="/root/.local/bin:$PATH"

# Generic global flags for predictability
export LC_ALL="C.UTF-8"
export LANG="C.UTF-8"
export DEBIAN_FRONTEND="noninteractive"
export TZ="UTC"
export PATH="/root/.local/bin:$PATH"

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

function prepare_docker_env {
  label "Preparing Docker environment"

  echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf

  apt-get update
  apt-get install -y ca-certificates cron
  mkdir -p /etc/cron.hourly/
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
deb http://de.archive.ubuntu.com/ubuntu/ focal main restricted
deb http://de.archive.ubuntu.com/ubuntu/ focal multiverse
deb http://de.archive.ubuntu.com/ubuntu/ focal universe
deb http://de.archive.ubuntu.com/ubuntu/ focal-updates main restricted
deb http://de.archive.ubuntu.com/ubuntu/ focal-updates multiverse
deb http://de.archive.ubuntu.com/ubuntu/ focal-updates universe
deb http://de.archive.ubuntu.com/ubuntu/ focal-backports main restricted universe multiverse
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
  
  # Go
  add-apt-repository -y ppa:longsleep/golang-backports

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
    golang-1.18 \
    google-cloud-sdk \
    google-cloud-sdk-firestore-emulator \
    libffi-dev \
    libssl-dev \
    make \
    nodejs \
    npm \
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

  systemctl enable cron
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

  systemctl enable firebase
}

function setup_az {
  label "Setting up Azure CLI"
  az extension add --upgrade --name azure-devops
}

function setup_docuum {
  label "Setting up Docuum"
  
  echo "Installing Docuum"
  curl https://raw.githubusercontent.com/stepchowfun/docuum/main/install.sh -LSfs | sh

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

  systemctl enable docuum
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

    cat << EOF > /etc/profile.d/99-build-machine.sh
# GLOBAL ENV
export LC_ALL="C.UTF-8"
export LANG="C.UTF-8"
export DEBIAN_FRONTEND="noninteractive"
export TZ="UTC"
export GOPATH="$HOME/go"
export PATH="/root/.local/bin:/usr/lib/go-1.18/bin:$GOHOME/bin:$PATH"

$ENV_SETUP
EOF
}


echo -e "\x1b[1;31m"
echo "/---------------------------\\"
echo "|                           |"
echo "| Azure build machine setup |"
echo "|                           |"
echo "\\---------------------------/"
echo -en "\e[0m"
echo ""

start_time="$(date +%s)"

prepare_docker_env
configure_dpkg
configure_updates
setup_prerequisites
setup_python
setup_gcloud
setup_node
install_java
setup_git
setup_firestore_emulator
setup_az
setup_docuum
setup_builder_prune_cron
setup_env

label "Cleaning up"
apt-get autoremove -y
apt-get clean

end_time=$(date +%s)
elapsed=$(( end_time - start_time ))
label "Done in $elapsed seconds"
