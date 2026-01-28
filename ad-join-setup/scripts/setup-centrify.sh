#!/bin/bash
#
# Centrify (Delinea) Setup Script
# This script installs and configures Centrify DirectControl
# to join a Linux system to Active Directory
#
# Usage: sudo ./setup-centrify.sh
#
# Note: Centrify requires a license from Delinea. Trial available at:
#       https://www.delinea.com/products/server-suite
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

# Centrify package names
CENTRIFY_DC_PACKAGE="CentrifyDC"
CENTRIFY_SSHD_PACKAGE="CentrifyDC-openssh"

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
        VERSION_MAJOR=$(echo "$VERSION" | cut -d. -f1)
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

    hostnamectl set-hostname "${VM2_FQDN}"

    # Update /etc/hosts
    if ! grep -q "${VM2_IP}" /etc/hosts; then
        echo "${VM2_IP}    ${VM2_FQDN} ${VM2_HOSTNAME}" >> /etc/hosts
    fi

    # Add DC entry
    if ! grep -q "${DC_IP}" /etc/hosts; then
        echo "${DC_IP}    ${DC_FQDN} ${DC_HOSTNAME}" >> /etc/hosts
    fi

    print_status "Hostname set to ${VM2_FQDN}"
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
                nscd \
                perl \
                libsasl2-modules-gssapi-mit
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
                nscd \
                perl \
                cyrus-sasl-gssapi
            ;;
        *)
            print_warning "Unknown distribution. Attempting to continue..."
            ;;
    esac

    print_status "Prerequisites installed"
}

# Add Centrify repository
add_centrify_repo() {
    print_status "Adding Centrify repository..."

    case $DISTRO in
        ubuntu|debian)
            # Add Centrify GPG key
            print_info "Downloading Centrify GPG key..."
            wget -q -O /tmp/centrify-public.key https://edge.centrify.com/products/centrify-repo/7zip/RPM-GPG-KEY-centrify 2>/dev/null || {
                print_warning "Could not download GPG key automatically"
            }

            # Add repository
            cat > /etc/apt/sources.list.d/centrify.list << EOF
# Centrify Repository
# Note: Replace with actual repository URL from Delinea support portal
# deb https://repo.centrify.com/deb stable main
EOF

            print_info "Repository placeholder added. You need to:"
            print_info "1. Get Centrify packages from Delinea support portal"
            print_info "2. Or use the downloaded installer package"
            ;;

        rhel|centos|fedora|rocky|almalinux)
            # Add Centrify repository for RHEL-based systems
            cat > /etc/yum.repos.d/centrify.repo << EOF
[centrify]
name=Centrify Repository
baseurl=https://repo.centrify.com/rpm-redhat/\$releasever/\$basearch/
enabled=1
gpgcheck=1
gpgkey=https://edge.centrify.com/products/centrify-repo/7zip/RPM-GPG-KEY-centrify
EOF

            print_info "Repository added for RHEL-based system"
            ;;
    esac

    print_status "Centrify repository configured"
}

