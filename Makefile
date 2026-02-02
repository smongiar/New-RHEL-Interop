# Makefile for TNB Bootable RHEL Image Mode
# Provides convenient commands for building and deploying

.PHONY: help build build-jdk17 build-jdk21 build-cached transfer-to-root disk-qcow2 vm-create vm-recreate vm-start vm-stop vm-restart vm-ssh vm-console vm-status vm-logs vm-ip clean clean-all clean-vm rebuild-all setup-cache check-registry-auth vm-generate-reports sync-test-results vm-view-test-summary vm-view-credential-failures

# Default values
IMAGE_NAME ?= tnb-bootc-image
IMAGE_TAG ?= latest
BUILD_JDK ?= 21
TNB_BRANCH ?= main
TNB_TESTS_BRANCH ?= main
OUTPUT_DIR ?= $(HOME)/bootc-output
MAVEN_CACHE_DIR ?= $(HOME)/.m2-build-cache
TEST_RESULTS_DIR ?= $(HOME)/tnb-test-results
VM_NAME ?= tnb-bootc-vm
VM_MEMORY ?= 4096
VM_CPUS ?= 2

help:
	@echo "TNB Bootable RHEL Image Mode - Makefile Commands"
	@echo "=================================================="
	@echo ""
	@echo "Quick Start:"
	@echo "  make check-registry-auth - Check/setup Red Hat registry authentication"
	@echo "  make setup-cache        - Create Maven cache directory (first time only)"
	@echo "  make rebuild-all        - Complete rebuild: image + disk + VM (with cache)"
	@echo "  make quick-deploy       - Build and deploy everything from scratch"
	@echo ""
	@echo "Building Container Images:"
	@echo "  make build              - Build image with JDK $(BUILD_JDK)"
	@echo "  make build-cached       - Build with Maven cache (FASTER!) ⚡"
	@echo "  make build-jdk17        - Build with JDK 17"
	@echo "  make build-jdk21        - Build with JDK 21 (default)"
	@echo "  make transfer-to-root   - Transfer image to root podman storage"
	@echo ""
	@echo "Creating Bootable Disk Images:"
	@echo "  make disk-qcow2         - Generate QCOW2 disk image (for VMs)"
	@echo ""
	@echo "VM Management (requires libvirt):"
	@echo "  make vm-create          - Create new VM from QCOW2 image"
	@echo "  make vm-recreate        - Destroy and recreate VM with new disk"
	@echo "  make vm-start           - Start the VM"
	@echo "  make vm-stop            - Stop the VM"
	@echo "  make vm-restart         - Restart the VM"
	@echo "  make vm-ssh             - SSH into the VM"
	@echo "  make vm-console         - Connect to VM console"
	@echo "  make vm-status          - Show VM status and IP"
	@echo "  make vm-ip              - Show VM IP address only"
	@echo "  make vm-logs            - View TNB service logs"
	@echo ""
	@echo "Test Results & Reporting:"
	@echo "  make vm-generate-reports       - Generate test reports on VM"
	@echo "  make sync-test-results         - Sync test results from VM to host"
	@echo "  make vm-view-test-summary      - View test summary report"
	@echo "  make vm-view-credential-failures - View credential failure details"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean              - Remove built images"
	@echo "  make clean-vm           - Destroy VM and remove it"
	@echo "  make clean-all          - Remove everything (images, disk, VM)"
	@echo ""
	@echo "Variables (override with make VAR=value):"
	@echo "  IMAGE_NAME=$(IMAGE_NAME)"
	@echo "  IMAGE_TAG=$(IMAGE_TAG)"
	@echo "  BUILD_JDK=$(BUILD_JDK)"
	@echo "  OUTPUT_DIR=$(OUTPUT_DIR)"
	@echo "  MAVEN_CACHE_DIR=$(MAVEN_CACHE_DIR)"
	@echo "  TEST_RESULTS_DIR=$(TEST_RESULTS_DIR)"
	@echo "  VM_NAME=$(VM_NAME)"
	@echo "  VM_MEMORY=$(VM_MEMORY)"
	@echo "  VM_CPUS=$(VM_CPUS)"
	@echo ""

