#!/bin/bash
#
# VM Provisioning Script
# Creates two Linux VMs for AD join testing using VirtualBox
#
# Usage: ./provision-vms.sh [--hypervisor vbox|vmware|kvm]
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

# Default hypervisor
HYPERVISOR="vbox"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --hypervisor)
            HYPERVISOR="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--hypervisor vbox|vmware|kvm]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

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

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."

    case $HYPERVISOR in
        vbox)
            if ! command -v VBoxManage &> /dev/null; then
                print_error "VirtualBox not found. Please install VirtualBox first."
                exit 1
            fi
            print_status "VirtualBox found: $(VBoxManage --version)"
            ;;
        vmware)
            if ! command -v vmrun &> /dev/null && ! command -v vmware &> /dev/null; then
                print_error "VMware not found. Please install VMware Workstation/Fusion first."
                exit 1
            fi
            print_status "VMware found"
            ;;
        kvm)
            if ! command -v virsh &> /dev/null; then
                print_error "KVM/libvirt not found. Please install libvirt and qemu-kvm first."
                exit 1
            fi
            print_status "KVM/libvirt found"
            ;;
        *)
            print_error "Unsupported hypervisor: $HYPERVISOR"
            exit 1
            ;;
    esac
}

# Download Ubuntu ISO if not present
download_iso() {
    ISO_DIR="$HOME/VMs/ISOs"
    ISO_FILE="$ISO_DIR/ubuntu-22.04-server.iso"

    mkdir -p "$ISO_DIR"

    if [[ ! -f "$ISO_FILE" ]]; then
        print_status "Downloading Ubuntu 22.04 Server ISO..."
        print_warning "This may take a while depending on your internet connection"

        curl -L -o "$ISO_FILE" "$OS_ISO_URL" || {
            print_error "Failed to download ISO"
            exit 1
        }
    else
        print_status "Ubuntu ISO already exists at $ISO_FILE"
    fi

    echo "$ISO_FILE"
}

# Create VirtualBox VM
create_vbox_vm() {
    local VM_NAME="$1"
    local VM_IP="$2"
    local VM_HOSTNAME="$3"

    print_status "Creating VirtualBox VM: $VM_NAME"

    VM_DIR="$HOME/VMs/$VM_NAME"
    mkdir -p "$VM_DIR"

    # Check if VM exists
    if VBoxManage list vms | grep -q "\"$VM_NAME\""; then
        print_warning "VM $VM_NAME already exists. Skipping creation."
        return
    fi

    # Create VM
    VBoxManage createvm --name "$VM_NAME" --ostype Ubuntu_64 --register --basefolder "$HOME/VMs"

    # Configure VM
    VBoxManage modifyvm "$VM_NAME" \
        --memory ${VM_MEMORY_MB} \
        --cpus ${VM_CPUS} \
        --nic1 nat \
        --nic2 intnet \
        --intnet2 "adlab" \
        --boot1 dvd \
        --boot2 disk \
        --vram 16 \
        --graphicscontroller vmsvga

    # Create virtual disk
    VBoxManage createhd --filename "$VM_DIR/$VM_NAME.vdi" --size $((VM_DISK_GB * 1024)) --variant Standard

    # Add storage controllers
    VBoxManage storagectl "$VM_NAME" --name "SATA Controller" --add sata --controller IntelAhci
    VBoxManage storagectl "$VM_NAME" --name "IDE Controller" --add ide

    # Attach disk
    VBoxManage storageattach "$VM_NAME" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$VM_DIR/$VM_NAME.vdi"

    # Attach ISO
    ISO_FILE=$(download_iso)
    VBoxManage storageattach "$VM_NAME" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium "$ISO_FILE"

    print_status "VM $VM_NAME created successfully"
    print_info "VM Location: $VM_DIR"
}

