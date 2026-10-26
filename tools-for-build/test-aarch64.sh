#!/usr/bin/env bash

# Host: aarch64. The "aarch64" suffix names the assumed *host*
# architecture, not the target: this suite cross-compiles to every
# Seed and Sprout port.

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    echo "error: run this script, do not source it" >&2
    return 1
fi

source "$(dirname "${BASH_SOURCE[0]}")/test-common.sh"

if ! can_execute aarch64; then
    skip_note "aarch64 host suite skipped: $(runner_note aarch64)"
    exit 0
fi

BOOTSTRAP="$BOOTSTRAP_AARCH64"
host_suite "$BOOTSTRAP"