check-registry-auth:
	@echo "Checking Red Hat registry authentication..."
	@echo ""
	@echo "Checking user podman authentication..."
	@USER_LOGIN=$$(podman login --get-login registry.redhat.io 2>/dev/null); \
	if [ -n "$$USER_LOGIN" ]; then \
		echo "✓ User podman: authenticated as $$USER_LOGIN"; \
	else \
		echo "✗ User podman: NOT authenticated"; \
		echo "  Run: podman login registry.redhat.io"; \
	fi
	@echo ""
	@echo "Checking root podman authentication (required for bootc-image-builder)..."
	@ROOT_LOGIN=$$(sudo podman login --get-login registry.redhat.io 2>/dev/null); \
	if [ -n "$$ROOT_LOGIN" ]; then \
		echo "✓ Root podman: authenticated as $$ROOT_LOGIN"; \
	else \
		echo "✗ Root podman: NOT authenticated"; \
		echo ""; \
		echo "REQUIRED: You must login with root/sudo to pull bootc-image-builder:"; \
		echo ""; \
		echo "  sudo podman login registry.redhat.io"; \
		echo ""; \
		echo "Use your Red Hat Customer Portal credentials."; \
		echo "More info: https://access.redhat.com/RegistryAuthentication"; \
		exit 1; \
	fi
	@echo ""
	@echo "✓ All authentication checks passed!"

setup-cache:
	@echo "Setting up Maven build cache directory..."
	@mkdir -p $(MAVEN_CACHE_DIR)
	@echo "Maven cache directory created: $(MAVEN_CACHE_DIR)"
	@echo "This will speed up subsequent builds significantly!"

build:
	@echo "Building $(IMAGE_NAME):$(IMAGE_TAG) with JDK $(BUILD_JDK)..."
	podman build \
		--build-arg BUILD_JDK=$(BUILD_JDK) \
		--build-arg TNB_BRANCH=$(TNB_BRANCH) \
		--build-arg TNB_TESTS_BRANCH=$(TNB_TESTS_BRANCH) \
		-t $(IMAGE_NAME):$(IMAGE_TAG) \
		-f Containerfile \
		.
	@echo "Build completed successfully!"
	@podman images | grep $(IMAGE_NAME)

build-cached: setup-cache
	@echo "Building $(IMAGE_NAME):$(IMAGE_TAG) with JDK $(BUILD_JDK) using Maven cache..."
	@echo "Cache directory: $(MAVEN_CACHE_DIR)"
	podman build \
		--volume $(MAVEN_CACHE_DIR):/root/.m2:Z \
		--build-arg BUILD_JDK=$(BUILD_JDK) \
		--build-arg TNB_BRANCH=$(TNB_BRANCH) \
		--build-arg TNB_TESTS_BRANCH=$(TNB_TESTS_BRANCH) \
		-t $(IMAGE_NAME):$(IMAGE_TAG) \
		-f Containerfile \
		.
	@echo "Build completed successfully with cache!"
	@podman images | grep $(IMAGE_NAME)

build-jdk17:
	@$(MAKE) build-cached BUILD_JDK=17 IMAGE_TAG=jdk17

build-jdk21:
	@$(MAKE) build-cached BUILD_JDK=21 IMAGE_TAG=jdk21

transfer-to-root:
	@echo "Transferring image to root podman storage..."
	@echo "This allows bootc-image-builder to access the image"
	podman save localhost/$(IMAGE_NAME):$(IMAGE_TAG) | sudo podman load
	@echo "Image transferred successfully!"
	@echo "Verifying image in root storage:"
	@sudo podman images | grep $(IMAGE_NAME)

disk-qcow2: check-bootc-builder transfer-to-root
	@echo "Generating QCOW2 disk image with RHEL 10 bootc-image-builder..."
	@mkdir -p $(OUTPUT_DIR)
	@sudo rm -f $(OUTPUT_DIR)/qcow2/disk.qcow2
	sudo podman run \
		--rm \
		-it \
		--privileged \
		--pull=newer \
		-v $(OUTPUT_DIR):/output \
		-v /var/lib/containers/storage:/var/lib/containers/storage \
		registry.redhat.io/rhel10/bootc-image-builder:latest \
		--type qcow2 \
		--rootfs xfs \
		--local \
		localhost/$(IMAGE_NAME):$(IMAGE_TAG)
	@echo "Expanding disk size to 50GB for TNB tests (containers + Maven artifacts)..."
	@sudo qemu-img resize $(OUTPUT_DIR)/qcow2/disk.qcow2 50G
	@echo "QCOW2 image created and resized: $(OUTPUT_DIR)/qcow2/disk.qcow2"
	@sudo qemu-img info $(OUTPUT_DIR)/qcow2/disk.qcow2 | grep "virtual size"

