# Bootable RHEL Image Mode with TNB Testing Environment
# This Containerfile creates a bootable RHEL image that includes:
# - TNB framework
# - TNB-tests environment
# - Maven build system
# - Required certificates and tools

# Build arguments
ARG BUILD_JDK=21
ARG TNB_BRANCH=main
ARG TNB_TESTS_BRANCH=main

# Base image - RHEL 10 bootc for image mode
FROM registry.redhat.io/rhel10/rhel-bootc

# Re-declare build arguments after FROM to make them available in build stages
ARG BUILD_JDK=21
ARG TNB_BRANCH=main
ARG TNB_TESTS_BRANCH=main

# Set labels
LABEL description="Bootable RHEL Image Mode with TNB Testing Environment"
LABEL vendor="Red Hat"
LABEL version="1.0"

# Set environment variables
ENV JAVA_HOME=/usr/lib/jvm/jre-${BUILD_JDK}
ENV MAVEN_HOME=/opt/maven
ENV PATH="${MAVEN_HOME}/bin:${PATH}"
ENV TNB_HOME=/opt/tnb
ENV TNB_TESTS_HOME=/opt/tnb-tests

# Update system and install base packages
RUN dnf update -y && \
    dnf install -y \
    java-${BUILD_JDK}-openjdk-devel \
    rsync \
    git \
    openssl \
    skopeo \
    jq \
    procps-ng \
    wget \
    curl \
    tar \
    gzip \
    vim \
    sudo \
    systemd \
    podman \
    podman-docker \
    buildah \
    slirp4netns \
    fuse-overlayfs \
    openssh-server \
    firewalld \
    cloud-utils-growpart \
    xfsprogs \
    && dnf clean all

# Configure SSH server and disable bootc auto-updates (no registry available)
RUN systemctl enable sshd && \
    systemctl enable firewalld && \
    systemctl disable bootc-fetch-apply-updates.service bootc-fetch-apply-updates.timer 2>/dev/null || true

# Configure firewall to allow SSH
RUN firewall-offline-cmd --add-service=ssh

# Set Italian keyboard layout and locale by default
RUN dnf install -y glibc-langpack-it && \
    echo "KEYMAP=it" > /etc/vconsole.conf && \
    echo "FONT=eurlatgr" >> /etc/vconsole.conf && \
    echo "LANG=it_IT.UTF-8" > /etc/locale.conf && \
    localectl set-keymap it || true && \
    localectl set-locale LANG=it_IT.UTF-8 || true

# Create necessary directories
RUN mkdir -p /opt/tnb \
    /opt/tnb-tests \
    /deployments \
    /artifacts-tests \
    /root/.m2 \
    /scripts \
    /config \
    /var/log/tnb

# Copy setup scripts and configuration files
COPY scripts/setup-certificates.sh /scripts/
COPY scripts/setup-maven.sh /scripts/
COPY scripts/setup-testcontainers.sh /scripts/
COPY scripts/setup-podman-socket.sh /scripts/
COPY scripts/entrypoint.sh /scripts/
COPY config/settings-tnb.xml /config/
COPY config/log4j2.xml /config/

