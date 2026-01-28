# Troubleshooting Guide

This guide covers common issues encountered when joining Linux systems to Active Directory using BeyondTrust AD Bridge or Centrify.

## Table of Contents

1. [DNS Issues](#dns-issues)
2. [Time Synchronization](#time-synchronization)
3. [Kerberos Problems](#kerberos-problems)
4. [Domain Join Failures](#domain-join-failures)
5. [Authentication Issues](#authentication-issues)
6. [BeyondTrust AD Bridge Specific](#beyondtrust-ad-bridge-specific)
7. [Centrify Specific](#centrify-specific)
8. [SSSD Issues](#sssd-issues)

---

## DNS Issues

### Symptom: Cannot resolve domain controller hostname

```bash
# Test DNS resolution
nslookup dc1.lab.local
host dc1.lab.local
dig dc1.lab.local
```

**Solutions:**

1. **Check /etc/resolv.conf:**
   ```bash
   cat /etc/resolv.conf
   # Should contain:
   # search lab.local
   # nameserver 10.0.0.10
   ```

2. **For systemd-resolved systems:**
   ```bash
   # Check current DNS settings
   resolvectl status

   # Configure DNS
   sudo mkdir -p /etc/systemd/resolved.conf.d
   cat <<EOF | sudo tee /etc/systemd/resolved.conf.d/ad-dns.conf
   [Resolve]
   DNS=10.0.0.10
   Domains=lab.local
   EOF

   sudo systemctl restart systemd-resolved
   ```

3. **Verify SRV records:**
   ```bash
   host -t SRV _ldap._tcp.lab.local
   host -t SRV _kerberos._tcp.lab.local
   ```

### Symptom: DNS resolution intermittent

**Solutions:**

1. **Add entries to /etc/hosts:**
   ```bash
   echo "10.0.0.10    dc1.lab.local dc1" | sudo tee -a /etc/hosts
   ```

2. **Check for NetworkManager overwriting resolv.conf:**
   ```bash
   # Prevent NetworkManager from managing DNS
   sudo sed -i '/\[main\]/a dns=none' /etc/NetworkManager/NetworkManager.conf
   sudo systemctl restart NetworkManager
   ```

---

## Time Synchronization

### Symptom: Kerberos errors about clock skew

Kerberos requires time to be synchronized within 5 minutes between client and server.

**Solutions:**

1. **Check current time difference:**
   ```bash
   # Local time
   date

   # Compare with DC (if accessible)
   ssh dc1.lab.local date
   ```

2. **Sync time immediately:**
   ```bash
   sudo ntpdate -u dc1.lab.local
   # or
   sudo chronyd -q 'server dc1.lab.local iburst'
   ```

3. **Enable persistent NTP:**
   ```bash
   # Using chronyd
   sudo systemctl enable chronyd
   sudo systemctl start chronyd

   # Using systemd-timesyncd
   sudo timedatectl set-ntp true
   ```

4. **Configure NTP server:**
   ```bash
   # /etc/chrony.conf or /etc/ntp.conf
   server dc1.lab.local iburst prefer
   ```

---

## Kerberos Problems

### Symptom: kinit fails with "Cannot contact any KDC"

**Solutions:**

1. **Verify /etc/krb5.conf:**
   ```ini
   [libdefaults]
       default_realm = LAB.LOCAL
       dns_lookup_kdc = true

   [realms]
       LAB.LOCAL = {
           kdc = dc1.lab.local
           admin_server = dc1.lab.local
       }

   [domain_realm]
       .lab.local = LAB.LOCAL
       lab.local = LAB.LOCAL
   ```

2. **Test Kerberos ports:**
   ```bash
   nc -zv dc1.lab.local 88
   nc -zv dc1.lab.local 464
   ```

3. **Check firewall:**
   ```bash
   sudo firewall-cmd --list-all
   # Ensure ports 88, 464, 389, 636 are allowed
   ```

### Symptom: kinit fails with "Preauthentication failed"

**Solutions:**

1. **Verify username format:**
   ```bash
   # Use uppercase realm
   kinit Administrator@LAB.LOCAL

   # Or with domain prefix
   kinit LAB\\Administrator
   ```

2. **Check password:**
   ```bash
   # Ensure special characters are properly escaped
   kinit Administrator@LAB.LOCAL <<< 'P@ssw0rd123!'
   ```

3. **Verify account status in AD:**
   - Check if account is locked
   - Check if account is disabled
   - Check if password has expired

### Symptom: "Clock skew too great" error

See [Time Synchronization](#time-synchronization) section above.

---

## Domain Join Failures

### Symptom: "Failed to join domain" error

**General troubleshooting steps:**

1. **Pre-join checklist:**
   ```bash
   # DNS resolution
   host dc1.lab.local

   # Network connectivity
   ping dc1.lab.local

   # LDAP connectivity
   nc -zv dc1.lab.local 389

   # Time sync
   ntpdate -q dc1.lab.local
   ```

2. **Check credentials:**
   ```bash
   # Verify credentials work
   kinit Administrator@LAB.LOCAL
   klist
   ```

3. **Check permissions:**
   - Ensure the user has permission to join computers to the domain
   - Check OU permissions if specifying a target OU

### Symptom: "Computer account already exists"

**Solutions:**

1. **Remove existing computer account:**
   ```bash
   # Using PBIS
   /opt/pbis/bin/domainjoin-cli leave

   # Using Centrify
   adleave

   # Using realmd
   realm leave
   ```

2. **Delete from AD:**
   ```powershell
   # On AD DC (PowerShell)
   Remove-ADComputer -Identity "linux-bt"
   ```

3. **Force rejoin:**
   ```bash
   # PBIS
   /opt/pbis/bin/domainjoin-cli join --force lab.local Administrator

   # Centrify
   adjoin --force lab.local -u Administrator
   ```

---

## Authentication Issues

### Symptom: Cannot login with AD user

**Solutions:**

1. **Verify user exists:**
   ```bash
   id testuser1
   id testuser1@lab.local
   getent passwd testuser1
   ```

2. **Check NSS configuration:**
   ```bash
   # /etc/nsswitch.conf should include:
   passwd: files sss  # for SSSD
   passwd: files lsass  # for PBIS
   group:  files sss
   group:  files lsass
   ```

3. **Check PAM configuration:**
   ```bash
   # Look for AD-related PAM modules
   grep -r "pam_sss\|pam_lsass\|pam_centrify" /etc/pam.d/
   ```

4. **Test authentication:**
   ```bash
   # Using su
   su - testuser1

   # Using SSH
   ssh testuser1@localhost
   ```

### Symptom: Home directory not created

**Solutions:**

1. **Enable pam_mkhomedir:**
   ```bash
   # Ubuntu/Debian
   sudo pam-auth-update --enable mkhomedir

   # RHEL/CentOS
   sudo authconfig --enablemkhomedir --update
   ```

2. **Manual PAM configuration:**
   ```bash
   # Add to /etc/pam.d/common-session (Debian) or /etc/pam.d/system-auth (RHEL)
   session required pam_mkhomedir.so skel=/etc/skel/ umask=0077
   ```

3. **Check home directory template:**
   ```bash
   # PBIS
   /opt/pbis/bin/config HomeDirTemplate

   # SSSD - check /etc/sssd/sssd.conf
   grep fallback_homedir /etc/sssd/sssd.conf
   ```

### Symptom: Groups not working

**Solutions:**

1. **Verify group membership:**
   ```bash
   id testuser1
   groups testuser1
   ```

2. **Check group lookup:**
   ```bash
   getent group linux-admins
   getent group "Domain Users"
   ```

3. **Clear caches:**
   ```bash
   # SSSD
   sudo sss_cache -E

   # PBIS
   /opt/pbis/bin/ad-cache --delete-all

   # Centrify
   adflush
   ```

---

## BeyondTrust AD Bridge Specific

### Service management

```bash
# List services
/opt/pbis/bin/lwsm list

# Restart LSASS
/opt/pbis/bin/lwsm restart lsass

# Check service status
/opt/pbis/bin/lwsm status lsass
```

### Enable debug logging

```bash
# Set debug level
/opt/pbis/bin/lwsm set-log-level lsass debug

# View logs
tail -f /var/log/lsass.log
```

### Common PBIS commands

```bash
# Query domain status
/opt/pbis/bin/domainjoin-cli query

# Find user
/opt/pbis/bin/find-user-by-name testuser1

# Find group
/opt/pbis/bin/find-group-by-name linux-admins

# Enumerate users
/opt/pbis/bin/enum-users

# View configuration
/opt/pbis/bin/config --dump
```

### Reset PBIS

```bash
# Leave domain
sudo /opt/pbis/bin/domainjoin-cli leave

# Clear cache
sudo /opt/pbis/bin/ad-cache --delete-all

# Restart services
sudo /opt/pbis/bin/lwsm restart

# Rejoin
sudo /opt/pbis/bin/domainjoin-cli join lab.local Administrator
```

---

## Centrify Specific

### Service management

```bash
# Check status
adinfo

# Restart Centrify
sudo systemctl restart centrifydc

# Check agent status
adinfo -A
```

### Enable debug logging

```bash
# Enable debug
sudo dacontrol -e auth -e user -e group

# View logs
tail -f /var/centrifydc/log/centrifydc.log
```

### Common Centrify commands

```bash
# Query user
adquery user testuser1

# Query group
adquery group linux-admins

# Check zone
dzinfo

# Flush cache
adflush

# Leave domain
adleave
```

### Reset Centrify

```bash
# Leave domain
sudo adleave --force

# Remove all Centrify data
sudo rm -rf /var/centrifydc

# Reinstall and rejoin
sudo yum reinstall CentrifyDC
sudo adjoin lab.local -u Administrator
```

---

## SSSD Issues

### Service management

```bash
# Check status
systemctl status sssd

# Restart
sudo systemctl restart sssd

# View logs
sudo journalctl -u sssd -f
```

### Enable debug logging

```bash
# Edit /etc/sssd/sssd.conf
[domain/lab.local]
debug_level = 9

# Restart SSSD
sudo systemctl restart sssd

# View debug logs
tail -f /var/log/sssd/sssd_lab.local.log
```

### Common SSSD commands

```bash
# Check domain status
sssctl domain-status lab.local

# Clear cache
sudo sss_cache -E

# User lookup debugging
sssctl user-checks testuser1

# Config check
sssctl config-check
```

### Reset SSSD

```bash
# Stop SSSD
sudo systemctl stop sssd

# Clear cache
sudo rm -rf /var/lib/sss/db/*
sudo rm -rf /var/lib/sss/mc/*

# Start SSSD
sudo systemctl start sssd
```

---

## Useful Diagnostic Commands

### Network diagnostics

```bash
# Check all network connectivity
ping dc1.lab.local
nc -zv dc1.lab.local 88    # Kerberos
nc -zv dc1.lab.local 389   # LDAP
nc -zv dc1.lab.local 636   # LDAPS
nc -zv dc1.lab.local 464   # Kerberos password change
nc -zv dc1.lab.local 53    # DNS
```

### LDAP diagnostics

```bash
# Test LDAP search
ldapsearch -x -H ldap://dc1.lab.local -b "dc=lab,dc=local" "(objectClass=user)" cn

# With authentication
ldapsearch -x -H ldap://dc1.lab.local -D "Administrator@lab.local" -W -b "dc=lab,dc=local" "(cn=testuser1)"
```

### System diagnostics

```bash
# Check hostname
hostname -f
hostname -d

# Check NSS
getent passwd | grep -E "testuser|Administrator"
getent group | grep linux-admins

# Check PAM
pamtester login testuser1 authenticate

# View all AD-related logs
sudo journalctl -u sssd -u sshd | tail -100
```

---

## Getting Help

If you're still having issues:

1. **Gather diagnostic information:**
   ```bash
   ./verify-ad-join.sh > diagnostic-output.txt 2>&1
   ```

2. **Collect logs:**
   ```bash
   # SSSD logs
   sudo tar czf sssd-logs.tar.gz /var/log/sssd/

   # PBIS logs
   sudo tar czf pbis-logs.tar.gz /var/log/lsass.log /var/log/pbis-open-install.log

   # Centrify logs
   sudo tar czf centrify-logs.tar.gz /var/centrifydc/log/
   ```

3. **Check vendor documentation:**
   - [BeyondTrust AD Bridge Docs](https://www.beyondtrust.com/docs/ad-bridge/)
   - [Delinea/Centrify Docs](https://docs.delinea.com/)
   - [SSSD Documentation](https://sssd.io/docs/)
