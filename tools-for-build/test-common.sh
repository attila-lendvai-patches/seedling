#!/usr/bin/env bash

# Shared by the test-<arch>.sh scripts.  The suffix in those names is
# the assumed host architecture, not the target architecture: every
# suite cross-compiles to all the Seed and Sprout ports.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "error: test-common.sh is a library; run tools-for-build/test.sh" >&2
    exit 1
fi

set -euo pipefail
if [ "${TEST_DEBUG:-0}" = 1 ]; then
    set -x
fi

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TOOLS="$ROOT/tools-for-build"
BUILD="$TOOLS/build"
BOOTSTRAP_AMD64="$ROOT/seed/bin/seed-linux-amd64"
BOOTSTRAP_AARCH64="$ROOT/seed/bin/seed-linux-aarch64"
Z80SIM_DIR="$TOOLS/z80sim"
Z80SIM="$Z80SIM_DIR/z80sim"
Z80SIM_REV=4bb8be2

trap 'echo "Error: command failed on line $LINENO: $BASH_COMMAND" >&2; exit 1' ERR

require() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "error: $1 not found${2:+; $2}" >&2
        exit 1
    }
}

rel() {
    printf '%s\n' "${1#"$ROOT"/}"
}

seed_run() {
    local bin=$1 input=$2 output=$3
    printf '  %s < %s > %s\n' \
        "$(rel "$bin")" "$(rel "$input")" "$(rel "$output")"
    "$bin" <"$input" >"$output"
}

prepare_build() {
    mkdir -p "$BUILD"
}

source_line_check() {
    echo "==> source line lengths"
    cd "$ROOT"
    python3 - <<'PY'
import glob
import os
import sys

bad = False
wide = []
for path in sorted(glob.glob('seed/src/*.seed') +
                   glob.glob('sprout/src/*.seed')):
    with open(path, encoding='utf-8') as source:
        for number, line in enumerate(source, 1):
            line = line.rstrip('\r\n')
            size = len(line.encode('utf-8'))
            if size > 64:
                print(f'{path}:{number}: {size} bytes (max 64)',
                      file=sys.stderr)
                bad = True
            width = len(line.expandtabs(8))
            if width > 64:
                wide.append((path, number, width))
if wide:
    print(f'warning: {len(wide)} source lines exceed 64 columns; '
          'tolerated until edited', file=sys.stderr)
    if os.environ.get('TEST_VERBOSE') == '1':
        for path, number, width in wide:
            print(f'{path}:{number}: {width} columns (max 64)',
                  file=sys.stderr)
if bad:
    sys.exit(1)
PY
}

committed_binary_check() {
    echo "==> committed Seed binaries"
    echo "    bootstrap: $(rel "$BOOTSTRAP")"
    local src bin failed=0
    for src in "$ROOT"/seed/src/seed-*.seed; do
        bin="$ROOT/seed/bin/$(basename "$src" .seed)"
        if [ ! -f "$bin" ]; then
            echo "error: $(rel "$bin") is not committed;" \
                 "build it from $(rel "$src")" >&2
            failed=1
            continue
        fi
        if ! seed_run "$BOOTSTRAP" "$src" "$BUILD/.committed-check"; then
            echo "error: $(rel "$BOOTSTRAP") failed on $(rel "$src")" >&2
            rm -f "$BUILD/.committed-check"
            return 1
        fi
        if ! cmp -s "$BUILD/.committed-check" "$bin"; then
            echo "error: $(rel "$bin") differs from a fresh build of" \
                 "$(rel "$src")" >&2
            failed=1
        fi
    done
    rm -f "$BUILD/.committed-check"
    return "$failed"
}

