# Linux Active Directory Join Setup

This project provides automation scripts and documentation for setting up two Linux VMs and joining them to an Active Directory domain using two different enterprise products:

1. **VM1**: Joined using **BeyondTrust AD Bridge** (formerly PowerBroker Identity Services)
2. **VM2**: Joined using **Centrify** (now Delinea)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    AD Simulation Environment                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐                                           │
│  │   AD Domain      │                                           │
│  │   Controller     │                                           │
│  │  (Samba AD DC)   │                                           │
│  │                  │                                           │
│  │  Domain:         │                                           │
│  │  lab.local       │                                           │
│  │  IP: 10.0.0.10   │                                           │
│  └────────┬─────────┘                                           │
│           │                                                      │
│           │  LDAP/Kerberos                                      │
│           │                                                      │
│     ┌─────┴─────┐                                               │
│     │           │                                               │
│  ┌──▼───────────▼──┐    ┌──────────────────┐                   │
│  │   Linux VM 1    │    │   Linux VM 2     │                   │
│  │                 │    │                  │                   │
│  │  BeyondTrust    │    │    Centrify      │                   │
│  │   AD Bridge     │    │                  │                   │
│  │                 │    │                  │                   │
│  │  IP: 10.0.0.11  │    │  IP: 10.0.0.12   │                   │
│  └─────────────────┘    └──────────────────┘                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Hardware/Infrastructure Requirements
- Hypervisor: VirtualBox, VMware Workstation/ESXi, KVM, or Hyper-V
- Minimum 8GB RAM for host machine
- 60GB free disk space
- Network connectivity between VMs

### Software Requirements
- Linux distributions supported:
  - Ubuntu 20.04/22.04 LTS (recommended)
  - RHEL/CentOS 7/8/9
  - Debian 10/11
- For AD simulation: Samba 4.x
- Internet access for package downloads

### License Requirements
- **BeyondTrust AD Bridge**: Enterprise license required (trial available)
- **Centrify**: Delinea Platform license required (trial available)

## Quick Start

### 1. Set Up AD Domain Controller (Samba AD DC)

```bash
# Run the AD DC setup script
cd scripts
chmod +x setup-samba-ad-dc.sh
sudo ./setup-samba-ad-dc.sh
```

### 2. Provision Linux VMs

```bash
# Using the VM provisioning script (VirtualBox example)
chmod +x provision-vms.sh
./provision-vms.sh
```

### 3. Join VM1 with BeyondTrust AD Bridge

```bash
# On VM1 (10.0.0.11)
chmod +x setup-beyondtrust-adbridge.sh
sudo ./setup-beyondtrust-adbridge.sh
```

### 4. Join VM2 with Centrify

```bash
# On VM2 (10.0.0.12)
chmod +x setup-centrify.sh
sudo ./setup-centrify.sh
```

## Directory Structure

```
ad-join-setup/
├── README.md                          # This file
├── docs/
│   ├── beyondtrust-detailed-guide.md  # Detailed BeyondTrust setup guide
│   ├── centrify-detailed-guide.md     # Detailed Centrify setup guide
│   └── troubleshooting.md             # Common issues and solutions
├── scripts/
│   ├── setup-samba-ad-dc.sh           # Samba AD DC installation
│   ├── provision-vms.sh               # VM provisioning automation
│   ├── setup-beyondtrust-adbridge.sh  # BeyondTrust AD Bridge setup
│   ├── setup-centrify.sh              # Centrify setup
│   └── verify-ad-join.sh              # Verification script
└── config/
    ├── smb.conf.template              # Samba configuration template
    ├── krb5.conf.template             # Kerberos configuration template
    └── network-config.env             # Network configuration variables
```

## Network Configuration

Default network settings (can be modified in `config/network-config.env`):

| Component | IP Address | Hostname | Role |
|-----------|------------|----------|------|
| AD DC | 10.0.0.10 | dc1.lab.local | Domain Controller |
| VM1 | 10.0.0.11 | linux-bt.lab.local | BeyondTrust AD Bridge |
| VM2 | 10.0.0.12 | linux-centrify.lab.local | Centrify |

## Domain Configuration

| Setting | Value |
|---------|-------|
| Domain Name | lab.local |
| NetBIOS Name | LAB |
| Domain Admin | Administrator |
| Default Password | P@ssw0rd123! |

**Note**: Change default passwords in production environments!

## Verification

After completing the AD join, verify the setup:

```bash
# Run verification script
chmod +x scripts/verify-ad-join.sh
./scripts/verify-ad-join.sh
```

### Manual Verification Commands

```bash
# Check domain membership
realm list

# Test Kerberos authentication
kinit administrator@LAB.LOCAL

# List domain users
id administrator@lab.local

# Test SSH with AD credentials
ssh administrator@lab.local@localhost
```

## Comparison: BeyondTrust AD Bridge vs Centrify

| Feature | BeyondTrust AD Bridge | Centrify |
|---------|----------------------|----------|
| AD Integration | Full AD schema extension | Agentless + Agent options |
| GPO Support | Yes | Yes |
| MFA Support | Via integration | Native |
| Privileged Access | Separate product (PBPM) | Integrated |
| Supported Platforms | 100+ Unix/Linux | 100+ Unix/Linux |
| Management Console | Enterprise Console | Cloud-based Portal |
| Offline Authentication | Yes | Yes |
| License Model | Per-endpoint | Per-endpoint or user |

## Security Considerations

1. **Change Default Passwords**: Never use default passwords in production
2. **Use Strong Passwords**: Enforce complexity requirements
3. **Enable Encryption**: Use LDAPS and Kerberos encryption
4. **Audit Logging**: Enable comprehensive logging
5. **Network Segmentation**: Isolate AD infrastructure
6. **Regular Updates**: Keep all components patched

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for common issues and solutions.

### Quick Fixes

```bash
# DNS resolution issues
nslookup dc1.lab.local
systemctl restart systemd-resolved

# Time sync issues (critical for Kerberos)
timedatectl set-ntp true
ntpdate -u dc1.lab.local

# Kerberos ticket issues
kdestroy
kinit administrator@LAB.LOCAL
```

## References

- [BeyondTrust AD Bridge Documentation](https://www.beyondtrust.com/docs/ad-bridge/)
- [Centrify/Delinea Documentation](https://docs.delinea.com/)
- [Samba AD DC Wiki](https://wiki.samba.org/index.php/Setting_up_Samba_as_an_Active_Directory_Domain_Controller)
- [Microsoft AD Documentation](https://docs.microsoft.com/en-us/windows-server/identity/ad-ds/)

## License

This project is provided for educational and testing purposes.
