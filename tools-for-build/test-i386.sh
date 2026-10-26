#!/usr/bin/env bash

# Host: i386. The "i386" suffix names the assumed *host* architecture,
# not the target: this suite covers the i386 Seed and Sprout, the
# aarch64 Seed, and the amd64/i386 cross-checks the host supports.

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    echo "error: run this script, do not source it" >&2
    return 1
fi

source "$(dirname "${BASH_SOURCE[0]}")/test-common.sh"

BOOTSTRAP="$BOOTSTRAP_AMD64"
i386_suite
