#!/usr/bin/env bash

# Host: z80. The "z80" suffix names the assumed *host* architecture,
# not the target: the z80 Seed is run with z80sim and cross-compiles
# to every Seed port.

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    echo "error: run this script, do not source it" >&2
    return 1
fi

source "$(dirname "${BASH_SOURCE[0]}")/test-common.sh"

BOOTSTRAP=$(bootstrap_for_host)

prepare_build
if [ "${TEST_CHECKS_DONE:-0}" != 1 ]; then
    source_line_check
    source_literal_check
fi
ensure_z80sim

z80_run() {
    local seed=$1 input=$2 output=$3
    printf '  %s %s < %s > %s\n' \
        "$(rel "$Z80SIM")" "$(rel "$seed")" \
        "$(rel "$input")" "$(rel "$output")"
    "$Z80SIM" "$seed" <"$input" >"$output" 2>/dev/null
}

echo "==> z80 suite"
echo "    bootstrap: $(rel "$BOOTSTRAP")"
echo "    z80 simulator: $(rel "$Z80SIM")"

# Build the z80 Seed from the worktree and probe it before the z80
# cross-compilation tests.
seed_run "$BOOTSTRAP" "$ROOT/seed/src/seed-z80-fictional.seed" "$BUILD/seed.z80"
runtime_suite "$BUILD/seed.z80" seed-z80

# The committed Seed binaries are the cross-compiled references. The
# committed_binary_check at the start of the suite proves that each of
# them is a fixpoint of its source.
# (z80) Seed cross-compiles to amd64
z80_run "$BUILD/seed.z80" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed.z80-amd64"
cmp --verbose "$ROOT/seed/bin/seed-linux-amd64" "$BUILD/seed.z80-amd64"

# (z80) Seed cross-compiles to i386
z80_run "$BUILD/seed.z80" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed.i386.by-z80"
cmp --verbose "$ROOT/seed/bin/seed-linux-i386" "$BUILD/seed.i386.by-z80"

# (z80) Seed cross-compiles to aarch64
z80_run "$BUILD/seed.z80" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.by-z80"
cmp --verbose "$ROOT/seed/bin/seed-linux-aarch64" "$BUILD/seed-aarch64.by-z80"

# Sprout references come from the host suite when it has already built
# them; build only what is missing or stale.
sprout_ref() {
    local ref=$1 src=$2
    if [ ! -f "$ref" ] || [ "$src" -nt "$ref" ]; then
        seed_run "$BOOTSTRAP" "$src" "$ref"
    fi
}

sprout_ref "$BUILD/sprout" "$ROOT/sprout/src/sprout-linux-amd64.seed"
sprout_ref "$BUILD/sprout-i386" "$ROOT/sprout/src/sprout-linux-i386.seed"
sprout_ref "$BUILD/sprout-aarch64" "$ROOT/sprout/src/sprout-linux-aarch64.seed"
sprout_ref "$BUILD/sprout-z80" "$ROOT/sprout/src/sprout-z80-fictional.seed"

# (z80) Seed cross-compiles the amd64 Sprout
z80_run "$BUILD/seed.z80" "$ROOT/sprout/src/sprout-linux-amd64.seed" "$BUILD/sprout-amd64.by-z80"
cmp --verbose "$BUILD/sprout" "$BUILD/sprout-amd64.by-z80"

# (z80) Seed cross-compiles the i386 Sprout
z80_run "$BUILD/seed.z80" "$ROOT/sprout/src/sprout-linux-i386.seed" "$BUILD/sprout-i386.by-z80"
cmp --verbose "$BUILD/sprout-i386" "$BUILD/sprout-i386.by-z80"

# (z80) Seed cross-compiles the aarch64 Sprout
z80_run "$BUILD/seed.z80" "$ROOT/sprout/src/sprout-linux-aarch64.seed" "$BUILD/sprout-aarch64.by-z80"
cmp --verbose "$BUILD/sprout-aarch64" "$BUILD/sprout-aarch64.by-z80"

# (z80) Seed cross-compiles the z80 Sprout
z80_run "$BUILD/seed.z80" "$ROOT/sprout/src/sprout-z80-fictional.seed" "$BUILD/sprout-z80.by-z80"
cmp --verbose "$BUILD/sprout-z80" "$BUILD/sprout-z80.by-z80"

# (z80) Seed bootstraps itself
z80_run "$BUILD/seed.z80" "$ROOT/seed/src/seed-z80-fictional.seed" "$BUILD/seed.z80.1"
z80_run "$BUILD/seed.z80.1" "$ROOT/seed/src/seed-z80-fictional.seed" "$BUILD/seed.z80.2"
cmp --verbose "$BUILD/seed.z80" "$BUILD/seed.z80.1"
cmp --verbose "$BUILD/seed.z80.1" "$BUILD/seed.z80.2"

elf_check
