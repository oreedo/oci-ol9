# Firewall Configuration for Oracle Linux 9
## Docker, Podman, and Kubernetes Ports Reference

This document lists all firewall ports configured for container and Kubernetes workloads.

---

## Quick Commands

```bash
# Configure all ports automatically
/mnt/data/scripts/k3s/configure-firewall.sh

# View active rules
sudo firewall-cmd --list-all
sudo firewall-cmd --zone=trusted --list-all

# Check specific port
sudo firewall-cmd --query-port=6443/tcp

# Test firewall status
sudo firewall-cmd --state
```

---

## Kubernetes/K3s Ports

### Control Plane Ports

| Port(s)      | Protocol | Purpose                    | Required For          |
|--------------|----------|----------------------------|-----------------------|
| 6443         | TCP      | Kubernetes API Server      | All nodes             |
| 2379-2380    | TCP      | etcd server client API     | HA clusters only      |
| 10250        | TCP      | Kubelet API                | All nodes             |
| 10257        | TCP      | kube-controller-manager    | Control plane         |
| 10259        | TCP      | kube-scheduler             | Control plane         |

### Worker Node Ports

| Port(s)      | Protocol | Purpose                    | Required For          |
|--------------|----------|----------------------------|-----------------------|
| 10250        | TCP      | Kubelet API                | All nodes             |
| 30000-32767  | TCP      | NodePort Services          | All nodes (optional)  |

### K3s Specific Ports

| Port(s)      | Protocol | Purpose                    | Required For          |
|--------------|----------|----------------------------|-----------------------|
| 8472         | UDP      | Flannel VXLAN              | All nodes (default)   |
| 51820        | UDP      | Flannel WireGuard IPv4     | If using WireGuard    |
| 51821        | UDP      | Flannel WireGuard IPv6     | If using WireGuard    |
| 5001         | TCP      | Spegel (embedded registry) | All nodes (optional)  |

---

## Container Network CIDRs (Trusted Zones)

| Network         | Purpose                    | Zone    |
|-----------------|----------------------------|---------|
| 10.42.0.0/16    | K3s Pod network (default)  | trusted |
| 10.43.0.0/16    | K3s Service network        | trusted |
| 172.17.0.0/16   | Docker bridge network      | trusted |

---

## Podman/Docker Ports

| Port(s)      | Protocol | Purpose                    | Notes                 |
|--------------|----------|----------------------------|-----------------------|
| 5000         | TCP      | Container Registry         | Local registry        |
| 2375         | TCP      | Docker API (HTTP)          | **Insecure - disabled by default** |
| 2376         | TCP      | Docker API (HTTPS)         | If remote access needed |

---

## Ingress/Load Balancer Ports

| Port(s)      | Protocol | Purpose                    | Required For          |
|--------------|----------|----------------------------|-----------------------|
| 80           | TCP      | HTTP Ingress               | Web services          |
| 443          | TCP      | HTTPS Ingress              | Web services (TLS)    |
| 8080         | TCP      | Traefik Dashboard          | K3s default ingress   |

---

## Firewall Zones Explained

### Public Zone
- Default zone for external interfaces
- Has restricted access
- Only explicitly opened ports allowed
- Masquerading enabled for NAT

### Trusted Zone
- Used for container networks
- All traffic allowed from these sources
- Includes pod and service CIDRs

---

## Common Firewall Commands

### View Configuration
```bash
# List all active rules
sudo firewall-cmd --list-all

# List trusted zone rules
sudo firewall-cmd --zone=trusted --list-all

# List all zones
sudo firewall-cmd --get-active-zones

# List all services
sudo firewall-cmd --get-services
```

### Add Rules Manually
```bash
# Add a port
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload

# Add a service
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --reload

# Add source to trusted zone
sudo firewall-cmd --permanent --zone=trusted --add-source=192.168.1.0/24
sudo firewall-cmd --reload
```

### Remove Rules
```bash
# Remove a port
sudo firewall-cmd --permanent --remove-port=8080/tcp
sudo firewall-cmd --reload

# Remove source from trusted zone
sudo firewall-cmd --permanent --zone=trusted --remove-source=192.168.1.0/24
sudo firewall-cmd --reload
```

### Troubleshooting
```bash
# Check if specific port is open
sudo firewall-cmd --query-port=6443/tcp

# Check if masquerading is enabled
sudo firewall-cmd --query-masquerade

# View firewall logs (requires logging enabled)
sudo journalctl -u firewalld -f

# Test connection to port
nc -zv localhost 6443
```

---

## Security Best Practices

1. **Only open required ports**
   - Review your workload requirements
   - Close unused ports regularly

2. **Use trusted zones appropriately**
   - Only add internal networks to trusted zone
   - Never add public IPs to trusted zone

3. **Enable rich rules for specific sources**
   ```bash
   # Allow API access only from specific IP
   sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.100" port port="6443" protocol="tcp" accept'
   ```

4. **Regular audits**
   ```bash
   # Review all rules monthly
   sudo firewall-cmd --list-all-zones > firewall-audit-$(date +%Y%m%d).txt
   ```

5. **Backup before changes**
   ```bash
   # The configure-firewall.sh script does this automatically
   sudo firewall-cmd --list-all > firewall-backup.txt
   ```

---

## Common Issues and Solutions

### Issue: Pods can't reach external networks
**Solution:** Enable masquerading
```bash
sudo firewall-cmd --permanent --zone=public --add-masquerade
sudo firewall-cmd --reload
```

### Issue: NodePort services not accessible
**Solution:** Open NodePort range
```bash
sudo firewall-cmd --permanent --add-port=30000-32767/tcp
sudo firewall-cmd --reload
```

### Issue: Pods can't communicate with each other
**Solution:** Add pod network to trusted zone
```bash
sudo firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
sudo firewall-cmd --reload
```

### Issue: K3s installation fails with firewall active
**Solution:** Temporarily add all K3s ports or disable firewall during install
```bash
# Option 1: Run configure-firewall.sh before installing K3s
/mnt/data/scripts/k3s/configure-firewall.sh

# Option 2: Temporarily disable (NOT recommended for production)
sudo systemctl stop firewalld
# ... install K3s ...
sudo systemctl start firewalld
```

---

## Reference Links

- [K3s Networking Documentation](https://docs.k3s.io/networking)
- [Kubernetes Ports and Protocols](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)
- [Oracle Linux Firewalld Guide](https://docs.oracle.com/en/operating-systems/oracle-linux/9/security/security-WorkingWithFirewalld.html)
- [Flannel Documentation](https://github.com/flannel-io/flannel)

---

## Complete Port List for Quick Reference

```bash
# Kubernetes/K3s
6443/tcp       # API Server
2379-2380/tcp  # etcd
10250/tcp      # Kubelet
8472/udp       # Flannel VXLAN
51820-51821/udp # Flannel WireGuard
5001/tcp       # Spegel
30000-32767/tcp # NodePort

# Ingress
80/tcp         # HTTP
443/tcp        # HTTPS
8080/tcp       # Traefik Dashboard

# Registry
5000/tcp       # Container Registry

# Trusted Networks
10.42.0.0/16   # Pod network
10.43.0.0/16   # Service network
172.17.0.0/16  # Docker bridge
```
