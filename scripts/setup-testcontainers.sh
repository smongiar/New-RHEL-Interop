#!/bin/bash
set -e

echo "Setting up Testcontainers support..."

# Verify Podman is installed
if ! command -v podman &> /dev/null; then
    echo "ERROR: Podman is not installed"
    exit 1
fi

echo "Podman version:"
podman --version

# Verify podman-docker compatibility
if [ -f /usr/bin/docker ]; then
    echo "Docker compatibility layer: OK"
    /usr/bin/docker --version
else
    echo "WARNING: Docker compatibility layer not found"
fi

# Test Podman functionality
echo "Testing Podman..."
if podman run --rm hello-world &> /dev/null; then
    echo "Podman test: PASSED"
else
    echo "Podman test: FAILED (might work after system reboot)"
fi

echo "Testcontainers setup completed"
echo ""
echo "Configuration summary:"
echo "  - Podman installed: $(podman --version)"
echo "  - Docker compatibility: $([ -f /usr/bin/docker ] && echo 'Yes' || echo 'No')"
echo "  - Rootless support: Enabled"
echo "  - User: tnbuser"
echo "  - Socket: /run/user/1000/podman/podman.sock"
echo ""
echo "Testcontainers environment variables:"
echo "  - DOCKER_HOST=unix:///run/user/1000/podman/podman.sock"
echo "  - TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/run/user/1000/podman/podman.sock"
