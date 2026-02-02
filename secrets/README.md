# Registry Authentication for TNB Tests

This directory contains registry authentication credentials needed for pulling container images during tests.

## Setup Instructions

### Option 1: Using git-crypt (Recommended)

1. **Install git-crypt**:
   ```bash
   sudo dnf install git-crypt
   ```

2. **Initialize git-crypt** (if not already done):
   ```bash
   git-crypt init
   git-crypt export-key ~/.git-crypt-key
   # Save this key securely! You'll need it to decrypt on other machines
   ```

3. **Create your auth file**:
   ```bash
   # Generate base64 credentials
   echo -n "your-username:your-password" | base64

   # Create auth.json with your credentials
   cp secrets/containers-auth.json.template secrets/containers-auth.json
   # Edit secrets/containers-auth.json and replace placeholders with your base64 credentials
   ```

4. **Configure git-crypt** (if not already configured):
   ```bash
   # Add to .gitattributes
   echo "secrets/containers-auth.json filter=git-crypt diff=git-crypt" >> .gitattributes

   # Verify encryption status
   git-crypt status
   ```

5. **Commit the encrypted file**:
   ```bash
   git add secrets/containers-auth.json .gitattributes
   git commit -m "Add encrypted registry credentials"
   ```

### Option 2: Using Host Credentials (Development Only)

For local development, you can copy your existing podman credentials:

```bash
# If you're already logged in to registries on your host
cp ~/.config/containers/auth.json secrets/containers-auth.json
```

**WARNING**: Don't commit this file without encryption!

### Option 3: Generate During Build

You can also log in during the image build (less secure, credentials in build logs):

Edit `Containerfile` and add before the COPY command:
```dockerfile
RUN podman login -u USERNAME -p PASSWORD registry.redhat.io
RUN podman login -u USERNAME -p PASSWORD quay.io
```

## Required Registries

The TNB test suite needs authentication for:

- **registry.redhat.io** - Red Hat container registry (requires Red Hat account)
- **quay.io** - Quay.io registry (may need account for private images)

## Getting Base64 Credentials

```bash
# For registry.redhat.io
echo -n "your-redhat-username:your-password" | base64

# For quay.io
echo -n "your-quay-username:your-token" | base64
```

Copy the output and paste into `containers-auth.json` as the `auth` value.

## Verifying

After building the image, verify credentials work in the VM:

```bash
# In the VM
podman login --get-login registry.redhat.io
podman login --get-login quay.io

# Test pulling an image
podman pull registry.redhat.io/amq7/amq-broker-rhel8:7.12.3
```

## Security Notes

- **Never commit unencrypted credentials** to git
- Use git-crypt or similar encryption for the auth.json file
- Keep your git-crypt key secure and backed up
- Rotate credentials periodically
- Use tokens/service accounts instead of personal passwords when possible