# Make scripts executable
RUN chmod +x /scripts/*.sh

# Setup certificates
RUN /scripts/setup-certificates.sh

# Install and configure Maven
RUN /scripts/setup-maven.sh

# Setup and verify Testcontainers support
RUN /scripts/setup-testcontainers.sh

# Clone TNB framework
RUN git clone --depth=1 --branch=${TNB_BRANCH} \
    https://github.com/tnb-software/TNB ${TNB_HOME}

# Clone TNB-tests
# Configure git to use system trust store and disable SSL verification for internal GitLab
RUN git config --global http.sslCAInfo /etc/pki/tls/certs/ca-bundle.crt && \
    git config --global http."https://gitlab.cee.redhat.com/".sslVerify false && \
    git clone --depth=1 --branch=${TNB_TESTS_BRANCH} \
    https://gitlab.cee.redhat.com/jboss-fuse-qe/t-n-b/tnb-tests.git ${TNB_TESTS_HOME} && \
    git config --global --unset http."https://gitlab.cee.redhat.com/".sslVerify

# Copy log4j2 configuration (if paths exist)
RUN if [ -d ${TNB_HOME}/system-x/common/src/main/resources ]; then \
        cp /config/log4j2.xml ${TNB_HOME}/system-x/common/src/main/resources/log4j2.xml; \
    fi && \
    if [ -d ${TNB_TESTS_HOME}/system-x/common/src/main/resources ]; then \
        cp /config/log4j2.xml ${TNB_TESTS_HOME}/system-x/common/src/main/resources/log4j2.xml; \
    fi

# Download Maven dependencies for TNB framework (cached in a separate layer)
# This downloads dependencies during build to speed up runtime test execution
RUN echo "========================================" && \
    echo "Downloading Maven dependencies for TNB framework..." && \
    echo "This may take several minutes on first build but will be cached" && \
    echo "========================================" && \
    cd ${TNB_HOME} && \
    /opt/maven/bin/mvn dependency:go-offline -s /root/.m2/settings.xml -B -q || \
    /opt/maven/bin/mvn dependency:resolve -s /root/.m2/settings.xml -B || true && \
    cd ${TNB_TESTS_HOME} && \
    /opt/maven/bin/mvn dependency:go-offline -s /root/.m2/settings.xml -B -q || \
    /opt/maven/bin/mvn dependency:resolve -s /root/.m2/settings.xml -B || true && \
    echo "========================================" && \
    echo "Maven dependencies downloaded successfully!" && \
    echo "========================================"

# Create a user for running tests BEFORE setting up services
# Create user with password hash directly using useradd -p (required for bootc/ostree)
# Password: tnbuser (hash generated with: python3 -c "import crypt; print(crypt.crypt('tnbuser', crypt.mksalt(crypt.METHOD_SHA512)))")
RUN useradd -m -s /bin/bash -p '$6$iUu38TfmLuVppHhS$8teMXk6O5q06bYqIM7D37NlrwrDu1lfW/TMKPFuvCv2auVj61mlICkMgoGSLdkOSWcKYXL2yKTOxpYR918h.g/' tnbuser && \
    echo "tnbuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    chown -R tnbuser:tnbuser /opt/tnb /opt/tnb-tests /deployments /artifacts-tests /var/log/tnb

# Set up systemd services for TNB
COPY systemd/tnb.service /etc/systemd/system/
COPY systemd/podman-tnbuser.service /etc/systemd/system/

# Set up tmpfiles.d configurations
# tnb-tests.conf: writable TNB tests directory (required because /opt is read-only in bootc/ostree)
# tnb-runtime.conf: user runtime directory for Podman socket
COPY config/tnb-tests.conf /usr/lib/tmpfiles.d/tnb-tests.conf
COPY config/tnb-runtime.conf /usr/lib/tmpfiles.d/tnb-runtime.conf

# Enable lingering for tnbuser (allows services to run without login)
# and create runtime directory
RUN TNB_UID=$(id -u tnbuser) && \
    mkdir -p /var/lib/systemd/linger && \
    touch /var/lib/systemd/linger/tnbuser && \
    mkdir -p /run/user/$TNB_UID/podman && \
    chown -R tnbuser:tnbuser /run/user/$TNB_UID && \
    chmod 700 /run/user/$TNB_UID

# Enable TNB services to run automatically on boot
RUN systemctl enable podman-tnbuser.service && \
    systemctl enable tnb.service

# Configure Podman for rootless containers (Testcontainers support)
RUN mkdir -p /home/tnbuser/.config/containers && \
    mkdir -p /run/user/$(id -u tnbuser) && \
    chown -R tnbuser:tnbuser /home/tnbuser/.config

# Copy Podman configuration for rootless mode
COPY config/containers.conf /etc/containers/containers.conf
COPY config/storage.conf /etc/containers/storage.conf

# Copy registry authentication for pulling images from authenticated registries
# This file should contain credentials for registry.redhat.io, quay.io, etc.
# Use git-crypt to encrypt this file in your repository for security
RUN mkdir -p /root/.config/containers /home/tnbuser/.config/containers
COPY --chown=root:root secrets/containers-auth.json /root/.config/containers/auth.json
COPY --chown=tnbuser:tnbuser secrets/containers-auth.json /home/tnbuser/.config/containers/auth.json
RUN chmod 600 /root/.config/containers/auth.json && \
    chmod 600 /home/tnbuser/.config/containers/auth.json

# Enable Podman socket for Testcontainers
RUN systemctl enable podman.socket

# Configure subuid/subgid for rootless containers
RUN echo "tnbuser:100000:65536" > /etc/subuid && \
    echo "tnbuser:100000:65536" > /etc/subgid

# Copy Maven settings and repository cache to tnbuser home
# This shares the downloaded dependencies with tnbuser to avoid re-downloading at runtime
RUN mkdir -p /home/tnbuser/.m2 && \
    cp /root/.m2/settings.xml /home/tnbuser/.m2/settings.xml && \
    if [ -d /root/.m2/repository ]; then \
        cp -r /root/.m2/repository /home/tnbuser/.m2/repository; \
    fi && \
    chown -R tnbuser:tnbuser /home/tnbuser/.m2

# Set DOCKER_HOST environment for Testcontainers to use Podman
RUN echo 'export DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock' >> /home/tnbuser/.bashrc && \
    echo 'export TESTCONTAINERS_RYUK_DISABLED=false' >> /home/tnbuser/.bashrc && \
    echo 'export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/run/user/$(id -u)/podman/podman.sock' >> /home/tnbuser/.bashrc

# Configure git for tnbuser (required for tests that clone repositories)
RUN su - tnbuser -c 'git config --global user.name "TNB User" && \
    git config --global user.email "tnbuser@localhost" && \
    git config --global init.defaultBranch main'

# Expose commonly used ports (adjust as needed)
EXPOSE 8080 8443

# Set working directory
WORKDIR /opt/tnb-tests

# Set entrypoint
ENTRYPOINT ["/scripts/entrypoint.sh"]
