#!/bin/bash
# Execute report generation scripts on the VM

set -e

VM_NAME="${1:-tnb-bootc-vm}"
VM_USER="${2:-tnbuser}"
VM_PASSWORD="${3:-tnbuser}"

echo "Generating test reports on VM..."
echo ""

# Get VM IP
VM_IP=$(sudo virsh domifaddr "$VM_NAME" 2>/dev/null | grep -oP '(\d+\.){3}\d+' | head -1)

if [ -z "$VM_IP" ]; then
    echo "ERROR: Could not get VM IP. Is the VM running?"
    exit 1
fi

echo "VM IP: $VM_IP"
echo ""

# Install sshpass if not available
if ! command -v sshpass &> /dev/null; then
    echo "Installing sshpass..."
    sudo dnf install -y sshpass
fi

# Copy scripts to VM
echo "Copying report scripts to VM..."
# Get script directory (works from project root or scripts/reporting)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sshpass -p "$VM_PASSWORD" scp \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o PubkeyAuthentication=no \
    "$SCRIPT_DIR/generate-test-report.sh" \
    "$SCRIPT_DIR/list-credential-failures.sh" \
    "${VM_USER}@${VM_IP}:/tmp/"

# Make scripts executable on VM
echo "Making scripts executable..."
sshpass -p "$VM_PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o PubkeyAuthentication=no \
    "${VM_USER}@${VM_IP}" \
    "chmod +x /tmp/generate-test-report.sh /tmp/list-credential-failures.sh"

# Run test summary report
echo ""
echo "=================================================="
echo "Generating Test Summary Report..."
echo "=================================================="
sshpass -p "$VM_PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o PubkeyAuthentication=no \
    "${VM_USER}@${VM_IP}" \
    "/tmp/generate-test-report.sh"

echo ""
echo "=================================================="
echo "Generating Credential Failures Report..."
echo "=================================================="
sshpass -p "$VM_PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o PubkeyAuthentication=no \
    "${VM_USER}@${VM_IP}" \
    "/tmp/list-credential-failures.sh"

echo ""
echo "=================================================="
echo "Reports generated successfully!"
echo "=================================================="
echo ""
echo "To view the reports:"
echo "  - Test summary: make vm-view-test-summary"
echo "  - Credential failures: make vm-view-credential-failures"
echo ""
echo "To sync all test results to host:"
echo "  - make sync-test-results"
echo ""
