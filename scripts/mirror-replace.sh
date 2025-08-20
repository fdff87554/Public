#!/bin/bash
#
# Automatically detects system architecture (amd64/arm64) and replaces the
# APT source with a specified mirror, ensuring the setting is permanent.
# Version: 2.0 (Multi-Arch)

# set -e: Exit immediately if a command exits with a non-zero status.
# set -u: Treat unset variables as an error when substituting.
set -eu

# --- Variables ---
# Define the base URI for the new mirror.
# This mirror MUST support both 'ubuntu/' and 'ubuntu-ports/' paths.
NEW_MIRROR_BASE_URI="https://mirror.twds.com.tw"

SOURCES_FILE="/etc/apt/sources.list.d/ubuntu.sources"
CLOUD_CONFIG_FILE="/etc/cloud/cloud.cfg"


# --- Pre-flight Checks ---

# 1. Ensure the script is run as root.
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# 2. Ensure the target source file exists.
if [ ! -f "$SOURCES_FILE" ]; then
    echo "Error: Source file '$SOURCES_FILE' not found. Aborting." >&2
    exit 1
fi


# --- Architecture Detection and Configuration ---

ARCH=$(dpkg --print-architecture)
DEFAULT_MIRROR_URI=""
NEW_MIRROR_URI=""

case "$ARCH" in
    arm64)
        echo "Info: Detected arm64 architecture."
        DEFAULT_MIRROR_URI="http://ports.ubuntu.com/ubuntu-ports"
        NEW_MIRROR_URI="${NEW_MIRROR_BASE_URI}/ubuntu-ports"
    ;;
    amd64)
        echo "Info: Detected amd64 architecture."
        # Note: The default URI for amd64 can sometimes be country-specific (e.g., tw.archive.ubuntu.com).
        # This script targets the most common canonical URI 'archive.ubuntu.com'.
        DEFAULT_MIRROR_URI="http://archive.ubuntu.com/ubuntu"
        NEW_MIRROR_URI="${NEW_MIRROR_BASE_URI}/ubuntu"
    ;;
    *)
        echo "Error: Unsupported architecture '$ARCH'. This script only supports arm64 and amd64." >&2
        exit 1
    ;;
esac


# --- Idempotency & Sanity Checks (using arch-specific variables) ---

# 3. Idempotency check: Exit if the mirror is already set.
if grep -qF "$NEW_MIRROR_URI" "$SOURCES_FILE"; then
    echo "Info: Mirror is already set to '$NEW_MIRROR_URI'. No changes needed."
    exit 0
fi

# 4. Sanity check: Ensure the default mirror is present before trying to replace it.
if ! grep -qF "$DEFAULT_MIRROR_URI" "$SOURCES_FILE"; then
    echo "Error: Default mirror '$DEFAULT_MIRROR_URI' not found in $SOURCES_FILE." >&2
    echo "The file might have been already modified. Aborting for safety." >&2
    exit 1
fi


# --- Core Operations ---

echo "Updating APT source mirror for $ARCH..."

# Prevent cloud-init from overwriting the changes on reboot.
if ! grep -qFx 'apt_preserve_sources_list: true' "$CLOUD_CONFIG_FILE"; then
    echo 'apt_preserve_sources_list: true' >> "$CLOUD_CONFIG_FILE"
fi

# Replace the mirror URI. A backup of the original file is created with a .bak extension.
sed -i.bak "s|$DEFAULT_MIRROR_URI|$NEW_MIRROR_URI|g" "$SOURCES_FILE"

# Update the APT package list from the new mirror.
echo "Updating APT package list..."
apt-get update

echo "Operation completed successfully."

exit 0