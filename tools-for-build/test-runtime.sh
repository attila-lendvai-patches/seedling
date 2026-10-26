#!/usr/bin/env bash

# Run the runtime probes against a freshly built Seed or Sprout binary.
# With no argument, run them against the standard set of worktree
# binaries in tools-for-build/build/.
#
# The full suite calls runtime_suite directly after each build; this
# script is for manual runs.

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    echo "error: run this script, do not source it" >&2
    return 1
fi

source "$(dirname "${BASH_SOURCE[0]}")/test-common.sh"

prepare_build

status=0

if [ "$#" -gt 0 ]; then
    bin=$1
    label=${2:-$(basename "$bin")}
    if [ -f "$bin" ] && [ "$(elf_machine "$bin")" = raw ]; then
        ensure_z80sim
    fi
    runtime_suite "$bin" "$label" || status=1
else
    ensure_z80sim
    runtime_suite "$BUILD/seed.amd64.2" seed-amd64 || status=1
    runtime_suite "$BUILD/seed-i386.2" seed-i386 || status=1
    runtime_suite "$BUILD/seed-aarch64" seed-aarch64-gen1 || status=1
    runtime_suite "$BUILD/seed-aarch64.2" seed-aarch64-gen2 || status=1
    runtime_suite "$BUILD/seed.z80" seed-z80 || status=1
    runtime_suite "$BUILD/sprout" sprout-amd64 || status=1
    runtime_suite "$BUILD/sprout-i386" sprout-i386 || status=1
    runtime_suite "$BUILD/sprout-aarch64" sprout-aarch64-gen1 || status=1
    runtime_suite "$BUILD/sprout-aarch64.2" sprout-aarch64-gen2 || status=1
fi

if ! test_summary; then
    status=1
fi
exit "$status"
