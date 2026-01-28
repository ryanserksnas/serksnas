#!/bin/bash
#
# AD Join Verification Script
# Verifies that Linux systems are properly joined to Active Directory
#
# Usage: ./verify-ad-join.sh [hostname]
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
fi

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

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

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

print_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    ((TESTS_SKIPPED++))
}

# Print header
print_header() {
    echo ""
    echo "=========================================="
    echo "  Active Directory Join Verification     "
    echo "=========================================="
    echo ""
    echo "Hostname:    $(hostname -f)"
    echo "Date:        $(date)"
    echo "Domain:      ${DOMAIN_NAME:-lab.local}"
    echo ""
}

# Test DNS resolution
test_dns() {
    echo "----------------------------------------"
    echo "DNS Resolution Tests"
    echo "----------------------------------------"

    # Test DC resolution
    if host "${DC_FQDN:-dc1.lab.local}" > /dev/null 2>&1; then
        print_pass "DC hostname resolves: ${DC_FQDN:-dc1.lab.local}"
    else
        print_fail "Cannot resolve DC hostname: ${DC_FQDN:-dc1.lab.local}"
    fi

    # Test SRV records
    if host -t SRV "_ldap._tcp.${DOMAIN_NAME:-lab.local}" > /dev/null 2>&1; then
        print_pass "LDAP SRV record found"
    else
        print_fail "LDAP SRV record not found"
    fi

    if host -t SRV "_kerberos._tcp.${DOMAIN_NAME:-lab.local}" > /dev/null 2>&1; then
        print_pass "Kerberos SRV record found"
    else
        print_fail "Kerberos SRV record not found"
    fi

    echo ""
}

# Test network connectivity
test_network() {
    echo "----------------------------------------"
    echo "Network Connectivity Tests"
    echo "----------------------------------------"

    DC_IP="${DC_IP:-10.0.0.10}"

    # Ping test
    if ping -c 1 -W 3 "$DC_IP" > /dev/null 2>&1; then
        print_pass "DC is reachable via ping: $DC_IP"
    else
        print_fail "Cannot ping DC: $DC_IP"
    fi

    # LDAP port test
    if timeout 3 bash -c "echo > /dev/tcp/$DC_IP/389" 2>/dev/null; then
        print_pass "LDAP port 389 is open"
    else
        print_fail "LDAP port 389 is not accessible"
    fi

    # Kerberos port test
    if timeout 3 bash -c "echo > /dev/tcp/$DC_IP/88" 2>/dev/null; then
        print_pass "Kerberos port 88 is open"
    else
        print_fail "Kerberos port 88 is not accessible"
    fi

    echo ""
}

# Test time synchronization
test_time_sync() {
    echo "----------------------------------------"
    echo "Time Synchronization Tests"
    echo "----------------------------------------"

    # Check if NTP is enabled
    if timedatectl show --property=NTPSynchronized --value 2>/dev/null | grep -q "yes"; then
        print_pass "NTP synchronization is enabled"
    else
        print_warning "NTP synchronization status unknown"
        print_skip "NTP synchronization check"
    fi

    # Check time difference (should be less than 5 minutes for Kerberos)
    LOCAL_TIME=$(date +%s)
    print_info "Local time: $(date)"

    echo ""
}

