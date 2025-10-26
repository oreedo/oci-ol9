# OCI Oracle Linux 9 Setup Scripts

Infrastructure setup scripts for Oracle Cloud Infrastructure (OCI) running Oracle Linux 9 on ARM64.

## Overview

This repository contains automation scripts for setting up and managing container workloads and Kubernetes on Oracle Linux 9 (ARM64 architecture).

## Contents

### Podman Setup
- `setup_podman_structure.sh` - Podman directory structure setup

### K3s Kubernetes Setup (`k3s/`)
- `check-requirements.sh` - Pre-installation system requirements check
- `install.sh` - K3s installation with custom data directory
- `configure-firewall.sh` - Comprehensive firewall configuration
- `setup-kubectl.sh` - kubectl configuration for users
- `status.sh` - Cluster status monitoring
- `uninstall.sh` - Clean uninstallation
- `FIREWALL-REFERENCE.md` - Complete firewall port documentation
- `README.md` - Detailed K3s setup documentation
- `QUICKSTART.txt` - Quick reference guide

## System Requirements

- Oracle Linux 9.x
- ARM64 (aarch64) architecture
- 2GB+ RAM (22GB recommended)
- 20GB+ disk space
- Firewalld (configured automatically)
- SELinux (policies installed automatically)

## Quick Start

### K3s Installation

```bash
# Check system requirements
cd k3s
./check-requirements.sh

# Install K3s with Helm
./install.sh

# Check status
./status.sh
```

### Features

- ✅ K3s v1.33+ with ARM64 support
- ✅ Custom data directory at `/mnt/data/k3s`
- ✅ SELinux policies automatically configured
- ✅ Firewall rules for Kubernetes, Docker, and Podman
- ✅ kubectl configured for non-root users
- ✅ Helm 3 with multiple repositories
- ✅ Comprehensive monitoring and status scripts

## Data Directories

All persistent data is stored under `/mnt/data/`:
- `/mnt/data/k3s` - K3s cluster data
- `/mnt/data/podman` - Podman containers and images

## Documentation

See individual README files in each directory for detailed documentation.

## License

MIT License

## Author

Oreedo DevOps Team
