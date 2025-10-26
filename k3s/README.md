# K3s Scripts

Scripts for managing K3s on Oracle Linux 9 ARM64 with custom data directory.

## Pre-Installation

**Important:** Run the requirements check before installing:

```bash
./check-requirements.sh
```

This verifies:
- ARM64 architecture (aarch64)
- Kernel page size (must be 4K for ARM64)
- Available memory and disk space
- SELinux configuration
- Firewall status
- Network connectivity

### Optional: Configure Firewall First

If you want to configure comprehensive firewall rules before installation:

```bash
./configure-firewall.sh
```

This configures ports for:
- Kubernetes/K3s (API, etcd, metrics, CNI)
- Podman (container registry)
- Docker (if installed)
- Common ingress ports (80, 443)
- NodePort range (30000-32767)

**Note:** The install script will offer firewall configuration options, so this step is optional.

## Installation

```bash
./install.sh
```

Installs K3s with data directory at `/mnt/data/k3s`.

The installation script will:
- Verify system architecture
- Install SELinux policies (if SELinux is enabled)
- Configure firewall rules (if firewalld is active)
- Install K3s with custom data directory
- Wait for cluster to be ready
- **Automatically configure kubectl for current user**
- **Install Helm 3 package manager**
- Add common Helm repositories (stable, bitnami)

## System Warnings Addressed

The requirements check may show these warnings:

### ⚠️ SELinux: Enforcing
**Resolution:** The install script automatically installs K3s SELinux policies:
- `container-selinux`
- `selinux-policy-base`  
- `k3s-selinux-1.6-1.el9.noarch.rpm`

### ⚠️ Firewalld: Active
**Resolution:** The install script prompts to configure firewall rules:
- Port 6443/tcp (Kubernetes API server)
- Trusted zone: 10.42.0.0/16 (Pod network)
- Trusted zone: 10.43.0.0/16 (Service network)

These warnings are **expected and handled automatically** during installation.

## Setup kubectl

```bash
./setup-kubectl.sh
```

Configures kubectl for the current user (no sudo required for kubectl commands).

**Note:** This is now done automatically during installation, but you can run this script manually if needed or for additional users.

## Check Status

```bash
./status.sh
```

Displays cluster status, running pods, and resource usage.

## Uninstall

```bash
./uninstall.sh
```

Removes K3s and optionally deletes the data directory.

## Firewall Management

```bash
# Configure comprehensive firewall rules
./configure-firewall.sh

# View current firewall rules
sudo firewall-cmd --list-all
sudo firewall-cmd --zone=trusted --list-all

# See detailed port reference
cat FIREWALL-REFERENCE.md
```

The firewall script configures:
- **Kubernetes ports:** 6443, 2379-2380, 10250, 8472, 51820-51821, 5001
- **NodePort range:** 30000-32767
- **Ingress ports:** 80, 443, 8080
- **Registry:** 5000
- **Trusted networks:** Pod (10.42.0.0/16), Service (10.43.0.0/16), Docker (172.17.0.0/16)
- **Masquerading:** Enabled for NAT

See `FIREWALL-REFERENCE.md` for complete documentation.

## Data Directory

All K3s data (images, containers, volumes, etcd database) is stored in:
- `/mnt/data/k3s`

## Kubeconfig

- System: `/etc/rancher/k3s/k3s.yaml`
- User: `~/.kube/config` (automatically configured during install)

## Installed Tools

After installation, you'll have:
- **kubectl** - Kubernetes command-line tool (configured for your user)
- **helm** - Kubernetes package manager (v3)
- **k3s** - K3s cluster management
- **crictl** - Container runtime CLI
- **ctr** - Containerd CLI

## Using Helm

```bash
# Search for charts
helm search repo nginx

# Install a chart
helm install my-release bitnami/nginx

# List installations
helm list

# Add more repositories
helm repo add <name> <url>
helm repo update
```