check-bootc-builder:
	@echo "Checking for RHEL 10 bootc-image-builder..."
	@sudo podman pull registry.redhat.io/rhel10/bootc-image-builder:latest

vm-create: check-libvirt
	@echo "Creating VM $(VM_NAME)..."
	@if [ ! -f $(OUTPUT_DIR)/qcow2/disk.qcow2 ]; then \
		echo "Error: QCOW2 image not found. Run 'make disk-qcow2' first."; \
		exit 1; \
	fi
	@if sudo virsh list --all | grep -q "$(VM_NAME)"; then \
		echo "Error: VM $(VM_NAME) already exists. Use 'make vm-recreate' to destroy and recreate."; \
		exit 1; \
	fi
	sudo virt-install \
		--name $(VM_NAME) \
		--memory $(VM_MEMORY) \
		--vcpus $(VM_CPUS) \
		--disk path=$(OUTPUT_DIR)/qcow2/disk.qcow2,format=qcow2 \
		--import \
		--os-variant rhel10.0 \
		--network network=default \
		--graphics vnc,listen=0.0.0.0 \
		--noautoconsole
	@echo "VM created successfully!"
	@echo "Waiting for VM to boot (30 seconds)..."
	@sleep 30
	@$(MAKE) vm-status

vm-recreate: clean-vm disk-qcow2
	@echo "Recreating VM $(VM_NAME) with new disk image..."
	sudo virt-install \
		--name $(VM_NAME) \
		--memory $(VM_MEMORY) \
		--vcpus $(VM_CPUS) \
		--disk path=$(OUTPUT_DIR)/qcow2/disk.qcow2,format=qcow2 \
		--import \
		--os-variant rhel10.0 \
		--network network=default \
		--graphics vnc,listen=0.0.0.0 \
		--noautoconsole
	@echo "VM recreated successfully!"
	@echo "Waiting for VM to boot (30 seconds)..."
	@sleep 30
	@$(MAKE) vm-status

vm-start:
	@echo "Starting VM $(VM_NAME)..."
	@sudo virsh start $(VM_NAME) 2>/dev/null || echo "VM may already be running"
	@sleep 5
	@$(MAKE) vm-status

vm-stop:
	@echo "Stopping VM $(VM_NAME)..."
	@sudo virsh shutdown $(VM_NAME) 2>/dev/null || echo "VM may already be stopped"

vm-restart: vm-stop
	@echo "Waiting for VM to shut down..."
	@sleep 5
	@$(MAKE) vm-start

vm-status:
	@echo "========================================="
	@echo "VM Status: $(VM_NAME)"
	@echo "========================================="
	@sudo virsh list --all | grep $(VM_NAME) || echo "VM not found"
	@echo ""
	@echo "Network Information:"
	@sudo virsh domifaddr $(VM_NAME) 2>/dev/null || echo "VM may still be booting or not running..."
	@echo ""

vm-ip:
	@sudo virsh domifaddr $(VM_NAME) 2>/dev/null | grep -oP '(\d+\.){3}\d+' | head -1 || echo "Could not get IP (VM may be booting or stopped)"

vm-ssh:
	@echo "Getting VM IP address..."
	@VM_IP=$$(sudo virsh domifaddr $(VM_NAME) 2>/dev/null | grep -oP '(\d+\.){3}\d+' | head -1); \
	if [ -z "$$VM_IP" ]; then \
		echo "Could not get VM IP. Is the VM running?"; \
		echo "Try: make vm-status"; \
		exit 1; \
	fi; \
	echo "Connecting to tnbuser@$$VM_IP..."; \
	echo "Password: tnbuser"; \
	ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password tnbuser@$$VM_IP

vm-console:
	@echo "Connecting to VM console (press Ctrl+] to exit)..."
	sudo virsh console $(VM_NAME)

vm-logs:
	@echo "Fetching TNB service logs from VM..."
	@VM_IP=$$(sudo virsh domifaddr $(VM_NAME) 2>/dev/null | grep -oP '(\d+\.){3}\d+' | head -1); \
	if [ -z "$$VM_IP" ]; then \
		echo "Could not get VM IP. Is the VM running?"; \
		exit 1; \
	fi; \
	echo "Connecting to $$VM_IP to fetch logs..."; \
	ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password tnbuser@$$VM_IP "sudo journalctl -u tnb.service --no-pager"