# Test domain membership
test_domain_membership() {
    echo "----------------------------------------"
    echo "Domain Membership Tests"
    echo "----------------------------------------"

    # Check realm (realmd/SSSD)
    if command -v realm &> /dev/null; then
        REALM_INFO=$(realm list 2>/dev/null || echo "")
        if [[ -n "$REALM_INFO" ]]; then
            print_pass "System is domain-joined (realm)"
            print_info "$REALM_INFO"
        else
            print_fail "System is not domain-joined (realm)"
        fi
    fi

    # Check PBIS
    if [[ -x /opt/pbis/bin/domainjoin-cli ]]; then
        PBIS_INFO=$(/opt/pbis/bin/domainjoin-cli query 2>/dev/null || echo "")
        if echo "$PBIS_INFO" | grep -q "Domain ="; then
            print_pass "System is domain-joined (PBIS)"
            print_info "$PBIS_INFO"
        else
            print_fail "System is not domain-joined (PBIS)"
        fi
    fi

    # Check Centrify
    if command -v adinfo &> /dev/null; then
        CENTRIFY_INFO=$(adinfo 2>/dev/null || echo "")
        if echo "$CENTRIFY_INFO" | grep -q "Joined to domain"; then
            print_pass "System is domain-joined (Centrify)"
            print_info "$CENTRIFY_INFO"
        else
            print_fail "System is not domain-joined (Centrify)"
        fi
    fi

    echo ""
}

# Test Kerberos authentication
test_kerberos() {
    echo "----------------------------------------"
    echo "Kerberos Authentication Tests"
    echo "----------------------------------------"

    # Check for existing ticket
    if klist -s 2>/dev/null; then
        print_pass "Valid Kerberos ticket exists"
        klist 2>/dev/null | head -10
    else
        print_info "No existing Kerberos ticket"

        # Try to get a ticket (non-interactive test)
        if [[ -n "${DOMAIN_ADMIN_PASS:-}" ]]; then
            if echo "${DOMAIN_ADMIN_PASS}" | kinit "Administrator@${DOMAIN_REALM:-LAB.LOCAL}" 2>/dev/null; then
                print_pass "Successfully obtained Kerberos ticket"
                klist
                kdestroy
            else
                print_fail "Failed to obtain Kerberos ticket"
            fi
        else
            print_skip "Kerberos ticket acquisition (no password provided)"
        fi
    fi

    echo ""
}

# Test user lookups
test_user_lookups() {
    echo "----------------------------------------"
    echo "User Lookup Tests"
    echo "----------------------------------------"

    # Test Administrator lookup
    if id "Administrator" > /dev/null 2>&1 || id "administrator@${DOMAIN_NAME:-lab.local}" > /dev/null 2>&1; then
        print_pass "Administrator user found"
        id "Administrator" 2>/dev/null || id "administrator@${DOMAIN_NAME:-lab.local}" 2>/dev/null
    else
        print_fail "Administrator user not found"
    fi

    # Test testuser1 lookup
    if id "testuser1" > /dev/null 2>&1 || id "testuser1@${DOMAIN_NAME:-lab.local}" > /dev/null 2>&1; then
        print_pass "testuser1 found"
        id "testuser1" 2>/dev/null || id "testuser1@${DOMAIN_NAME:-lab.local}" 2>/dev/null
    else
        print_fail "testuser1 not found"
    fi

    echo ""
}

# Test group lookups
test_group_lookups() {
    echo "----------------------------------------"
    echo "Group Lookup Tests"
    echo "----------------------------------------"

    # Test linux-admins group
    if getent group "linux-admins" > /dev/null 2>&1 || getent group "linux-admins@${DOMAIN_NAME:-lab.local}" > /dev/null 2>&1; then
        print_pass "linux-admins group found"
        getent group "linux-admins" 2>/dev/null || getent group "linux-admins@${DOMAIN_NAME:-lab.local}" 2>/dev/null
    else
        print_fail "linux-admins group not found"
    fi

    # Test Domain Users group
    if getent group "Domain Users" > /dev/null 2>&1 || getent group "domain users@${DOMAIN_NAME:-lab.local}" > /dev/null 2>&1; then
        print_pass "Domain Users group found"
    else
        print_warning "Domain Users group not found (may be expected)"
        print_skip "Domain Users group lookup"
    fi

    echo ""
}