# Create KVM/libvirt VM
create_kvm_vm() {
    local VM_NAME="$1"
    local VM_IP="$2"
    local VM_HOSTNAME="$3"

    print_status "Creating KVM VM: $VM_NAME"

    VM_DIR="/var/lib/libvirt/images"
    ISO_FILE=$(download_iso)

    # Check if VM exists
    if virsh list --all | grep -q "$VM_NAME"; then
        print_warning "VM $VM_NAME already exists. Skipping creation."
        return
    fi

    # Create disk image
    qemu-img create -f qcow2 "$VM_DIR/$VM_NAME.qcow2" ${VM_DISK_GB}G

    # Create VM
    virt-install \
        --name "$VM_NAME" \
        --memory ${VM_MEMORY_MB} \
        --vcpus ${VM_CPUS} \
        --disk path="$VM_DIR/$VM_NAME.qcow2",format=qcow2 \
        --cdrom "$ISO_FILE" \
        --os-variant ubuntu22.04 \
        --network network=default \
        --network network=adlab \
        --graphics vnc \
        --noautoconsole

    print_status "VM $VM_NAME created successfully"
}

# Create network for internal communication
create_internal_network() {
    print_status "Creating internal network for AD lab..."

    case $HYPERVISOR in
        vbox)
            # VirtualBox uses intnet automatically
            print_status "VirtualBox internal network 'adlab' will be created automatically"
            ;;
        kvm)
            # Check if network exists
            if ! virsh net-list --all | grep -q "adlab"; then
                cat > /tmp/adlab-network.xml << EOF
<network>
  <name>adlab</name>
  <bridge name="virbr-adlab"/>
  <forward mode="nat"/>
  <ip address="10.0.0.1" netmask="255.255.255.0">
    <dhcp>
      <range start="10.0.0.100" end="10.0.0.200"/>
      <host mac="52:54:00:ad:00:10" ip="${DC_IP}"/>
      <host mac="52:54:00:ad:00:11" ip="${VM1_IP}"/>
      <host mac="52:54:00:ad:00:12" ip="${VM2_IP}"/>
    </dhcp>
  </ip>
</network>
EOF
                virsh net-define /tmp/adlab-network.xml
                virsh net-start adlab
                virsh net-autostart adlab
                rm /tmp/adlab-network.xml
            fi
            print_status "KVM network 'adlab' configured"
            ;;
    esac
}

# Generate cloud-init configuration
generate_cloud_init() {
    local HOSTNAME="$1"
    local IP="$2"

    print_status "Generating cloud-init configuration for $HOSTNAME..."

    CLOUD_INIT_DIR="$SCRIPT_DIR/../config/cloud-init"
    mkdir -p "$CLOUD_INIT_DIR"

    # User-data
    cat > "$CLOUD_INIT_DIR/$HOSTNAME-user-data.yaml" << EOF
#cloud-config
hostname: ${HOSTNAME}
fqdn: ${HOSTNAME}.${DOMAIN_NAME}
manage_etc_hosts: true

users:
  - name: labadmin
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    passwd: \$6\$rounds=4096\$xyz\$hashed_password_here

package_update: true
package_upgrade: true

packages:
  - openssh-server
  - curl
  - wget
  - vim
  - net-tools
  - dnsutils
  - krb5-user
  - ntp

write_files:
  - path: /etc/netplan/01-netcfg.yaml
    content: |
      network:
        version: 2
        ethernets:
          eth0:
            dhcp4: no
            addresses:
              - ${IP}/24
            gateway4: ${NETWORK_GATEWAY}
            nameservers:
              addresses:
                - ${DC_IP}
                - ${NETWORK_DNS_SECONDARY}
              search:
                - ${DOMAIN_NAME}

runcmd:
  - netplan apply
  - systemctl restart systemd-resolved
EOF

    # Network-config
    cat > "$CLOUD_INIT_DIR/$HOSTNAME-network-config.yaml" << EOF
version: 2
ethernets:
  eth0:
    dhcp4: false
    addresses:
      - ${IP}/24
    gateway4: ${NETWORK_GATEWAY}
    nameservers:
      addresses:
        - ${DC_IP}
        - ${NETWORK_DNS_SECONDARY}
      search:
        - ${DOMAIN_NAME}
EOF

    print_status "Cloud-init configuration saved to $CLOUD_INIT_DIR"
}

