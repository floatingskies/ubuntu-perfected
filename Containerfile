# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build /build
COPY custom /custom

###############################################################################
# DPKG-STATE RECONSTRUCTION
###############################################################################
# The bootcrew base image wipes /var at build time (see bootcrew/mono
# shared/bootc-rootfs.sh) - including the ENTIRE dpkg database. The published
# image therefore has no apt/dpkg state, which made the first build-unblocking
# attempts produce an image where:
#   - `apt list --installed` was garbage (only the desktop closure known),
#   - reinstalling base packages reset their conffiles to package defaults
#     (e.g. /etc/default/useradd lost HOME=/var/home), and
#   - host-side `apt upgrade` could not work safely.
#
# This stage rebuilds a dpkg database that EXACTLY matches the packages baked
# into the base image's /usr, by replaying bootcrew's base build recipe
# (see https://github.com/bootcrew/ubuntu-bootc Containerfile) against the
# Ubuntu archive snapshot that matches the base /usr content. The base's
# kernel (linux-image 6.17.0-41-generic), systemd (257.9-0ubuntu2.5) and
# openssh (1:10.0p1-5ubuntu5.4) all match the archive as of
# 2026-07-22T00:00:00Z, so APT_SNAPSHOT defaults to that archive state.
#
# If the bootcrew base is ever rebuilt with a NEWER /usr, APT_SNAPSHOT must be
# bumped to the archive state matching it. The coherence check in
# build/10-build.sh fails the build loudly if the pin has gone stale.
#
# Only /var/lib/dpkg is imported from this stage (below); nothing else from it
# ends up in the image.
ARG APT_SNAPSHOT=20260722T000000Z

FROM docker.io/library/ubuntu:questing AS apt-state
ARG APT_SNAPSHOT
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=tmpfs,dst=/tmp --mount=type=tmpfs,dst=/boot \
    if [ -n "$APT_SNAPSHOT" ]; then \
      printf 'APT::Snapshot "%s";\n' "$APT_SNAPSHOT" > /etc/apt/apt.conf.d/50snapshot; \
    fi && \
    apt-get update -y && \
    apt-get install -y btrfs-progs dosfstools e2fsprogs fdisk linux-firmware linux-image-generic skopeo systemd systemd-boot* xfsprogs && \
    apt-get install -y git curl make build-essential go-md2man libzstd-dev pkgconf dracut libostree-dev ostree && \
    apt-get purge -y git curl make build-essential go-md2man libzstd-dev pkgconf libostree-dev && \
    apt-get autoremove -y && \
    apt-get clean -y

###############################################################################
# PROJECT NAME CONFIGURATION
###############################################################################
# Name: ubuntu-perfected
#
# IMPORTANT: Change "ubuntu-perfected" above to your desired project name.
# This name should be used consistently throughout the repository in:
#   - Justfile: export image_name := env("IMAGE_NAME", "your-name-here")
#   - README.md: # your-name-here (title)
#   - artifacthub-repo.yml: repositoryID: your-name-here
#   - custom/ujust/README.md: localhost/your-name-here:stable (in bootc switch example)
#
# The project name defined here is the single source of truth for your
# custom image's identity. When changing it, update all references above
# to maintain consistency.
###############################################################################

# Base Image - Ubuntu bootc
FROM ghcr.io/bootcrew/ubuntu-bootc:latest

## This image is based on Ubuntu bootc, providing a bootable container image
## based on Ubuntu instead of Fedora-based distributions.
##
## Ubuntu bootc images: https://github.com/bootcrew/ubuntu-bootc

### /opt
## Some bootable images have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build scripts
## the following RUN directive does all the things required to run scripts as recommended.
## Scripts are run in numerical order (10-build.sh, 20-example.sh, etc.)

# Import the dpkg database reconstructed by the apt-state stage above. This
# makes apt/dpkg fully coherent with the base image's /usr: package installs
# become upgrades (preserving the base's conffile customizations), and host
# side `apt upgrade` works like on a regular Ubuntu machine.
COPY --from=apt-state /var/lib/dpkg /var/lib/dpkg

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/10-build.sh
    
### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
