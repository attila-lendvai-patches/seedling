#!/usr/bin/env bash

# Host: amd64. The "amd64" suffix names the assumed *host*
# architecture, not the target: this suite cross-compiles to every
# Seed and Sprout port.

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    echo "error: run this script, do not source it" >&2
    return 1
fi

source "$(dirname "${BASH_SOURCE[0]}")/test-common.sh"

BOOTSTRAP="$BOOTSTRAP_AMD64"
host_suite "$BOOTSTRAP"