# Print post-setup instructions
print_instructions() {
    echo ""
    echo "=========================================="
    echo "       VM Provisioning Complete          "
    echo "=========================================="
    echo ""
    echo "VMs Created:"
    echo "  1. AD-DC        (${DC_IP})     - Samba AD Domain Controller"
    echo "  2. ${VM1_HOSTNAME}   (${VM1_IP})    - BeyondTrust AD Bridge"
    echo "  3. ${VM2_HOSTNAME}   (${VM2_IP})    - Centrify"
    echo ""
    echo "Network Configuration:"
    echo "  Subnet:     ${NETWORK_SUBNET}"
    echo "  Gateway:    ${NETWORK_GATEWAY}"
    echo "  DNS:        ${DC_IP}"
    echo ""
    echo "Next Steps:"
    echo ""
    echo "1. Start the VMs and complete OS installation:"
    case $HYPERVISOR in
        vbox)
            echo "   VBoxManage startvm 'AD-DC' --type gui"
            echo "   VBoxManage startvm '${VM1_HOSTNAME}' --type gui"
            echo "   VBoxManage startvm '${VM2_HOSTNAME}' --type gui"
            ;;
        kvm)
            echo "   virsh start AD-DC"
            echo "   virsh start ${VM1_HOSTNAME}"
            echo "   virsh start ${VM2_HOSTNAME}"
            echo "   Use virt-manager or 'virsh console' to access"
            ;;
    esac
    echo ""
    echo "2. After OS installation, configure static IPs:"
    echo "   - AD-DC:        ${DC_IP}"
    echo "   - ${VM1_HOSTNAME}:   ${VM1_IP}"
    echo "   - ${VM2_HOSTNAME}:   ${VM2_IP}"
    echo ""
    echo "3. On AD-DC, run:"
    echo "   sudo ./setup-samba-ad-dc.sh"
    echo ""
    echo "4. On ${VM1_HOSTNAME}, run:"
    echo "   sudo ./setup-beyondtrust-adbridge.sh"
    echo ""
    echo "5. On ${VM2_HOSTNAME}, run:"
    echo "   sudo ./setup-centrify.sh"
    echo ""
    echo "Cloud-init configurations have been generated in:"
    echo "   ${SCRIPT_DIR}/../config/cloud-init/"
    echo ""
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "     VM Provisioning for AD Lab          "
    echo "=========================================="
    echo ""
    print_info "Hypervisor: $HYPERVISOR"
    echo ""

    check_prerequisites
    create_internal_network

    # Create VMs based on hypervisor
    case $HYPERVISOR in
        vbox)
            create_vbox_vm "AD-DC" "$DC_IP" "$DC_HOSTNAME"
            create_vbox_vm "$VM1_HOSTNAME" "$VM1_IP" "$VM1_HOSTNAME"
            create_vbox_vm "$VM2_HOSTNAME" "$VM2_IP" "$VM2_HOSTNAME"
            ;;
        kvm)
            create_kvm_vm "AD-DC" "$DC_IP" "$DC_HOSTNAME"
            create_kvm_vm "$VM1_HOSTNAME" "$VM1_IP" "$VM1_HOSTNAME"
            create_kvm_vm "$VM2_HOSTNAME" "$VM2_IP" "$VM2_HOSTNAME"
            ;;
    esac

    # Generate cloud-init configs
    generate_cloud_init "$DC_HOSTNAME" "$DC_IP"
    generate_cloud_init "$VM1_HOSTNAME" "$VM1_IP"
    generate_cloud_init "$VM2_HOSTNAME" "$VM2_IP"

    print_instructions
}

main "$@"