# Download Centrify packages
download_centrify() {
    print_status "Preparing Centrify installation..."

    CENTRIFY_DIR="/tmp/centrify-install"
    mkdir -p "$CENTRIFY_DIR"
    cd "$CENTRIFY_DIR"

    print_info ""
    print_info "=========================================="
    print_info "  Centrify Package Download Required     "
    print_info "=========================================="
    print_info ""
    print_info "Centrify (Delinea Server Suite) requires a license."
    print_info ""
    print_info "To obtain Centrify packages:"
    print_info ""
    print_info "1. Visit: https://www.delinea.com/products/server-suite"
    print_info "2. Request a trial or purchase a license"
    print_info "3. Download the Centrify Infrastructure Services package"
    print_info "4. Extract and place packages in: $CENTRIFY_DIR"
    print_info ""
    print_info "Expected packages:"
    print_info "  - CentrifyDC-<version>.<arch>.rpm (or .deb)"
    print_info "  - CentrifyDC-openssh-<version>.<arch>.rpm (or .deb)"
    print_info ""
    print_info "After placing packages, re-run this script."
    print_info ""

    # Check if packages exist
    PACKAGES_FOUND=0

    case $DISTRO in
        ubuntu|debian)
            if ls -1 CentrifyDC*.deb 2>/dev/null | head -1 > /dev/null; then
                print_status "Found Centrify DEB packages"
                PACKAGES_FOUND=1
            fi
            ;;
        rhel|centos|fedora|rocky|almalinux)
            if ls -1 CentrifyDC*.rpm 2>/dev/null | head -1 > /dev/null; then
                print_status "Found Centrify RPM packages"
                PACKAGES_FOUND=1
            fi
            ;;
    esac

    if [[ $PACKAGES_FOUND -eq 0 ]]; then
        print_warning "Centrify packages not found. Using alternative SSSD-based AD join..."
        return 1
    fi

    return 0
}

# Install Centrify
install_centrify() {
    print_status "Installing Centrify..."

    CENTRIFY_DIR="/tmp/centrify-install"
    cd "$CENTRIFY_DIR"

    case $DISTRO in
        ubuntu|debian)
            # Install DEB packages
            dpkg -i CentrifyDC*.deb || apt-get install -f -y
            ;;
        rhel|centos|fedora|rocky|almalinux)
            # Install RPM packages
            yum localinstall -y CentrifyDC*.rpm
            ;;
    esac

    print_status "Centrify installed"
}

# Install SSSD as alternative to Centrify
install_sssd_alternative() {
    print_status "Installing SSSD as Centrify alternative..."

    case $DISTRO in
        ubuntu|debian)
            apt-get install -y \
                sssd \
                sssd-ad \
                sssd-tools \
                realmd \
                adcli \
                krb5-user \
                packagekit \
                samba-common \
                samba-common-bin \
                samba-libs \
                oddjob \
                oddjob-mkhomedir
            ;;
        rhel|centos|fedora|rocky|almalinux)
            yum install -y \
                sssd \
                sssd-ad \
                sssd-tools \
                realmd \
                adcli \
                krb5-workstation \
                samba-common \
                samba-common-tools \
                oddjob \
                oddjob-mkhomedir
            ;;
    esac

    print_status "SSSD installed"
}

# Configure SSSD for AD
configure_sssd() {
    print_status "Configuring SSSD for Active Directory..."

    # Create SSSD configuration
    cat > /etc/sssd/sssd.conf << EOF
[sssd]
services = nss, pam, ssh, sudo
config_file_version = 2
domains = ${DOMAIN_NAME}

[domain/${DOMAIN_NAME}]
ad_domain = ${DOMAIN_NAME}
krb5_realm = ${DOMAIN_REALM}
realmd_tags = manages-system joined-with-adcli
cache_credentials = True
id_provider = ad
access_provider = ad
auth_provider = ad
chpass_provider = ad

# Use short names for users
use_fully_qualified_names = False
fallback_homedir = /home/%u
default_shell = /bin/bash

# LDAP settings
ldap_id_mapping = True
ldap_schema = ad
ldap_idmap_range_min = 200000
ldap_idmap_range_max = 2000200000
ldap_idmap_range_size = 200000

# Performance tuning
enumerate = False
ldap_referrals = False

# Access control
ad_gpo_access_control = permissive

# Debug level (0-9, higher = more verbose)
debug_level = 3

[nss]
filter_groups = root
filter_users = root

[pam]
offline_credentials_expiration = 7

[sudo]
EOF

    # Set permissions
    chmod 600 /etc/sssd/sssd.conf
    chown root:root /etc/sssd/sssd.conf

    print_status "SSSD configured"
}

