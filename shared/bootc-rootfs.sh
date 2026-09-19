#!/usr/bin/env bash

set -xeuo pipefail

# Convert the container root into the bootc/ostree + composefs root layout.
#
# Based on bootcrew/mono's shared/bootc-rootfs.sh (Apache-2.0,
# (c) tulilirockz) with two deliberate changes:
#
#  1. /var is NOT wiped. The upstream scripts `rm -rf /var`, which deletes the
#     dpkg/apt state baked into the official Ubuntu base image and leaves the
#     deployed system with no working package manager. We prune only volatile
#     data and keep /var/lib (dpkg + apt lists), so the deployed host has a
#     fully coherent apt/dpkg state that matches /usr.
#
#  2. /home, /root, /opt, /mnt and /srv are real directories bound from their
#     /var counterparts by systemd *.mount units (snap-compatible layout from
#     jmarrero/ubuntu-bootc, Apache-2.0). snap-confine cannot rbind-mount
#     through symlinks on composefs.

# Prune volatile state only - dpkg/apt state in /var/lib must survive.
rm -rf /var/cache/* /var/log/* /var/tmp/* /var/backups/* /var/crash

# The directories that bootc's layout expects; the bootc var subdirs double as
# the targets of the snap-compat bind mounts.
mkdir -p \
    /sysroot /boot /usr/lib/ostree \
    /var/lib /var/log /var/cache /var/tmp \
    /var/opt /var/home /var/srv /var/mnt /var/usrlocal /var/roothome /var/crash \
    /var/lib/apt/lists/partial \
    /var/lib/snapd/snap /var/cache/snapd /var/snap \
    /home /root /opt /mnt /srv /snap /run/media

# Only /ostree and /usr/local remain symlinks; the rest are real directories
# backed by the systemd bind-mount units in usr/lib/systemd/system/.
ln -sT sysroot/ostree /ostree
ln -sT ../var/usrlocal /usr/local

# Recreate the bootc var subdirs on every boot as well (tmpfiles), together
# with the snapd writable paths.
printf 'd /var/lib/snapd 0755 root root -\nd /var/cache/snapd 0755 root root -\nd /var/snap 0755 root root -\n' > /usr/lib/tmpfiles.d/bootc-base-dirs.conf
for dir in opt home srv mnt usrlocal; do
    printf "d /var/%s 0755 root root -\n" "$dir" >> /usr/lib/tmpfiles.d/bootc-base-dirs.conf
done
printf 'd /var/roothome 0700 root root -\nd /run/media 0755 root root -\n' >> /usr/lib/tmpfiles.d/bootc-base-dirs.conf

# composefs-backed, read-only sysroot
printf '[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n' > /usr/lib/ostree/prepare-root.conf

# snap-compat bind mounts (units shipped into /usr by the Containerfile)
systemctl enable snap.mount home.mount root.mount opt.mount mnt.mount srv.mount