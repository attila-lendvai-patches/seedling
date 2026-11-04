#!/usr/bin/env bash
#
# Run the CI matrix. CI and a local run both go through this, so there
# is no second list of steps to keep in sync.
#
# Modes: --native (the host suite and the z80 suite), --cross (the
# aarch64 host suite, from an x86_64 host), --all (default).
#
# A foreign binary is always run by prefixing it with qemu-<arch>, so
# binfmt_misc is not required.

set -euo pipefail

TOOLS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

mode=all
case "${1:-}" in
    --native)   mode=native ;;
    --cross)    mode=cross ;;
    --all)      mode=all ;;
    "")         mode=all ;;
    *)          echo "usage: $0 [--native|--cross|--all]" >&2; exit 2 ;;
esac

# The suites' own library: can_execute and runner_note answer the same
# question here that they answer inside a suite.
source "$TOOLS/test-common.sh"

echo "===== system ====="
uname -a
if command -v lsb_release >/dev/null 2>&1; then
    lsb_release -a 2>/dev/null || true
else
    cat /etc/os-release
fi
echo "===== targets ====="
for arch in amd64 i386 aarch64; do
    if can_execute "$arch"; then
        echo "  $arch: executable"
    else
        echo "  $arch: not executable ($(runner_note "$arch"))"
    fi
done

cross_supported() {
    case "$(uname -m)" in
        x86_64|amd64) return 0 ;;
        *)            return 1 ;;
    esac
}

run_native() {
    bash "$TOOLS/test.sh"
}

run_cross() {
    local status=0

    if ! cross_supported; then
        echo "error: --cross runs on an x86_64 host, this is $(uname -m)" >&2
        exit 1
    fi
    # Without a runner the suite prints SKIP and exits 0, which would
    # turn the job into a silent no-op.
    if [ "${TEST_NO_QEMU:-0}" = 1 ]; then
        echo "error: --cross exists to run through qemu;" \
            "TEST_NO_QEMU is set" >&2
        exit 1
    fi
    if ! can_execute aarch64; then
        echo "error: cannot run the aarch64 host suite:" \
            "$(runner_note aarch64)" >&2
        exit 1
    fi

    echo "::group::aarch64 host suite (qemu)"
    bash "$TOOLS/test-aarch64.sh" || status=$?
    echo "::endgroup::"
    return "$status"
}

case "$mode" in
    native)
        run_native
        ;;
    cross)
        run_cross
        ;;
    all)
        run_native
        if cross_supported; then
            run_cross
        else
            echo "skipping --cross on $(uname -m)" >&2
        fi
        ;;
esac
