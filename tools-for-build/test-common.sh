#!/usr/bin/env bash

# Shared by the test-<arch>.sh scripts. The suffix in those names is
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
PROBES="$TOOLS/probes"
BOOTSTRAP_AMD64="$ROOT/seed/bin/seed-linux-amd64"
BOOTSTRAP_AARCH64="$ROOT/seed/bin/seed-linux-aarch64"
BOOTSTRAP_I386="$ROOT/seed/bin/seed-linux-i386"
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

host_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo amd64 ;;
        i386|i486|i586|i686) echo i386 ;;
        aarch64|arm64) echo aarch64 ;;
        *) uname -m ;;
    esac
}

qemu_candidates() {
    case "$1" in
        amd64) echo "qemu-x86_64 qemu-x86_64-static qemu-amd64 qemu-amd64-static" ;;
        i386) echo "qemu-i386 qemu-i386-static" ;;
        aarch64) echo "qemu-aarch64 qemu-aarch64-static" ;;
        *) : ;;
    esac
}

# True when a binary of arch can be executed on this host, natively or
# through qemu.  TEST_NO_QEMU=1 forces foreign targets to be skipped.
can_execute() {
    local arch=$1 host q
    if [ "$arch" = raw ]; then
        [ -x "$Z80SIM" ]
        return
    fi
    host=$(host_arch)
    [ "$arch" = "$host" ] && return 0
    [ "$arch" = i386 ] && [ "$host" = amd64 ] && return 0
    [ "${TEST_NO_QEMU:-0}" = 1 ] && return 1
    for q in $(qemu_candidates "$arch"); do
        if command -v "$q" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

runner_note() {
    case "$1" in
        amd64) echo "install qemu-x86_64 or enable binfmt" ;;
        i386) echo "install qemu-i386 or enable binfmt" ;;
        aarch64) echo "install qemu-aarch64 or enable binfmt" ;;
        raw) echo "build z80sim" ;;
        *) echo "no runner available" ;;
    esac
}

skip_note() {
    printf 'SKIP: %s\n' "$*" >&2
}

suite_capabilities() {
    HAVE_AMD64=0
    HAVE_I386=0
    HAVE_AARCH64=0
    if can_execute amd64; then HAVE_AMD64=1; fi
    if can_execute i386; then HAVE_I386=1; fi
    if can_execute aarch64; then HAVE_AARCH64=1; fi
}

bootstrap_for_host() {
    case "$(host_arch)" in
        aarch64) echo "$BOOTSTRAP_AARCH64" ;;
        i386)
            if can_execute amd64; then
                echo "$BOOTSTRAP_AMD64"
            else
                echo "$BOOTSTRAP_I386"
            fi
            ;;
        *) echo "$BOOTSTRAP_AMD64" ;;
    esac
}

elf_machine() {
    local file=$1 magic
    magic=$(head -c 4 "$file" | od -An -tx1 | tr -d ' \n')
    if [ "$magic" != 7f454c46 ]; then
        echo raw
        return
    fi
    case "$(dd if="$file" bs=1 skip=18 count=2 2>/dev/null |
            od -An -tx1 | tr -d ' \n')" in
        3e00) echo amd64 ;;
        0300) echo i386 ;;
        b700) echo aarch64 ;;
        *) echo unknown ;;
    esac
}

# Run a target binary natively, or through qemu.  Return 77 when no
# runner is available; callers treat that as a skipped test.
run_target() {
    local bin=$1 arch host q limit
    shift
    limit=${TEST_TIMEOUT:-120}
    arch=$(elf_machine "$bin")
    if [ "$arch" = raw ]; then
        timeout "$limit" "$Z80SIM" "$bin" "$@"
        return
    fi
    host=$(host_arch)
    if [ "$arch" = "$host" ] ||
       { [ "$arch" = i386 ] && [ "$host" = amd64 ]; }; then
        timeout "$limit" "$bin" "$@"
        return
    fi
    if [ "${TEST_NO_QEMU:-0}" != 1 ]; then
        for q in $(qemu_candidates "$arch"); do
            if command -v "$q" >/dev/null 2>&1; then
                timeout "$limit" "$q" "$bin" "$@"
                return
            fi
        done
    fi
    skip_note "cannot execute $arch binary: $(runner_note "$arch")"
    return 77
}

seed_run() {
    local bin=$1 input=$2 output=$3
    printf '  %s < %s > %s\n' \
        "$(rel "$bin")" "$(rel "$input")" "$(rel "$output")"
    run_target "$bin" <"$input" >"$output"
}

prepare_build() {
    mkdir -p "$BUILD"
}

