#!/usr/bin/bash

set -eoux pipefail

###############################################################################
# Main Build Script - Ubuntu Edition (26.04 LTS "resolute")
###############################################################################
# Builds the final bootc image on top of the official Canonical Ubuntu 26.04
# LTS base (docker.io/library/ubuntu:resolute).
###############################################################################

export DEBIAN_FRONTEND=noninteractive

echo "::group:: Update apt and converge the base image"

# The official ubuntu:resolute base ships its full dpkg database in
# /var/lib/dpkg (unlike the old bootcrew base, which wiped /var). Every change
# below is therefore a normal apt transaction on top of that database, so the
# final image's package-manager state is coherent with /usr BY CONSTRUCTION -
# no state reconstruction, no archive-snapshot pinning.
apt-get update -y
apt-get upgrade -y \
    -o Dpkg::Options::=--force-confold \
    -o Dpkg::Options::=--force-confdef

echo "::endgroup::"

echo "::group:: Install kernel first (before desktop hooks exist)"

# The kernel is installed BEFORE the desktop stack on purpose. Configuring a
# linux-image package runs every /etc/kernel/postinst.d/ hook, and the desktop
# stack later pulls hooks that cannot run inside a build container:
#   - kdump-tools' hook calls mkinitramfs with a kdump-specific config and dies
#     with "mkinitramfs: failed to determine device for /", aborting the whole
#     apt transaction (dpkg: error processing package linux-image-...
#     postinst exit status 1)
#   - grub's zz-update-grub runs update-grub (device probing, also
#     container-hostile)
# When the kernel is configured first, the only hook present is dracut's, which
# works fine in a container (update-initramfs fronts to dracut when it is
# installed, and the dracut hook regenerates /boot/initrd.img without device
# probing). The desktop transaction later CONFIGURES initramfs-tools/
# kdump-tools/grub, but their configure-time postinsts are container-safe and
# no kernel package is configured then, so the hostile hooks never run.
apt-get install -y \
    -o Dpkg::Options::=--force-confold \
    -o Dpkg::Options::=--force-confdef \
    dracut \
    linux-firmware \
    linux-image-generic

echo "::endgroup::"

echo "::group:: Install bootc base and desktop packages"

# Base packages: the bootc plumbing and filesystem tooling the bootc installer
# needs. Ubuntu 26.04 uses dracut for the initramfs (see kernel step above).
#
# Desktop: ubuntu-desktop-minimal installed WITH its Recommends (the default),
# so you get exactly what a stock Ubuntu Desktop talks to - gnome-initial-setup
# for first-boot user creation, NetworkManager, snapd, fwupd, etc.
apt-get install -y \
    -o Dpkg::Options::=--force-confold \
    -o Dpkg::Options::=--force-confdef \
    btrfs-progs \
    dosfstools \
    e2fsprogs \
    fdisk \
    gnome-initial-setup \
    libostree-dev \
    openssh-server \
    ostree \
    skopeo \
    sudo \
    systemd \
    'systemd-boot*' \
    ubuntu-desktop-minimal \
    xfsprogs

echo "::endgroup::"

echo "::group:: Drop crash-dump tooling"

# kdump-tools pairs a crash-dump service with a reserved crash-kernel boot
# argument (/etc/default/grub.d/kdump-tools.cfg) - not wanted on a
# daily-driver desktop. Purging also removes its /etc/kernel/postinst.d/
# hook, so a future manual kernel install won't regenerate a kdump initrd
# (kernels are held anyway, see next block). Its postrm touches no initramfs
# machinery, so this is clean.
if dpkg-query -s kdump-tools >/dev/null 2>&1; then
    apt-get purge -y kdump-tools
fi

echo "::endgroup::"

echo "::group:: Hold bootc kernel packages"

# The image boots from the kernel + dracut initramfs baked into
# /usr/lib/modules/<kver>/. If apt ever installs or replaces a kernel package
# on the booted system, its postinst would regenerate the initramfs WITHOUT
# the bootc dracut module (and could write to /boot, which bootc requires to
# stay empty) - producing an unbootable system. Hold every installed linux-*
# package for the life of this image; kernel updates belong in the base image
# rebuild, not in a derived apt system.
# linux-firmware is excluded: it is plain firmware blobs and can keep updating.
set +e
kernel_packages=$(dpkg-query -W -f='${Package}\n' 'linux-*' 2>/dev/null | grep -v '^linux-firmware$')
set -e
if [ -n "$kernel_packages" ]; then
    echo "$kernel_packages" | xargs -r apt-mark hold
