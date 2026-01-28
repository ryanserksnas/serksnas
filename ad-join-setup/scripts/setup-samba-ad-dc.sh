#!/bin/bash
#
# Samba AD Domain Controller Setup Script
# This script sets up a Samba server as an Active Directory Domain Controller
# for testing Linux AD join scenarios
#
# Usage: sudo ./setup-samba-ad-dc.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/network-config.env"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo -e "${RED}Error: Configuration file not found at $CONFIG_FILE${NC}"
    exit 1
fi

# Function to print status messages
print_status() {
    echo -e "${GREEN}[*]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[x]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Detect Linux distribution
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    else
        print_error "Cannot detect Linux distribution"
        exit 1
    fi
    print_status "Detected: $DISTRO $VERSION"
}

# Set hostname
configure_hostname() {
    print_status "Configuring hostname to ${DC_HOSTNAME}..."
    hostnamectl set-hostname "${DC_FQDN}"

    # Update /etc/hosts
    cat > /etc/hosts << EOF
127.0.0.1       localhost
${DC_IP}        ${DC_FQDN} ${DC_HOSTNAME}

# AD Lab hosts
${VM1_IP}       ${VM1_FQDN} ${VM1_HOSTNAME}
${VM2_IP}       ${VM2_FQDN} ${VM2_HOSTNAME}
EOF
    print_status "Hostname configured"
}

# Configure static IP
configure_network() {
    print_status "Configuring network..."

    # For Ubuntu/Debian with netplan
    if [[ -d /etc/netplan ]]; then
        cat > /etc/netplan/01-netcfg.yaml << EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: no
      addresses:
        - ${DC_IP}/24
      gateway4: ${NETWORK_GATEWAY}
      nameservers:
        addresses:
          - 127.0.0.1
          - ${NETWORK_DNS_SECONDARY}
        search:
          - ${DOMAIN_NAME}
EOF
        netplan apply || true
    fi

    print_status "Network configured"
}

# Install required packages
install_packages_ubuntu() {
    print_status "Installing packages for Ubuntu/Debian..."

    export DEBIAN_FRONTEND=noninteractive

    apt-get update
    apt-get install -y \
        samba \
        smbclient \
        krb5-user \
        krb5-config \
        winbind \
        libpam-winbind \
        libnss-winbind \
        acl \
        attr \
        dnsutils \
        ldb-tools \
        python3-dnspython \
        ntp \
        ntpdate

    print_status "Packages installed"
}

install_packages_rhel() {
    print_status "Installing packages for RHEL/CentOS..."

    # Enable EPEL if needed
    yum install -y epel-release || true

    yum install -y \
        samba \
        samba-dc \
        samba-client \
        krb5-workstation \
        krb5-libs \
        bind-utils \
        python3-dns \
        chrony \
        acl \
        attr

    print_status "Packages installed"
}