TEST_PASS=0
TEST_FAIL=0
TEST_SKIP=0

test_pass() {
    TEST_PASS=$((TEST_PASS + 1))
    if [ "${TEST_VERBOSE:-0}" = 1 ]; then
        printf '  PASS: %s\n' "$*"
    fi
    return 0
}

test_fail() {
    TEST_FAIL=$((TEST_FAIL + 1))
    printf '  FAIL: %s\n' "$*" >&2
    return 0
}

test_skip() {
    TEST_SKIP=$((TEST_SKIP + 1))
    printf '  SKIP: %s\n' "$*" >&2
    return 0
}

test_summary() {
    printf '\n==> runtime: %d passed, %d failed, %d skipped\n' \
        "$TEST_PASS" "$TEST_FAIL" "$TEST_SKIP"
    [ "$TEST_FAIL" -eq 0 ]
}

# Run a Seed program and compare its whitespace-normalised stdout.
check_stdout() {
    local label=$1 want=$2 bin=$3 src=$4
    local out="$BUILD/probe.out" err="$BUILD/probe.err"
    local status=0 got
    run_target "$bin" <"$src" >"$out" 2>"$err" || status=$?
    if [ "$status" -eq 77 ]; then
        test_skip "$label: no runner"
        return 0
    fi
    if [ "$status" -ne 0 ]; then
        test_fail "$label: exited $status ($(head -c 120 "$err" |
            tr '\n' ' '))"
        return 0
    fi
    got=$(tr -d '[:space:]' <"$out")
    if [ "$got" = "$want" ]; then
        test_pass "$label"
    else
        test_fail "$label: expected '$want', got '$got'"
    fi
    return 0
}

probe_expected() {
    case "$(basename "$1")" in
        postpone.seed) echo 31 ;;
        constant.seed) echo 2A ;;
        macro.seed) echo 5 ;;
        self.seed) echo 321 ;;
        variable.seed) echo 7 ;;
        string.seed) echo hi ;;
        base.seed) echo 41255 ;;
        *) echo "" ;;
    esac
}

