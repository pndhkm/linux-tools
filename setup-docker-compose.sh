#!/bin/bash

set -e

if [ "$(id -u)" != "0" ]; then
   echo "Please run this script as root."
   exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=$VERSION_ID
else
    echo "Cannot detect operating system."
    exit 1
fi

echo "Detected OS: $OS $VERSION_ID"

# Install prerequisites
case "$OS" in
    ubuntu|debian)
        apt-get update -y
        apt-get install -y ca-certificates curl gnupg lsb-release
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/$OS $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ;;
    centos|rhel|rocky|almalinux)
        yum install -y yum-utils ca-certificates curl
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ;;
    fedora)
        dnf install -y dnf-plugins-core ca-certificates curl
        dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ;;
    opensuse*|sles)
        zypper install -y curl ca-certificates
        zypper addrepo https://download.docker.com/linux/opensuse/docker-ce.repo
        zypper refresh
        zypper install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        ;;
    *)
        echo "Unsupported operating system: $OS"
        exit 1
        ;;
esac

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Test Docker
docker run --rm hello-world || echo "Docker test failed."

# Add user to docker group if needed
if [ "$SUDO_USER" ]; then
    usermod -aG docker "$SUDO_USER"
    echo "Added $SUDO_USER to docker group. Re-login required."
else
    echo "To run docker as non-root user, add your user to the docker group:"
    echo "usermod -aG docker <your-user>"
fi

# Check docker compose
docker compose version || echo "Use 'docker compose' instead of 'docker-compose'."

echo "Docker installation complete."
