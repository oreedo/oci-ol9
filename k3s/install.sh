#!/bin/bash
set -e

echo "=== K3s Installation Script for Oracle Linux 9 ARM64 ==="
echo ""

# Define data directory
K3S_DATA_DIR="/mnt/data/k3s"

# Check system requirements
echo "Checking system requirements..."
echo "Architecture: $(uname -m)"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME)"

# Verify ARM64 architecture
if [ "$(uname -m)" != "aarch64" ]; then
    echo "Warning: This script is optimized for ARM64 (aarch64) architecture."
    echo "Current architecture: $(uname -m)"
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# Check if SELinux is enabled
if command -v getenforce &> /dev/null; then
    SELINUX_STATUS=$(getenforce)
    echo "SELinux status: $SELINUX_STATUS"
    
    if [ "$SELINUX_STATUS" != "Disabled" ]; then
        echo ""
        echo "SELinux is enabled. Installing K3s SELinux policies..."
        
        # Install required packages for SELinux
        sudo dnf install -y container-selinux selinux-policy-base
        
        # Install K3s SELinux RPM for Oracle Linux 9
        echo "Installing K3s SELinux RPM..."
        sudo dnf install -y https://rpm.rancher.io/k3s/latest/common/centos/9/noarch/k3s-selinux-1.6-1.el9.noarch.rpm
    fi
fi

# Check firewalld status
if systemctl is-active --quiet firewalld; then
    echo ""
    echo "Firewalld is active."
    echo ""
    echo "Firewall configuration options:"
    echo "  1) Basic K3s only (minimal - just API server and pod/service networks)"
    echo "  2) Comprehensive (K3s + Docker + Podman + all common ports)"
    echo "  3) Skip (configure manually later)"
    echo ""
    read -p "Choose firewall configuration [1/2/3]: " -n 1 -r
    echo
    
    case $REPLY in
        1)
            echo "Configuring basic K3s firewall rules..."
            sudo firewall-cmd --permanent --add-port=6443/tcp  # API server
            sudo firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16  # Pods
            sudo firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16  # Services
            sudo firewall-cmd --reload
            echo "✓ Basic firewall rules configured."
            ;;
        2)
            echo "Running comprehensive firewall configuration..."
            if [ -f /mnt/data/scripts/k3s/configure-firewall.sh ]; then
                /mnt/data/scripts/k3s/configure-firewall.sh
            else
                echo "⚠ Comprehensive script not found, applying basic rules..."
                sudo firewall-cmd --permanent --add-port=6443/tcp
                sudo firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
                sudo firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16
                sudo firewall-cmd --reload
            fi
            ;;
        3)
            echo "Skipping firewall configuration."
            echo "You can configure it later with: /mnt/data/scripts/k3s/configure-firewall.sh"
            ;;
        *)
            echo "Invalid choice. Skipping firewall configuration."
            ;;
    esac
fi

# Create data directory
echo ""
echo "Creating K3s data directory at $K3S_DATA_DIR..."
sudo mkdir -p "$K3S_DATA_DIR"
sudo chmod 755 "$K3S_DATA_DIR"

# Install K3s with custom data directory
echo ""
echo "Installing K3s..."
echo "This may take a few minutes..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--data-dir=$K3S_DATA_DIR" sh -

# Wait for K3s to be ready
echo ""
echo "Waiting for K3s to start..."
sleep 5

# Wait for service to be active
echo "Checking K3s service status..."
for i in {1..30}; do
    if sudo systemctl is-active --quiet k3s; then
        echo "K3s service is active!"
        break
    fi
    echo "Waiting for K3s service... ($i/30)"
    sleep 2
done

# Check node readiness
echo ""
echo "Waiting for node to be ready..."
for i in {1..30}; do
    if sudo kubectl get nodes 2>/dev/null | grep -q " Ready "; then
        echo "Node is ready!"
        break
    fi
    echo "Waiting for node... ($i/30)"
    sleep 2
done

# Check status
echo ""
echo "=== K3s Installation Complete ==="
echo "Cluster status:"
sudo kubectl get nodes

# Setup kubectl for current user automatically
echo ""
echo "=== Setting up kubectl for current user ==="
if [ ! -f ~/.kube/config ]; then
    echo "Creating kubectl config for user $USER..."
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $USER:$USER ~/.kube/config
    chmod 600 ~/.kube/config
    echo "✓ kubectl configured for user $USER"
    
    # Verify kubectl works without sudo
    if kubectl get nodes &>/dev/null; then
        echo "✓ kubectl verified - you can now run kubectl without sudo"
    else
        echo "⚠ kubectl config created but verification failed - you may need to logout/login"
    fi
else
    echo "⚠ kubectl config already exists at ~/.kube/config"
    echo "  Skipping kubectl setup to avoid overwriting existing config"
fi

# Install Helm
echo ""
echo "=== Installing Helm ==="
if command -v helm &> /dev/null; then
    echo "⚠ Helm is already installed"
    helm version
else
    echo "Downloading and installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    if command -v helm &> /dev/null; then
        echo "✓ Helm installed successfully"
        helm version
        
        # Add common Helm repos
        echo ""
        echo "Adding common Helm repositories..."
        helm repo add stable https://charts.helm.sh/stable 2>/dev/null || true
        helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
        helm repo update
        echo "✓ Helm repositories configured"
    else
        echo "✗ Helm installation failed"
    fi
fi

echo ""
echo "=== Installation Summary ==="
echo "✓ K3s is installed and running!"
echo "✓ Data directory: $K3S_DATA_DIR"
echo "✓ Kubeconfig: /etc/rancher/k3s/k3s.yaml"
echo "✓ User kubectl config: ~/.kube/config"
echo "✓ K3s version: $(k3s --version | head -n1)"
if command -v helm &> /dev/null; then
    echo "✓ Helm version: $(helm version --short)"
fi
echo ""
echo "Next steps:"
echo "  • Check cluster status: /mnt/data/scripts/k3s/status.sh"
echo "  • View all pods: kubectl get pods -A"
echo "  • Deploy apps with Helm: helm search repo <chart-name>"
echo ""
echo "System pods will take a few moments to start."
echo "View pods with: sudo kubectl get pods -A"
