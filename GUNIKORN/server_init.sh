#!/bin/bash
#
# server_init.sh
#
# This script installs Docker, kubectl, Minikube, and the AWS CLI v2
# on a fresh Debian-based Linux system (e.g., Ubuntu).
# It must be run as root or with sudo privileges.

# Exit immediately if a command exits with a non-zero status.
set -e

echo "========================================================================"
echo "=> 1. Updating system and installing prerequisite packages..."
echo "========================================================================"
apt-get update
apt-get install -y ca-certificates curl gnupg unzip

echo "========================================================================"
echo "=> 2. Installing Docker..."
echo "========================================================================"
# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Set up the Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
echo "=> Docker installed successfully!"

echo "========================================================================"
echo "=> 3. Installing kubectl..."
echo "========================================================================"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl # Clean up downloaded file
echo "=> kubectl installed successfully!"

echo "========================================================================"
echo "=> 4. Installing Minikube..."
echo "========================================================================"
curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
install minikube /usr/local/bin/minikube
rm minikube # Clean up downloaded file
echo "=> Minikube installed successfully!"

echo "========================================================================"
echo "=> 5. Installing AWS CLI v2..."
echo "========================================================================"
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip # Clean up installation files
echo "=> AWS CLI v2 installed successfully!"

echo "========================================================================"
echo "=> INSTALLATION COMPLETE! The system is ready to run 'make mk-build'."
echo "========================================================================"