fi
apt-mark showhold

echo "::endgroup::"

echo "::group:: Bootstrap boot files"

# linux-image postinst normally publishes vmlinuz into /usr/lib/modules/<kver>/
# on Ubuntu 6.8+; make it explicit and idempotent. The real boot files live in
# /usr/lib/modules - bootc copies them to /boot at deploy time.
kernel_dir=$(basename "$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)")
echo "Baked kernel directory: $kernel_dir"

# linux-image postinst publishes vmlinuz into /usr/lib/modules/<kver>/ on
# Ubuntu 6.8+; make it explicit and idempotent in case it did not.
if [ -f "/boot/vmlinuz-$kernel_dir" ]; then
    cp -av "/boot/vmlinuz-$kernel_dir" "/usr/lib/modules/$kernel_dir/vmlinuz"
fi
test -f "/usr/lib/modules/$kernel_dir/vmlinuz" || { echo "ERROR: no vmlinuz for $kernel_dir" >&2; exit 1; }

# Generate the bootc initramfs (dracut module 51bootc from the builder stage).
/ctx/shared/initramfs.sh

# Kernel/desktop postinsts (and dracut) write boot files to /boot; bootc
# requires /boot to stay EMPTY in the image.
if [ -d /boot ]; then
    find /boot -mindepth 1 -delete
fi

# Don't bake downloaded package archives into the image
apt-get clean

echo "::endgroup::"

echo "::group:: System configuration"

# First user: the image ships with no user accounts, so on first boot GDM runs
# the gnome-initial-setup "create your account" wizard (it is a Recommends of
# ubuntu-desktop-minimal and installed explicitly above). Nothing else is
# needed to provision a day-one desktop user.

# New users should start in the persistent /var home: bootc keeps /var across
# deployments and /home is bind-mounted from /var/home (see
# shared/bootc-rootfs.sh).
grep -q '^HOME=' /etc/default/useradd || echo 'HOME=/var/home' >> /etc/default/useradd

# DNS through systemd-resolved (NetworkManager from the desktop stack feeds it)
mkdir -p /usr/lib/tmpfiles.d
printf 'L! /etc/resolv.conf - - - - /run/systemd/resolve/stub-resolv.conf\n' > /usr/lib/tmpfiles.d/resolved-fix.conf

# Enable the services the image should boot with. The desktop stack (GDM) is
# enabled by its package postinst; wire up the rest explicitly.
mkdir -p /etc/systemd/system/multi-user.target.wants
for unit in \
    ssh.service \
    systemd-resolved.service \
    NetworkManager.service; do
    ln -sf "/usr/lib/systemd/system/$unit" "/etc/systemd/system/multi-user.target.wants/$unit"
done
ln -sf /usr/lib/systemd/system/gdm.service /etc/systemd/system/display-manager.service

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

echo "::group:: Convert to bootc root layout"

# bootc/ostree + composefs layout. Keeps /var/lib (dpkg/apt) - see the big
# comment at the top of shared/bootc-rootfs.sh.
/ctx/shared/bootc-rootfs.sh

echo "::endgroup::"

echo "::group:: Final sanity checks"

test -x /usr/bin/dpkg || { echo "ERROR: dpkg missing" >&2; exit 1; }
dpkg-query -W -f='${Package} ${Status}\n' linux-image-generic
test -f "/usr/lib/modules/$kernel_dir/vmlinuz" || { echo "ERROR: vmlinuz missing for $kernel_dir" >&2; exit 1; }
test -f "/usr/lib/modules/$kernel_dir/initramfs.img" || { echo "ERROR: initramfs.img missing for $kernel_dir" >&2; exit 1; }
if [ -d /boot ]; then
    [ -z "$(find /boot -mindepth 1 -print -quit)" ] || { echo "ERROR: /boot is not empty" >&2; exit 1; }
fi

echo "::endgroup::"

echo "Custom build complete!"
echo
echo "  Kernel:        $kernel_dir"
echo "  dpkg state:    $(dpkg-query -W -f='${Status}' linux-image-generic)"
echo "  Bootc:         $(bootc --version | head -n 1)"