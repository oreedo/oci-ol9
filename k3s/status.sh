#!/bin/bash

echo "=== K3s Cluster Status ==="
echo ""

# Check if K3s is installed
if ! command -v k3s &> /dev/null; then
    echo "K3s is not installed."
    exit 1
fi

# Check service status
echo "Service Status:"
sudo systemctl status k3s --no-pager | head -n 10

echo ""
echo "Nodes:"
sudo kubectl get nodes

echo ""
echo "Pods (all namespaces):"
sudo kubectl get pods -A

echo ""
echo "Data Directory Usage:"
du -sh /mnt/data/k3s 2>/dev/null || echo "Data directory not found"

echo ""
echo "K3s Version:"
k3s --version

echo ""
echo "Helm Version:"
if command -v helm &> /dev/null; then
    helm version --short
else
    echo "Helm is not installed"
fi

echo ""
echo "Kubectl Access:"
if [ -f ~/.kube/config ]; then
    echo "✓ kubectl configured for current user (no sudo needed)"
    kubectl version --client --short 2>/dev/null || kubectl version --client
else
    echo "⚠ kubectl not configured for current user (sudo required)"
    echo "  Run: /mnt/data/scripts/k3s/setup-kubectl.sh"
fi
