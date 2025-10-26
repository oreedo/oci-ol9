#!/bin/bash
set -e

echo "=== Setting up kubectl for current user ==="
echo ""

# Check if K3s is installed
if [ ! -f /etc/rancher/k3s/k3s.yaml ]; then
    echo "Error: K3s is not installed or kubeconfig not found."
    exit 1
fi

# Create .kube directory
mkdir -p ~/.kube

# Copy kubeconfig
echo "Copying kubeconfig..."
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config

echo ""
echo "kubectl configured successfully!"
echo "You can now use kubectl without sudo."
echo ""
echo "Test with: kubectl get nodes"