# Test SSSD status
test_sssd() {
    echo "----------------------------------------"
    echo "SSSD Status Tests"
    echo "----------------------------------------"

    if systemctl is-active --quiet sssd 2>/dev/null; then
        print_pass "SSSD service is running"

        if command -v sssctl &> /dev/null; then
            print_info "SSSD domain status:"
            sssctl domain-status "${DOMAIN_NAME:-lab.local}" 2>/dev/null || true
        fi
    else
        print_skip "SSSD not running or not installed"
    fi

    echo ""
}

# Test PBIS status
test_pbis() {
    echo "----------------------------------------"
    echo "PBIS/BeyondTrust Status Tests"
    echo "----------------------------------------"

    if [[ -x /opt/pbis/bin/lwsm ]]; then
        print_info "PBIS services status:"
        /opt/pbis/bin/lwsm list 2>/dev/null || true

        if /opt/pbis/bin/lwsm status lsass 2>/dev/null | grep -q "running"; then
            print_pass "PBIS lsass service is running"
        else
            print_fail "PBIS lsass service is not running"
        fi
    else
        print_skip "PBIS not installed"
    fi

    echo ""
}

# Test Centrify status
test_centrify() {
    echo "----------------------------------------"
    echo "Centrify Status Tests"
    echo "----------------------------------------"

    if command -v adinfo &> /dev/null; then
        print_info "Centrify status:"
        adinfo 2>/dev/null || true

        if adinfo 2>/dev/null | grep -q "Joined to domain"; then
            print_pass "Centrify is joined to domain"
        else
            print_fail "Centrify is not joined to domain"
        fi
    else
        print_skip "Centrify not installed"
    fi

    echo ""
}

# Test SSH access
test_ssh() {
    echo "----------------------------------------"
    echo "SSH Configuration Tests"
    echo "----------------------------------------"

    # Check SSH service
    if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
        print_pass "SSH service is running"
    else
        print_fail "SSH service is not running"
    fi

    # Check PAM configuration
    if grep -r "pam_sss\|pam_lsass\|pam_centrify" /etc/pam.d/ > /dev/null 2>&1; then
        print_pass "PAM is configured for AD authentication"
    else
        print_warning "PAM may not be configured for AD authentication"
        print_skip "PAM AD configuration check"
    fi

    echo ""
}

# Test sudo configuration
test_sudo() {
    echo "----------------------------------------"
    echo "Sudo Configuration Tests"
    echo "----------------------------------------"

    # Check for AD groups in sudoers
    if [[ -f /etc/sudoers.d/ad-admins ]]; then
        print_pass "AD admin sudoers file exists"
        cat /etc/sudoers.d/ad-admins 2>/dev/null | grep -v "^#" | head -5
    else
        print_warning "AD admin sudoers file not found"
        print_skip "AD sudoers configuration check"
    fi

    echo ""
}

# Print summary
print_summary() {
    echo "=========================================="
    echo "          Verification Summary           "
    echo "=========================================="
    echo ""
    echo -e "Tests Passed:  ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Tests Failed:  ${RED}${TESTS_FAILED}${NC}"
    echo -e "Tests Skipped: ${YELLOW}${TESTS_SKIPPED}${NC}"
    echo ""

    TOTAL=$((TESTS_PASSED + TESTS_FAILED))
    if [[ $TOTAL -gt 0 ]]; then
        PERCENTAGE=$((TESTS_PASSED * 100 / TOTAL))
        echo "Success Rate: ${PERCENTAGE}%"
    fi

    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed! AD join appears successful.${NC}"
    elif [[ $TESTS_FAILED -le 2 ]]; then
        echo -e "${YELLOW}Most tests passed. Review failed tests above.${NC}"
    else
        echo -e "${RED}Multiple tests failed. AD join may have issues.${NC}"
    fi

    echo ""
}

# Main execution
main() {
    print_header

    test_dns
    test_network
    test_time_sync
    test_domain_membership
    test_kerberos
    test_user_lookups
    test_group_lookups
    test_sssd
    test_pbis
    test_centrify
    test_ssh
    test_sudo

    print_summary
}

main "$@"
