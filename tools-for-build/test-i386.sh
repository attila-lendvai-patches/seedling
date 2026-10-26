#!/usr/bin/env bash

# Host: i386. The "i386" suffix names the assumed *host* architecture,
# not the target: this suite covers the i386 Seed and Sprout, the
# aarch64 Seed, and the amd64/i386 cross-checks the host supports.

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    echo "error: run this script, do not source it" >&2
    return 1
fi

source "$(dirname "${BASH_SOURCE[0]}")/test-common.sh"

if ! can_execute i386; then
    skip_note "i386 host suite skipped: $(runner_note i386)"
    exit 0
fi

BOOTSTRAP=$(bootstrap_for_host)
i386_suite
