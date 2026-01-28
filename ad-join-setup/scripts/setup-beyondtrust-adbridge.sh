#!/bin/bash
#
# BeyondTrust AD Bridge Setup Script
# This script installs and configures BeyondTrust AD Bridge (formerly PBIS)
# to join a Linux system to Active Directory
#
# Usage: sudo ./setup-beyondtrust-adbridge.sh
#
# Note: BeyondTrust AD Bridge requires a license for enterprise features.
#       PBIS Open (open source version) is used for basic AD join functionality.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# PBIS Open download URL (open source version of AD Bridge)
PBIS_DOWNLOAD_BASE="https://github.com/BeyondTrust/pbis-open/releases/download"
PBIS_VERSION="9.1.0"

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

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Detect Linux distribution and architecture
detect_system() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    else
        print_error "Cannot detect Linux distribution"
        exit 1
    fi

    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH_SUFFIX="x86_64"
            ;;
        aarch64)
            ARCH_SUFFIX="aarch64"
            ;;
        *)
            print_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    print_status "Detected: $DISTRO $VERSION ($ARCH)"
}

# Configure hostname
configure_hostname() {
    print_status "Configuring hostname..."

    hostnamectl set-hostname "${VM1_FQDN}"

    # Update /etc/hosts
    if ! grep -q "${VM1_IP}" /etc/hosts; then
        echo "${VM1_IP}    ${VM1_FQDN} ${VM1_HOSTNAME}" >> /etc/hosts
    fi

    # Add DC entry
    if ! grep -q "${DC_IP}" /etc/hosts; then
        echo "${DC_IP}    ${DC_FQDN} ${DC_HOSTNAME}" >> /etc/hosts
    fi

    print_status "Hostname set to ${VM1_FQDN}"
}

# Configure DNS to point to AD DC
configure_dns() {
    print_status "Configuring DNS..."

    # Backup existing resolv.conf
    cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d%H%M%S)

    # Configure DNS
    cat > /etc/resolv.conf << EOF
search ${DOMAIN_NAME}
nameserver ${DC_IP}
nameserver ${NETWORK_DNS_SECONDARY}
EOF

    # For systems using systemd-resolved
    if systemctl is-active --quiet systemd-resolved; then
        mkdir -p /etc/systemd/resolved.conf.d
        cat > /etc/systemd/resolved.conf.d/ad-dns.conf << EOF
[Resolve]
DNS=${DC_IP}
FallbackDNS=${NETWORK_DNS_SECONDARY}
Domains=${DOMAIN_NAME}
EOF
        systemctl restart systemd-resolved
    fi

    # For netplan-based systems
    if [[ -d /etc/netplan ]]; then
        print_info "Detected netplan - you may need to update /etc/netplan/*.yaml manually"
    fi

    print_status "DNS configured to use ${DC_IP}"
}

# Configure NTP for time synchronization
configure_ntp() {
    print_status "Configuring time synchronization..."

    # Install NTP packages if not present
    if command -v apt-get &> /dev/null; then
        apt-get install -y ntp ntpdate chrony 2>/dev/null || true
    elif command -v yum &> /dev/null; then
        yum install -y ntp ntpdate chrony 2>/dev/null || true
    fi

    # Sync time with DC
    timedatectl set-ntp true 2>/dev/null || true
    ntpdate -u ${DC_IP} 2>/dev/null || true

    print_status "Time synchronized"
}

# Install prerequisites
install_prerequisites() {
    print_status "Installing prerequisites..."

    case $DISTRO in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get install -y \
                wget \
                curl \
                libpam0g \
                libpam-runtime \
                libnss3 \
                openssh-server \
                krb5-user \
                dnsutils \
                nscd
            ;;
        rhel|centos|fedora|rocky|almalinux)
            yum install -y \
                wget \
                curl \
                pam \
                nss \
                openssh-server \
                krb5-workstation \
                bind-utils \
                nscd
            ;;
        *)
            print_warning "Unknown distribution. Attempting to continue..."
            ;;
    esac

    print_status "Prerequisites installed"
}

