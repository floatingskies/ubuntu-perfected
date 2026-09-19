# syntax=docker/dockerfile:1

###############################################################################
# Build context - scripts and units are made available to build stages without
# ever being copied into the final image.
###############################################################################
FROM scratch AS ctx
COPY build /build
COPY custom /custom
COPY shared /shared
COPY usr /usr

###############################################################################
# Base image
###############################################################################
# Official Canonical Ubuntu 26.04 LTS ("Resolute Raccoon") container image.
# Canonical rebuilds it regularly, and - unlike the old bootcrew base - it
# ships its full dpkg/apt state in /var, so package management works natively
# on the booted system and the image's apt/dpkg state stays coherent with /usr
# by construction (no state reconstruction, no archive snapshot pinning).
#
# To pin a dated tag for reproducible builds, change this ONE line to e.g.
#   FROM docker.io/library/ubuntu:resolute-20260912 AS base
FROM docker.io/library/ubuntu:resolute AS base

###############################################################################
# Stage 1: compile bootc from upstream source
###############################################################################
# Ubuntu ships no bootc package, so we compile the current upstream bootc.
# Building from current source matters: it includes the composefs-rs fix for
# PAX-format tar headers (https://github.com/composefs/composefs-rs/pull/292)
# which is required to install Ubuntu 26.04 images built with Canonical's
# Rockcraft/umoci tooling.
FROM base AS builder

ARG DEBIAN_FRONTEND=noninteractive

# libclang-dev + libselinux1-dev are required to compile bootc's selinux-sys
# dependency (bindgen generates the C bindings against libclang and the
# selinux headers).
RUN --mount=type=tmpfs,dst=/tmp --mount=type=tmpfs,dst=/root --mount=type=tmpfs,dst=/boot \
    apt-get update -y && \
    apt-get install -y git curl make build-essential go-md2man libzstd-dev pkgconf libostree-dev ostree libclang-dev libselinux1-dev

ENV CARGO_HOME=/tmp/rust \
    RUSTUP_HOME=/tmp/rust

WORKDIR /home/build

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile minimal -y && \
    sh -c ". ${RUSTUP_HOME}/env && /ctx/shared/build.sh"

###############################################################################
# Stage 2: final system image
###############################################################################
FROM base AS system

ARG DEBIAN_FRONTEND=noninteractive

# bootc binaries, systemd units, bootc-systemd-generator and the 51bootc
# dracut module (installed by `make install-all` in the builder stage)
COPY --from=builder /output /

# snap-compatibility bind-mount units (see shared/bootc-rootfs.sh)
COPY usr/ /usr/

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/10-build.sh

LABEL containers.bootc 1

# Verify the final image satisfies bootc's container requirements
RUN bootc container lint