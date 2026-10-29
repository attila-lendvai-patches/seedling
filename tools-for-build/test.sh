#!/usr/bin/env bash

# Run the suite for the current host (and the i386 suite on amd64,
# which executes i386 ELF directly), then the z80 suite.
# The suffix of a test-<arch>.sh script is the assumed *host*
# architecture, not the target architecture.

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    echo "error: run this script, do not source it" >&2
    return 1
fi

set -euo pipefail
if [ "${TEST_DEBUG:-0}" = 1 ]; then
    set -x
fi

TOOLS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$TOOLS/.." && pwd)
BUILD="$TOOLS/build"
LOG="$BUILD/test.log"
mkdir -p "$BUILD"
: >"$LOG"

run() {
    "$@" 2>&1 | tee -a "$LOG"
}

source "$TOOLS/test-common.sh"

echo "==> log: ${LOG#"$ROOT"/}"

case "$(uname -m)" in
    x86_64|amd64)
        host=amd64
        ;;
    i386|i486|i586|i686)
        host=i386
        ;;
    aarch64|arm64)
        host=aarch64
        ;;
    *)
        echo "error: unsupported host architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

echo "==> host architecture: $host"

BOOTSTRAP=$(bootstrap_for_host)

run source_line_check
run source_literal_check
run committed_binary_check
export TEST_CHECKS_DONE=1

run bash "$TOOLS/test-$host.sh"

# An amd64 host can run i386 ELF binaries natively, so exercise the
# i386 host suite there too.
if [ "$host" = amd64 ]; then
    run bash "$TOOLS/test-i386.sh"
fi

run bash "$TOOLS/test-z80.sh"
