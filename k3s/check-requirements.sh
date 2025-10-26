#!/bin/bash

echo "=== K3s System Requirements Check for Oracle Linux 9 ARM64 ==="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
WARNINGS=0
FAILED=0

# Check architecture
echo "1. Checking Architecture..."
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
    echo -e "${GREEN}✓ Architecture: $ARCH (ARM64)${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠ Architecture: $ARCH (Expected: aarch64/ARM64)${NC}"
    ((WARNINGS++))
fi

# Check OS
echo ""
echo "2. Checking Operating System..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo -e "${GREEN}✓ OS: $PRETTY_NAME${NC}"
    echo "  Version: $VERSION"
    ((PASSED++))
fi

# Check kernel page size (important for ARM64)
echo ""
echo "3. Checking Kernel Page Size..."
PAGE_SIZE=$(getconf PAGESIZE)
if [ "$PAGE_SIZE" = "4096" ]; then
    echo -e "${GREEN}✓ Kernel page size: ${PAGE_SIZE} bytes (4K pages)${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ Kernel page size: ${PAGE_SIZE} bytes${NC}"
    echo "  K3s requires 4K pages on ARM64"
    ((FAILED++))
fi

# Check available memory
echo ""
echo "4. Checking Available Memory..."
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
if [ "$TOTAL_MEM" -ge 2 ]; then
    echo -e "${GREEN}✓ Total Memory: ${TOTAL_MEM}GB (minimum 2GB recommended)${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠ Total Memory: ${TOTAL_MEM}GB (less than recommended 2GB)${NC}"
    ((WARNINGS++))
fi

# Check available disk space
echo ""
echo "5. Checking Disk Space for /mnt/data..."
AVAIL_SPACE=$(df -BG /mnt/data | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$AVAIL_SPACE" -ge 20 ]; then
    echo -e "${GREEN}✓ Available space: ${AVAIL_SPACE}GB (20GB+ recommended)${NC}"
    ((PASSED++))
elif [ "$AVAIL_SPACE" -ge 10 ]; then
    echo -e "${YELLOW}⚠ Available space: ${AVAIL_SPACE}GB (20GB+ recommended)${NC}"
    ((WARNINGS++))
else
    echo -e "${RED}✗ Available space: ${AVAIL_SPACE}GB (less than 10GB)${NC}"
    ((FAILED++))
fi

# Check SELinux
echo ""
echo "6. Checking SELinux..."
if command -v getenforce &> /dev/null; then
    SELINUX_STATUS=$(getenforce)
    if [ "$SELINUX_STATUS" = "Enforcing" ] || [ "$SELINUX_STATUS" = "Permissive" ]; then
        echo -e "${YELLOW}⚠ SELinux: $SELINUX_STATUS${NC}"
        echo "  K3s SELinux policies will be installed during setup"
        ((WARNINGS++))
    else
        echo -e "${GREEN}✓ SELinux: $SELINUX_STATUS${NC}"
        ((PASSED++))
    fi
else
    echo -e "${GREEN}✓ SELinux: Not installed${NC}"
    ((PASSED++))
fi

# Check firewalld
echo ""
echo "7. Checking Firewall..."
if systemctl is-active --quiet firewalld; then
    echo -e "${YELLOW}⚠ Firewalld: Active${NC}"
    echo "  Firewall rules will need to be configured for K3s"
    
    # Check if required ports are open
    echo ""
    echo "  Checking firewall rules..."
    if sudo firewall-cmd --list-ports 2>/dev/null | grep -q "6443/tcp"; then
        echo -e "  ${GREEN}✓ Port 6443/tcp is open${NC}"
    else
        echo -e "  ${YELLOW}⚠ Port 6443/tcp needs to be opened${NC}"
    fi
    ((WARNINGS++))
else
    echo -e "${GREEN}✓ Firewalld: Inactive${NC}"
    ((PASSED++))
fi

# Check if K3s is already installed
echo ""
echo "8. Checking K3s Installation..."
if command -v k3s &> /dev/null; then
    echo -e "${YELLOW}⚠ K3s is already installed${NC}"
    echo "  Version: $(k3s --version | head -n1)"
    if systemctl is-active --quiet k3s; then
        echo "  Status: Running"
    else
        echo "  Status: Stopped"
    fi
    ((WARNINGS++))
else
    echo -e "${GREEN}✓ K3s is not installed${NC}"
    ((PASSED++))
fi

# Check for required packages
echo ""
echo "9. Checking Required Packages..."
MISSING_PKGS=""
for pkg in curl iptables; do
    if ! command -v $pkg &> /dev/null; then
        MISSING_PKGS="$MISSING_PKGS $pkg"
    fi
done

if [ -z "$MISSING_PKGS" ]; then
    echo -e "${GREEN}✓ All required packages are installed${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ Missing packages:${MISSING_PKGS}${NC}"
    echo "  Install with: sudo dnf install -y${MISSING_PKGS}"
    ((FAILED++))
fi

# Check network connectivity
echo ""
echo "10. Checking Network Connectivity..."
if curl -s --connect-timeout 5 https://get.k3s.io > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Can reach K3s installation server${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ Cannot reach K3s installation server${NC}"
    echo "  Check your internet connection"
    ((FAILED++))
fi

# Summary
echo ""
echo "========================================"
echo "=== Requirements Check Summary ==="
echo "========================================"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}✗ System does not meet all requirements${NC}"
    echo "Please fix the failed checks before installing K3s"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠ System meets minimum requirements with warnings${NC}"
    echo "K3s can be installed, but please review the warnings"
    exit 0
else
    echo -e "${GREEN}✓ System meets all requirements!${NC}"
    echo "Ready to install K3s"
    exit 0
fi