# Configure Kerberos
configure_kerberos() {
    print_status "Configuring Kerberos..."

    cat > /etc/krb5.conf << EOF
[libdefaults]
    default_realm = ${DOMAIN_REALM}
    dns_lookup_realm = false
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = false

[realms]
    ${DOMAIN_REALM} = {
        kdc = ${DC_FQDN}
        admin_server = ${DC_FQDN}
        default_domain = ${DOMAIN_NAME}
    }

[domain_realm]
    .${DOMAIN_NAME} = ${DOMAIN_REALM}
    ${DOMAIN_NAME} = ${DOMAIN_REALM}
EOF

    print_status "Kerberos configured"
}

# Join domain using Centrify
join_domain_centrify() {
    print_status "Joining domain using Centrify..."

    # Join using adjoin
    /usr/sbin/adjoin \
        --zone "Auto Zone" \
        --container "OU=Linux Servers,DC=lab,DC=local" \
        --user "Administrator" \
        --password "${DOMAIN_ADMIN_PASS}" \
        "${DOMAIN_NAME}"

    if [[ $? -eq 0 ]]; then
        print_status "Successfully joined domain using Centrify"
    else
        print_error "Failed to join domain using Centrify"
        exit 1
    fi
}

# Join domain using realmd/SSSD
join_domain_sssd() {
    print_status "Joining domain using realmd/SSSD..."

    # Discover domain
    print_info "Discovering domain ${DOMAIN_NAME}..."
    realm discover "${DOMAIN_NAME}" || {
        print_warning "Domain discovery failed. Attempting manual join..."
    }

    # Join domain
    print_info "Joining domain..."
    echo "${DOMAIN_ADMIN_PASS}" | realm join \
        --user=Administrator \
        --computer-ou="OU=Linux Servers,DC=lab,DC=local" \
        "${DOMAIN_NAME}"

    if [[ $? -eq 0 ]]; then
        print_status "Successfully joined domain using realmd/SSSD"
    else
        print_error "Failed to join domain"
        exit 1
    fi

    # Configure SSSD
    configure_sssd

    # Enable and start SSSD
    systemctl enable sssd
    systemctl restart sssd

    # Enable home directory creation
    if command -v pam-auth-update &> /dev/null; then
        pam-auth-update --enable mkhomedir
    elif command -v authconfig &> /dev/null; then
        authconfig --enablemkhomedir --update
    else
        # Manual PAM configuration
        if ! grep -q "pam_mkhomedir.so" /etc/pam.d/common-session 2>/dev/null; then
            echo "session required pam_mkhomedir.so skel=/etc/skel/ umask=0077" >> /etc/pam.d/common-session
        fi
    fi
}

# Configure sudo for AD groups
configure_sudo() {
    print_status "Configuring sudo for AD groups..."

    # Create sudoers file for AD groups
    cat > /etc/sudoers.d/ad-admins << EOF
# Allow AD linux-admins group to run sudo
%linux-admins    ALL=(ALL)    ALL

# Allow AD sudo-users group to run sudo
%sudo-users    ALL=(ALL)    ALL

# Allow specific admin user
linuxadmin    ALL=(ALL)    NOPASSWD: ALL
EOF

    chmod 440 /etc/sudoers.d/ad-admins

    print_status "Sudo configured for AD groups"
}

