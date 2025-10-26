#!/bin/bash
set -e

echo "=== K3s Uninstall Script ==="
echo ""

# Check if K3s is installed
if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
    echo "Uninstalling K3s..."
    sudo /usr/local/bin/k3s-uninstall.sh
    echo "K3s uninstalled successfully."
else
    echo "K3s is not installed."
fi

# Ask about data directory
echo ""
read -p "Do you want to remove K3s data directory /mnt/data/k3s? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing K3s data directory..."
    sudo rm -rf /mnt/data/k3s
    echo "Data directory removed."
else
    echo "Data directory preserved."
fi

echo ""
echo "Uninstall complete!"
