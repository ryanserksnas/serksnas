# BeyondTrust AD Bridge Detailed Setup Guide

This guide provides comprehensive instructions for installing and configuring BeyondTrust AD Bridge (formerly PowerBroker Identity Services / PBIS) to join Linux systems to Active Directory.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Installation](#installation)
5. [Domain Join](#domain-join)
6. [Configuration](#configuration)
7. [User and Group Management](#user-and-group-management)
8. [SSH Configuration](#ssh-configuration)
9. [Sudo Configuration](#sudo-configuration)
10. [Advanced Features](#advanced-features)
11. [Maintenance](#maintenance)
12. [Uninstallation](#uninstallation)

---

## Overview

BeyondTrust AD Bridge enables Linux and Unix systems to join Microsoft Active Directory domains, providing:

- **Single Sign-On (SSO)**: Users authenticate with their AD credentials
- **Centralized Identity Management**: Manage users and groups from AD
- **Group Policy Support**: Apply Windows Group Policy to Linux systems
- **Privileged Access Management**: Control who can access what on Linux systems
- **Compliance**: Audit trails and logging for compliance requirements

### Editions

- **PBIS Open**: Open-source version with basic AD integration (used in this guide)
- **AD Bridge Enterprise**: Commercial version with full features including GPO support

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    BeyondTrust AD Bridge                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   LSASS      │    │   NETLOGON   │    │   EVENTLOG   │      │
│  │  (Auth)      │◄──►│  (Domain)    │◄──►│  (Logging)   │      │
│  └──────┬───────┘    └──────────────┘    └──────────────┘      │
│         │                                                        │
│         │                                                        │
│  ┌──────▼───────┐    ┌──────────────┐                          │
│  │   PAM/NSS    │    │   Kerberos   │                          │
│  │  Integration │◄──►│   Client     │                          │
│  └──────────────┘    └──────────────┘                          │
│                                                                  │
│         │                                                        │
│         │  LDAP/Kerberos                                        │
│         ▼                                                        │
│  ┌──────────────────────────────────────────────────────┐      │
│  │              Active Directory Domain                  │      │
│  └──────────────────────────────────────────────────────┘      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Description |
|-----------|-------------|
| lsass | Local Security Authority Subsystem - handles authentication |
| netlogon | Manages domain membership and secure channel |
| eventlog | Logs security events |
| lwregd | Registry service for configuration |
| lwsmd | Service manager |

---

## Prerequisites

### System Requirements

- **Supported Operating Systems:**
  - Ubuntu 18.04, 20.04, 22.04
  - Debian 10, 11
  - RHEL/CentOS 7, 8, 9
  - Rocky Linux 8, 9
  - AlmaLinux 8, 9
  - SUSE Linux Enterprise 12, 15

- **Hardware:**
  - 512 MB RAM minimum
  - 500 MB disk space

- **Network:**
  - DNS resolution to AD domain controllers
  - Network access to ports 53, 88, 389, 464, 636

### Pre-installation Checklist

```bash
# 1. Verify DNS resolution
host dc1.lab.local
nslookup _ldap._tcp.lab.local

# 2. Verify network connectivity
ping dc1.lab.local
nc -zv dc1.lab.local 389
nc -zv dc1.lab.local 88

# 3. Verify time synchronization
timedatectl status
ntpdate -q dc1.lab.local

# 4. Verify hostname configuration
hostname -f
# Should return FQDN like: linux-bt.lab.local
```

---

## Installation

### Download PBIS Open

```bash
# Create installation directory
mkdir -p /tmp/pbis-install
cd /tmp/pbis-install

# Download for Ubuntu/Debian (x86_64)
wget https://github.com/BeyondTrust/pbis-open/releases/download/9.1.0/pbis-open-9.1.0.linux.x86_64.deb.sh

# Download for RHEL/CentOS (x86_64)
wget https://github.com/BeyondTrust/pbis-open/releases/download/9.1.0/pbis-open-9.1.0.linux.x86_64.rpm.sh

# Make executable
chmod +x pbis-open-*.sh
```

### Run Installer

```bash
# Install without joining domain
sudo ./pbis-open-9.1.0.linux.x86_64.deb.sh -- --dont-join --no-legacy

# Or for RHEL
sudo ./pbis-open-9.1.0.linux.x86_64.rpm.sh -- --dont-join --no-legacy
```

### Verify Installation

```bash
# Check installed services
/opt/pbis/bin/lwsm list

# Verify LSASS is running
/opt/pbis/bin/lwsm status lsass

# Check version
/opt/pbis/bin/pbis-status
```

---

## Domain Join

### Basic Domain Join

```bash
# Join domain
sudo /opt/pbis/bin/domainjoin-cli join lab.local Administrator

# Enter password when prompted
```

### Domain Join with Options

```bash
# Join to specific OU
sudo /opt/pbis/bin/domainjoin-cli join \
    --ou "OU=Linux Servers,DC=lab,DC=local" \
    lab.local Administrator

# Join with password in command (not recommended for production)
sudo /opt/pbis/bin/domainjoin-cli join \
    --ou "OU=Linux Servers,DC=lab,DC=local" \
    lab.local Administrator "P@ssw0rd123!"

# Force rejoin if computer account exists
sudo /opt/pbis/bin/domainjoin-cli join --force lab.local Administrator
```

### Verify Domain Join

```bash
# Query domain status
/opt/pbis/bin/domainjoin-cli query

# Get machine info
/opt/pbis/bin/lsa ad-get-machine

# Test user lookup
id administrator@lab.local
id testuser1
```

---

## Configuration

### Configuration Tool

PBIS uses a centralized configuration system:

```bash
# View all settings
/opt/pbis/bin/config --dump

# View specific setting
/opt/pbis/bin/config AssumeDefaultDomain

# Set a configuration value
/opt/pbis/bin/config AssumeDefaultDomain true
```

### Essential Settings

```bash
# Allow users to login with short names (no domain suffix)
/opt/pbis/bin/config AssumeDefaultDomain true
/opt/pbis/bin/config UserDomainPrefix LAB

# Set default shell
/opt/pbis/bin/config LoginShellTemplate /bin/bash

# Set home directory template
/opt/pbis/bin/config HomeDirTemplate %H/%U

# Enable home directory creation
/opt/pbis/bin/config CreateK5Login true

# Enable NSS enumeration (for getent passwd to work)
/opt/pbis/bin/config NssEnumerationEnabled true
```

### All Configuration Options

| Setting | Description | Default |
|---------|-------------|---------|
| AssumeDefaultDomain | Allow short usernames | false |
| UserDomainPrefix | Default domain prefix | (domain) |
| LoginShellTemplate | Default user shell | /bin/sh |
| HomeDirTemplate | Home directory pattern | %H/%D/%U |
| HomeDirUmask | Umask for home dirs | 022 |
| CreateK5Login | Create .k5login file | true |
| NssEnumerationEnabled | Allow user/group enumeration | true |
| RequireMembershipOf | Require group membership for login | (empty) |
| DomainSeparator | Character between domain and user | \\ |

---

## User and Group Management

### User Lookups

```bash
# Find user by name
/opt/pbis/bin/find-user-by-name testuser1
/opt/pbis/bin/find-user-by-name administrator@lab.local

# Find user by ID
/opt/pbis/bin/find-user-by-id 10001

# Enumerate all users
/opt/pbis/bin/enum-users

# Get user info with details
/opt/pbis/bin/enum-users --level 2
```

### Group Lookups

```bash
# Find group by name
/opt/pbis/bin/find-group-by-name linux-admins
/opt/pbis/bin/find-group-by-name "Domain Users"

# Find group by ID
/opt/pbis/bin/find-group-by-id 10002

# Enumerate all groups
/opt/pbis/bin/enum-groups

# Get group members
/opt/pbis/bin/enum-members "linux-admins"
```

### Using Standard Commands

```bash
# Standard Unix commands work with AD users
id testuser1
groups testuser1
getent passwd testuser1
getent group linux-admins
```

---

## SSH Configuration

### Basic SSH Configuration

```bash
# /etc/ssh/sshd_config
PasswordAuthentication yes
ChallengeResponseAuthentication yes
UsePAM yes
GSSAPIAuthentication yes
```

### Restrict SSH to Specific Groups

```bash
# /etc/ssh/sshd_config
AllowGroups root sudo linux-admins@lab.local linux-users@lab.local
```

### Kerberos-based SSH

```bash
# Enable GSSAPI
GSSAPIAuthentication yes
GSSAPICleanupCredentials yes
```

### Apply SSH Changes

```bash
sudo systemctl restart sshd
```

---

## Sudo Configuration

### Grant Sudo to AD Groups

```bash
# Create /etc/sudoers.d/ad-admins
cat <<EOF | sudo tee /etc/sudoers.d/ad-admins
# Allow AD linux-admins group full sudo
%linux-admins@lab.local    ALL=(ALL)    ALL

# Allow AD sudo-users group full sudo
%sudo-users@lab.local    ALL=(ALL)    ALL

# Allow linuxadmin user passwordless sudo
linuxadmin@lab.local    ALL=(ALL)    NOPASSWD: ALL

# Allow Domain Admins full sudo
%Domain\ Admins@lab.local    ALL=(ALL)    ALL
EOF

# Set permissions
sudo chmod 440 /etc/sudoers.d/ad-admins
```

### Grant Sudo Without Domain Suffix

If `AssumeDefaultDomain` is enabled:

```bash
# /etc/sudoers.d/ad-admins
%linux-admins    ALL=(ALL)    ALL
linuxadmin    ALL=(ALL)    NOPASSWD: ALL
```

---

## Advanced Features

### Restrict Login to Specific Groups

```bash
# Only allow members of linux-users or linux-admins to login
/opt/pbis/bin/config RequireMembershipOf "LAB\\linux-users" "LAB\\linux-admins"

# Clear restrictions (allow all domain users)
/opt/pbis/bin/config RequireMembershipOf ""
```

### Offline Authentication

PBIS supports offline authentication when the DC is unavailable:

```bash
# Enable offline caching
/opt/pbis/bin/config DomainManagerCheckDomainOnlineInterval 60
/opt/pbis/bin/config CacheEntryExpiry 86400
```

### Password Policy Integration

```bash
# View password policy
/opt/pbis/bin/lsa ad-get-machine | grep -i password

# Force password change on next login (requires AD admin rights)
# This is typically done on the AD side
```

### Smart Card Authentication

AD Bridge Enterprise supports smart card authentication:

```bash
# Enable smart card authentication (Enterprise only)
/opt/pbis/bin/config SmartCardAuthenticationEnabled true
```

---

## Maintenance

### Cache Management

```bash
# Clear all cached data
/opt/pbis/bin/ad-cache --delete-all

# Clear specific user cache
/opt/pbis/bin/ad-cache --delete-user testuser1

# View cache statistics
/opt/pbis/bin/ad-cache --list
```

### Service Management

```bash
# List all services
/opt/pbis/bin/lwsm list

# Restart LSASS
/opt/pbis/bin/lwsm restart lsass

# Stop all services
/opt/pbis/bin/lwsm shutdown

# Start all services
/opt/pbis/bin/lwsm autostart
```

### Log Management

```bash
# Set log level
/opt/pbis/bin/lwsm set-log-level lsass debug

# View logs
tail -f /var/log/lsass.log

# Reset to normal logging
/opt/pbis/bin/lwsm set-log-level lsass warning
```

### Update Computer Password

Computer accounts have passwords that expire by default:

```bash
# Manually update machine password
/opt/pbis/bin/lsa ad-get-machine --refresh
```

---

## Uninstallation

### Leave Domain

```bash
# Leave domain (removes computer account)
sudo /opt/pbis/bin/domainjoin-cli leave

# Leave domain with credentials
sudo /opt/pbis/bin/domainjoin-cli leave --username Administrator --password "P@ssw0rd123!"
```

### Uninstall PBIS

```bash
# Ubuntu/Debian
sudo /opt/pbis/bin/uninstall.sh

# Or using package manager
sudo dpkg -P pbis-open

# RHEL/CentOS
sudo /opt/pbis/bin/uninstall.sh
# Or
sudo yum remove pbis-open
```

### Clean Up

```bash
# Remove configuration
sudo rm -rf /var/lib/pbis
sudo rm -rf /var/log/lsass.log
sudo rm -rf /opt/pbis

# Restore original nsswitch.conf
sudo sed -i 's/lsass//g' /etc/nsswitch.conf
```

---

## Quick Reference

### Common Commands

| Command | Description |
|---------|-------------|
| `/opt/pbis/bin/domainjoin-cli query` | Check domain status |
| `/opt/pbis/bin/domainjoin-cli join` | Join domain |
| `/opt/pbis/bin/domainjoin-cli leave` | Leave domain |
| `/opt/pbis/bin/config --dump` | View all settings |
| `/opt/pbis/bin/find-user-by-name` | Find AD user |
| `/opt/pbis/bin/find-group-by-name` | Find AD group |
| `/opt/pbis/bin/enum-users` | List all AD users |
| `/opt/pbis/bin/enum-groups` | List all AD groups |
| `/opt/pbis/bin/ad-cache --delete-all` | Clear cache |
| `/opt/pbis/bin/lwsm restart lsass` | Restart auth service |

### Important Files

| File | Description |
|------|-------------|
| `/opt/pbis/` | Installation directory |
| `/var/lib/pbis/` | Data and cache |
| `/var/log/lsass.log` | Authentication log |
| `/etc/krb5.conf` | Kerberos configuration |
| `/etc/nsswitch.conf` | NSS configuration |
| `/etc/pam.d/` | PAM configuration |

### Log Files

```bash
# Main authentication log
/var/log/lsass.log

# Installation log
/var/log/pbis-open-install.log

# System authentication log
/var/log/auth.log      # Debian/Ubuntu
/var/log/secure        # RHEL/CentOS
```