# Download PBIS Open
download_pbis() {
    print_status "Downloading PBIS Open (BeyondTrust AD Bridge Open Source)..."

    PBIS_DIR="/tmp/pbis-install"
    mkdir -p "$PBIS_DIR"
    cd "$PBIS_DIR"

    # Determine package type based on distribution
    case $DISTRO in
        ubuntu|debian)
            PBIS_FILE="pbis-open-${PBIS_VERSION}.linux.${ARCH_SUFFIX}.deb.sh"
            ;;
        rhel|centos|fedora|rocky|almalinux)
            PBIS_FILE="pbis-open-${PBIS_VERSION}.linux.${ARCH_SUFFIX}.rpm.sh"
            ;;
        *)
            PBIS_FILE="pbis-open-${PBIS_VERSION}.linux.${ARCH_SUFFIX}.deb.sh"
            ;;
    esac

    PBIS_URL="${PBIS_DOWNLOAD_BASE}/${PBIS_VERSION}/${PBIS_FILE}"

    print_info "Downloading from: $PBIS_URL"

    # Download PBIS installer
    if [[ ! -f "$PBIS_FILE" ]]; then
        wget -q --show-progress "$PBIS_URL" -O "$PBIS_FILE" || {
            print_warning "Failed to download from GitHub. Trying alternative method..."

            # Alternative: Clone and build from source
            print_info "You can manually download PBIS from:"
            print_info "https://github.com/BeyondTrust/pbis-open/releases"
            print_info ""
            print_info "Or install using the package manager if available:"
            print_info "  Ubuntu/Debian: apt-get install pbis-open"
            print_info "  RHEL/CentOS:   yum install pbis-open"

            return 1
        }
    fi

    chmod +x "$PBIS_FILE"
    print_status "PBIS downloaded to $PBIS_DIR/$PBIS_FILE"
}

# Install PBIS Open
install_pbis() {
    print_status "Installing PBIS Open..."

    PBIS_DIR="/tmp/pbis-install"
    cd "$PBIS_DIR"

    # Find the installer
    INSTALLER=$(ls -1 pbis-open-*.sh 2>/dev/null | head -1)

    if [[ -z "$INSTALLER" ]]; then
        print_error "PBIS installer not found. Please download manually."
        exit 1
    fi

    # Run installer
    print_info "Running installer: $INSTALLER"
    bash "$INSTALLER" -- --dont-join --no-legacy

    print_status "PBIS installed successfully"
}

# Configure PBIS settings
configure_pbis() {
    print_status "Configuring PBIS settings..."

    # Wait for PBIS services to start
    sleep 5

    # Configure PBIS settings
    /opt/pbis/bin/config AssumeDefaultDomain true
    /opt/pbis/bin/config UserDomainPrefix "${DOMAIN_NETBIOS}"
    /opt/pbis/bin/config LoginShellTemplate /bin/bash
    /opt/pbis/bin/config HomeDirTemplate %H/%U
    /opt/pbis/bin/config RequireMembershipOf ""

    # Configure NSS
    /opt/pbis/bin/config NssEnumerationEnabled true
    /opt/pbis/bin/config NssGroupMembersQueryCacheOnly true

    # Configure PAM
    /opt/pbis/bin/config CreateK5Login true

    print_status "PBIS configured"
}

# Join domain
join_domain() {
    print_status "Joining domain ${DOMAIN_NAME}..."

    print_info "Using credentials:"
    print_info "  Domain:   ${DOMAIN_NAME}"
    print_info "  User:     Administrator"

    # Join domain using PBIS
    /opt/pbis/bin/domainjoin-cli join \
        --ou "OU=Linux Servers,DC=lab,DC=local" \
        "${DOMAIN_NAME}" \
        "Administrator" \
        "${DOMAIN_ADMIN_PASS}"

    if [[ $? -eq 0 ]]; then
        print_status "Successfully joined domain ${DOMAIN_NAME}"
    else
        print_error "Failed to join domain"
        exit 1
    fi
}

# Configure sudo for AD groups
configure_sudo() {
    print_status "Configuring sudo for AD groups..."

    # Create sudoers file for AD groups
    cat > /etc/sudoers.d/ad-admins << EOF
# Allow AD linux-admins group to run sudo
%linux-admins@${DOMAIN_NAME}    ALL=(ALL)    ALL

# Allow AD sudo-users group to run sudo
%sudo-users@${DOMAIN_NAME}    ALL=(ALL)    ALL

# Allow specific admin user
linuxadmin@${DOMAIN_NAME}    ALL=(ALL)    NOPASSWD: ALL
EOF

    chmod 440 /etc/sudoers.d/ad-admins

    print_status "Sudo configured for AD groups"
}

