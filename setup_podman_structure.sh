#!/bin/bash
# Script to create and prepare the file tree structure for Podman in /mnt/data/podman

set -e

PODMAN_ROOT="/mnt/data/podman"

echo "Creating Podman directory structure in ${PODMAN_ROOT}..."

# Create main directories
sudo mkdir -p "${PODMAN_ROOT}"/{storage,volumes,containers,config,tmp}

# Create storage subdirectories (for container images and layers)
sudo mkdir -p "${PODMAN_ROOT}/storage"/{overlay,overlay-images,overlay-layers,vfs,vfs-images,vfs-layers}

# Create network configuration directory
sudo mkdir -p "${PODMAN_ROOT}/config/networks"

# Create run directory for runtime files
sudo mkdir -p "${PODMAN_ROOT}/run"

# Set proper permissions
echo "Setting permissions..."
sudo chmod 755 "${PODMAN_ROOT}"
sudo chmod 700 "${PODMAN_ROOT}/storage"
sudo chmod 755 "${PODMAN_ROOT}/volumes"
sudo chmod 755 "${PODMAN_ROOT}/containers"
sudo chmod 755 "${PODMAN_ROOT}/config"
sudo chmod 755 "${PODMAN_ROOT}/tmp"

# Create storage.conf for Podman
echo "Creating storage configuration..."
sudo tee "${PODMAN_ROOT}/config/storage.conf" > /dev/null << 'STORAGE_EOF'
[storage]
driver = "overlay"
runroot = "/mnt/data/podman/run"
graphroot = "/mnt/data/podman/storage"

[storage.options]
additionalimagestores = []

[storage.options.overlay]
mountopt = "nodev,metacopy=on"
STORAGE_EOF

# Create containers.conf for Podman
echo "Creating containers configuration..."
sudo tee "${PODMAN_ROOT}/config/containers.conf" > /dev/null << 'CONTAINERS_EOF'
[containers]
default_ulimits = [
  "nofile=65536:65536",
]

[engine]
cgroup_manager = "systemd"
events_logger = "file"
runtime = "crun"

[network]
network_backend = "netavark"
CONTAINERS_EOF

# Display the created structure
echo ""
echo "Podman directory structure created successfully!"
echo ""
echo "Directory tree:"
find "${PODMAN_ROOT}" -maxdepth 2 -type d | sort

echo ""
echo "Configuration files created:"
ls -lh "${PODMAN_ROOT}/config/"

echo ""
echo "========================================="
echo "Next steps to configure Podman:"
echo "========================================="
echo ""
echo "1. Install Podman (if not already installed):"
echo "   sudo dnf install -y podman"
echo ""
echo "2. Configure Podman to use this storage location:"
echo "   For rootless mode (recommended):"
echo "     mkdir -p ~/.config/containers"
echo "     ln -sf ${PODMAN_ROOT}/config/storage.conf ~/.config/containers/storage.conf"
echo "     ln -sf ${PODMAN_ROOT}/config/containers.conf ~/.config/containers/containers.conf"
echo ""
echo "   For root mode:"
echo "     sudo ln -sf ${PODMAN_ROOT}/config/storage.conf /etc/containers/storage.conf"
echo "     sudo ln -sf ${PODMAN_ROOT}/config/containers.conf /etc/containers/containers.conf"
echo ""
echo "3. Set environment variable (add to ~/.bashrc for persistence):"
echo "   export CONTAINERS_STORAGE_CONF=${PODMAN_ROOT}/config/storage.conf"
echo ""
echo "4. Verify configuration:"
echo "   podman info | grep -A 10 graphRoot"
echo ""
echo "========================================="
