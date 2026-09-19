#!/usr/bin/env bash

set -xeuo pipefail

# Generate the bootc initramfs with dracut.
#
# The bootc dracut module (installed by `make install-all` in the builder
# stage, into /usr/lib/dracut/modules.d/51bootc) is what lets the initramfs
# hand off to ostree/composefs at boot; without it the image is not bootable
# as a bootc deployment. `hostonly=no` keeps the initramfs generic so the
# image can deploy to any machine.
#
# Upstream: jmarrero/ubuntu-bootc shared/initramfs.sh (Apache-2.0, (c) tulilirockz)
mkdir -p /usr/lib/dracut/dracut.conf.d/
printf "systemdsystemconfdir=/etc/systemd/system\nsystemdsystemunitdir=/usr/lib/systemd/system\n" > /usr/lib/dracut/dracut.conf.d/30-bootcrew-fix-bootc-module.conf
printf 'reproducible=yes\nhostonly=no\ncompress=zstd\nadd_dracutmodules+=" bootc "' > /usr/lib/dracut/dracut.conf.d/30-bootcrew-bootc-container-build.conf

dracut --force "$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d ! -name '*.img' | sort | tail -n 1)/initramfs.img"