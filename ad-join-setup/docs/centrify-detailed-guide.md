# Centrify (Delinea Server Suite) Detailed Setup Guide

This guide provides comprehensive instructions for installing and configuring Centrify DirectControl (now Delinea Server Suite) to join Linux systems to Active Directory.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Installation](#installation)
5. [Domain Join](#domain-join)
6. [Configuration](#configuration)
7. [Zone Management](#zone-management)
8. [User and Group Management](#user-and-group-management)
9. [Access Control](#access-control)
10. [Privilege Elevation](#privilege-elevation)
11. [Maintenance](#maintenance)
12. [Alternative: SSSD Setup](#alternative-sssd-setup)

---

## Overview

Centrify DirectControl (now Delinea Server Suite) provides enterprise-grade Active Directory integration for Linux and Unix systems, offering:

- **Active Directory Integration**: Join Linux systems to AD without schema changes
- **Zone-Based Management**: Organize and manage systems using zones
- **Role-Based Access Control**: Fine-grained control over who can access what
- **Privilege Elevation**: Control sudo-like access through AD
- **Multi-Factor Authentication**: Integrated MFA support
- **Compliance**: Comprehensive audit trails

### Product Editions

- **Delinea Server Suite Standard**: Basic AD integration
- **Delinea Server Suite Enterprise**: Full features including privilege elevation
- **Delinea Server PAM**: Advanced privileged access management

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Centrify Architecture                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────┐        │
│  │                  Delinea Cloud                       │        │
│  │            (Optional Management Portal)              │        │
│  └──────────────────────┬──────────────────────────────┘        │
│                         │                                        │
│  ┌──────────────────────▼──────────────────────────────┐        │
│  │              Active Directory                        │        │
│  │                                                      │        │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐    │        │
│  │  │   Zones    │  │   Roles    │  │ Computer   │    │        │
│  │  │            │  │            │  │  Objects   │    │        │
│  │  └────────────┘  └────────────┘  └────────────┘    │        │
│  └──────────────────────┬──────────────────────────────┘        │
│                         │                                        │
│           LDAP/Kerberos │                                        │
│                         │                                        │
│  ┌──────────────────────▼──────────────────────────────┐        │
│  │              Linux System                            │        │
│  │                                                      │        │
│  │  ┌──────────────┐  ┌──────────────┐                │        │
│  │  │  Centrify    │  │    PAM/NSS   │                │        │
│  │  │   Agent      │──│  Integration │                │        │
│  │  │  (adclient)  │  │              │                │        │
│  │  └──────────────┘  └──────────────┘                │        │
│  │                                                      │        │
│  └──────────────────────────────────────────────────────┘        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Description |
|-----------|-------------|
| adclient | Main agent daemon |
| adinfo | System information tool |
| adjoin | Domain join utility |
| adleave | Domain leave utility |
| adquery | User/group query tool |
| dzinfo | Zone information tool |
| dzdo | Privilege elevation (like sudo) |

---

## Prerequisites

### System Requirements

- **Supported Operating Systems:**
  - Ubuntu 18.04, 20.04, 22.04 LTS
  - Debian 10, 11
  - RHEL/CentOS 7, 8, 9
  - Rocky Linux 8, 9
  - SUSE Linux Enterprise 12, 15
  - Amazon Linux 2

- **Hardware:**
  - 512 MB RAM minimum
  - 250 MB disk space

- **Network:**
  - DNS resolution to AD domain controllers
  - Network access to ports 53, 88, 389, 464, 636

### Licensing

Centrify/Delinea requires a commercial license. To obtain:

1. Visit: https://www.delinea.com/products/server-suite
2. Request a trial or contact sales
3. Download the software package from the support portal

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
# Should return FQDN like: linux-centrify.lab.local
```

---

## Installation

### Download Centrify Packages

1. Log into the Delinea Support Portal
2. Download the Centrify Infrastructure Services package
3. Extract the archive

```bash
# Example extraction
mkdir -p /tmp/centrify-install
cd /tmp/centrify-install
tar xzf centrify-infrastructure-services-*.tgz
cd centrify-infrastructure-services-*
```

### Install on Ubuntu/Debian

```bash
# Install the main package
sudo dpkg -i CentrifyDC-*.deb

# Install OpenSSH integration (optional)
sudo dpkg -i CentrifyDC-openssh-*.deb

# Fix any dependency issues
sudo apt-get install -f
```

### Install on RHEL/CentOS

```bash
# Install the main package
sudo yum localinstall -y CentrifyDC-*.rpm

# Install OpenSSH integration (optional)
sudo yum localinstall -y CentrifyDC-openssh-*.rpm
```

### Verify Installation

```bash
# Check installed packages
rpm -qa | grep -i centrify  # RHEL
dpkg -l | grep -i centrify  # Debian

# Check agent status
adinfo --version
```

---

## Domain Join

### Basic Domain Join

```bash
# Join domain
sudo adjoin lab.local

# Enter administrator credentials when prompted
```

### Domain Join with Options

```bash
# Join to specific zone
sudo adjoin --zone "Unix Servers" lab.local

# Join to specific OU
sudo adjoin --container "OU=Linux Servers,DC=lab,DC=local" lab.local

# Join with username specified
sudo adjoin -u Administrator lab.local

# Join with password (not recommended)
sudo adjoin -u Administrator -p "P@ssw0rd123!" lab.local

# Force rejoin
sudo adjoin --force lab.local
```

### Join to Auto Zone

Auto Zone allows joining without pre-creating zones:

```bash
# Join to Auto Zone (creates computer account automatically)
sudo adjoin --zone "Auto Zone" lab.local
```

### Verify Domain Join

```bash
# Check domain status
adinfo

# Detailed status
adinfo -A

# Test user lookup
adquery user testuser1
id testuser1
```

---

## Configuration

### Main Configuration File

The main configuration file is `/etc/centrifydc/centrifydc.conf`:

```bash
# View current configuration
cat /etc/centrifydc/centrifydc.conf

# Key settings
adclient.cache.cleanup.interval: 86400
adclient.dns.cachingserver: false
pam.allow.groups: linux-admins linux-users
pam.deny.groups:
```

### Common Configuration Options

```bash
# Edit configuration
sudo vi /etc/centrifydc/centrifydc.conf

# Important settings:

# Allow specific groups to login
pam.allow.groups: linux-admins linux-users

# Set default shell
nss.shell: /bin/bash

# Set home directory location
nss.home: /home/%{user}

# Enable offline authentication
adclient.krb5.cache.type: FILE

# Cache timeout
adclient.cache.cleanup.interval: 86400
```

### Apply Configuration Changes

```bash
# Restart Centrify agent
sudo systemctl restart centrifydc

# Or flush and restart
sudo adflush
sudo systemctl restart centrifydc
```

---

## Zone Management

### Understanding Zones

Zones allow you to:
- Organize computers into logical groups
- Define which users can access which systems
- Set role-based access control
- Manage privilege elevation

### View Zone Information

```bash
# Show current zone
dzinfo

# Show zone details
dzinfo --verbose
```

### Zone Types

1. **Classic Zones**: Traditional AD-based zones with schema extension
2. **Hierarchical Zones**: Inherit permissions from parent zones
3. **Auto Zone**: Automatic zone for quick deployments

### Zone Commands

```bash
# List available zones (requires AD admin tools)
# Typically done from Windows or using LDAP queries

# Change zone (requires rejoin)
sudo adleave
sudo adjoin --zone "New Zone" lab.local
```

---

## User and Group Management

### Query Users

```bash
# Query specific user
adquery user testuser1
adquery user administrator@lab.local

# Query all users
adquery user -A

# Query user with specific attributes
adquery user --uid testuser1
```

### Query Groups

```bash
# Query specific group
adquery group linux-admins
adquery group "Domain Users"

# Query all groups
adquery group -A

# Query group members
adquery group --members linux-admins
```

### Standard Commands

```bash
# These work after domain join
id testuser1
groups testuser1
getent passwd testuser1
getent group linux-admins
```

### User Mapping

Centrify maps AD users to Unix UIDs:

```bash
# View user's Unix profile
adquery user --unix testuser1

# The mapping is stored in AD or computed via algorithmic mapping
```

---

## Access Control

### PAM Configuration

Centrify automatically configures PAM. Key settings in `/etc/centrifydc/centrifydc.conf`:

```ini
# Allow only specific groups
pam.allow.groups: linux-admins linux-users sudo-users

# Deny specific groups
pam.deny.groups: denied-group

# Allow specific users
pam.allow.users: admin1 admin2

# Deny specific users
pam.deny.users: baduser
```

### SSH Access Control

```bash
# /etc/centrifydc/centrifydc.conf
# Only allow these groups to SSH
sshd.allow.groups: linux-admins linux-users

# Or configure in sshd_config
# AllowGroups linux-admins linux-users
```

### Centrify-Specific Access Control

```bash
# Using Access Manager (Delinea Console)
# - Define computer roles
# - Assign users to roles
# - Roles determine access rights

# Command-line role viewing
dzinfo --roles
```

---

## Privilege Elevation

### dzdo (Centrify's sudo replacement)

Centrify provides `dzdo` for privilege elevation with AD-based control:

```bash
# Run command as root
dzdo whoami

# Run command as specific user
dzdo -u postgres psql
```

### Configure dzdo Rights

Rights are configured in AD using Delinea Access Manager or via command line:

```bash
# View current rights
dzinfo --rights

# Rights are defined in AD and applied to zones
```

### Traditional sudo Integration

You can also use traditional sudo with AD groups:

```bash
# /etc/sudoers.d/ad-admins
%linux-admins    ALL=(ALL)    ALL
%sudo-users      ALL=(ALL)    ALL
linuxadmin       ALL=(ALL)    NOPASSWD: ALL
```

---

## Maintenance

### Cache Management

```bash
# Flush all caches
sudo adflush

# Flush user cache
sudo adflush -u testuser1

# Flush group cache
sudo adflush -g linux-admins

# View cache statistics
adinfo --cinfo
```

### Service Management

```bash
# Check status
systemctl status centrifydc

# Restart service
sudo systemctl restart centrifydc

# Stop service
sudo systemctl stop centrifydc

# Enable on boot
sudo systemctl enable centrifydc
```

### Log Management

```bash
# View logs
tail -f /var/centrifydc/log/centrifydc.log

# Enable debug logging
sudo dacontrol -e auth -e user -e group

# Disable debug logging
sudo dacontrol -d auth -d user -d group

# View debug log
tail -f /var/centrifydc/log/centrifydc.log
```

### Health Check

```bash
# Full diagnostic
adinfo -A

# Test authentication
adinfo --test

# Check connectivity
adinfo --diag
```

---

## Alternative: SSSD Setup

If Centrify is not available, you can use SSSD with realmd as an alternative:

### Install SSSD

```bash
# Ubuntu/Debian
sudo apt-get install sssd sssd-ad sssd-tools realmd adcli krb5-user

# RHEL/CentOS
sudo yum install sssd sssd-ad sssd-tools realmd adcli krb5-workstation
```

### Join Domain with realmd

```bash
# Discover domain
realm discover lab.local

# Join domain
sudo realm join -U Administrator lab.local

# Verify
realm list
```

### Configure SSSD

```bash
# /etc/sssd/sssd.conf
[sssd]
services = nss, pam, ssh, sudo
config_file_version = 2
domains = lab.local

[domain/lab.local]
ad_domain = lab.local
krb5_realm = LAB.LOCAL
realmd_tags = manages-system joined-with-adcli
cache_credentials = True
id_provider = ad
access_provider = ad
auth_provider = ad
chpass_provider = ad
use_fully_qualified_names = False
fallback_homedir = /home/%u
default_shell = /bin/bash
ldap_id_mapping = True
```

### Start SSSD

```bash
sudo chmod 600 /etc/sssd/sssd.conf
sudo systemctl enable sssd
sudo systemctl start sssd
```

---

## Uninstallation

### Leave Domain

```bash
# Leave domain (removes computer account from AD)
sudo adleave

# Leave without removing AD computer object
sudo adleave --remove local
```

### Uninstall Centrify

```bash
# RHEL/CentOS
sudo yum remove CentrifyDC CentrifyDC-openssh

# Ubuntu/Debian
sudo apt-get remove --purge centrifydc centrifydc-openssh
```

### Clean Up

```bash
# Remove configuration
sudo rm -rf /etc/centrifydc
sudo rm -rf /var/centrifydc

# Restore original PAM and NSS
sudo pam-auth-update --remove centrify
```

---

## Quick Reference

### Common Commands

| Command | Description |
|---------|-------------|
| `adinfo` | Check domain status |
| `adjoin` | Join domain |
| `adleave` | Leave domain |
| `adquery user` | Query AD user |
| `adquery group` | Query AD group |
| `adflush` | Clear caches |
| `dzinfo` | Zone information |
| `dzdo` | Privilege elevation |
| `dacontrol` | Debug control |

### Important Files

| File | Description |
|------|-------------|
| `/etc/centrifydc/centrifydc.conf` | Main configuration |
| `/var/centrifydc/log/centrifydc.log` | Agent log |
| `/etc/krb5.conf` | Kerberos configuration |
| `/etc/nsswitch.conf` | NSS configuration |
| `/etc/pam.d/` | PAM configuration |

### Useful Options

```bash
# adinfo options
adinfo                 # Basic status
adinfo -A             # All information
adinfo --diag         # Diagnostics
adinfo --version      # Version info

# adjoin options
adjoin --zone ZONE    # Join to specific zone
adjoin --container OU # Join to specific OU
adjoin -u USER        # Specify username
adjoin -p PASS        # Specify password (insecure)
adjoin --force        # Force rejoin

# adquery options
adquery user -A       # All users
adquery group -A      # All groups
adquery user --unix   # Unix attributes
```