elf_check() {
    echo "==> ELF validation"
    require eu-elflint "install elfutils"
    local failures=0 f
    for f in "$BUILD"/* "$ROOT"/seed/bin/*; do
        [ -f "$f" ] || continue
        [ "$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')" = 7f454c46 ] || continue
        if ! eu-elflint -q "$f"; then
            echo "eu-elflint failed: $(rel "$f")" >&2
            failures=1
        fi
    done
    [ "$failures" -eq 0 ]
}

ensure_z80sim() {
    require git "install git"
    require make "install make"
    require gcc "install gcc"

    if [ ! -x "$Z80SIM" ]; then
        if [ -d "$Z80SIM_DIR/.git" ]; then
            git -C "$Z80SIM_DIR" fetch --all --tags
            git -C "$Z80SIM_DIR" checkout "$Z80SIM_REV"
        else
            if [ -e "$Z80SIM_DIR" ] && [ -n "$(ls -A "$Z80SIM_DIR" 2>/dev/null)" ]; then
                echo "error: $Z80SIM_DIR exists but is not a git checkout" >&2
                exit 1
            fi
            git clone https://github.com/nagydani/z80sim.git "$Z80SIM_DIR"
            git -C "$Z80SIM_DIR" checkout "$Z80SIM_REV"
        fi
        make -C "$Z80SIM_DIR" || {
            echo "error: failed to build z80sim; install libz80ex-dev" >&2
            exit 1
        }
    fi
    [ -x "$Z80SIM" ] || {
        echo "error: $Z80SIM was not built" >&2
        exit 1
    }
}

host_suite() {
    local host_seed=$1
    [ -x "$host_seed" ] || {
        echo "error: host Seed is not executable: $host_seed" >&2
        exit 1
    }

    prepare_build
    echo "==> host suite"
    echo "    host Seed: $(rel "$host_seed")"
    echo "    bootstrap: $(rel "$BOOTSTRAP")"
    if [ "${TEST_CHECKS_DONE:-0}" != 1 ]; then
        source_line_check
        committed_binary_check
    fi

    # (x86) Compile Sprout from the host Seed
    seed_run "$host_seed" "$ROOT/sprout/src/sprout-linux-amd64.seed" "$BUILD/sprout"
    chmod +x "$BUILD/sprout"

    # (x86) Compile Seed from the Sprout binary
    seed_run "$BUILD/sprout" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed"
    chmod +x "$BUILD/seed"

    # (amd64) Seed bootstraps itself
    seed_run "$host_seed" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed.amd64.2"
    chmod +x "$BUILD/seed.amd64.2"
    seed_run "$BUILD/seed.amd64.2" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed.amd64.3"
    cmp --verbose "$BUILD/seed.amd64.2" "$BUILD/seed.amd64.3"

    # (aarch64) Seed cross-compiles from the host Seed
    seed_run "$host_seed" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64"
    chmod +x "$BUILD/seed-aarch64"

    # (aarch64) Seed bootstraps itself
    seed_run "$BUILD/seed-aarch64" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.2"
    chmod +x "$BUILD/seed-aarch64.2"
    seed_run "$BUILD/seed-aarch64.2" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.3"
    cmp --verbose "$BUILD/seed-aarch64" "$BUILD/seed-aarch64.2"
    cmp --verbose "$BUILD/seed-aarch64.2" "$BUILD/seed-aarch64.3"

    # (i386) Seed cross-compiles from the host Seed
    seed_run "$host_seed" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed-i386"
    chmod +x "$BUILD/seed-i386"

    # (i386) Seed bootstraps itself
    seed_run "$BUILD/seed-i386" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed-i386.2"
    chmod +x "$BUILD/seed-i386.2"
    seed_run "$BUILD/seed-i386.2" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed-i386.3"
    cmp --verbose "$BUILD/seed-i386.2" "$BUILD/seed-i386.3"

    # (aarch64) Compile Sprout from the host Sprout
    seed_run "$BUILD/sprout" "$ROOT/sprout/src/sprout-linux-aarch64.seed" "$BUILD/sprout-aarch64"
    chmod +x "$BUILD/sprout-aarch64"

    # (aarch64) Sprout builds identically with the host Seed and the
    # aarch64 Seed
    seed_run "$host_seed" "$ROOT/sprout/src/sprout-linux-aarch64.seed" "$BUILD/sprout-aarch64.by-seed"
    cmp --verbose "$BUILD/sprout-aarch64" "$BUILD/sprout-aarch64.by-seed"
    seed_run "$BUILD/seed-aarch64.2" "$ROOT/sprout/src/sprout-linux-aarch64.seed" "$BUILD/sprout-aarch64.by-aarch64-seed"
    cmp --verbose "$BUILD/sprout-aarch64" \
        "$BUILD/sprout-aarch64.by-aarch64-seed"

    # (aarch64) Sprout bootstraps itself
    seed_run "$BUILD/sprout-aarch64" "$ROOT/sprout/src/sprout-linux-aarch64.seed" "$BUILD/sprout-aarch64.2"
    chmod +x "$BUILD/sprout-aarch64.2"
    seed_run "$BUILD/sprout-aarch64.2" "$ROOT/sprout/src/sprout-linux-aarch64.seed" "$BUILD/sprout-aarch64.3"
    cmp --verbose "$BUILD/sprout-aarch64" "$BUILD/sprout-aarch64.2"
    cmp --verbose "$BUILD/sprout-aarch64.2" "$BUILD/sprout-aarch64.3"

    # (aarch64) Sprout compiles the Seed; the result bootstraps itself
    seed_run "$BUILD/sprout-aarch64" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.by-sprout"
    chmod +x "$BUILD/seed-aarch64.by-sprout"
    cmp --verbose "$BUILD/seed-aarch64" "$BUILD/seed-aarch64.by-sprout"
    seed_run "$BUILD/seed-aarch64.by-sprout" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.by-sprout.2"
    chmod +x "$BUILD/seed-aarch64.by-sprout.2"
    seed_run "$BUILD/seed-aarch64.by-sprout.2" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.by-sprout.3"
    cmp --verbose "$BUILD/seed-aarch64.by-sprout.2" \
        "$BUILD/seed-aarch64.by-sprout.3"

    # (i386) Compile Sprout from the host Seed
    seed_run "$host_seed" "$ROOT/sprout/src/sprout-linux-i386.seed" "$BUILD/sprout-i386"
    chmod +x "$BUILD/sprout-i386"

    # (i386) Sprout bootstraps itself
    seed_run "$BUILD/sprout-i386" "$ROOT/sprout/src/sprout-linux-i386.seed" "$BUILD/sprout-i386.2"
    chmod +x "$BUILD/sprout-i386.2"
    seed_run "$BUILD/sprout-i386.2" "$ROOT/sprout/src/sprout-linux-i386.seed" "$BUILD/sprout-i386.3"
    cmp --verbose "$BUILD/sprout-i386.2" "$BUILD/sprout-i386.3"

    # (amd64) Sprout compiles the aarch64 and i386 sources
    seed_run "$BUILD/sprout" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.by-sprout"
    cmp --verbose "$BUILD/seed-aarch64.2" "$BUILD/seed-aarch64.by-sprout"
    seed_run "$BUILD/sprout" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed-i386.by-sprout"
    cmp --verbose "$BUILD/seed-i386.2" "$BUILD/seed-i386.by-sprout"
    seed_run "$BUILD/sprout" "$ROOT/sprout/src/sprout-linux-aarch64.seed" "$BUILD/sprout-aarch64.by-sprout"
    cmp --verbose "$BUILD/sprout-aarch64" "$BUILD/sprout-aarch64.by-sprout"
    seed_run "$BUILD/sprout" "$ROOT/sprout/src/sprout-linux-i386.seed" "$BUILD/sprout-i386.by-sprout"
    cmp --verbose "$BUILD/sprout-i386.2" "$BUILD/sprout-i386.by-sprout"

    # (aarch64) Seed compiles the amd64 and i386 Seeds and Sprouts
    seed_run "$BUILD/seed-aarch64.2" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed-amd64.by-aarch64"
    cmp --verbose "$BUILD/seed.amd64.2" "$BUILD/seed-amd64.by-aarch64"
    seed_run "$BUILD/seed-aarch64.2" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed-i386.by-aarch64"
    cmp --verbose "$BUILD/seed-i386.2" "$BUILD/seed-i386.by-aarch64"
    seed_run "$BUILD/seed-aarch64.2" "$ROOT/sprout/src/sprout-linux-amd64.seed" "$BUILD/sprout-amd64.by-aarch64"
    cmp --verbose "$BUILD/sprout" "$BUILD/sprout-amd64.by-aarch64"
    seed_run "$BUILD/seed-aarch64.2" "$ROOT/sprout/src/sprout-linux-i386.seed" "$BUILD/sprout-i386.by-aarch64"
    cmp --verbose "$BUILD/sprout-i386.2" "$BUILD/sprout-i386.by-aarch64"

    # (aarch64) Sprout compiles the amd64 and i386 sources
    seed_run "$BUILD/sprout-aarch64" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed-amd64.by-aarch64-sprout"
    cmp --verbose "$BUILD/seed.amd64.2" \
        "$BUILD/seed-amd64.by-aarch64-sprout"
    seed_run "$BUILD/sprout-aarch64" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed-i386.by-aarch64-sprout"
    cmp --verbose "$BUILD/seed-i386.2" \
        "$BUILD/seed-i386.by-aarch64-sprout"
    seed_run "$BUILD/sprout-aarch64" "$ROOT/sprout/src/sprout-linux-amd64.seed" "$BUILD/sprout-amd64.by-aarch64-sprout"
    cmp --verbose "$BUILD/sprout" \
        "$BUILD/sprout-amd64.by-aarch64-sprout"
    seed_run "$BUILD/sprout-aarch64" "$ROOT/sprout/src/sprout-linux-i386.seed" "$BUILD/sprout-i386.by-aarch64-sprout"
    cmp --verbose "$BUILD/sprout-i386.2" \
        "$BUILD/sprout-i386.by-aarch64-sprout"

    # (i386) Seed and Sprout compile the amd64 Seed and the i386 sources
    seed_run "$BUILD/seed-i386.2" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed-amd64.by-i386"
    cmp --verbose "$BUILD/seed.amd64.2" "$BUILD/seed-amd64.by-i386"
    seed_run "$BUILD/seed-i386.2" "$ROOT/sprout/src/sprout-linux-i386.seed" "$BUILD/sprout-i386.by-i386-seed"
    cmp --verbose "$BUILD/sprout-i386.2" \
        "$BUILD/sprout-i386.by-i386-seed"
    seed_run "$BUILD/sprout-i386.2" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed-i386.by-sprout"
    cmp --verbose "$BUILD/seed-i386.2" "$BUILD/seed-i386.by-sprout"
    seed_run "$BUILD/sprout-i386.2" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed-amd64.by-i386-sprout"
    cmp --verbose "$BUILD/seed.amd64.2" \
        "$BUILD/seed-amd64.by-i386-sprout"

    # (i386) Seed and Sprout compile the aarch64 Seed
    seed_run "$BUILD/seed-i386.2" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.by-i386"
    cmp --verbose "$BUILD/seed-aarch64" "$BUILD/seed-aarch64.by-i386"
    seed_run "$BUILD/sprout-i386.2" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.by-i386-sprout"
    cmp --verbose "$BUILD/seed-aarch64" \
        "$BUILD/seed-aarch64.by-i386-sprout"

    elf_check
}

# The i386 host can compile the 16-bit-safe aarch64 Seed, but not the
# aarch64 Sprout: its floating-point constants are 64-bit and do not
# fit the i386 host's cells.  This suite covers the i386 Seed and
# Sprout, the aarch64 Seed, and the amd64/i386 cross-checks.
i386_suite() {
    prepare_build
    echo "==> i386 host suite"
    echo "    bootstrap: $(rel "$BOOTSTRAP")"
    if [ "${TEST_CHECKS_DONE:-0}" != 1 ]; then
        source_line_check
        committed_binary_check
    fi

    # (amd64) reference Seed
    seed_run "$BOOTSTRAP" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed.amd64.2"
    chmod +x "$BUILD/seed.amd64.2"
    seed_run "$BUILD/seed.amd64.2" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed.amd64.3"
    cmp --verbose "$BUILD/seed.amd64.2" "$BUILD/seed.amd64.3"

    # (aarch64) reference Seed
    seed_run "$BOOTSTRAP" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64"
    chmod +x "$BUILD/seed-aarch64"
    seed_run "$BUILD/seed-aarch64" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.2"
    chmod +x "$BUILD/seed-aarch64.2"
    seed_run "$BUILD/seed-aarch64.2" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.3"
    cmp --verbose "$BUILD/seed-aarch64" "$BUILD/seed-aarch64.2"
    cmp --verbose "$BUILD/seed-aarch64.2" "$BUILD/seed-aarch64.3"

    # (i386) Seed cross-compiles from the amd64 Seed
    seed_run "$BOOTSTRAP" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed-i386"
    chmod +x "$BUILD/seed-i386"

    # (i386) Seed bootstraps itself
    seed_run "$BUILD/seed-i386" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed-i386.2"
    chmod +x "$BUILD/seed-i386.2"
    seed_run "$BUILD/seed-i386.2" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed-i386.3"
    cmp --verbose "$BUILD/seed-i386" "$BUILD/seed-i386.2"
    cmp --verbose "$BUILD/seed-i386.2" "$BUILD/seed-i386.3"

    # (i386) Compile Sprout from the amd64 Seed
    seed_run "$BOOTSTRAP" "$ROOT/sprout/src/sprout-linux-i386.seed" "$BUILD/sprout-i386"
    chmod +x "$BUILD/sprout-i386"

    # (i386) Sprout bootstraps itself
    seed_run "$BUILD/sprout-i386" "$ROOT/sprout/src/sprout-linux-i386.seed" "$BUILD/sprout-i386.2"
    chmod +x "$BUILD/sprout-i386.2"
    seed_run "$BUILD/sprout-i386.2" "$ROOT/sprout/src/sprout-linux-i386.seed" "$BUILD/sprout-i386.3"
    cmp --verbose "$BUILD/sprout-i386" "$BUILD/sprout-i386.2"
    cmp --verbose "$BUILD/sprout-i386.2" "$BUILD/sprout-i386.3"

    # (i386) Seed and Sprout compile the amd64 Seed and the i386 sources
    seed_run "$BUILD/seed-i386.2" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed-amd64.by-i386"
    cmp --verbose "$BUILD/seed.amd64.2" "$BUILD/seed-amd64.by-i386"
    seed_run "$BUILD/seed-i386.2" "$ROOT/sprout/src/sprout-linux-i386.seed" "$BUILD/sprout-i386.by-i386-seed"
    cmp --verbose "$BUILD/sprout-i386.2" \
        "$BUILD/sprout-i386.by-i386-seed"
    seed_run "$BUILD/sprout-i386.2" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed-i386.by-sprout"
    cmp --verbose "$BUILD/seed-i386.2" "$BUILD/seed-i386.by-sprout"
    seed_run "$BUILD/sprout-i386.2" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed-amd64.by-i386-sprout"
    cmp --verbose "$BUILD/seed.amd64.2" \
        "$BUILD/seed-amd64.by-i386-sprout"

    # (i386) Seed and Sprout compile the aarch64 Seed
    seed_run "$BUILD/seed-i386.2" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.by-i386"
    cmp --verbose "$BUILD/seed-aarch64" "$BUILD/seed-aarch64.by-i386"
    seed_run "$BUILD/sprout-i386.2" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.by-i386-sprout"
    cmp --verbose "$BUILD/seed-aarch64" \
        "$BUILD/seed-aarch64.by-i386-sprout"

    elf_check
}
