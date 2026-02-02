#!/bin/bash
set -e

echo "Setting up Apache Maven..."

MAVEN_VERSION="3.9.10"
MAVEN_URL="https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"

# Download and install Apache Maven
echo "Downloading Apache Maven ${MAVEN_VERSION}..."
if curl -fsSL "${MAVEN_URL}" -o /tmp/maven.tar.gz; then
    echo "Maven downloaded successfully ($(du -h /tmp/maven.tar.gz | cut -f1))"
else
    echo "ERROR: Failed to download Maven from ${MAVEN_URL}"
    exit 1
fi

echo "Extracting Maven to /opt/..."
if tar -xzf /tmp/maven.tar.gz -C /opt/; then
    echo "Maven extracted successfully"
else
    echo "ERROR: Failed to extract Maven archive"
    exit 1
fi

# Check if the expected directory exists
if [ -d "/opt/apache-maven-${MAVEN_VERSION}" ]; then
    echo "Found /opt/apache-maven-${MAVEN_VERSION}"

    # Remove /opt/maven if it exists
    if [ -d "/opt/maven" ]; then
        echo "Removing existing /opt/maven directory"
        rm -rf /opt/maven
    fi

    mv /opt/apache-maven-${MAVEN_VERSION} /opt/maven
    echo "Renamed to /opt/maven"
else
    echo "ERROR: Expected directory /opt/apache-maven-${MAVEN_VERSION} not found"
    ls -la /opt/
    exit 1
fi

# Verify mvn binary exists
if [ -f /opt/maven/bin/mvn ]; then
    echo "Maven binary found at /opt/maven/bin/mvn"
else
    echo "ERROR: Maven binary not found at /opt/maven/bin/mvn"
    ls -laR /opt/maven
    exit 1
fi

rm -f /tmp/maven.tar.gz

# Copy TNB Maven settings from config
echo "Configuring Maven with TNB settings..."
mkdir -p /root/.m2
if [ -f /config/settings-tnb.xml ]; then
    cp /config/settings-tnb.xml /root/.m2/settings.xml
    echo "Maven settings copied successfully"
else
    echo "WARNING: /config/settings-tnb.xml not found, Maven will use defaults"
fi

echo "Maven setup completed successfully"
echo "Configured repositories (active profiles):"
echo "  - FuseQE Nexus (fuse-all)"
echo "  - JBoss QA Releases"
echo "  - Red Hat GA"
echo "  - TNB Main"
echo "  - Mirror: RH Maven Central Proxy"
echo ""
echo "Maven version:"
/opt/maven/bin/mvn --version