# Stop and disable conflicting services
stop_services() {
    print_status "Stopping conflicting services..."

    systemctl stop smbd nmbd winbind 2>/dev/null || true
    systemctl disable smbd nmbd winbind 2>/dev/null || true

    # Remove existing Samba configuration
    rm -f /etc/samba/smb.conf
    rm -rf /var/lib/samba/*
    rm -rf /var/cache/samba/*

    print_status "Services stopped and cleaned"
}

# Configure time synchronization
configure_ntp() {
    print_status "Configuring time synchronization..."

    if command -v timedatectl &> /dev/null; then
        timedatectl set-ntp true
    fi

    # Configure NTP
    if [[ -f /etc/ntp.conf ]]; then
        cat > /etc/ntp.conf << EOF
driftfile /var/lib/ntp/drift
restrict default nomodify notrap nopeer noquery
restrict 127.0.0.1
restrict ::1
server 0.pool.ntp.org iburst
server 1.pool.ntp.org iburst
server 2.pool.ntp.org iburst
EOF
        systemctl restart ntp 2>/dev/null || systemctl restart ntpd 2>/dev/null || true
    fi

    print_status "Time synchronization configured"
}

# Provision Samba AD DC
provision_samba_ad() {
    print_status "Provisioning Samba AD Domain Controller..."
    print_status "Domain: ${DOMAIN_NAME}"
    print_status "Realm: ${DOMAIN_REALM}"
    print_status "NetBIOS: ${DOMAIN_NETBIOS}"

    samba-tool domain provision \
        --use-rfc2307 \
        --realm="${DOMAIN_REALM}" \
        --domain="${DOMAIN_NETBIOS}" \
        --server-role=dc \
        --dns-backend=SAMBA_INTERNAL \
        --adminpass="${DOMAIN_ADMIN_PASS}"

    print_status "Samba AD DC provisioned"
}

# Configure Kerberos
configure_kerberos() {
    print_status "Configuring Kerberos..."

    # Copy Samba's krb5.conf
    cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

    print_status "Kerberos configured"
}

# Start Samba AD DC service
start_samba_ad() {
    print_status "Starting Samba AD DC service..."

    # Unmask and enable samba-ad-dc service
    systemctl unmask samba-ad-dc 2>/dev/null || true
    systemctl enable samba-ad-dc
    systemctl start samba-ad-dc

    print_status "Samba AD DC service started"
}

# Create test users and groups
create_test_users() {
    print_status "Creating test users and groups..."

    # Wait for Samba to fully start
    sleep 5

    # Create organizational units
    samba-tool ou create "OU=Linux Servers,DC=lab,DC=local" 2>/dev/null || true
    samba-tool ou create "OU=Linux Users,DC=lab,DC=local" 2>/dev/null || true

    # Create groups
    samba-tool group add "linux-admins" --description="Linux Administrators" 2>/dev/null || true
    samba-tool group add "linux-users" --description="Linux Users" 2>/dev/null || true
    samba-tool group add "sudo-users" --description="Users with sudo access" 2>/dev/null || true

    # Create test users
    samba-tool user create testuser1 "TestPass123!" \
        --given-name="Test" \
        --surname="User1" \
        --mail="testuser1@${DOMAIN_NAME}" 2>/dev/null || true

    samba-tool user create testuser2 "TestPass123!" \
        --given-name="Test" \
        --surname="User2" \
        --mail="testuser2@${DOMAIN_NAME}" 2>/dev/null || true

    samba-tool user create linuxadmin "LinuxAdmin123!" \
        --given-name="Linux" \
        --surname="Admin" \
        --mail="linuxadmin@${DOMAIN_NAME}" 2>/dev/null || true

    # Add users to groups
    samba-tool group addmembers "linux-admins" linuxadmin 2>/dev/null || true
    samba-tool group addmembers "linux-users" testuser1,testuser2 2>/dev/null || true
    samba-tool group addmembers "sudo-users" linuxadmin 2>/dev/null || true

    print_status "Test users and groups created"
}

# Configure DNS
configure_dns() {
    print_status "Configuring DNS..."

    # Point resolv.conf to local DNS
    cat > /etc/resolv.conf << EOF
search ${DOMAIN_NAME}
nameserver 127.0.0.1
nameserver ${NETWORK_DNS_SECONDARY}
EOF

    # Prevent NetworkManager from overwriting resolv.conf
    if [[ -f /etc/NetworkManager/NetworkManager.conf ]]; then
        if ! grep -q "dns=none" /etc/NetworkManager/NetworkManager.conf; then
            sed -i '/\[main\]/a dns=none' /etc/NetworkManager/NetworkManager.conf
            systemctl restart NetworkManager 2>/dev/null || true
        fi
    fi

    print_status "DNS configured"
}

# Verify installation
verify_installation() {
    print_status "Verifying installation..."

    echo ""
    echo "=========================================="
    echo "       AD DC Verification Tests          "
    echo "=========================================="
    echo ""

    # Test Samba
    print_status "Testing Samba..."
    smbclient -L localhost -U% | head -20

    # Test DNS
    print_status "Testing DNS resolution..."
    host -t SRV _ldap._tcp.${DOMAIN_NAME}. localhost || true
    host -t SRV _kerberos._tcp.${DOMAIN_NAME}. localhost || true
    host -t A ${DC_FQDN}. localhost || true

    # Test Kerberos
    print_status "Testing Kerberos..."
    echo "${DOMAIN_ADMIN_PASS}" | kinit Administrator@${DOMAIN_REALM}
    klist

    # List domain users
    print_status "Listing domain users..."
    samba-tool user list

    # List domain groups
    print_status "Listing domain groups..."
    samba-tool group list

    echo ""
    echo "=========================================="
    echo "     AD DC Setup Complete!               "
    echo "=========================================="
    echo ""
    echo "Domain Information:"
    echo "  Domain:     ${DOMAIN_NAME}"
    echo "  Realm:      ${DOMAIN_REALM}"
    echo "  NetBIOS:    ${DOMAIN_NETBIOS}"
    echo "  DC IP:      ${DC_IP}"
    echo "  DC FQDN:    ${DC_FQDN}"
    echo ""
    echo "Admin Credentials:"
    echo "  Username:   Administrator"
    echo "  Password:   ${DOMAIN_ADMIN_PASS}"
    echo ""
    echo "Test Users Created:"
    echo "  - testuser1 / TestPass123!"
    echo "  - testuser2 / TestPass123!"
    echo "  - linuxadmin / LinuxAdmin123!"
    echo ""
    echo "Next Steps:"
    echo "  1. Configure Linux VMs to use ${DC_IP} as DNS"
    echo "  2. Run setup-beyondtrust-adbridge.sh on VM1"
    echo "  3. Run setup-centrify.sh on VM2"
    echo ""
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "  Samba AD Domain Controller Setup       "
    echo "=========================================="
    echo ""

    check_root
    detect_distro

    # Install packages based on distribution
    case $DISTRO in
        ubuntu|debian)
            install_packages_ubuntu
            ;;
        rhel|centos|fedora|rocky|almalinux)
            install_packages_rhel
            ;;
        *)
            print_error "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac

    configure_hostname
    configure_network
    configure_ntp
    stop_services
    provision_samba_ad
    configure_kerberos
    configure_dns
    start_samba_ad

    # Wait for services to start
    sleep 10

    create_test_users
    verify_installation
}

main "$@"
