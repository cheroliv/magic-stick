#!/usr/bin/env bash
set -euo pipefail

echo "Installing software packages in chroot..."

PACKAGES=(
    curl
    wget
    git
    vim
    htop
    ncdu
    tree
    nmap
    iperf3
    wireshark
    tshark
    terminator
    firefox
    openssh-client
    rsync
    jq
    tmux
    usbutils
    pciutils
    lshw
    smartmontools
    net-tools
    dnsutils
    whois
    traceroute
    iptraf-ng
    iftop
    nload
)

echo "Installing apt packages: ${PACKAGES[*]}"
apt-get update
apt-get install -y "${PACKAGES[@]}"

echo ""
echo "Installing Docker..."
if ! command -v docker &>/dev/null; then
    apt-get install -y ca-certificates gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    usermod -aG docker ubuntu 2>/dev/null || true
    usermod -aG docker user 2>/dev/null || true
    echo "  Docker installed."
else
    echo "  Docker already installed."
fi

echo ""
echo "Installing Ollama..."
if ! command -v ollama &>/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
    echo "  Ollama installed."
else
    echo "  Ollama already installed."
fi

echo ""
echo "Installing SDKMAN..."
if ! command -v sdk &>/dev/null; then
    curl -s "https://get.sdkman.io" | bash
    source "/root/.sdkman/bin/sdkman-init.sh" 2>/dev/null || true
    if command -v sdk &>/dev/null; then
        sdk install java 21.0.2-tem
        echo "  SDKMAN + JDK 21 installed."
    else
        echo "  WARNING: SDKMAN installation incomplete"
    fi
else
    echo "  SDKMAN already installed."
fi

echo ""
echo "Software installation complete."