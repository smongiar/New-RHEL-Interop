# TNB Bootable RHEL 10 Image Mode

A bootable RHEL 10 image with TNB (Test and Build) framework for automated testing.

## What's Included

- **RHEL 10** bootc (image mode)
- **OpenJDK 21** (default, configurable to 25)
- **Apache Maven 3.9.9**
- **TNB framework** and **TNB-tests** (cloned from repositories)
- **Podman** with Testcontainers support (rootless containers)
- **systemd service** for automatic TNB test execution
- Pre-configured certificates and Maven settings

## Quick Start

### Prerequisites

- RHEL 10 or Fedora with Podman
- Access to `registry.redhat.io` (Red Hat subscription)
- Libvirt for VM management
- git-crypt (for encrypted registry credentials: `sudo dnf install git-crypt`)
- 20GB disk space, 4GB RAM minimum

### One-Command Deploy

```bash
# First time setup - builds image, creates disk, and starts VM
make quick-deploy
```

This will:
1. Create Maven cache directory
2. Build the bootc container image (with caching)
3. Generate QCOW2 bootable disk image
4. Create and start a VM
5. Wait for boot and display connection info

**Note**: Some tests will fail without registry credentials. See [Registry Authentication](#registry-authentication) to set up encrypted credentials for `registry.redhat.io` and `quay.io`.

### Access the VM

```bash
# SSH into the VM (default password: tnbuser)
make vm-ssh

# View TNB test logs
make vm-logs

# Check VM status and IP
make vm-status
```

## Common Tasks

### Building

```bash
# Build with Maven cache (fast rebuild)
make build-cached

# Build with JDK 21 (default)
make build-jdk21

# Build with JDK 25
make build-jdk25

# Build with custom branches
make build-cached TNB_BRANCH=development TNB_TESTS_BRANCH=feature-x
```

### VM Management

```bash
# Rebuild everything from scratch
make rebuild-all

# Recreate VM with new disk image
make vm-recreate

# Start/stop/restart VM
make vm-start
make vm-stop
make vm-restart

# Connect to VM console
make vm-console

# Get VM IP address
make vm-ip
```

### Test Reporting

After tests run in the VM, generate reports and analyze results:

```bash
# Generate test reports on VM
make vm-generate-reports

# View test summary (successful, failed, errors, skipped)
make vm-view-test-summary

# View tests failing with credential errors
make vm-view-credential-failures

# Sync test results to host (default: ~/tnb-test-results/)
make sync-test-results
```

**Understanding credential failures:**

Tests failing with `java.lang.RuntimeException: Couldnt get credentials from ids:` can be excluded if credentials aren't available. The credential failures report provides ready-to-use Maven exclusion patterns:

```bash
# Get exclusion patterns
make vm-view-credential-failures

# Example output:
#   -Dtest='!AuthRequiredTest,!SecretManagerTest'
```

Use these patterns in Maven commands or add to `pom.xml`:

```xml
<plugin>
  <groupId>org.apache.maven.plugins</groupId>
  <artifactId>maven-failsafe-plugin</artifactId>
  <configuration>
    <excludes>
      <exclude>**/AuthRequiredTest.java</exclude>
    </excludes>
  </configuration>
</plugin>
```

**Report locations:**
- VM: `/var/opt/tnb-tests/test-summary-report.txt`
- VM: `/var/opt/tnb-tests/credential-failures.txt`
- Host (after sync): `~/tnb-test-results/`

### Cleanup

```bash
# Remove built images
make clean

# Remove VM only
make clean-vm

# Remove everything (images, disk, VM)
make clean-all
```

## Build Configuration

### Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `BUILD_JDK` | `21` | OpenJDK version (21 or 25) |
| `TNB_BRANCH` | `main` | TNB framework branch |
| `TNB_TESTS_BRANCH` | `main` | TNB-tests branch |
| `VM_MEMORY` | `4096` | VM memory in MB |
| `VM_CPUS` | `2` | VM CPU cores |

### Override Variables

```bash
# Build with 8GB RAM and 4 CPUs
make vm-create VM_MEMORY=8192 VM_CPUS=4

# Use different TNB branch
make build-cached TNB_BRANCH=feature-branch
```

## How It Works

### Image Build Process

1. **Base Image**: RHEL 10 bootc from `registry.redhat.io/rhel10/rhel-bootc`
2. **Setup**: Installs JDK, Maven, Podman, certificates
3. **Clone Repositories**:
   - TNB framework from GitHub
   - TNB-tests from GitLab (requires access)
4. **Dependencies**: Downloads Maven dependencies (cached for speed)
5. **User Setup**: Creates `tnbuser` with sudo access (password: `tnbuser`)
6. **Services**: Enables `tnb.service` for automatic test execution

### VM Runtime

- **Bootc/OSTree**: `/opt` is read-only, sources copied to `/var/opt/tnb-tests` at runtime
- **Tests**: Run automatically on boot via `tnb.service`
- **Containers**: Rootless Podman with Testcontainers support
- **Logs**: View with `journalctl -u tnb.service` or `make vm-logs`

## Project Structure

```
.
├── Containerfile              # Bootc image definition
├── Makefile                   # Automation commands
├── config/                    # Configuration files
│   ├── containers.conf        # Podman rootless config
│   ├── storage.conf          # Podman storage config
│   ├── settings-tnb.xml      # Maven settings
│   ├── log4j2.xml            # Logging configuration
│   └── tnb-tests.conf        # tmpfiles.d for writable directory
├── scripts/                   # Build-time and runtime scripts
│   ├── setup-certificates.sh # Import SSL certificates
│   ├── setup-maven.sh        # Install Maven
│   ├── setup-testcontainers.sh # Configure Podman
│   ├── entrypoint.sh         # Container entrypoint
│   └── reporting/            # Test reporting scripts
│       ├── generate-test-report.sh      # Generate test summary
│       ├── list-credential-failures.sh  # List credential errors
│       ├── sync-test-results.sh         # Sync results to host
│       └── vm-generate-reports.sh       # Run reports on VM
└── systemd/                   # systemd service definitions
    ├── tnb.service           # TNB test execution service
    └── podman-tnbuser.service # Podman API service
```

## Authentication

### VM Login

- **Username**: `tnbuser`
- **Password**: `tnbuser`
- **Sudo**: Passwordless sudo enabled

### Registry Authentication

#### For Building the Image

Login to Red Hat registry before building:

```bash
podman login registry.redhat.io
sudo podman login registry.redhat.io  # Also needed for bootc-image-builder
```

#### For Running Tests (Required)

TNB tests pull container images from authenticated registries. You need to embed credentials in the image:

**Quick Setup:**

```bash
# 1. Install git-crypt (one time)
sudo dnf install git-crypt

# 2. Initialize git-crypt (one time)
git-crypt init
git-crypt export-key ~/.git-crypt-key
# ⚠️ IMPORTANT: Save this key securely!

# 3. Create encrypted credentials file
./secrets/create-auth.sh
# Enter your Red Hat registry credentials when prompted
# Optionally enter Quay.io credentials

# 4. Verify encryption
git-crypt status
# Should show: secrets/containers-auth.json: encrypted

# 5. Commit the encrypted file
git add secrets/containers-auth.json .gitattributes .gitignore
git commit -m "Add encrypted registry credentials"

# 6. Rebuild with credentials
make rebuild-all
```

**What registries need authentication:**
- `registry.redhat.io` - Required for AMQ, Fuse, and other Red Hat images
- `quay.io` - Optional, for private Quay images

For more details, see [`secrets/README.md`](secrets/README.md).

### TNB-tests Repository

TNB-tests is hosted on Red Hat internal GitLab. You need access to:
- `https://gitlab.cee.redhat.com/jboss-fuse-qe/t-n-b/tnb-tests.git`

## Troubleshooting

### Build Issues

**Problem**: Maven dependencies download is slow
**Solution**: Use `make build-cached` - subsequent builds reuse cached dependencies

**Problem**: Authentication error to registry.redhat.io
**Solution**: Run `podman login registry.redhat.io` with valid Red Hat credentials

**Problem**: Cannot access TNB-tests repository
**Solution**: Ensure you have access to Red Hat internal GitLab

### VM Issues

**Problem**: Cannot SSH to VM
**Solution**:
```bash
make vm-status  # Check if VM is running and has IP
make vm-console # Connect via console if SSH fails
```

**Problem**: TNB tests failing in VM
**Solution**:
```bash
make vm-logs  # View full test logs
# SSH into VM and check:
ls -la /var/opt/tnb-tests  # Verify writable directory exists
sudo systemctl status tnb.service  # Check service status
```

**Problem**: Tests fail with "Can't get Docker image" or authentication errors
**Solution**: Registry credentials are missing. Set up encrypted credentials:
```bash
./secrets/create-auth.sh  # Create encrypted auth file
git-crypt status          # Verify encryption
make rebuild-all          # Rebuild with credentials
# In VM, verify:
podman login --get-login registry.redhat.io  # Should show username
```
See [Registry Authentication](#registry-authentication) for detailed setup.

**Problem**: VM won't start
**Solution**:
```bash
# Check libvirtd is running
sudo systemctl status libvirtd
sudo systemctl start libvirtd

# View VM console for boot errors
make vm-console
```

### Permission Issues

**Problem**: "Cannot create resource output directory" error
**Solution**: This is fixed in the current version. The service copies sources from read-only `/opt` to writable `/var/opt` automatically.

## Performance Tips

### Speed Up Builds

- **Use Maven cache**: `make build-cached` (2-5 min vs 15-20 min)
- **Reuse images**: Only rebuild when Containerfile changes
- **Parallel builds**: Podman uses all CPU cores by default

### Speed Up Testing

- Tests download dependencies on first run (cached afterwards)
- Maven local repository persists in VM at `/home/tnbuser/.m2/repository`

## Advanced Usage

### Manual Build Steps

If you prefer manual control over the Makefile:

```bash
# 1. Build container image with cache
mkdir -p ~/.m2-build-cache
podman build \
  --volume ~/.m2-build-cache:/root/.m2:Z \
  -t tnb-bootc-image:latest \
  -f Containerfile .

# 2. Transfer to root storage
podman save localhost/tnb-bootc-image:latest | sudo podman load

# 3. Create bootable disk
mkdir -p ~/bootc-output
sudo podman run --rm -it --privileged \
  --pull=newer \
  -v ~/bootc-output:/output \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  registry.redhat.io/rhel10/bootc-image-builder:latest \
  --type qcow2 \
  --local localhost/tnb-bootc-image:latest

# 4. Create VM
sudo virt-install \
  --name tnb-bootc-vm \
  --memory 4096 \
  --vcpus 2 \
  --disk path=~/bootc-output/qcow2/disk.qcow2,format=qcow2 \
  --import \
  --os-variant rhel10.0 \
  --network network=default \
  --graphics vnc,listen=0.0.0.0 \
  --noautoconsole
```

### Disable Automatic Tests

By default, `tnb.service` runs tests automatically on boot. To disable:

```bash
# In the VM
sudo systemctl disable tnb.service
sudo systemctl stop tnb.service

# Run tests manually when needed
sudo systemctl start tnb.service
```

## Contributing

When making changes:

1. Update the `Containerfile` for image modifications
2. Use `make rebuild-all` to test changes end-to-end
3. Verify tests run successfully with `make vm-logs`

## License

This project uses components with various licenses:
- RHEL 10: Red Hat Enterprise Linux license
- TNB framework: Check repository for license
- Apache Maven: Apache License 2.0
- Podman: Apache License 2.0

## Help

```bash
# Show all available make targets
make help
```

For issues or questions, refer to the inline comments in:
- `Containerfile` - Image build process
- `Makefile` - Automation commands
- `systemd/tnb.service` - Test execution service
