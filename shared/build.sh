#!/usr/bin/env bash

set -xeuo pipefail

# Compile bootc from the current upstream source and install it into /output
# (the filesystem of the final system stage).
#
# Ubuntu ships no bootc package, and building from current source is what pulls
# in the composefs-rs PAX-tar parsing fix needed to install Ubuntu 26.04 images
# (Canonical builds them with Rockcraft/umoci, which emits PAX headers).
# See: https://github.com/composefs/composefs-rs/pull/292
#
# Upstream: jmarrero/ubuntu-bootc shared/build.sh (Apache-2.0, (c) tulilirockz)
git clone "https://github.com/bootc-dev/bootc.git" .

make bin install-all DESTDIR=/output