check-libvirt:
	@if ! command -v virt-install > /dev/null; then \
		echo "Error: libvirt tools not found. Install with:"; \
		echo "  sudo dnf install -y virt-install libvirt"; \
		exit 1; \
	fi
	@if ! sudo systemctl is-active --quiet libvirtd; then \
		echo "Error: libvirtd service is not running. Start with:"; \
		echo "  sudo systemctl start libvirtd"; \
		echo "  sudo systemctl enable libvirtd"; \
		exit 1; \
	fi

clean:
	@echo "Removing built images from user podman storage..."
	@podman rmi -f $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true
	@podman rmi -f localhost/$(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true
	@echo "Removing image from root podman storage..."
	@sudo podman rmi -f $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true
	@sudo podman rmi -f localhost/$(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true
	@echo "Image cleanup completed!"

clean-vm:
	@echo "Destroying and removing VM $(VM_NAME)..."
	@sudo virsh destroy $(VM_NAME) 2>/dev/null || true
	@sleep 2
	@sudo virsh undefine $(VM_NAME) --nvram 2>/dev/null || sudo virsh undefine $(VM_NAME) 2>/dev/null || true
	@echo "VM removed!"

clean-all: clean clean-vm
	@echo "Removing output directory and disk images..."
	@rm -rf $(OUTPUT_DIR)
	@echo "Full cleanup completed!"
	@echo "Note: Maven cache ($(MAVEN_CACHE_DIR)) is preserved for faster rebuilds"

# Complete rebuild workflow with caching
rebuild-all: check-registry-auth clean build-cached disk-qcow2 vm-recreate
	@echo ""
	@echo "========================================="
	@echo "Complete rebuild finished!"
	@echo "========================================="
	@echo "VM $(VM_NAME) is running"
	@echo ""
	@echo "Next steps:"
	@echo "  make vm-ssh             - SSH into the VM"
	@echo "  make vm-logs            - View TNB test logs"
	@echo "  make vm-status          - Check VM status"
	@echo "========================================="

# Quick build and deploy workflow (for first-time setup)
quick-deploy: check-registry-auth setup-cache build-cached disk-qcow2 vm-create
	@echo ""
	@echo "========================================="
	@echo "Quick deploy completed!"
	@echo "========================================="
	@echo "VM $(VM_NAME) is running"
	@echo ""
	@echo "Next steps:"
	@echo "  make vm-ssh             - SSH into the VM"
	@echo "  make vm-logs            - View TNB test logs"
	@echo "  make vm-status          - Check VM status"
	@echo "========================================="

# Test reporting targets
vm-generate-reports:
	@echo "Generating test reports on VM..."
	@./scripts/reporting/vm-generate-reports.sh $(VM_NAME) tnbuser tnbuser

sync-test-results:
	@echo "Syncing test results from VM to host..."
	@./scripts/reporting/sync-test-results.sh $(VM_NAME) tnbuser tnbuser $(TEST_RESULTS_DIR)

vm-view-test-summary:
	@echo "Fetching test summary from VM..."
	@VM_IP=$$(sudo virsh domifaddr $(VM_NAME) 2>/dev/null | grep -oP '(\d+\.){3}\d+' | head -1); \
	if [ -z "$$VM_IP" ]; then \
		echo "Could not get VM IP. Is the VM running?"; \
		exit 1; \
	fi; \
	if ! command -v sshpass > /dev/null; then \
		echo "Installing sshpass..."; \
		sudo dnf install -y sshpass; \
	fi; \
	sshpass -p tnbuser ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no tnbuser@$$VM_IP "cat /var/opt/tnb-tests/test-summary-report.txt 2>/dev/null || echo 'Report not found. Run: make vm-generate-reports'"

vm-view-credential-failures:
	@echo "Fetching credential failures report from VM..."
	@VM_IP=$$(sudo virsh domifaddr $(VM_NAME) 2>/dev/null | grep -oP '(\d+\.){3}\d+' | head -1); \
	if [ -z "$$VM_IP" ]; then \
		echo "Could not get VM IP. Is the VM running?"; \
		exit 1; \
	fi; \
	if ! command -v sshpass > /dev/null; then \
		echo "Installing sshpass..."; \
		sudo dnf install -y sshpass; \
	fi; \
	sshpass -p tnbuser ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no tnbuser@$$VM_IP "cat /var/opt/tnb-tests/credential-failures.txt 2>/dev/null || echo 'Report not found. Run: make vm-generate-reports'"
