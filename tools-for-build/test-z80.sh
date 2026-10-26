#!/usr/bin/env bash

# Host: z80.  The "z80" suffix names the assumed *host* architecture,
# not the target: the z80 Seed is run with z80sim and cross-compiles
# to every Seed port.

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    echo "error: run this script, do not source it" >&2
    return 1
fi

source "$(dirname "${BASH_SOURCE[0]}")/test-common.sh"

case "$(uname -m)" in
    aarch64|arm64)
        BOOTSTRAP="$BOOTSTRAP_AARCH64"
        ;;
    *)
        BOOTSTRAP="$BOOTSTRAP_AMD64"
        ;;
esac

prepare_build
if [ "${TEST_CHECKS_DONE:-0}" != 1 ]; then
    source_line_check
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

seed_run "$BOOTSTRAP" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/ref.amd64"
seed_run "$BOOTSTRAP" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/ref.i386"
seed_run "$BOOTSTRAP" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/ref.aarch64"
seed_run "$BOOTSTRAP" "$ROOT/seed/src/seed-z80-fictional.seed" "$BUILD/seed.z80"

# (z80) Seed cross-compiles to amd64
z80_run "$BUILD/seed.z80" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed.z80-amd64"
cmp --verbose "$BUILD/ref.amd64" "$BUILD/seed.z80-amd64"

# (z80) Seed cross-compiles to i386
z80_run "$BUILD/seed.z80" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed.i386.by-z80"
cmp --verbose "$BUILD/ref.i386" "$BUILD/seed.i386.by-z80"

# (z80) Seed cross-compiles to aarch64
z80_run "$BUILD/seed.z80" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.by-z80"
cmp --verbose "$BUILD/ref.aarch64" "$BUILD/seed-aarch64.by-z80"

# (z80) Seed bootstraps itself
z80_run "$BUILD/seed.z80" "$ROOT/seed/src/seed-z80-fictional.seed" "$BUILD/seed.z80.1"
z80_run "$BUILD/seed.z80.1" "$ROOT/seed/src/seed-z80-fictional.seed" "$BUILD/seed.z80.2"
cmp --verbose "$BUILD/seed.z80" "$BUILD/seed.z80.1"
cmp --verbose "$BUILD/seed.z80.1" "$BUILD/seed.z80.2"

elf_check
