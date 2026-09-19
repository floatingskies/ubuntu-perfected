#!/usr/bin/bash

set -eoux pipefail

###############################################################################
# Main Build Script - Ubuntu Edition
###############################################################################
# This script installs ubuntu-desktop and configures the system
###############################################################################

echo "::group:: Recreate apt state"

# The bootc base image ships an EMPTY /var (bootcrew's build wipes /var and
# recreates the standard base directories at boot via tmpfiles.d), so apt has
# no lists to work with and `apt-get update` dies with:
#   E: List directory /var/lib/apt/lists/partial is missing.
# The dpkg database itself was already restored by the Containerfile
# (COPY --from=apt-state /var/lib/dpkg /var/lib/dpkg); here we just recreate
# the apt lists directory.
mkdir -p /var/lib/apt/lists/partial

export DEBIAN_FRONTEND=noninteractive

echo "::endgroup::"

echo "::group:: Verify dpkg state matches /usr"

# The imported dpkg database was pinned to the archive snapshot matching the
# base image's /usr (see the APT_SNAPSHOT arg in the Containerfile). Sanity
# check that the kernel recorded in the database lines up with the kernel
# actually baked into the image. If the bootcrew base is ever rebuilt with a
# newer /usr, this fails and APT_SNAPSHOT must be bumped to the archive state
# matching the new base.
kernel_dir=$(basename "$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)")
# kernel_dir is e.g. "6.17.0-41-generic"; strip the flavor to get the ABI that
# the linux-image-generic meta package version also carries (6.17.0-41.41).
kernel_abi=${kernel_dir%-generic}
recorded_kernel=$(dpkg-query -W -f='${Version}' linux-image-generic)
case "$recorded_kernel" in
    "$kernel_abi".*) : ;;
    *)
        echo "ERROR: dpkg database kernel ($recorded_kernel) does not match image kernel ($kernel_dir)." >&2
        echo "Bump APT_SNAPSHOT in the Containerfile to the matching archive state and rebuild." >&2
        exit 1
        ;;
esac
echo "dpkg database matches image kernel: $recorded_kernel / $kernel_dir"

echo "::endgroup::"

echo "::group:: Hold bootc kernel packages"

# The bootc image boots from the kernel + dracut initramfs baked into
# /usr/lib/modules/<kver>/. If apt ever installs or replaces a kernel package,
# its postinst would regenerate the initramfs WITHOUT the bootc dracut module
# (and could write to /boot, which bootc requires to stay empty) - producing an
# unbootable system. Hold every installed linux-* package for the life of this
# image; kernel updates belong in the base image, not in a derived apt system.
# linux-firmware is excluded: it is plain firmware blobs and can keep updating.
set +e
kernel_packages=$(dpkg-query -W -f='${Package}\n' 'linux-*' 2>/dev/null | grep -v '^linux-firmware$')
set -e
if [ -n "$kernel_packages" ]; then
    echo "$kernel_packages" | xargs -r apt-mark hold
fi
apt-mark showhold

echo "::endgroup::"

echo "::group:: Upgrade base packages to current"

# The base image freezes its /usr at the archive snapshot pinned by
# APT_SNAPSHOT (their build state). Bring everything else up to the current
# archive so the image ships as up to date as possible. Kernel packages are
# held above, so this can never touch the bootc kernel/initramfs.
apt-get upgrade -y

echo "::endgroup::"

echo "::group:: Install Ubuntu Desktop"

# Install ubuntu-desktop
apt-get install -y ubuntu-desktop-minimal

# A couple of desktop packages (e.g. initramfs-tools) may write kernel/initramfs
# images into /boot during their postinst. bootc requires /boot to stay EMPTY
# in the image - the real boot files live in /usr/lib/modules and bootc copies
# them to /boot at deploy time. Clean up anything that leaked in.
find /boot -mindepth 1 -delete 2>/dev/null || true

# Don't bake downloaded package archives into the image
apt-get clean

echo "::endgroup::"

echo "::group:: Copy Custom Files"

# Copy Brewfiles to standard location (if using homebrew)
mkdir -p /usr/share/ublue-os/homebrew/
if [ -d /ctx/custom/brew ]; then
    cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/ 2>/dev/null || true
fi

# Consolidate Just Files (if using ujust)
mkdir -p /usr/share/ublue-os/just/
if [ -d /ctx/custom/ujust ]; then
    find /ctx/custom/ujust -iname '*.just' -exec printf "\n\n" \; -exec cat {} \; >> /usr/share/ublue-os/just/60-custom.just 2>/dev/null || true
fi

# Copy Flatpak preinstall files (if using flatpak)
mkdir -p /etc/flatpak/preinstall.d/
if [ -d /ctx/custom/flatpaks ]; then
    cp /ctx/custom/flatpaks/*.preinstall /etc/flatpak/preinstall.d/ 2>/dev/null || true
fi

echo "::endgroup::"

echo "::group:: System Configuration"

# Enable/disable systemd services as needed
# Example: systemctl enable podman.socket
# Example: systemctl mask unwanted-service

echo "::endgroup::"

echo "Custom build complete!"