# Configure SSH for AD authentication
configure_ssh() {
    print_status "Configuring SSH for AD authentication..."

    SSHD_CONFIG="/etc/ssh/sshd_config"

    # Enable password authentication
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
    sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' "$SSHD_CONFIG"
    sed -i 's/^#*UsePAM.*/UsePAM yes/' "$SSHD_CONFIG"
    sed -i 's/^#*GSSAPIAuthentication.*/GSSAPIAuthentication yes/' "$SSHD_CONFIG"

    # Add allowed groups (if not using Centrify SSHD)
    if ! grep -q "AllowGroups" "$SSHD_CONFIG"; then
        echo "" >> "$SSHD_CONFIG"
        echo "# AD Groups allowed to SSH" >> "$SSHD_CONFIG"
        echo "AllowGroups root sudo linux-admins linux-users" >> "$SSHD_CONFIG"
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

    # Check realm status
    print_status "Realm/Domain status:"
    realm list 2>/dev/null || /usr/sbin/adinfo 2>/dev/null || true

    echo ""

    # Test user lookup
    print_status "Testing AD user lookup (Administrator):"
    id "Administrator" || id "administrator@${DOMAIN_NAME}" || true

    echo ""

    # Test user lookup for test users
    print_status "Testing AD user lookup (testuser1):"
    id "testuser1" || id "testuser1@${DOMAIN_NAME}" || true

    echo ""

    # Test group lookup
    print_status "Testing AD group lookup (linux-admins):"
    getent group linux-admins || getent group "linux-admins@${DOMAIN_NAME}" || true

    echo ""

    # Test Kerberos
    print_status "Testing Kerberos authentication:"
    echo "${DOMAIN_ADMIN_PASS}" | kinit "Administrator@${DOMAIN_REALM}" 2>/dev/null && {
        klist
        kdestroy
    } || print_warning "Kerberos test skipped"

    echo ""

    # Check SSSD status (if using SSSD)
    if systemctl is-active --quiet sssd; then
        print_status "SSSD Status:"
        systemctl status sssd --no-pager | head -10
    fi

    # Check Centrify status (if using Centrify)
    if command -v adinfo &> /dev/null; then
        print_status "Centrify Status:"
        adinfo
    fi

    echo ""
}

# Print summary
print_summary() {
    echo ""
    echo "=========================================="
    echo "     Centrify/SSSD Setup Complete        "
    echo "=========================================="
    echo ""
    echo "System Information:"
    echo "  Hostname:     ${VM2_FQDN}"
    echo "  IP Address:   ${VM2_IP}"
    echo "  Domain:       ${DOMAIN_NAME}"
    echo "  DC:           ${DC_FQDN}"
    echo ""

    if command -v adinfo &> /dev/null; then
        echo "Centrify Commands:"
        echo "  Status:       adinfo"
        echo "  User Info:    adquery user <username>"
        echo "  Group Info:   adquery group <groupname>"
        echo "  Leave Domain: adleave"
        echo "  Flush Cache:  adflush"
        echo ""
    else
        echo "SSSD/Realm Commands:"
        echo "  Status:       realm list"
        echo "  User Info:    id <username>"
        echo "  Group Info:   getent group <groupname>"
        echo "  Leave Domain: realm leave"
        echo "  Cache Status: sssctl domain-status ${DOMAIN_NAME}"
        echo ""
    fi

    echo "Test Login:"
    echo "  ssh testuser1@${VM2_IP}"
    echo "  Password: TestPass123!"
    echo ""
    echo "Log Files:"
    echo "  /var/log/sssd/*.log"
    echo "  /var/log/auth.log (or /var/log/secure)"
    echo ""
    echo "Troubleshooting:"
    echo "  Restart SSSD:  systemctl restart sssd"
    echo "  Clear cache:   sss_cache -E"
    echo "  Debug logs:    Set debug_level = 9 in /etc/sssd/sssd.conf"
    echo ""
}

# Cleanup function
cleanup() {
    print_status "Cleaning up temporary files..."
    rm -rf /tmp/centrify-install
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "     Centrify (Delinea) Setup Script     "
    echo "=========================================="
    echo ""

    check_root
    detect_system
    configure_hostname
    configure_dns
    configure_ntp
    install_prerequisites
    add_centrify_repo
    configure_kerberos

    # Try to download and install Centrify
    if download_centrify; then
        install_centrify
        join_domain_centrify
    else
        print_warning "Using SSSD as Centrify alternative..."
        install_sssd_alternative
        join_domain_sssd
    fi

    configure_sudo
    configure_ssh
    verify_join
    cleanup
    print_summary
}

main "$@"