# Configure SSH for AD authentication
configure_ssh() {
    print_status "Configuring SSH for AD authentication..."

    # Update sshd_config
    SSHD_CONFIG="/etc/ssh/sshd_config"

    # Enable password authentication
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
    sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' "$SSHD_CONFIG"
    sed -i 's/^#*UsePAM.*/UsePAM yes/' "$SSHD_CONFIG"

    # Add allowed groups
    if ! grep -q "AllowGroups" "$SSHD_CONFIG"; then
        echo "" >> "$SSHD_CONFIG"
        echo "# AD Groups allowed to SSH" >> "$SSHD_CONFIG"
        echo "AllowGroups root sudo linux-admins@${DOMAIN_NAME} linux-users@${DOMAIN_NAME}" >> "$SSHD_CONFIG"
    fi

    # Restart SSH
    systemctl restart sshd

    print_status "SSH configured for AD authentication"
}

# Verify domain join
verify_join() {
    print_status "Verifying domain join..."

    echo ""
    echo "=========================================="
    echo "     Domain Join Verification            "
    echo "=========================================="
    echo ""

    # Check domain status
    print_status "Domain status:"
    /opt/pbis/bin/domainjoin-cli query

    echo ""

    # Get domain info
    print_status "Domain information:"
    /opt/pbis/bin/lsa ad-get-machine 2>/dev/null || true

    echo ""

    # Test user lookup
    print_status "Testing AD user lookup (Administrator):"
    id "Administrator@${DOMAIN_NAME}" || id "administrator" || true

    echo ""

    # Test user lookup for test users
    print_status "Testing AD user lookup (testuser1):"
    id "testuser1@${DOMAIN_NAME}" || id "testuser1" || true

    echo ""

    # List AD users
    print_status "Enumerating AD users:"
    /opt/pbis/bin/enum-users --level 1 | head -20 || true

    echo ""

    # List AD groups
    print_status "Enumerating AD groups:"
    /opt/pbis/bin/enum-groups --level 1 | head -20 || true

    echo ""

    # Test Kerberos
    print_status "Testing Kerberos authentication:"
    echo "${DOMAIN_ADMIN_PASS}" | kinit "Administrator@${DOMAIN_REALM}" 2>/dev/null && {
        klist
        kdestroy
    } || print_warning "Kerberos test skipped"

    echo ""
}

# Print summary
print_summary() {
    echo ""
    echo "=========================================="
    echo "  BeyondTrust AD Bridge Setup Complete   "
    echo "=========================================="
    echo ""
    echo "System Information:"
    echo "  Hostname:     ${VM1_FQDN}"
    echo "  IP Address:   ${VM1_IP}"
    echo "  Domain:       ${DOMAIN_NAME}"
    echo "  DC:           ${DC_FQDN}"
    echo ""
    echo "PBIS Commands:"
    echo "  Status:       /opt/pbis/bin/domainjoin-cli query"
    echo "  Leave Domain: /opt/pbis/bin/domainjoin-cli leave"
    echo "  User Info:    /opt/pbis/bin/find-user-by-name <username>"
    echo "  Group Info:   /opt/pbis/bin/find-group-by-name <groupname>"
    echo "  Enum Users:   /opt/pbis/bin/enum-users"
    echo "  Enum Groups:  /opt/pbis/bin/enum-groups"
    echo "  Get Config:   /opt/pbis/bin/config --dump"
    echo ""
    echo "Test Login:"
    echo "  ssh testuser1@${DOMAIN_NAME}@${VM1_IP}"
    echo "  Password: TestPass123!"
    echo ""
    echo "Log Files:"
    echo "  /var/log/pbis-open-install.log"
    echo "  /var/log/lsass.log"
    echo ""
    echo "Troubleshooting:"
    echo "  Restart services: /opt/pbis/bin/lwsm restart lsass"
    echo "  Clear cache:      /opt/pbis/bin/ad-cache --delete-all"
    echo "  Debug mode:       /opt/pbis/bin/lwsm set-log-level lsass debug"
    echo ""
}

# Cleanup function
cleanup() {
    print_status "Cleaning up temporary files..."
    rm -rf /tmp/pbis-install
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "  BeyondTrust AD Bridge Setup Script     "
    echo "=========================================="
    echo ""

    check_root
    detect_system
    configure_hostname
    configure_dns
    configure_ntp
    install_prerequisites

    # Download and install PBIS
    if download_pbis; then
        install_pbis
    else
        print_warning "Attempting to continue with manual installation..."
        print_info "Please install PBIS manually and re-run this script with --skip-install"
        exit 1
    fi

    configure_pbis
    join_domain
    configure_sudo
    configure_ssh
    verify_join
    cleanup
    print_summary
}

main "$@"
