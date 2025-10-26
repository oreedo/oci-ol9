#!/bin/bash

echo "=== Oracle Linux 9 Firewall Configuration ==="
echo "=== Docker, Podman, and Kubernetes Ports ==="
echo ""

# Check if firewalld is installed
if ! command -v firewall-cmd &> /dev/null; then
    echo "Error: firewalld is not installed."
    echo "Install with: sudo dnf install -y firewalld"
    exit 1
fi

# Check if firewalld is running
if ! systemctl is-active --quiet firewalld; then
    echo "Firewalld is not running."
    read -p "Do you want to start firewalld? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo systemctl start firewalld
        sudo systemctl enable firewalld
        echo "✓ Firewalld started and enabled"
    else
        echo "Firewalld must be running to configure rules. Exiting."
        exit 1
    fi
fi

echo "Current firewalld status:"
sudo firewall-cmd --state
echo ""

# Backup current configuration
echo "Creating backup of current firewall configuration..."
BACKUP_DIR="$HOME/firewall-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
sudo firewall-cmd --list-all > "$BACKUP_DIR/firewall-rules.txt"
echo "✓ Backup saved to: $BACKUP_DIR"
echo ""

# Confirm with user
echo "This script will configure firewall rules for:"
echo "  • Kubernetes/K3s (API, etcd, metrics, CNI)"
echo "  • Podman (container registry)"
echo "  • Docker (if installed)"
echo "  • Common container networking"
echo ""
read -p "Continue with firewall configuration? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Firewall configuration cancelled."
    exit 0
fi

echo ""
echo "=== Configuring Kubernetes/K3s Ports ==="
echo ""

# Kubernetes API Server
echo "Opening Kubernetes API Server (6443/tcp)..."
sudo firewall-cmd --permanent --add-port=6443/tcp
echo "✓ Port 6443/tcp (Kubernetes API)"

# etcd (for HA clusters with embedded etcd)
echo "Opening etcd ports for HA (2379-2380/tcp)..."
sudo firewall-cmd --permanent --add-port=2379-2380/tcp
echo "✓ Ports 2379-2380/tcp (etcd)"

# Kubelet API
echo "Opening Kubelet metrics (10250/tcp)..."
sudo firewall-cmd --permanent --add-port=10250/tcp
echo "✓ Port 10250/tcp (Kubelet)"

# NodePort Services (default range)
echo "Opening NodePort range (30000-32767/tcp)..."
sudo firewall-cmd --permanent --add-port=30000-32767/tcp
echo "✓ Ports 30000-32767/tcp (NodePort Services)"

# Flannel VXLAN (K3s default CNI)
echo "Opening Flannel VXLAN (8472/udp)..."
sudo firewall-cmd --permanent --add-port=8472/udp
echo "✓ Port 8472/udp (Flannel VXLAN)"

# Flannel WireGuard (alternative CNI)
echo "Opening Flannel WireGuard (51820-51821/udp)..."
sudo firewall-cmd --permanent --add-port=51820-51821/udp
echo "✓ Ports 51820-51821/udp (Flannel WireGuard)"

# Spegel (embedded distributed registry)
echo "Opening Spegel registry (5001/tcp)..."
sudo firewall-cmd --permanent --add-port=5001/tcp
echo "✓ Port 5001/tcp (Spegel distributed registry)"

echo ""
echo "=== Configuring Pod and Service Networks ==="
echo ""

# Pod network CIDR (K3s default: 10.42.0.0/16)
echo "Adding Pod network to trusted zone (10.42.0.0/16)..."
sudo firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
echo "✓ 10.42.0.0/16 (Pod network - trusted)"

# Service network CIDR (K3s default: 10.43.0.0/16)
echo "Adding Service network to trusted zone (10.43.0.0/16)..."
sudo firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16
echo "✓ 10.43.0.0/16 (Service network - trusted)"

# Docker default bridge network (if Docker is used)
echo "Adding Docker bridge network to trusted zone (172.17.0.0/16)..."
sudo firewall-cmd --permanent --zone=trusted --add-source=172.17.0.0/16
echo "✓ 172.17.0.0/16 (Docker bridge - trusted)"

echo ""
echo "=== Configuring Podman Ports ==="
echo ""

# Podman container registry (if using podman as registry)
echo "Opening Podman registry port (5000/tcp)..."
sudo firewall-cmd --permanent --add-port=5000/tcp
echo "✓ Port 5000/tcp (Podman/Docker registry)"

echo ""
echo "=== Configuring Common Container Ports ==="
echo ""

# HTTP/HTTPS for Ingress
echo "Opening HTTP/HTTPS for Ingress (80,443/tcp)..."
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
echo "✓ Ports 80,443/tcp (HTTP/HTTPS Ingress)"

# Traefik Dashboard (K3s default ingress controller)
echo "Opening Traefik Dashboard (8080/tcp)..."
sudo firewall-cmd --permanent --add-port=8080/tcp
echo "✓ Port 8080/tcp (Traefik Dashboard)"

# Docker daemon API (if remote access needed - OPTIONAL, commented by default)
# echo "Opening Docker API (2375-2376/tcp)..."
# sudo firewall-cmd --permanent --add-port=2375-2376/tcp
# echo "✓ Ports 2375-2376/tcp (Docker API)"

echo ""
echo "=== Configuring Masquerading ==="
echo ""

# Enable masquerading for NAT (required for pods to access external networks)
echo "Enabling masquerading for public zone..."
sudo firewall-cmd --permanent --zone=public --add-masquerade
echo "✓ Masquerading enabled (NAT for containers)"

echo ""
echo "=== Applying Firewall Rules ==="
echo ""

# Reload firewall to apply all changes
sudo firewall-cmd --reload
echo "✓ Firewall rules reloaded and applied"

echo ""
echo "=== Firewall Configuration Complete ==="
echo ""

# Display current configuration
echo "Active Firewall Rules:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo firewall-cmd --list-all
echo ""
echo "Trusted Zone:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo firewall-cmd --zone=trusted --list-all
echo ""

# Summary
echo "=== Configuration Summary ==="
echo "✓ Kubernetes/K3s ports configured"
echo "✓ Podman/Docker ports configured"
echo "✓ Pod network (10.42.0.0/16) trusted"
echo "✓ Service network (10.43.0.0/16) trusted"
echo "✓ Docker network (172.17.0.0/16) trusted"
echo "✓ Masquerading enabled for NAT"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "To verify: sudo firewall-cmd --list-all"
echo "To check trusted zone: sudo firewall-cmd --zone=trusted --list-all"
