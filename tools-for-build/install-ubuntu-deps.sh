#!/bin/sh
#
# The Ubuntu packages the suite needs. This is the one list: CI, the
# CI image, and a human setting up a machine all use it.
#
# Not a Debian-only list, but the package names are Ubuntu's.

set -eu

apt_flags=
case "${1:-}" in
    --no-install-recommends)  apt_flags=--no-install-recommends ;;
    "")                       ;;
    *)                        echo "usage: $0 [--no-install-recommends]" >&2; exit 2 ;;
esac

if [ "$(id -u)" != 0 ]; then
    echo "run as root: sudo $0" >&2
    exit 1
fi

# qemu-user provides the qemu-<arch> binaries the suite runs foreign
# targets with; the suite prefixes them, so no binfmt handler is
# consulted. qemu-user-binfmt covers the one path the kernel handles
# itself: 32-bit x86 binaries on an amd64 machine without 32-bit
# support. 24.04 also ships qemu-user-static, 26.04 dropped it, so
# qemu-user is the name both releases share.
packages="
  qemu-user qemu-user-binfmt elfutils libz80ex-dev
  build-essential git
"

export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"

apt-get update
# shellcheck disable=SC2086 # intentional word splitting
apt-get install -y $apt_flags $packages
