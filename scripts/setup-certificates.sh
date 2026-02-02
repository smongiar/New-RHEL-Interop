#!/bin/bash
set -e

echo "Setting up certificates..."

# Import Red Hat 2022 IT Root CA certificate
echo "Importing Red Hat 2022 IT Root CA..."
if curl -sk https://certs.corp.redhat.com/certs/2022-IT-Root-CA.pem -o /etc/pki/ca-trust/source/anchors/RH-IT-Root-CA.crt; then
    echo "Red Hat IT Root CA downloaded successfully"
else
    echo "WARNING: Could not download Red Hat IT Root CA (this is optional)"
fi

# Import Nexus SSL certificate (optional)
echo "Importing Nexus SSL certificate..."

# Fetch certificate directly from Nexus server using openssl
NEXUS_HOST="repository.engineering.redhat.com"
NEXUS_PORT="443"

echo "Fetching SSL certificate from ${NEXUS_HOST}:${NEXUS_PORT}..."
if echo | openssl s_client -connect ${NEXUS_HOST}:${NEXUS_PORT} -servername ${NEXUS_HOST} 2>/dev/null | openssl x509 -outform PEM > /tmp/nexus-ssl.crt 2>/dev/null; then
    # Validate that we got a valid certificate
    if openssl x509 -in /tmp/nexus-ssl.crt -noout -subject 2>/dev/null; then
        echo "Nexus SSL certificate retrieved successfully"
        openssl x509 -in /tmp/nexus-ssl.crt -noout -subject -issuer

        # Import into system trust store
        cp /tmp/nexus-ssl.crt /etc/pki/ca-trust/source/anchors/nexus-ssl.crt
        echo "Nexus SSL certificate copied to system trust store"
    else
        echo "WARNING: Could not validate Nexus SSL certificate"
        echo "Continuing without Nexus certificate (Maven may still work with system CAs)"
    fi
else
    echo "WARNING: Could not fetch Nexus SSL certificate from ${NEXUS_HOST}"
    echo "Continuing without Nexus certificate (Maven may still work with system CAs)"
fi

# Import GitLab SSL certificate (required for TNB-tests clone)
echo "Importing GitLab SSL certificate..."

GITLAB_HOST="gitlab.cee.redhat.com"
GITLAB_PORT="443"

echo "Fetching SSL certificate from ${GITLAB_HOST}:${GITLAB_PORT}..."
if echo | openssl s_client -connect ${GITLAB_HOST}:${GITLAB_PORT} -servername ${GITLAB_HOST} 2>/dev/null | openssl x509 -outform PEM > /tmp/gitlab-ssl.crt 2>/dev/null; then
    # Validate that we got a valid certificate
    if openssl x509 -in /tmp/gitlab-ssl.crt -noout -subject 2>/dev/null; then
        echo "GitLab SSL certificate retrieved successfully"
        openssl x509 -in /tmp/gitlab-ssl.crt -noout -subject -issuer

        # Import into system trust store
        cp /tmp/gitlab-ssl.crt /etc/pki/ca-trust/source/anchors/gitlab-ssl.crt
        echo "GitLab SSL certificate copied to system trust store"
    else
        echo "WARNING: Could not validate GitLab SSL certificate"
    fi
else
    echo "WARNING: Could not fetch GitLab SSL certificate from ${GITLAB_HOST}"
fi

# Update system-wide CA trust store (this also updates Java's trust store)
echo "Updating system CA trust store..."
update-ca-trust

# Verify Java will use the system trust store
if command -v keytool &> /dev/null; then
    echo "Java keytool is available"
    # In RHEL 10, Java uses /etc/pki/java/cacerts which is linked to system trust
    if [ -f /etc/pki/java/cacerts ]; then
        echo "Java cacerts found at /etc/pki/java/cacerts (system-wide trust store)"
    fi
fi

# Cleanup
rm -f /tmp/nexus-ssl.crt /tmp/gitlab-ssl.crt

echo "Certificate setup completed successfully"
