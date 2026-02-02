#!/bin/bash
# Setup runtime directory for tnbuser's Podman socket
# This script runs as root to create directories for tnbuser

set -e

# Get tnbuser's actual UID
TNB_UID=$(id -u tnbuser)

echo "Setting up Podman runtime directory for tnbuser (UID: $TNB_UID)"

# Create runtime directory
mkdir -p /run/user/$TNB_UID/podman

# Set ownership and permissions
chown -R tnbuser:tnbuser /run/user/$TNB_UID
chmod 700 /run/user/$TNB_UID

# Enable lingering for tnbuser (allows services to run without login)
loginctl enable-linger tnbuser 2>/dev/null || true

echo "Runtime directory ready at /run/user/$TNB_UID"
echo "XDG_RUNTIME_DIR=/run/user/$TNB_UID"
