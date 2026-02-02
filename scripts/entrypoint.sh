#!/bin/bash

echo "Starting TNB Bootable Image..."
echo "================================"
echo "JAVA_HOME: ${JAVA_HOME}"
echo "MAVEN_HOME: ${MAVEN_HOME}"
echo "TNB_HOME: ${TNB_HOME} (pre-built)"
echo "TNB_TESTS_HOME: ${TNB_TESTS_HOME}"
echo "Maven: Configured with TNB settings"
echo "Repositories: Verified during build"
echo "================================"

# Verify Java installation
java -version

# Verify Maven installation
mvn --version

# For bootc image mode, we need to start systemd
exec /usr/sbin/init
