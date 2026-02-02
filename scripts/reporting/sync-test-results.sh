#!/bin/bash
# Sync test results from VM to host

set -e

VM_NAME="${1:-tnb-bootc-vm}"
VM_USER="${2:-tnbuser}"
VM_PASSWORD="${3:-tnbuser}"
LOCAL_DIR="${4:-$HOME/tnb-test-results}"
REMOTE_DIR="${5:-/var/opt/tnb-tests/tests/springboot/examples/target}"

echo "Syncing test results from VM to host..."
echo "VM: $VM_NAME"
echo "Remote directory: $REMOTE_DIR"
echo "Local directory: $LOCAL_DIR"
echo ""

# Get VM IP
VM_IP=$(sudo virsh domifaddr "$VM_NAME" 2>/dev/null | grep -oP '(\d+\.){3}\d+' | head -1)

if [ -z "$VM_IP" ]; then
    echo "ERROR: Could not get VM IP. Is the VM running?"
    echo "Try: sudo virsh list --all"
    exit 1
fi

echo "VM IP: $VM_IP"
echo ""

# Create local directory
mkdir -p "$LOCAL_DIR"

# Install sshpass if not available (for password-based SSH)
if ! command -v sshpass &> /dev/null; then
    echo "Installing sshpass for password-based SSH..."
    sudo dnf install -y sshpass
fi

# Sync files using rsync over SSH with password
echo "Syncing files..."
sshpass -p "$VM_PASSWORD" rsync -avz \
    -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no" \
    "${VM_USER}@${VM_IP}:${REMOTE_DIR}/" \
    "$LOCAL_DIR/"

echo ""
echo "Sync completed!"
echo "Test results available at: $LOCAL_DIR"
echo ""

# List what was synced
echo "Synced files:"
ls -lh "$LOCAL_DIR" | head -20