# Run all probes against one freshly built Seed or Sprout binary.
runtime_suite() {
    local bin=$1 label=$2 before=$TEST_FAIL probe want arch
    if [ ! -f "$bin" ]; then
        test_skip "$label: not built"
        return 0
    fi
    arch=$(elf_machine "$bin")
    if ! can_execute "$arch"; then
        test_skip "$label: $(runner_note "$arch")"
        return 0
    fi
    chmod +x "$bin" 2>/dev/null || true
    for probe in "$PROBES"/*.seed; do
        want=$(probe_expected "$probe")
        if [ -z "$want" ]; then
            test_fail "$label $(basename "$probe"): no expected output"
            continue
        fi
        check_stdout "$label $(basename "$probe")" "$want" "$bin" "$probe"
    done
    if [ "$TEST_FAIL" -eq "$before" ]; then
        printf '  runtime %s: ok\n' "$label"
        return 0
    fi
    printf '  runtime %s: FAILED\n' "$label" >&2
    return 1
}

source_line_check() {
    echo "==> source line lengths"
    cd "$ROOT"
    local bad=0 wide=0 f n
    for f in seed/src/*.seed sprout/src/*.seed; do
        if ! LC_ALL=C awk '
            length($0) > 64 {
                printf "%s:%d: %d bytes (max 64)\n", FILENAME, FNR,
                    length($0) > "/dev/stderr"
                bad = 1
            }
            END { exit bad }
        ' "$f"; then
            bad=1
        fi
        n=$(expand -t 8 "$f" | awk 'length($0) > 64 { n++ } END { print n+0 }')
        if [ "$n" -gt 0 ]; then
            wide=$((wide + n))
            if [ "${TEST_VERBOSE:-0}" = 1 ]; then
                expand -t 8 "$f" | awk -v file="$f" '
                    length($0) > 64 {
                        printf "%s:%d: %d columns (max 64)\n",
                            file, FNR, length($0) > "/dev/stderr"
                    }'
            fi
        fi
    done
    if [ "$wide" -gt 0 ]; then
        echo "warning: $wide source lines exceed 64 columns;" \
             "tolerated until edited" >&2
    fi
    [ "$bad" -eq 0 ]
}

# List, but do not fail, numerals the compiling host cannot hold in
# 16 bits. A wide literal is fine when the code truncates it before
# use; the list is a review aid. All sources are written in hex.
source_literal_check() {
    echo "==> source literals"
    cd "$ROOT"
    local f findings="$BUILD/.source-literals"
    : >"$findings"
    for f in seed/src/*.seed sprout/src/*.seed; do
        awk '
            {
                line = $0
                code = ""
                string = 0
                n = length(line)
                for (i = 1; i <= n; i++) {
                    c = substr(line, i, 1)
                    if (string) {
                        if (c == "\\") { i++; continue }
                        if (c == "\"") string = 0
                        continue
                    }
                    if (c == "\\") break
                    if (c == "\"") { string = 1; continue }
                    code = code c
                }
                m = split(code, tok, /[ \t]+/)
                for (j = 1; j <= m; j++) {
                    if (tok[j] ~ /^[0-9A-F]+$/ && length(tok[j]) > 4)
                        printf "%s:%d: %s\n", FILENAME, FNR, tok[j]
                }
            }
        ' "$f" >>"$findings"
    done
    if [ -s "$findings" ]; then
        while IFS= read -r f; do
            printf '\033[33m%s\033[0m\n' "$f" >&2
        done <"$findings"
        printf '\033[33mwarning: %s source literals are wider than 16 bits\033[0m\n' \
            "$(wc -l <"$findings")" >&2
    fi
    rm -f "$findings"
    return 0
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


# Build and self-host one target architecture from the worktree.  Used
# when not every target has a runner; the full matrix runs otherwise.
target_suite() {
    local host_seed=$1 arch=$2 seed_src=$3 sprout_src=$4
    local seed_bin="$BUILD/seed-$arch" sprout_bin="$BUILD/sprout-$arch"

    echo "==> $arch target suite"
    seed_run "$host_seed" "$seed_src" "$seed_bin"
    chmod +x "$seed_bin"
    runtime_suite "$seed_bin" "seed-$arch-gen1"
    seed_run "$seed_bin" "$seed_src" "$seed_bin.2"
    chmod +x "$seed_bin.2"
    runtime_suite "$seed_bin.2" "seed-$arch-gen2"
    seed_run "$seed_bin.2" "$seed_src" "$seed_bin.3"
    cmp --verbose "$seed_bin" "$seed_bin.2"
    cmp --verbose "$seed_bin.2" "$seed_bin.3"

    seed_run "$host_seed" "$sprout_src" "$sprout_bin"
    chmod +x "$sprout_bin"
    runtime_suite "$sprout_bin" "sprout-$arch-gen1"
    seed_run "$sprout_bin" "$sprout_src" "$sprout_bin.2"
    chmod +x "$sprout_bin.2"
    runtime_suite "$sprout_bin.2" "sprout-$arch-gen2"
    seed_run "$sprout_bin.2" "$sprout_src" "$sprout_bin.3"
    cmp --verbose "$sprout_bin" "$sprout_bin.2"
    cmp --verbose "$sprout_bin.2" "$sprout_bin.3"
}

all_targets_available() {
    [ "$HAVE_AMD64" = 1 ] && [ "$HAVE_I386" = 1 ] &&
        [ "$HAVE_AARCH64" = 1 ]
}

print_missing_targets() {
    [ "$HAVE_AMD64" = 1 ] ||
        skip_note "amd64 tests skipped: $(runner_note amd64)"
    [ "$HAVE_I386" = 1 ] ||
        skip_note "i386 tests skipped: $(runner_note i386)"
    [ "$HAVE_AARCH64" = 1 ] ||
        skip_note "aarch64 tests skipped: $(runner_note aarch64)"
}

host_suite() {
    local host_seed=$1
    suite_capabilities
    if all_targets_available; then
        host_suite_full "$host_seed"
        return
    fi

    prepare_build
    echo "==> host suite"
    echo "    host Seed: $(rel "$host_seed")"
    echo "    bootstrap: $(rel "$BOOTSTRAP")"
    if [ "${TEST_CHECKS_DONE:-0}" != 1 ]; then
        source_line_check
        source_literal_check
        committed_binary_check
    fi
    print_missing_targets
    if [ "$HAVE_AMD64" = 1 ]; then
        target_suite "$host_seed" amd64 \
            "$ROOT/seed/src/seed-linux-amd64.seed" \
            "$ROOT/sprout/src/sprout-linux-amd64.seed"
    fi
    if [ "$HAVE_I386" = 1 ]; then
        target_suite "$host_seed" i386 \
            "$ROOT/seed/src/seed-linux-i386.seed" \
            "$ROOT/sprout/src/sprout-linux-i386.seed"
    fi
    if [ "$HAVE_AARCH64" = 1 ]; then
        target_suite "$host_seed" aarch64 \
            "$ROOT/seed/src/seed-linux-aarch64.seed" \
            "$ROOT/sprout/src/sprout-linux-aarch64.seed"
    fi
    skip_note "cross-compilation matrix skipped: not all targets executable"
    elf_check
}

host_suite_full() {
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
        source_literal_check
        committed_binary_check
    fi

    # (x86) Compile Sprout from the host Seed
    seed_run "$host_seed" "$ROOT/sprout/src/sprout-linux-amd64.seed" "$BUILD/sprout"
    chmod +x "$BUILD/sprout"
    runtime_suite "$BUILD/sprout" sprout-amd64

    # (x86) Compile Seed from the Sprout binary
    seed_run "$BUILD/sprout" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed"
    chmod +x "$BUILD/seed"

    # (amd64) Seed bootstraps itself
    seed_run "$host_seed" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed.amd64.2"
    chmod +x "$BUILD/seed.amd64.2"
    runtime_suite "$BUILD/seed.amd64.2" seed-amd64
    seed_run "$BUILD/seed.amd64.2" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed.amd64.3"
    cmp --verbose "$BUILD/seed.amd64.2" "$BUILD/seed.amd64.3"

    # (aarch64) Seed cross-compiles from the host Seed
    seed_run "$host_seed" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64"
    chmod +x "$BUILD/seed-aarch64"
    runtime_suite "$BUILD/seed-aarch64" seed-aarch64-gen1

    # (aarch64) Seed bootstraps itself
    seed_run "$BUILD/seed-aarch64" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.2"
    chmod +x "$BUILD/seed-aarch64.2"
    runtime_suite "$BUILD/seed-aarch64.2" seed-aarch64-gen2
    seed_run "$BUILD/seed-aarch64.2" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.3"
    cmp --verbose "$BUILD/seed-aarch64" "$BUILD/seed-aarch64.2"
    cmp --verbose "$BUILD/seed-aarch64.2" "$BUILD/seed-aarch64.3"

    # (i386) Seed cross-compiles from the host Seed
    seed_run "$host_seed" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed-i386"
    chmod +x "$BUILD/seed-i386"

    # (i386) Seed bootstraps itself
    seed_run "$BUILD/seed-i386" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed-i386.2"
    chmod +x "$BUILD/seed-i386.2"
    runtime_suite "$BUILD/seed-i386.2" seed-i386
    seed_run "$BUILD/seed-i386.2" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed-i386.3"
    cmp --verbose "$BUILD/seed-i386.2" "$BUILD/seed-i386.3"

    # (aarch64) Compile Sprout from the host Sprout
    seed_run "$BUILD/sprout" "$ROOT/sprout/src/sprout-linux-aarch64.seed" "$BUILD/sprout-aarch64"
    chmod +x "$BUILD/sprout-aarch64"
    runtime_suite "$BUILD/sprout-aarch64" sprout-aarch64-gen1

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
    runtime_suite "$BUILD/sprout-aarch64.2" sprout-aarch64-gen2
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
    runtime_suite "$BUILD/sprout-i386.2" sprout-i386
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

    # (i386) Seed and Sprout compile the aarch64 Sprout
    if [ ! -f "$BUILD/sprout-aarch64" ] ||
       [ "$ROOT/sprout/src/sprout-linux-aarch64.seed" -nt "$BUILD/sprout-aarch64" ]; then
        seed_run "$BOOTSTRAP" \
            "$ROOT/sprout/src/sprout-linux-aarch64.seed" "$BUILD/sprout-aarch64"
    fi
    seed_run "$BUILD/seed-i386.2" \
        "$ROOT/sprout/src/sprout-linux-aarch64.seed" \
        "$BUILD/sprout-aarch64.by-i386"
    cmp --verbose "$BUILD/sprout-aarch64" "$BUILD/sprout-aarch64.by-i386"
    seed_run "$BUILD/sprout-i386.2" \
        "$ROOT/sprout/src/sprout-linux-aarch64.seed" \
        "$BUILD/sprout-aarch64.by-i386-sprout"
    cmp --verbose "$BUILD/sprout-aarch64" \
        "$BUILD/sprout-aarch64.by-i386-sprout"

    elf_check
}

# The i386 host could not compile the aarch64 Sprout while its
# floating-point constants needed more than the host's cells. It now
# compiles the 16-bit-safe aarch64 Seed and Sprout.

i386_suite() {
    suite_capabilities
    if all_targets_available; then
        i386_suite_full
        return
    fi

    prepare_build
    echo "==> i386 host suite"
    echo "    bootstrap: $(rel "$BOOTSTRAP")"
    if [ "${TEST_CHECKS_DONE:-0}" != 1 ]; then
        source_line_check
        source_literal_check
        committed_binary_check
    fi
    print_missing_targets
    if [ "$(host_arch)" = i386 ]; then
        # The i386 host can compile a foreign Seed, but not the amd64 or
        # aarch64 Sprout; run only the native target in a partial setup.
        target_suite "$BOOTSTRAP" i386 \
            "$ROOT/seed/src/seed-linux-i386.seed" \
            "$ROOT/sprout/src/sprout-linux-i386.seed"
        skip_note "amd64 tests skipped on i386 host without amd64 runner"
        skip_note "aarch64 tests skipped on i386 host without amd64 runner"
    else
        if [ "$HAVE_AMD64" = 1 ]; then
            target_suite "$BOOTSTRAP" amd64 \
                "$ROOT/seed/src/seed-linux-amd64.seed" \
                "$ROOT/sprout/src/sprout-linux-amd64.seed"
        fi
        if [ "$HAVE_I386" = 1 ]; then
            target_suite "$BOOTSTRAP" i386 \
                "$ROOT/seed/src/seed-linux-i386.seed" \
                "$ROOT/sprout/src/sprout-linux-i386.seed"
        fi
        if [ "$HAVE_AARCH64" = 1 ]; then
            target_suite "$BOOTSTRAP" aarch64 \
                "$ROOT/seed/src/seed-linux-aarch64.seed" \
                "$ROOT/sprout/src/sprout-linux-aarch64.seed"
        fi
    fi
    skip_note "cross-compilation matrix skipped: not all targets executable"
    elf_check
}

i386_suite_full() {
    prepare_build
    echo "==> i386 host suite"
    echo "    bootstrap: $(rel "$BOOTSTRAP")"
    if [ "${TEST_CHECKS_DONE:-0}" != 1 ]; then
        source_line_check
        source_literal_check
        committed_binary_check
    fi

    # (amd64) reference Seed
    seed_run "$BOOTSTRAP" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed.amd64.2"
    chmod +x "$BUILD/seed.amd64.2"
    runtime_suite "$BUILD/seed.amd64.2" seed-amd64
    seed_run "$BUILD/seed.amd64.2" "$ROOT/seed/src/seed-linux-amd64.seed" "$BUILD/seed.amd64.3"
    cmp --verbose "$BUILD/seed.amd64.2" "$BUILD/seed.amd64.3"

    # (aarch64) reference Seed
    seed_run "$BOOTSTRAP" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64"
    chmod +x "$BUILD/seed-aarch64"
    runtime_suite "$BUILD/seed-aarch64" seed-aarch64-gen1
    seed_run "$BUILD/seed-aarch64" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.2"
    chmod +x "$BUILD/seed-aarch64.2"
    runtime_suite "$BUILD/seed-aarch64.2" seed-aarch64-gen2
    seed_run "$BUILD/seed-aarch64.2" "$ROOT/seed/src/seed-linux-aarch64.seed" "$BUILD/seed-aarch64.3"
    cmp --verbose "$BUILD/seed-aarch64" "$BUILD/seed-aarch64.2"
    cmp --verbose "$BUILD/seed-aarch64.2" "$BUILD/seed-aarch64.3"

    # (i386) Seed cross-compiles from the amd64 Seed
    seed_run "$BOOTSTRAP" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed-i386"
    chmod +x "$BUILD/seed-i386"

    # (i386) Seed bootstraps itself
    seed_run "$BUILD/seed-i386" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed-i386.2"
    chmod +x "$BUILD/seed-i386.2"
    runtime_suite "$BUILD/seed-i386.2" seed-i386
    seed_run "$BUILD/seed-i386.2" "$ROOT/seed/src/seed-linux-i386.seed" "$BUILD/seed-i386.3"
    cmp --verbose "$BUILD/seed-i386" "$BUILD/seed-i386.2"
    cmp --verbose "$BUILD/seed-i386.2" "$BUILD/seed-i386.3"

    # (i386) Compile Sprout from the amd64 Seed
    seed_run "$BOOTSTRAP" "$ROOT/sprout/src/sprout-linux-i386.seed" "$BUILD/sprout-i386"
    chmod +x "$BUILD/sprout-i386"

    # (i386) Sprout bootstraps itself
    seed_run "$BUILD/sprout-i386" "$ROOT/sprout/src/sprout-linux-i386.seed" "$BUILD/sprout-i386.2"
    chmod +x "$BUILD/sprout-i386.2"
    runtime_suite "$BUILD/sprout-i386.2" sprout-i386
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
